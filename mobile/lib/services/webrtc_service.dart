import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:synchronization/services/guest_session_controller.dart';
import 'package:synchronization/services/host_session_controller.dart';
import 'package:synchronization/utils/user_error_message.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:synchronization/config/server_config.dart';
import 'package:synchronization/services/background_keep_alive_service.dart';
import 'package:synchronization/services/location_service.dart';

enum AppConnectionState { idle, connecting, connected, reconnecting, error }

enum ConnectionQuality { excellent, good, poor, unknown }

class WebRTCService extends ChangeNotifier {
  static String get _signalingServer => ServerConfig.signalingServer;

  static const Map<String, dynamic> _iceConfig = {
    'iceServers': [
      // Always try Google STUN first (Fastest, uses 0MB)
      {'urls': 'stun:stun.l.google.com:19302'},
      
      // ExpressTURN STUN Backup
      {
        'urls': 'stun:free.expressturn.com:3478',
      },

      // ExpressTURN TURN (Try this first)
      {
        'urls': 'turn:free.expressturn.com:3478',
        'username': '000000002096352701',
        'credential': 'I4PrWLgp6znLfV6BXYK7xQviwTw=',
      },

      // If ExpressTURN fails, try your private 500MB TURN server (Fast, reliable)
      {
        'urls': "stun:stun.relay.metered.ca:80",
      },
      {
        'urls': "turn:global.relay.metered.ca:80",
        'username': "3bc60cb6f671013bf50ac68c",
        'credential': "6w0c+6c2jfIWt5v1",
      },
      {
        'urls': "turn:global.relay.metered.ca:80?transport=tcp",
        'username': "3bc60cb6f671013bf50ac68c",
        'credential': "6w0c+6c2jfIWt5v1",
      },
      {
        'urls': "turn:global.relay.metered.ca:443",
        'username': "3bc60cb6f671013bf50ac68c",
        'credential': "6w0c+6c2jfIWt5v1",
      },
      {
        'urls': "turns:global.relay.metered.ca:443?transport=tcp",
        'username': "3bc60cb6f671013bf50ac68c",
        'credential': "6w0c+6c2jfIWt5v1",
      },
      
      // If the private one rejects us (quota reached), fallback to the overloaded free one
      {
        'urls': 'turn:openrelay.metered.ca:443?transport=udp',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
    'iceCandidatePoolSize': 1,
  };


  io.Socket? _socket;
  final Map<String, RTCPeerConnection> _peers = {};
  final Map<String, List<RTCIceCandidate>> _pendingIceCandidatesByPeer = {};
  final Set<String> _remoteDescriptionReadyPeers = {};
  final Map<String, List<RTCVideoRenderer>> _remoteAudioRenderersByPeer = {};
  final Map<String, List<MediaStreamTrack>> _remoteAudioTracksByPeer = {};
  final List<RTCVideoRenderer> _remoteAudioRenderers = [];
  final List<MediaStreamTrack> _remoteAudioTracks = [];
  bool _hasRemoteAudio = false;
  Timer? _connectionTimeoutTimer;
  Timer? _heartbeatTimer;
  Timer? _socketHeartbeatTimer;

  HostSessionController? hostController;
  GuestSessionController? guestController;

  AppConnectionState _state = AppConnectionState.idle;
  String _errorMessage = '';
  String _activeSessionId = '';
  bool _isDisposed = false;
  bool isHost = false;
  double _volume = 1.0;

  AppConnectionState get state => _state;
  String get errorMessage => _errorMessage;
  String get activeSessionId => _activeSessionId;
  bool get isWaitingForHost =>
      _state == AppConnectionState.connecting && !isHost;
  bool get isSynced => _state == AppConnectionState.connected;
  bool get hasRemoteAudio => _hasRemoteAudio;
  bool get isPaused => isHost
      ? !(hostController?.isPlaying ?? false)
      : !(guestController?.isPlaying ?? false);
  double get volume => _volume;
  int get guestCount => hostController?.guestCount ?? 0;
  ConnectionQuality get connectionQuality =>
      _state == AppConnectionState.connected
          ? ConnectionQuality.excellent
          : ConnectionQuality.unknown;
  double get currentDriftMs => 0;
  int get bufferSize => 0;
  String get syncStats => '';

  void initializeHost(HostSessionController controller) {
    hostController?.removeListener(notifyListeners);
    hostController = controller..addListener(notifyListeners);
    guestController = null;
    isHost = true;
  }

  void initializeGuest(GuestSessionController controller) {
    guestController?.removeListener(notifyListeners);
    guestController = controller..addListener(notifyListeners);
    hostController = null;
    isHost = false;
  }

  Future<String> createHostSession({String? serverUrl}) async {
    final sessionId = _generateSessionId();
    await host(sessionId, serverUrl: serverUrl);
    return sessionId;
  }

  Future<void> host(String sessionId, {String? serverUrl}) async {
    isHost = true;
    _activeSessionId = sessionId.toUpperCase();
    _setState(AppConnectionState.connecting);
    unawaited(_enableSessionWakelock());
    try {
      await _connectSocket(serverUrl ?? _signalingServer);
    } catch (_) {
      unawaited(_disableSessionWakelock());
      rethrow;
    }
  }

  Future<void> connect(String shareCode, [String? serverUrl]) async {
    isHost = false;
    _activeSessionId = _extractSessionId(shareCode).toUpperCase();
    _setState(AppConnectionState.connecting);
    unawaited(_enableSessionWakelock());
    try {
      await _connectSocket(serverUrl ?? _signalingServer);
    } catch (_) {
      unawaited(_disableSessionWakelock());
      rethrow;
    }
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    if (isHost) {
      await hostController?.setVolume(_volume);
    } else {
      await guestController?.setVolume(_volume);
      for (final track in _remoteAudioTracks) {
        await Helper.setVolume(_volume, track);
      }
    }
    notifyListeners();
  }

  Future<void> _connectSocket(String url) async {
    disconnect(notify: false, keepControllers: true);

    final completer = Completer<void>();
    _socket = io.io(
      url,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(9999999)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(8000)
          .setTimeout(30000)
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('[WebRTC] Socket connected, joining $_activeSessionId');
      _socket?.emit('join-session', _activeSessionId);
      if (isHost) _announceHost();
      if (!completer.isCompleted) completer.complete();

      // Socket-level keepalive: emit a heartbeat every 30 seconds so the
      // active session does not get pruned by the server's TTL logic.
      _socketHeartbeatTimer?.cancel();
      _socketHeartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _socket?.emit('session-heartbeat', {'sessionId': _activeSessionId});
      });
    });

    _socket!.on('session-peers', (data) {
      if (!isHost) return;
      final peers = _extractList(data, 'peers') ?? [];
      for (final peerId in peers.whereType<String>()) {
        if (peerId != _socket?.id) _createOffer(peerId);
      }
    });

    _socket!.on('peer-joined', (data) {
      if (!isHost) return;
      final peerId = _extractString(data, 'peerId');
      if (peerId != null && peerId != _socket?.id) _createOffer(peerId);
    });

    _socket!.on('signal', (data) async {
      final from = _extractString(data, 'from');
      final signal = _extractMap(data, 'signal');
      if (from == null || signal == null) return;
      try {
        await _handleSignal(from, signal);
      } catch (e) {
        debugPrint('[WebRTC] Signal error: $e');
        _setError('Failed to process WebRTC signal');
      }
    });

    _socket!.onConnectError((e) {
      debugPrint('[WebRTC] Socket connect error: $e');
      if (!completer.isCompleted) {
        completer.completeError(Exception('No internet connection.'));
      }
    });

    _socket!.onDisconnect((_) {
      if (!_isDisposed && _state == AppConnectionState.connected) {
        _setState(AppConnectionState.reconnecting);
      }
    });

    _socket!.connect();
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = Timer(const Duration(seconds: 60), () {
      if (_state == AppConnectionState.connecting) {
        _setError(isHost
            ? 'Session created, but no guests connected yet.'
            : 'Connection timed out. Check the session code.');
      }
    });

    await completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw Exception('Connection timed out'),
    );
  }

  ({double lat, double lng})? _hostLocation;

  void _announceHost() async {
    _hostLocation ??= await LocationService.getPosition();
    _doAnnounceHost();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      _socket?.emit('session-heartbeat', {'sessionId': _activeSessionId});
      _doAnnounceHost();
    });
  }

  /// Emits 'announce-session' with the host's GPS coordinates so the server
  /// knows where this session is physically located (50m filter).
  void _doAnnounceHost() {
    _socket?.emit('announce-session', {
      'sessionId': _activeSessionId,
      'label': 'Host Phone',
      'type': 'mobile-host',
      if (_hostLocation != null) 'lat': _hostLocation!.lat,
      if (_hostLocation != null) 'lng': _hostLocation!.lng,
    });
  }

  Future<void> _createOffer(String peerId) async {
    if (_peers.containsKey(peerId)) return;
    final pc = await createPeerConnection(_iceConfig);
    _peers[peerId] = pc;
    final channel = await pc.createDataChannel(
      'sync',
      RTCDataChannelInit()..ordered = true,
    );
    _wirePeer(peerId, pc);
    _wireDataChannel(channel);

    final offer = await pc.createOffer({
      'offerToReceiveAudio': false,
      'offerToReceiveVideo': false,
    });
    await pc.setLocalDescription(offer);
    _socket?.emit('signal', {
      'sessionId': _activeSessionId,
      'signal': {'type': offer.type, 'sdp': offer.sdp},
      'to': peerId,
    });
  }

  Future<void> _handleSignal(String fromId, Map<String, dynamic> signal) async {
    final type = signal['type'] as String?;

    if (type == 'offer') {
      final pc = await createPeerConnection(_iceConfig);
      _peers[fromId] = pc;
      _wirePeer(fromId, pc);
      pc.onDataChannel = _wireDataChannel;
      await pc.setRemoteDescription(
        RTCSessionDescription(signal['sdp'] as String?, 'offer'),
      );
      _remoteDescriptionReadyPeers.add(fromId);
      await _flushPendingIceCandidates(fromId, pc);
      final answer = await pc.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      await pc.setLocalDescription(answer);
      _socket?.emit('signal', {
        'sessionId': _activeSessionId,
        'signal': {'type': answer.type, 'sdp': answer.sdp},
        'to': fromId,
      });
      return;
    }

    final pc = _peers[fromId];
    if (pc == null) {
      if (signal['candidate'] != null) {
        final candidate = RTCIceCandidate(
          signal['candidate'] as String?,
          signal['sdpMid'] as String?,
          (signal['sdpMLineIndex'] as num?)?.toInt(),
        );
        _pendingIceCandidatesByPeer
            .putIfAbsent(fromId, () => [])
            .add(candidate);
      }
      return;
    }

    if (type == 'answer') {
      await pc.setRemoteDescription(
        RTCSessionDescription(signal['sdp'] as String?, 'answer'),
      );
      _remoteDescriptionReadyPeers.add(fromId);
      await _flushPendingIceCandidates(fromId, pc);
    } else if (signal['candidate'] != null) {
      final candidate = RTCIceCandidate(
        signal['candidate'] as String?,
        signal['sdpMid'] as String?,
        (signal['sdpMLineIndex'] as num?)?.toInt(),
      );
      if (!_remoteDescriptionReadyPeers.contains(fromId)) {
        _pendingIceCandidatesByPeer.putIfAbsent(fromId, () => []).add(candidate);
        return;
      }
      await pc.addCandidate(candidate);
    }
  }

  Future<void> _flushPendingIceCandidates(
    String peerId,
    RTCPeerConnection pc,
  ) async {
    final candidates = _pendingIceCandidatesByPeer.remove(peerId) ?? const [];
    for (final candidate in candidates) {
      try {
        await pc.addCandidate(candidate);
      } catch (e) {
        debugPrint('[WebRTC] Ignored stale ICE candidate for $peerId: $e');
      }
    }
  }

  void _wirePeer(String peerId, RTCPeerConnection pc) {
    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _socket?.emit('signal', {
          'sessionId': _activeSessionId,
          'signal': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
          'to': peerId,
        });
      }
    };

    pc.onConnectionState = (state) {
      debugPrint('[WebRTC] Peer $peerId state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _connectionTimeoutTimer?.cancel();
        _setState(AppConnectionState.connected);
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        // Attempt ICE restart instead of silently dropping the peer.
        _attemptIceRestart(peerId, pc);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _peers.remove(peerId);
        _pendingIceCandidatesByPeer.remove(peerId);
        _remoteDescriptionReadyPeers.remove(peerId);
        _disposePeerMedia(peerId);
        notifyListeners();
      }
    };

    pc.onTrack = (event) {
      if (event.track.kind == 'audio') {
        _attachRemoteAudio(peerId, event);
      }
    };
  }

  void _wireDataChannel(RTCDataChannel channel) {
    if (isHost) {
      hostController?.onGuestConnected(channel);
    } else {
      guestController?.setHostChannel(channel);
    }
    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        if (isHost) {
          hostController?.onGuestConnected(channel);
        } else {
          guestController?.setHostChannel(channel);
        }
        _connectionTimeoutTimer?.cancel();
        _setState(AppConnectionState.connected);
      }
      if (!isHost && state == RTCDataChannelState.RTCDataChannelClosed) {
        guestController?.markHostDisconnected();
        _setError('Host disconnected. Leave this session and reconnect.');
        return;
      }
      notifyListeners();
    };
  }

  void _attachRemoteAudio(String peerId, RTCTrackEvent event) {
    final stream = event.streams.isNotEmpty ? event.streams.first : null;
    if (stream == null) return;

    Future<void>(() async {
      try {
        final renderer = RTCVideoRenderer();
        await renderer.initialize();
        renderer.srcObject = stream;
        for (final track in stream.getAudioTracks()) {
          if (!_remoteAudioTracks.contains(track)) {
            _remoteAudioTracks.add(track);
            _remoteAudioTracksByPeer.putIfAbsent(peerId, () => []).add(track);
            await Helper.setVolume(_volume, track);
          }
        }
        _remoteAudioRenderers.add(renderer);
        _remoteAudioRenderersByPeer.putIfAbsent(peerId, () => []).add(renderer);
        _hasRemoteAudio = true;
        debugPrint('[WebRTC] Remote extension audio track attached');
        _connectionTimeoutTimer?.cancel();
        _setState(AppConnectionState.connected);
      } catch (e) {
        debugPrint('[WebRTC] Failed to attach remote audio: $e');
      }
    });
  }

  void _disposePeerMedia(String peerId) {
    final renderers = _remoteAudioRenderersByPeer.remove(peerId) ?? const [];
    for (final renderer in renderers) {
      _remoteAudioRenderers.remove(renderer);
      renderer.srcObject = null;
      renderer.dispose();
    }

    final tracks = _remoteAudioTracksByPeer.remove(peerId) ?? const [];
    for (final track in tracks) {
      _remoteAudioTracks.remove(track);
    }
    _hasRemoteAudio = _remoteAudioRenderers.isNotEmpty;
  }

  void disconnect({bool notify = true, bool keepControllers = false}) {
    _connectionTimeoutTimer?.cancel();
    _heartbeatTimer?.cancel();
    _socketHeartbeatTimer?.cancel();
    if (isHost && _activeSessionId.isNotEmpty) {
      _socket?.emit('end-session', {'sessionId': _activeSessionId});
    }
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    for (final pc in _peers.values) {
      pc.close();
    }
    _peers.clear();
    _pendingIceCandidatesByPeer.clear();
    _remoteDescriptionReadyPeers.clear();
    for (final renderer in _remoteAudioRenderers) {
      renderer.srcObject = null;
      renderer.dispose();
    }
    _remoteAudioRenderersByPeer.clear();
    _remoteAudioRenderers.clear();
    _remoteAudioTracksByPeer.clear();
    _remoteAudioTracks.clear();
    _hasRemoteAudio = false;
    if (!keepControllers) {
      hostController?.dispose();
      guestController?.dispose();
      hostController = null;
      guestController = null;
      _activeSessionId = '';
      isHost = false;
      unawaited(_disableSessionWakelock());
    }
    if (notify) _setState(AppConnectionState.idle);
  }

  String _generateSessionId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  String _extractSessionId(String input) {
    if (!input.startsWith('http')) return input;
    final uri = Uri.parse(input);
    final pathId = uri.pathSegments.length >= 2 && uri.pathSegments.first == 'c'
        ? uri.pathSegments[1]
        : null;
    return uri.queryParameters['id'] ?? pathId ?? '';
  }

  /// Attempt an ICE restart for a peer whose connection went to
  /// `disconnected` or `failed`. If the restart itself fails, the peer
  /// is removed as a last resort.
  Future<void> _attemptIceRestart(String peerId, RTCPeerConnection pc) async {
    debugPrint('[WebRTC] Attempting ICE restart for peer $peerId');
    try {
      final offer = await pc.createOffer({
        'iceRestart': true,
        'offerToReceiveAudio': !isHost,
        'offerToReceiveVideo': false,
      });
      await pc.setLocalDescription(offer);
      _socket?.emit('signal', {
        'sessionId': _activeSessionId,
        'signal': {'type': offer.type, 'sdp': offer.sdp},
        'to': peerId,
      });
    } catch (e) {
      debugPrint('[WebRTC] ICE restart failed for $peerId: $e');
      _peers.remove(peerId);
      _pendingIceCandidatesByPeer.remove(peerId);
      _remoteDescriptionReadyPeers.remove(peerId);
      _disposePeerMedia(peerId);
      if (!isHost) {
        guestController?.markHostDisconnected();
        _setError('Host disconnected. Leave this session and reconnect.');
        return;
      }
      notifyListeners();
    }
  }

  String? _extractString(dynamic data, String key) {
    if (data is List && data.isNotEmpty && data.first is Map) {
      return (data.first as Map)[key] as String?;
    }
    if (data is Map) return data[key] as String?;
    return null;
  }

  List? _extractList(dynamic data, String key) {
    if (data is List && data.isNotEmpty && data.first is Map) {
      return (data.first as Map)[key] as List?;
    }
    if (data is Map) return data[key] as List?;
    return null;
  }

  Map<String, dynamic>? _extractMap(dynamic data, String key) {
    final value = data is List && data.isNotEmpty && data.first is Map
        ? (data.first as Map)[key]
        : data is Map
            ? data[key]
            : null;
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  void _setState(AppConnectionState s) {
    if (_isDisposed) return;
    _state = s;
    if (s != AppConnectionState.error) _errorMessage = '';
    notifyListeners();
  }

  void _setError(String message) {
    if (_isDisposed) return;
    _errorMessage = UserErrorMessage.from(message);
    _state = AppConnectionState.error;
    notifyListeners();
  }

  Future<void> _enableSessionWakelock() async {
    try {
      await WakelockPlus.enable();
      await BackgroundKeepAliveService.start();
    } catch (e) {
      debugPrint('[WebRTC] Failed to enable wakelock: $e');
    }
  }

  Future<void> _disableSessionWakelock() async {
    try {
      await WakelockPlus.disable();
      await BackgroundKeepAliveService.stop();
    } catch (e) {
      debugPrint('[WebRTC] Failed to disable wakelock: $e');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    disconnect(notify: false);
    super.dispose();
  }
}
