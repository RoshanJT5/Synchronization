import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

enum MobileSourceState { idle, announcing, streaming, error }

/// Manages the "source phone" side of mobile-to-mobile streaming.
///
/// Flow:
///   1. [startSource] — captures mic, connects to signaling server,
///      announces the session, and waits for speaker phones to join.
///   2. For each speaker that joins, a WebRTC peer connection is created
///      (this device is the initiator / offerer).
///   3. [stopSource] — tears everything down cleanly.
class MobileSourceService extends ChangeNotifier {
  static const String _signalingServer =
      'https://synchronization-807q.onrender.com';

  static const Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  io.Socket? _socket;
  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _peers = {};
  Timer? _heartbeatTimer;

  MobileSourceState _state = MobileSourceState.idle;
  String _errorMessage = '';
  String _sessionId = '';
  int _speakerCount = 0;
  bool _isDisposed = false;

  MobileSourceState get state => _state;
  String get errorMessage => _errorMessage;
  String get sessionId => _sessionId;
  int get speakerCount => _speakerCount;

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> startSource() async {
    if (_state != MobileSourceState.idle) return;

    _sessionId = _generateSessionId();
    _setState(MobileSourceState.announcing);

    try {
      await _captureMic();
      await _connectSocket();
    } catch (e) {
      debugPrint('[MobileSource] Start failed: $e');
      _setError(e.toString());
    }
  }

  Future<void> stopSource() async {
    debugPrint('[MobileSource] Stopping...');

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    if (_socket?.connected == true) {
      _socket!.emit('end-session', {'sessionId': _sessionId});
    }
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;

    for (final pc in _peers.values) {
      try {
        await pc.close();
      } catch (_) {}
    }
    _peers.clear();

    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream = null;

    _speakerCount = 0;
    _sessionId = '';
    if (!_isDisposed) _setState(MobileSourceState.idle);
  }

  // ── Mic capture ────────────────────────────────────────────────────────────

  Future<void> _captureMic() async {
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': false,
        'noiseSuppression': false,
        'autoGainControl': false,
        'sampleRate': 48000,
        'channelCount': 1,
      },
      'video': false,
    });
    debugPrint('[MobileSource] Mic captured: ${_localStream!.id}');
  }

  // ── Signaling ──────────────────────────────────────────────────────────────

  Future<void> _connectSocket() async {
    _socket = io.io(
      _signalingServer,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(20)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(8000)
          .setTimeout(30000)
          .setExtraHeaders({'User-Agent': 'SyncronizationMobile/1.0'})
          .build(),
    );

    final completer = Completer<void>();

    _socket!.onConnect((_) {
      debugPrint('[MobileSource] Socket connected');
      if (!completer.isCompleted) completer.complete();
      _announceAndJoin();
    });

    _socket!.on('reconnect', (_) {
      debugPrint('[MobileSource] Reconnected — re-announcing');
      _announceAndJoin();
    });

    _socket!.onConnectError((e) {
      debugPrint('[MobileSource] Connect error: $e');
      if (!completer.isCompleted) {
        completer.completeError(Exception('Could not reach signaling server'));
      }
    });

    // A new speaker joined the session room
    _socket!.on('peer-joined', (data) {
      final peerId = _extractString(data, 'peerId');
      if (peerId == null || peerId == _socket?.id) return;
      debugPrint('[MobileSource] Speaker joined: $peerId');
      _createPeerForSpeaker(peerId);
    });

    // Speakers already in the room when we join
    _socket!.on('session-peers', (data) {
      final peers = _extractList(data, 'peers') ?? [];
      for (final peerId in peers) {
        if (peerId == _socket?.id) continue;
        debugPrint('[MobileSource] Existing speaker: $peerId');
        _createPeerForSpeaker(peerId as String);
      }
    });

    // Incoming WebRTC signals (answers + ICE from speakers)
    _socket!.on('signal', (data) async {
      final from = _extractString(data, 'from');
      final signal = _extractMap(data, 'signal');
      if (from == null || signal == null) return;
      await _handleSignal(from, signal);
    });

    _socket!.onDisconnect((_) {
      debugPrint('[MobileSource] Socket disconnected');
    });

    _socket!.connect();

    await completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () =>
          throw Exception('Connection timed out — server may be waking up'),
    );
  }

  void _announceAndJoin() {
    _socket?.emit('join-session', _sessionId);
    _socket?.emit('announce-session', {
      'sessionId': _sessionId,
      'label': 'This Phone 📱',
      'type': 'mobile-source',
    });
    _setState(MobileSourceState.streaming);

    // Heartbeat so the session stays alive
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (_socket?.connected == true) {
        _socket!.emit('session-heartbeat', {'sessionId': _sessionId});
        _socket!.emit('announce-session', {
          'sessionId': _sessionId,
          'label': 'This Phone 📱',
          'type': 'mobile-source',
        });
      }
    });
  }

  // ── WebRTC (initiator side) ────────────────────────────────────────────────

  Future<void> _createPeerForSpeaker(String speakerId) async {
    if (_peers.containsKey(speakerId)) return;

    final pc = await createPeerConnection(_iceConfig);
    _peers[speakerId] = pc;

    // Add mic tracks to this peer
    _localStream?.getTracks().forEach((track) {
      pc.addTrack(track, _localStream!);
    });

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _socket?.emit('signal', {
          'sessionId': _sessionId,
          'signal': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
          'to': speakerId,
        });
      }
    };

    pc.onConnectionState = (state) {
      debugPrint('[MobileSource] Peer $speakerId state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _speakerCount = _peers.values
            .where((p) =>
                p.connectionState ==
                RTCPeerConnectionState.RTCPeerConnectionStateConnected)
            .length;
        notifyListeners();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _peers.remove(speakerId);
        _speakerCount = _peers.values
            .where((p) =>
                p.connectionState ==
                RTCPeerConnectionState.RTCPeerConnectionStateConnected)
            .length;
        notifyListeners();
      }
    };

    // Create and send offer with low-latency Opus settings
    final offer = await pc.createOffer({
      'offerToReceiveAudio': false,
      'offerToReceiveVideo': false,
    });

    String sdp = offer.sdp ?? '';
    sdp = _patchOpusSdp(sdp);

    await pc.setLocalDescription(RTCSessionDescription(sdp, 'offer'));
    _socket?.emit('signal', {
      'sessionId': _sessionId,
      'signal': {'type': 'offer', 'sdp': sdp},
      'to': speakerId,
    });
  }

  Future<void> _handleSignal(
      String fromId, Map<String, dynamic> signal) async {
    final pc = _peers[fromId];
    if (pc == null) return;

    final type = signal['type'] as String?;

    if (type == 'answer') {
      await pc.setRemoteDescription(
        RTCSessionDescription(signal['sdp'] as String, 'answer'),
      );
    } else if (signal['candidate'] != null) {
      final candidateData = signal['candidate'];
      RTCIceCandidate? candidate;
      if (candidateData is Map) {
        final m = Map<String, dynamic>.from(candidateData);
        candidate = RTCIceCandidate(
          m['candidate'] as String?,
          m['sdpMid'] as String?,
          (m['sdpMLineIndex'] as num?)?.toInt(),
        );
      } else if (candidateData is String) {
        candidate = RTCIceCandidate(
          candidateData,
          signal['sdpMid'] as String?,
          (signal['sdpMLineIndex'] as num?)?.toInt(),
        );
      }
      if (candidate != null) {
        await pc.addCandidate(candidate);
      }
    }
  }

  // ── SDP patching for low-latency Opus ─────────────────────────────────────

  String _patchOpusSdp(String sdp) {
    return sdp.replaceAllMapped(
      RegExp(r'a=fmtp:(\d+) (.*opus.*)', caseSensitive: false),
      (m) {
        final pt = m.group(1)!;
        final params = m.group(2)!;
        final map = Map.fromEntries(
          params.split(';').map((p) {
            final parts = p.trim().split('=');
            return MapEntry(
                parts[0].trim(), parts.length > 1 ? parts[1].trim() : '1');
          }),
        );
        map['ptime'] = '10';
        map['maxptime'] = '10';
        map['useinbandfec'] = '1';
        map['usedtx'] = '0';
        map['stereo'] = '0'; // mono mic
        map['maxplaybackrate'] = '48000';
        return 'a=fmtp:$pt ${map.entries.map((e) => '${e.key}=${e.value}').join(';')}';
      },
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _generateSessionId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
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
    if (data is List && data.isNotEmpty && data.first is Map) {
      final v = (data.first as Map)[key];
      return v is Map ? Map<String, dynamic>.from(v) : null;
    }
    if (data is Map) {
      final v = data[key];
      return v is Map ? Map<String, dynamic>.from(v) : null;
    }
    return null;
  }

  void _setState(MobileSourceState s) {
    if (_isDisposed) return;
    _state = s;
    if (s != MobileSourceState.error) _errorMessage = '';
    notifyListeners();
  }

  void _setError(String msg) {
    if (_isDisposed) return;
    _errorMessage = msg;
    _state = MobileSourceState.error;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    stopSource();
    super.dispose();
  }
}
