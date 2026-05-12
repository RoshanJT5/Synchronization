import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'clock_sync_service.dart';

class BufferedChunk {
  final int chunkId;
  final double playbackTimestamp; // Source clock milliseconds
  final List<int> audioData;

  BufferedChunk({
    required this.chunkId,
    required this.playbackTimestamp,
    required this.audioData,
  });
}

typedef PlaybackCallback = Future<void> Function(List<int> audioData);

class PlaybackBuffer {
  final ClockSyncService _clock;
  PlaybackCallback? _onPlay;
  final DoubleLinkedQueue<BufferedChunk> _queue = DoubleLinkedQueue();
  Timer? _ticker;
  bool _isRunning = false;
  int _lastPlayedChunkId = -1;
  int? _checkpointChunkId;
  bool _isPaused = false;
  bool _isFeeding = false; // Serialization lock

  // Drift Correction
  double _currentDriftMs = 0;
  double _driftCorrectionFactor = 0;

  int get lastPlayedChunkId => _lastPlayedChunkId;
  bool get isPaused => _isPaused;
  double get currentDriftMs => _currentDriftMs;
  int get bufferSize => _queue.length;

  // Stats for debugging
  int _totalChunksReceived = 0;
  int _totalChunksPlayed = 0;
  int _totalChunksDropped = 0;

  PlaybackBuffer(this._clock);

  /// Convenient way to add a chunk without manual BufferedChunk creation
  void addChunk(Uint8List data, int chunkId, int timestamp) {
    final chunk = BufferedChunk(
      chunkId: chunkId,
      playbackTimestamp: timestamp.toDouble(),
      audioData: data,
    );
    _addChunkInternal(chunk);
  }

  void _addChunkInternal(BufferedChunk chunk) {
    _totalChunksReceived++;

    // 1. Duplicate check
    if (chunk.chunkId <= _lastPlayedChunkId) return;

    // 2. Buffer capacity check
    if (_queue.length > 500) {
      _totalChunksDropped++;
      _queue.removeFirst();
    }

    // 3. Stale chunk check
    final now = _clock.syncedNow();
    if (chunk.playbackTimestamp < now - 1000 && !_isPaused) {
      _totalChunksDropped++;
      return;
    }

    // Insert into queue sorted by playbackTimestamp
    // Optimization: find insertion point instead of full sort
    _queue.add(chunk);
    final list = _queue.toList();
    list.sort((a, b) => a.playbackTimestamp.compareTo(b.playbackTimestamp));
    _queue.clear();
    _queue.addAll(list);
  }

  void setCheckpoint(int chunkId) {
    _checkpointChunkId = chunkId;
  }

  void start(PlaybackCallback onPlay) {
    if (_isRunning) return;
    _isRunning = true;
    _onPlay = onPlay;

    _ticker = Timer.periodic(const Duration(milliseconds: 5), (_) async {
      if (_isPaused || _isFeeding || _queue.isEmpty || _onPlay == null) return;

      final now = _clock.syncedNow();
      final next = _queue.first;

      _currentDriftMs = now - next.playbackTimestamp;
      if (_currentDriftMs.abs() > 30) {
        _driftCorrectionFactor = _currentDriftMs > 0 ? 1.0 : -1.0;
      } else {
        _driftCorrectionFactor = 0;
      }

      if (_checkpointChunkId != null && next.chunkId >= _checkpointChunkId!) {
        _isPaused = true;
        _checkpointChunkId = null;
        return;
      }

      if (next.playbackTimestamp <= now + _driftCorrectionFactor) {
        _isFeeding = true; 
        try {
          _queue.removeFirst();
          _lastPlayedChunkId = next.chunkId;
          _totalChunksPlayed++;
          await _onPlay!(next.audioData); 
        } catch (e) {
          // Silent catch to prevent loop crash
        } finally {
          _isFeeding = false;
        }
      }
    });
  }

  void resume() {
    _isPaused = false;
    _checkpointChunkId = null;
  }

  void stop() {
    _isRunning = false;
    _ticker?.cancel();
    _queue.clear();
    _lastPlayedChunkId = -1;
    _onPlay = null;
  }

  String getDebugInfo() {
    return 'RX:$_totalChunksReceived PL:$_totalChunksPlayed DR:$_totalChunksDropped Q:${_queue.length} DRIFT:${_currentDriftMs.toStringAsFixed(1)}ms';
  }
}
