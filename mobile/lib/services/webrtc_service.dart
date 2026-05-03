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
  String _serverUrl = '';

  double _volume = 1.0;
  ConnectionQuality _connectionQuality = ConnectionQuality.unknown;
  Timer? _statsTimer;

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
    ],
  };

  static const Map<String, dynamic> _offerSdpConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': false,
    },
    'optional': [],
  };

  /// Connect to a session as a receiver (mobile = receiver)
  Future<void> connect(String sessionId, String serverUrl) async {
    if (_state == AppConnectionState.connecting ||
        _state == AppConnectionState.connected) {
      await disconnect();
    }

    _activeSessionId = sessionId;
    _serverUrl = serverUrl;
    _setState(AppConnectionState.connecting);

    try {
      await _initAudioRenderer();
      await _connectSocket(serverUrl, sessionId);
    } catch (e) {
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
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(double.infinity)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .setTimeout(20000)
          .build(),
    );

    final completer = Completer<void>();

    _socket!.onConnect((_) {
      debugPrint('[Socket] Connected to $serverUrl');
      if (!completer.isCompleted) completer.complete();
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

    _socket!.on('signal', (data) async {
      try {
        Map<String, dynamic> payload;
        if (data is List && data.isNotEmpty) {
          payload = data.first as Map<String, dynamic>;
        } else if (data is Map) {
          payload = Map<String, dynamic>.from(data);
        } else {
          debugPrint('[Socket] Invalid signal data type: ${data.runtimeType}');
          return;
        }
        
        debugPrint('[Socket] Received signal from ${payload['from']}');
        await _handleSignal(payload['from'] as String, payload['signal']);
      } catch (e) {
        debugPrint('[Socket] Error parsing signal: $e');
      }
    });

    _socket!.onDisconnect((_) {
      debugPrint('[Socket] Disconnected');
      if (_state == AppConnectionState.connected) {
        _setError('Disconnected from signaling server');
      }
    });

    _socket!.connect();

    // Wait for connection with timeout
    await completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw Exception(
        'Connection timed out. Is the signaling server running at $serverUrl?',
      ),
    );
  }

  void _joinSession(String sessionId) {
    debugPrint('[Socket] Joining session: $sessionId');
    _socket?.emit('join-session', sessionId);
  }

  Future<void> _handleSignal(String fromId, dynamic signal) async {
    try {
      if (_peerConnection == null) {
        await _createPeerConnection(fromId);
      }

      final Map<String, dynamic> sigMap;
      if (signal is Map) {
        sigMap = Map<String, dynamic>.from(signal);
      } else {
        debugPrint('[WebRTC] Invalid signal payload');
        return;
      }

      final type = sigMap['type'] as String?;

      if (type == 'offer') {
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(sigMap['sdp'] as String, 'offer'),
        );
        final answer = await _peerConnection!.createAnswer(
          _offerSdpConstraints,
        );
        await _peerConnection!.setLocalDescription(answer);
        _socket?.emit('signal', {
          'sessionId': _activeSessionId,
          'signal': {'type': 'answer', 'sdp': answer.sdp},
          'to': fromId,
        });
      } else if (type == 'answer') {
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(sigMap['sdp'] as String, 'answer'),
        );
      } else if (sigMap['candidate'] != null) {
        // ICE candidate
        await _peerConnection!.addCandidate(
          RTCIceCandidate(
            sigMap['candidate'] as String,
            sigMap['sdpMid'] as String?,
            sigMap['sdpMLineIndex'] as int?,
          ),
        );
      }
    } catch (e) {
      debugPrint('[WebRTC] Signal handling error: $e');
      _setError('WebRTC error: $e');
    }
  }

  Future<void> _createPeerConnection(String senderId) async {
    debugPrint('[WebRTC] Creating peer connection for sender: $senderId');

    _peerConnection = await createPeerConnection(_iceConfig);

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
        _setState(AppConnectionState.connected);
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _setError('WebRTC connection lost');
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
            final rtt = (report.values['currentRoundTripTime'] as num).toDouble();
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
    _volume = value.clamp(0.0, 1.0);
    // flutter_webrtc 0.12.x does not expose RTCVideoRenderer.volume.
    // Apply volume by toggling audio track enabled state (mute = 0.0).
    _remoteStream?.getAudioTracks().forEach((track) {
      track.enabled = _volume > 0.0;
    });
    notifyListeners();
  }

  Future<void> disconnect() async {
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
    _connectionQuality = ConnectionQuality.unknown;

    _activeSessionId = '';
    _setState(AppConnectionState.idle);
  }

  void _setState(AppConnectionState newState) {
    _state = newState;
    if (newState != AppConnectionState.error) {
      _errorMessage = '';
    }
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    _state = AppConnectionState.error;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
