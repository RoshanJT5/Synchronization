import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:synchronization/services/playback_buffer.dart';
import 'package:synchronization/services/clock_sync_service.dart';
import 'package:synchronization/services/sync_playback_engine.dart';

enum AppConnectionState {
  idle,
  connecting,
  connected,
  reconnecting,
  error
}

enum ConnectionQuality { excellent, good, poor, unknown }

class WebRTCService extends ChangeNotifier {
  static const String _signalingServer = 'https://synchronization-807q.onrender.com';
  
  io.Socket? _socket;
  RTCPeerConnection? _pc;
  RTCDataChannel? _dataChannel;
  PlaybackBuffer? _playbackBuffer;
  late ClockSyncService _syncClock;
  late SyncPlaybackEngine _syncEngine;
  
  AppConnectionState _state = AppConnectionState.idle;
  String _errorMessage = '';
  String _activeSessionId = '';
  bool _isDisposed = false;
  bool _isWaitingForHost = false;
  bool _isPaused = false;
  double _volume = 1.0;
  
  Timer? _connectionTimeoutTimer;
  Timer? _waitingForHostTimer;
  Timer? _disconnectGraceTimer;

  final StreamController<int> _pongController = StreamController<int>.broadcast();

  // Getters
  AppConnectionState get state => _state;
  String get errorMessage => _errorMessage;
  bool get isWaitingForHost => _isWaitingForHost;
  bool get isPaused => _isPaused;
  ClockSyncService get clockSync => _syncClock;
  SyncPlaybackEngine get syncEngine => _syncEngine;
  double get volume => _volume;
  String get activeSessionId => _activeSessionId;
  bool get isSynced => _playbackBuffer != null && _playbackBuffer!.currentDriftMs.abs() < 50;
  
  void setVolume(double v) {
    _volume = v.clamp(0.0, 1.0);
    notifyListeners();
  }
  
  ConnectionQuality get connectionQuality {
    if (_state != AppConnectionState.connected) return ConnectionQuality.unknown;
    final jitter = _syncClock.emaJitterMs;
    if (jitter < 15) return ConnectionQuality.excellent;
    if (jitter < 40) return ConnectionQuality.good;
    return ConnectionQuality.poor;
  }
  
  // Stats for UI
  double get currentDriftMs => _playbackBuffer?.currentDriftMs ?? 0;
  int get bufferSize => _playbackBuffer?.bufferSize ?? 0;
  String get syncStats => _playbackBuffer?.getDebugInfo() ?? '';

  WebRTCService() {
    _syncClock = ClockSyncService();
    _syncEngine = SyncPlaybackEngine();
  }

  Future<void> connect(String shareCode, [String? serverUrl]) async {
    if (_state == AppConnectionState.connected) return;
    
    final url = serverUrl ?? _signalingServer;
    _activeSessionId = shareCode;
    _setState(AppConnectionState.connecting);
    _isWaitingForHost = false;

    try {
      _socket = io.io(url, io.OptionBuilder()
        .setTransports(['websocket', 'polling'])
        .disableAutoConnect()
        .build());

      _socket!.onConnect((_) {
        debugPrint('[WebRTC] Socket connected, joining room: $shareCode');
        _socket!.emit('join-session', shareCode);
        
        _waitingForHostTimer?.cancel();
        _waitingForHostTimer = Timer(const Duration(seconds: 5), () {
          if (_state == AppConnectionState.connecting && _pc == null) {
            _isWaitingForHost = true;
            notifyListeners();
          }
        });
      });

      _socket!.on('offer', (data) async {
        debugPrint('[WebRTC] Received offer from extension');
        await _handleOffer(data['offer'], data['fromId']);
      });

      _socket!.on('ice-candidate', (data) async {
        if (_pc != null) {
          await _pc!.addCandidate(RTCIceCandidate(
            data['candidate']['candidate'],
            data['candidate']['sdpMid'],
            data['candidate']['sdpMLineIndex'],
          ));
        }
      });

      _socket!.onDisconnect((_) {
        debugPrint('[WebRTC] Socket disconnected');
        if (!_isDisposed && _state == AppConnectionState.connected) {
          _setState(AppConnectionState.reconnecting);
        }
      });

      _socket!.connect();

      _connectionTimeoutTimer = Timer(const Duration(seconds: 25), () {
        if (_state == AppConnectionState.connecting) {
          _setError('Connection timed out. Extension might be offline.');
        }
      });

    } catch (e) {
      _setError(e.toString());
    }
  }

  Future<void> _handleOffer(dynamic offerData, String fromId) async {
    _waitingForHostTimer?.cancel();
    _isWaitingForHost = false;

    _pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ]
    });

    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _socket?.emit('ice-candidate', {
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
          'toId': fromId,
        });
      }
    };

    _pc!.onConnectionState = (state) {
      debugPrint('[WebRTC] Connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _setState(AppConnectionState.connected);
        _connectionTimeoutTimer?.cancel();

        _playbackBuffer = PlaybackBuffer(_syncClock);
        _playbackBuffer!.start((audioData) async {
          await _playAudioChunk(Uint8List.fromList(audioData));
        });
        _syncEngine.startMonitoring(_syncClock);
        _startPositionReporting();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _setError('WebRTC connection failed');
      }
    };

    _pc!.onDataChannel = (channel) {
      if (channel.label == 'clock-sync') {
        _dataChannel = channel;
        _dataChannel!.onMessage = (message) {
          _handleDataMessage(message.text);
        };
      }
    };

    await _pc!.setRemoteDescription(RTCSessionDescription(offerData['sdp'], offerData['type']));
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);

    _socket?.emit('answer', {
      'answer': {'sdp': answer.sdp, 'type': answer.type},
      'toId': fromId,
    });
  }

  void _handleDataMessage(String text) {
    try {
      final msg = jsonDecode(text);
      
      // Clock sync ping/pong
      if (msg['t'] != null) {
        if (msg['r'] != null) {
          // pong from source
          _syncClock.handlePong(msg['t'], msg['r']);
        } else {
          // ping from source, echo back
          sendDataChannelMessage({'t': msg['t'], 'r': DateTime.now().millisecondsSinceEpoch});
        }
        return;
      }

      if (msg['type'] == 'audio') {
        final List<dynamic> audioData = msg['audioData'];
        final int chunkId = msg['chunkId'];
        final int timestamp = msg['playbackTimestamp'];
        
        _playbackBuffer?.addChunk(
          Uint8List.fromList(audioData.cast<int>()),
          chunkId,
          timestamp,
        );
      } else if (msg['type'] == 'sync-config') {
        _syncEngine.applySourceConfig(bufferMs: (msg['bufferMs'] as num).toDouble());
      } else if (msg['type'] == 'wait_at_checkpoint') {
        _playbackBuffer?.setCheckpoint(msg['checkpoint']);
      } else if (msg['type'] == 'resume') {
        _playbackBuffer?.resume();
      }
    } catch (e) {
      debugPrint('Data channel error: $e');
    }
  }

  void _startPositionReporting() {
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_isDisposed || _state != AppConnectionState.connected) {
        timer.cancel();
        return;
      }
      if (_playbackBuffer != null) {
        sendDataChannelMessage({
          'type': 'position_report',
          'currentChunkId': _playbackBuffer!.lastPlayedChunkId,
          't': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });
  }

  void sendDataChannelMessage(Map<String, dynamic> msg) {
    if (_dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      _dataChannel!.send(RTCDataChannelMessage(jsonEncode(msg)));
    }
  }

  void disconnect({bool notify = true}) {
    debugPrint('[WebRTC] Disconnecting...');
    
    _connectionTimeoutTimer?.cancel();
    _waitingForHostTimer?.cancel();
    _disconnectGraceTimer?.cancel();
    
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    
    _pc?.close();
    _pc = null;
    
    _syncEngine.stopMonitoring();
    _dataChannel = null;
    _playbackBuffer?.stop();
    _playbackBuffer = null;
    
    if (notify) _setState(AppConnectionState.idle);
  }

  Future<void> _playAudioChunk(Uint8List data) async {
    try {
      final samples = Int16List.view(data.buffer);
      
      // Manual volume scaling if volume < 1.0
      if (_volume < 0.99) {
        for (int i = 0; i < samples.length; i++) {
          samples[i] = (samples[i] * _volume).toInt();
        }
      }
      
      await FlutterPcmSound.feed(PcmArrayInt16(bytes: samples.buffer.asByteData()));
    } catch (e) {
      debugPrint('Audio playback error: $e');
    }
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
    _pongController.close();
    disconnect(notify: false);
    super.dispose();
  }
}
