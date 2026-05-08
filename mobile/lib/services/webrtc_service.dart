import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

enum AppConnectionState {
  idle,
  connecting,
  connected,
  error,
}

enum ConnectionQuality { excellent, good, poor, unknown }

class WebRTCService extends ChangeNotifier {
  io.Socket? _socket;
  RTCPeerConnection? _peerConnection;
  MediaStream? _remoteStream;
  RTCVideoRenderer? _audioRenderer;

  AppConnectionState _state = AppConnectionState.idle;
  String _errorMessage = '';
  String _activeSessionId = '';

  double _volume = 1.0;
  ConnectionQuality _connectionQuality = ConnectionQuality.unknown;
  Timer? _statsTimer;
  Timer? _connectionTimeoutTimer;
  Timer? _disconnectGraceTimer;
  bool _hasRemoteDescription = false;
  bool _isDisposed = false;
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];

  AppConnectionState get state => _state;
  String get errorMessage => _errorMessage;
  String get activeSessionId => _activeSessionId;
  MediaStream? get remoteStream => _remoteStream;
  double get volume => _volume;
  ConnectionQuality get connectionQuality => _connectionQuality;

  // ICE servers config
  static const Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      // {'urls': 'stun:openrelay.metered.ca:80'}, // optional STUN fallback (kept disabled)
      // {
      //   'urls': 'turn:openrelay.metered.ca:80',
      //   'username': 'openrelayproject',
      //   'credential': 'openrelayproject',
      // },
      // {
      //   'urls': 'turn:openrelay.metered.ca:443',
      //   'username': 'openrelayproject',
      //   'credential': 'openrelayproject',
      // },
      // {
      //   'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
      //   'username': 'openrelayproject',
      //   'credential': 'openrelayproject',
      // },
    ],
  };

  static const Map<String, dynamic> _offerSdpConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': false,
    },
    'optional': [],
  };

  Future<void>? _pcFuture;
  Future<void> _signalingQueue = Future.value();

  /// Connect to a session as a receiver (mobile = receiver)
  Future<void> connect(String sessionId, String serverUrl) async {
    if (_state != AppConnectionState.idle ||
        _socket != null ||
        _peerConnection != null ||
        _audioRenderer != null) {
      await disconnect(notify: false);
    }

    _activeSessionId = sessionId.toUpperCase();
    _setState(AppConnectionState.connecting);

    try {
      await _initAudioRenderer();
      await _connectSocket(serverUrl, _activeSessionId);
      _startConnectionTimeout();
    } catch (e) {
      debugPrint('[WebRTC] Connection failed: $e');
      _setError(e.toString());
    }
  }

  Future<void> _initAudioRenderer() async {
    _audioRenderer = RTCVideoRenderer();
    await _audioRenderer!.initialize();
  }

  Future<void> _connectSocket(String serverUrl, String sessionId) async {
    _socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(15)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(8000)
          .setTimeout(30000)
          .setExtraHeaders({'User-Agent': 'SyncronizationMobile/1.0'})
          .build(),
    );

    final completer = Completer<void>();

    _socket!.onConnect((_) {
      debugPrint('[Socket] Connected to $serverUrl');
      if (!completer.isCompleted) completer.complete();
      _joinSession(sessionId);
    });

    _socket!.on('reconnect', (_) {
      debugPrint('[Socket] Reconnected - rejoining session');
      _joinSession(sessionId);
    });

    _socket!.onConnectError((error) {
      debugPrint('[Socket] Connection error: $error');
      if (!completer.isCompleted) {
        completer.completeError(
          Exception('Could not connect to signaling server at $serverUrl'),
        );
      }
    });

    _socket!.on('signal', (data) {
      // Use a signaling queue to process signals sequentially
      _signalingQueue = _signalingQueue.then((_) async {
        try {
          Map<String, dynamic> payload;
          if (data is List && data.isNotEmpty) {
            payload = Map<String, dynamic>.from(data.first as Map);
          } else if (data is Map) {
            payload = Map<String, dynamic>.from(data);
          } else {
            debugPrint(
                '[Socket] Invalid signal data type: ${data.runtimeType}');
            return;
          }

          debugPrint('[Socket] Processing signal from ${payload['from']}');
          await _handleSignal(payload['from'] as String, payload['signal']);
        } catch (e) {
          debugPrint('[Socket] Error in signaling queue: $e');
        }
      });
    });

    _socket!.onDisconnect((_) {
      debugPrint('[Socket] Disconnected');
      if (_state == AppConnectionState.connecting) {
        _startConnectionTimeout();
      }
    });

    _socket!.connect();

    // Wait for connection with timeout (Render free tier may need 30s to wake)
    await completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw Exception(
        'Connection timed out. Server may be waking up — please try again.',
      ),
    );
  }

  void _joinSession(String sessionId) {
    debugPrint('[Socket] Joining session: $sessionId');
    _socket?.emit('join-session', sessionId);
  }

  Future<void> _handleSignal(String fromId, dynamic signal) async {
    try {
      // Ensure peer connection exists (atomic check)
      if (_peerConnection == null) {
        _pcFuture ??= _createPeerConnection(fromId);
        await _pcFuture;
      }

      final Map<String, dynamic> sigMap;
      if (signal is Map) {
        sigMap = Map<String, dynamic>.from(signal);
      } else {
        debugPrint('[WebRTC] Invalid signal payload');
        return;
      }

      final type = sigMap['type'] as String?;
      debugPrint(
          '[WebRTC] Handling signal type: ${type ?? (sigMap['candidate'] != null ? 'candidate' : 'unknown')} (State: ${_peerConnection?.signalingState})');

      if (type == 'offer') {
        final sdp = sigMap['sdp'] as String;
        debugPrint('[WebRTC] Setting remote offer');
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(sdp, 'offer'),
        );
        _hasRemoteDescription = true;
        await _flushPendingRemoteCandidates();

        debugPrint(
            '[WebRTC] Creating answer (Current State: ${_peerConnection!.signalingState})');
        final answer =
            await _peerConnection!.createAnswer(_offerSdpConstraints);

        debugPrint('[WebRTC] Setting local answer');
        await _peerConnection!.setLocalDescription(answer);

        _socket?.emit('signal', {
          'sessionId': _activeSessionId,
          'signal': {'type': 'answer', 'sdp': answer.sdp},
          'to': fromId,
        });
      } else if (type == 'answer') {
        debugPrint('[WebRTC] Setting remote answer');
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(sigMap['sdp'] as String, 'answer'),
        );
        _hasRemoteDescription = true;
        await _flushPendingRemoteCandidates();
      } else if (sigMap['candidate'] != null) {
        final candidate = _parseIceCandidate(sigMap);
        if (candidate == null) return;

        if (!_hasRemoteDescription) {
          debugPrint(
              '[WebRTC] Queueing ICE candidate until remote description is set');
          _pendingRemoteCandidates.add(candidate);
        } else {
          await _peerConnection!.addCandidate(candidate);
        }
      }
    } catch (e) {
      debugPrint('[WebRTC] Signal handling error: $e');
      _setError('WebRTC error: $e');
    }
  }

  Future<void> _createPeerConnection(String senderId) async {
    debugPrint('[WebRTC] Creating peer connection for sender: $senderId');

    _peerConnection = await createPeerConnection(_iceConfig);
    _hasRemoteDescription = false;
    _pendingRemoteCandidates.clear();

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _socket?.emit('signal', {
          'sessionId': _activeSessionId,
          'signal': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
          'to': senderId,
        });
      }
    };

    _peerConnection!.onConnectionState = (state) {
      debugPrint('[WebRTC] Connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _connectionTimeoutTimer?.cancel();
        _disconnectGraceTimer?.cancel();
        _setState(AppConnectionState.connected);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _setError('WebRTC connection lost');
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _startDisconnectGraceTimer();
      }
    };

    _peerConnection!.onTrack = (event) {
      debugPrint('[WebRTC] Got remote track: ${event.track.kind}');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        if (_audioRenderer != null) {
          _audioRenderer!.srcObject = _remoteStream;
        }
        notifyListeners();
      }
    };

    _peerConnection!.onAddStream = (stream) {
      debugPrint('[WebRTC] Got remote stream');
      _remoteStream = stream;
      if (_audioRenderer != null) {
        _audioRenderer!.srcObject = stream;
      }
      notifyListeners();
    };

    _startStatsTimer();
  }

  RTCIceCandidate? _parseIceCandidate(Map<String, dynamic> sigMap) {
    final candidateData = sigMap['candidate'];
    if (candidateData is Map) {
      final candMap = Map<String, dynamic>.from(candidateData);
      return RTCIceCandidate(
        candMap['candidate'] as String?,
        candMap['sdpMid'] as String?,
        (candMap['sdpMLineIndex'] as num?)?.toInt(),
      );
    }

    if (candidateData is String) {
      return RTCIceCandidate(
        candidateData,
        sigMap['sdpMid'] as String?,
        (sigMap['sdpMLineIndex'] as num?)?.toInt(),
      );
    }

    return null;
  }

  Future<void> _flushPendingRemoteCandidates() async {
    if (_pendingRemoteCandidates.isEmpty || _peerConnection == null) return;

    final pending = List<RTCIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in pending) {
      await _peerConnection!.addCandidate(candidate);
    }
  }

  void _startConnectionTimeout() {
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = Timer(const Duration(seconds: 45), () {
      if (_state == AppConnectionState.connecting) {
        _setError(
          'Could not complete WebRTC connection. Make sure the extension is still streaming and both devices are on the same network.',
        );
      }
    });
  }

  void _startDisconnectGraceTimer() {
    _disconnectGraceTimer?.cancel();
    _disconnectGraceTimer = Timer(const Duration(seconds: 10), () {
      if (_state == AppConnectionState.connected) {
        _setError('WebRTC connection lost');
      }
    });
  }

  void _startStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_peerConnection == null || _state != AppConnectionState.connected) {
        timer.cancel();
        _statsTimer = null;
        return;
      }

      try {
        final stats = await _peerConnection!.getStats();
        for (final report in stats) {
          if (report.type == 'candidate-pair' &&
              report.values.containsKey('currentRoundTripTime')) {
            final rtt =
                (report.values['currentRoundTripTime'] as num).toDouble();
            ConnectionQuality q;
            if (rtt < 0.05) {
              q = ConnectionQuality.excellent;
            } else if (rtt < 0.15) {
              q = ConnectionQuality.good;
            } else {
              q = ConnectionQuality.poor;
            }

            if (q != _connectionQuality) {
              _connectionQuality = q;
              notifyListeners();
            }
            break;
          }
        }
      } catch (e) {
        debugPrint('[WebRTC] Error getting stats: $e');
      }
    });
  }

  void setVolume(double value) {
    if (_isDisposed) return;
    _volume = value.clamp(0.0, 1.0);
    // flutter_webrtc 0.12.x does not expose RTCVideoRenderer.volume.
    // Apply volume by toggling audio track enabled state (mute = 0.0).
    _remoteStream?.getAudioTracks().forEach((track) {
      track.enabled = _volume > 0.0;
    });
    notifyListeners();
  }

  Future<void> disconnect({bool notify = true}) async {
    debugPrint('[WebRTC] Disconnecting...');

    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;

    await _peerConnection?.close();
    _peerConnection = null;

    _remoteStream?.getTracks().forEach((track) => track.stop());
    _remoteStream = null;

    if (_audioRenderer != null) {
      _audioRenderer!.srcObject = null;
      await _audioRenderer!.dispose();
      _audioRenderer = null;
    }

    _statsTimer?.cancel();
    _statsTimer = null;
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = null;
    _disconnectGraceTimer?.cancel();
    _disconnectGraceTimer = null;
    _connectionQuality = ConnectionQuality.unknown;

    _activeSessionId = '';
    _pcFuture = null;
    _signalingQueue = Future.value();
    _hasRemoteDescription = false;
    _pendingRemoteCandidates.clear();
    if (notify && !_isDisposed) {
      _setState(AppConnectionState.idle);
    } else {
      _state = AppConnectionState.idle;
      _errorMessage = '';
    }
  }

  void _setState(AppConnectionState newState) {
    if (_isDisposed) return;
    _state = newState;
    if (newState != AppConnectionState.error) {
      _errorMessage = '';
    }
    notifyListeners();
  }

  void _setError(String message) {
    if (_isDisposed) return;
    _connectionTimeoutTimer?.cancel();
    _disconnectGraceTimer?.cancel();
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
