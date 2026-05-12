import 'dart:async';
import 'dart:collection';
import 'sync_clock.dart';

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

class PlaybackBuffer {
  final SyncClock _clock;
  final Queue<BufferedChunk> _queue = Queue();
  Timer? _ticker;
  bool _isRunning = false;
  int _lastPlayedChunkId = -1;

  // Stats for debugging
  int _totalChunksReceived = 0;
  int _totalChunksPlayed = 0;
  int _totalChunksDropped = 0;

  PlaybackBuffer(this._clock);

  /// Add a received chunk to the buffer
  void addChunk(BufferedChunk chunk) {
    _totalChunksReceived++;

    // Drop if already played or too old (arrived more than 200ms late)
    final now = _clock.syncedNow();
    if (chunk.chunkId <= _lastPlayedChunkId) {
      return; // Duplicate, ignore
    }
    if (chunk.playbackTimestamp < now - 200) {
      _totalChunksDropped++;
      print('⚠️ Dropped late chunk ${chunk.chunkId} (${(now - chunk.playbackTimestamp).toStringAsFixed(0)}ms late)');
      return;
    }

    // Insert into queue sorted by playbackTimestamp
    final list = _queue.toList();
    list.add(chunk);
    list.sort((a, b) => a.playbackTimestamp.compareTo(b.playbackTimestamp));
    _queue.clear();
    _queue.addAll(list);
  }

  /// Begin playback loop. [onPlay] is called with audio data when it's time.
  void start(Function(List<int> audioData) onPlay) {
    if (_isRunning) return;
    _isRunning = true;

    // Check every 5ms whether any chunk's time has arrived
    _ticker = Timer.periodic(Duration(milliseconds: 5), (_) {
      final now = _clock.syncedNow();

      while (_queue.isNotEmpty) {
        final next = _queue.first;

        if (next.playbackTimestamp <= now) {
          _queue.removeFirst();
          _lastPlayedChunkId = next.chunkId;
          _totalChunksPlayed++;
          onPlay(next.audioData); // 🔊 Play this chunk
        } else {
          break; // Next chunk is scheduled in the future, stop for now
        }
      }
    });
  }

  void stop() {
    _isRunning = false;
    _ticker?.cancel();
    _queue.clear();
    _lastPlayedChunkId = -1;
  }

  /// How many chunks are waiting in buffer
  int get bufferSize => _queue.length;

  String get stats =>
    'Received: $_totalChunksReceived | Played: $_totalChunksPlayed | Dropped: $_totalChunksDropped | Queue: ${_queue.length}';
}
