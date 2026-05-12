import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'clock_sync_service.dart';
import 'sync_playback_engine.dart';
import 'sync_clock.dart';
import 'playback_buffer.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

enum AppConnectionState { idle, connecting, connected, error }

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
  Timer? _positionReportTimer;
  Timer? _connectionTimeoutTimer;
  Timer? _waitingForHostTimer;
  Timer? _disconnectGraceTimer;
  bool _hasRemoteDescription = false;
  bool _isWaitingForHost = false;
  bool _isDisposed = false;
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];

  // Clock sync
  final ClockSyncService clockSync = ClockSyncService();

  // Synchronized playback engine
  final SyncPlaybackEngine syncEngine = SyncPlaybackEngine();

  final SyncClock _syncClock = SyncClock();
  PlaybackBuffer? _playbackBuffer;
  final StreamController<Map<String, dynamic>> _pongController =
      StreamController<Map<String, dynamic>>.broadcast();
  RTCDataChannel? _dataChannel;

  AppConnectionState get state => _state;
  String get errorMessage => _errorMessage;
  String get activeSessionId => _activeSessionId;
  MediaStream? get remoteStream => _remoteStream;
  double get volume => _volume;
  ConnectionQuality get connectionQuality => _connectionQuality;
  bool get isWaitingForHost => _isWaitingForHost;

  // Sync state getters
  bool get isSynced => _syncClock.isCalibrated;
  bool get isPaused => _playbackBuffer?.isPaused ?? false;
  String get syncStats => _playbackBuffer?.stats ?? 'Buffer inactive';

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
    'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': false},
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
      _startWaitingForHostTimer();
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
              '[Socket] Invalid signal data type: ${data.runtimeType}',
            );
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
        '[WebRTC] Handling signal type: ${type ?? (sigMap['candidate'] != null ? 'candidate' : 'unknown')} (State: ${_peerConnection?.signalingState})',
      );

      if (type == 'offer') {
        final sdp = sigMap['sdp'] as String;
        debugPrint('[WebRTC] Setting remote offer');
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(sdp, 'offer'),
        );
        _hasRemoteDescription = true;
        await _flushPendingRemoteCandidates();

        debugPrint(
          '[WebRTC] Creating answer (Current State: ${_peerConnection!.signalingState})',
        );
        final answer = await _peerConnection!.createAnswer(
          _offerSdpConstraints,
        );

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
            '[WebRTC] Queueing ICE candidate until remote description is set',
          );
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

    _peerConnection!.onConnectionState = (state) async {
      debugPrint('[WebRTC] Connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _connectionTimeoutTimer?.cancel();
        _waitingForHostTimer?.cancel();
        _isWaitingForHost = false;
        _disconnectGraceTimer?.cancel();
        // Start sync-engine monitoring now that we have a live clock-sync channel
        syncEngine.startMonitoring(clockSync);
        _setState(AppConnectionState.connected);

        // Step 1: Sync clock with source
        unawaited(_syncClock.calibrate(
          sendPing: (pingId) {
            _dataChannel?.send(RTCDataChannelMessage(jsonEncode({
              'type': 'ping',
              'pingId': pingId,
            })));
          },
          pongStream: _pongController.stream,
        ));

        // Step 2: Initialize and start playback buffer
        await FlutterPcmSound.setup(
          sampleRate: 48000,
          channelCount: 2, // Stereo
        );
        await FlutterPcmSound.setFeedThreshold(8000);
        FlutterPcmSound.setFeedCallback((remainingFrames) async {
          // Buffer is running low — this is handled automatically
          // by our PlaybackBuffer feeding chunks continuously
        });

        _playbackBuffer = PlaybackBuffer(_syncClock);
        _playbackBuffer!.start((audioData) {
          _playAudioChunk(Uint8List.fromList(audioData));
        });
        _startPositionReporting();
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
        // Apply current volume to the new tracks
        for (var track in _remoteStream!.getAudioTracks()) {
          track.enabled = _volume > 0;
          Helper.setVolume(_volume, track);
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
      // Apply current volume to the new tracks
      for (var track in stream.getAudioTracks()) {
        track.enabled = _volume > 0;
        Helper.setVolume(_volume, track);
      }
      notifyListeners();
    };

    // ── Clock-sync data channel ──────────────────────────────────────────
    // The extension (initiator) opens a "clock-sync" data channel.
    // We receive it here and attach it to ClockSyncService.
    // The channel also carries sync-config messages from the source.
    _peerConnection!.onDataChannel = (channel) {
      if (channel.label == 'clock-sync') {
        debugPrint('[WebRTC] Clock-sync data channel received');
        _dataChannel = channel;
        clockSync.attach(channel);
        
        channel.onMessage = (RTCDataChannelMessage message) {
          try {
            final packet = jsonDecode(message.text);

            if (packet['type'] == 'pong') {
              // Feed pong to clock calibration
              _pongController.add({
                'sourceTime': packet['sourceTime'],
                'pingId': packet['pingId'],
              });
              return;
            }

            if (packet['type'] == 'audio') {
              _playbackBuffer?.addChunk(BufferedChunk(
                chunkId: packet['chunkId'],
                playbackTimestamp: (packet['playbackTimestamp'] as num).toDouble(),
                audioData: List<int>.from(packet['audioData']),
              ));
              notifyListeners(); // Refresh UI with new stats
              return;
            }

            if (packet['type'] == 'wait_at_checkpoint') {
              final checkpoint = packet['checkpoint'] as int;
              _playbackBuffer?.pauseAtCheckpoint(checkpoint);
              notifyListeners();
              return;
            }

            if (packet['type'] == 'resume') {
              _playbackBuffer?.resume();
              notifyListeners();
              return;
            }

            // Fallback for existing clock-sync logic if needed
            // (The existing ClockSyncService might still need these)
            // But we've replaced the core logic.
          } catch (e) {
            // If it's not JSON, it might be the old format or raw data
          }
        };

        // Forward source-buffer config into the sync engine whenever it arrives
        clockSync.addListener(() {
          if (clockSync.hasSyncConfig) {
            syncEngine.applySourceConfig(bufferMs: clockSync.sourceBufferMs!);
          }
        });
      }
    };
    // ─────────────────────────────────────────────────────────────────────

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

  void _startWaitingForHostTimer() {
    _waitingForHostTimer?.cancel();
    _isWaitingForHost = false;
    _waitingForHostTimer = Timer(const Duration(seconds: 2), () {
      if (_state == AppConnectionState.connecting) {
        _isWaitingForHost = true;
        notifyListeners();
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
            final rtt = (report.values['currentRoundTripTime'] as num)
                .toDouble();
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
            // Feed RTT into clock sync service for latency estimation
            clockSync.updateRtt(rtt);
            break;
          }
        }
      } catch (e) {
        debugPrint('[WebRTC] Error getting stats: $e');
      }
    });
  }

  void _startPositionReporting() {
    _positionReportTimer?.cancel();
    _positionReportTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen &&
          _playbackBuffer != null) {
        _dataChannel!.send(RTCDataChannelMessage(jsonEncode({
          'type': 'position_report',
          'currentChunkId': _playbackBuffer!.lastPlayedChunkId,
        })));
      }
    });
  }

  void setVolume(double value) {
    if (_isDisposed) return;
    _volume = value.clamp(0.0, 1.0);

    // Use Helper.setVolume for linear scaling on mobile.
    // track.enabled provides a reliable absolute mute at 0.0.
    _remoteStream?.getAudioTracks().forEach((track) {
      track.enabled = _volume > 0.0;
      Helper.setVolume(_volume, track);
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
    _positionReportTimer?.cancel();
    _positionReportTimer = null;
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = null;
    _waitingForHostTimer?.cancel();
    _waitingForHostTimer = null;
    _disconnectGraceTimer?.cancel();
    _disconnectGraceTimer = null;
    _connectionQuality = ConnectionQuality.unknown;
    _isWaitingForHost = false;
    clockSync.detach();
    syncEngine.stopMonitoring();
    _playbackBuffer?.stop();
    _playbackBuffer = null;
    await FlutterPcmSound.release();

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
    if (newState != AppConnectionState.connecting) {
      _isWaitingForHost = false;
    }
    notifyListeners();
  }

  void _setError(String message) {
    if (_isDisposed) return;
    _connectionTimeoutTimer?.cancel();
    _waitingForHostTimer?.cancel();
    _disconnectGraceTimer?.cancel();
    _isWaitingForHost = false;
    _errorMessage = message;
    _state = AppConnectionState.error;
    notifyListeners();
  }

  void _playAudioChunk(Uint8List data) async {
    try {
      // Convert raw bytes to 16-bit PCM frames
      final samples = Int16List.view(data.buffer);
      await FlutterPcmSound.feed(
        PcmArrayInt16(bytes: samples.buffer.asByteData()),
      );
    } catch (e) {
      debugPrint('Audio playback error: $e');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _pongController.close();
    disconnect(notify: false);
    super.dispose();
  }
}
