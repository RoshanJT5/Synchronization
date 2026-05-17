import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:synchronization/services/guest_session_controller.dart';
import 'package:synchronization/services/host_session_controller.dart';

enum AppConnectionState { idle, connecting, connected, reconnecting, error }

enum ConnectionQuality { excellent, good, poor, unknown }

class WebRTCService extends ChangeNotifier {
  static const String _signalingServer =
      'https://synchronization-807q.onrender.com';

  static const Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {
        'urls': 'turn:openrelay.metered.ca:443?transport=udp',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
  };

  io.Socket? _socket;
  final Map<String, RTCPeerConnection> _peers = {};
  final List<RTCVideoRenderer> _remoteAudioRenderers = [];
  final List<MediaStreamTrack> _remoteAudioTracks = [];
  bool _hasRemoteAudio = false;
  Timer? _connectionTimeoutTimer;
  Timer? _heartbeatTimer;

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
    await _connectSocket(serverUrl ?? _signalingServer);
  }

  Future<void> connect(String shareCode, [String? serverUrl]) async {
    isHost = false;
    _activeSessionId = _extractSessionId(shareCode).toUpperCase();
    _setState(AppConnectionState.connecting);
    await _connectSocket(serverUrl ?? _signalingServer);
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
          .setReconnectionAttempts(20)
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
        completer.completeError(Exception('Could not reach signaling server'));
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

  void _announceHost() {
    _socket?.emit('announce-session', {
      'sessionId': _activeSessionId,
      'label': 'Host Phone',
      'type': 'mobile-host',
    });
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      _socket?.emit('session-heartbeat', {'sessionId': _activeSessionId});
      _socket?.emit('announce-session', {
        'sessionId': _activeSessionId,
        'label': 'Host Phone',
        'type': 'mobile-host',
      });
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
    if (pc == null) return;

    if (type == 'answer') {
      await pc.setRemoteDescription(
        RTCSessionDescription(signal['sdp'] as String?, 'answer'),
      );
    } else if (signal['candidate'] != null) {
      await pc.addCandidate(RTCIceCandidate(
        signal['candidate'] as String?,
        signal['sdpMid'] as String?,
        (signal['sdpMLineIndex'] as num?)?.toInt(),
      ));
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
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _peers.remove(peerId);
        notifyListeners();
      }
    };

    pc.onTrack = (event) {
      if (event.track.kind == 'audio') {
        _attachRemoteAudio(event);
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
      notifyListeners();
    };
  }

  void _attachRemoteAudio(RTCTrackEvent event) {
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
            await Helper.setVolume(_volume, track);
          }
        }
        _remoteAudioRenderers.add(renderer);
        _hasRemoteAudio = true;
        debugPrint('[WebRTC] Remote extension audio track attached');
        _connectionTimeoutTimer?.cancel();
        _setState(AppConnectionState.connected);
      } catch (e) {
        debugPrint('[WebRTC] Failed to attach remote audio: $e');
      }
    });
  }

  void disconnect({bool notify = true, bool keepControllers = false}) {
    _connectionTimeoutTimer?.cancel();
    _heartbeatTimer?.cancel();
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
    for (final renderer in _remoteAudioRenderers) {
      renderer.srcObject = null;
      renderer.dispose();
    }
    _remoteAudioRenderers.clear();
    _remoteAudioTracks.clear();
    _hasRemoteAudio = false;
    if (!keepControllers) {
      hostController?.dispose();
      guestController?.dispose();
      hostController = null;
      guestController = null;
      _activeSessionId = '';
      isHost = false;
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
    _errorMessage = message;
    _state = AppConnectionState.error;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    disconnect(notify: false);
    super.dispose();
  }
}
