import 'dart:async';
import 'package:flutter/foundation.dart';
import 'clock_sync_service.dart';

/// Sync mode setting exposed to the UI.
enum SyncMode {
  /// Disabled — audio plays immediately with no added buffer.
  off,

  /// Low-latency mode — small buffer (~100 ms extra) for minimal delay.
  lowLatency,

  /// Balanced mode — 300 ms buffer (default, good sync for music/movies).
  balanced,

  /// Stability mode — 500 ms buffer for best sync on poor networks.
  stability,
}

extension SyncModeExt on SyncMode {
  String get label => switch (this) {
        SyncMode.off => 'Off',
        SyncMode.lowLatency => 'Low Latency',
        SyncMode.balanced => 'Balanced',
        SyncMode.stability => 'Stability',
      };

  String get description => switch (this) {
        SyncMode.off => 'Audio plays immediately — no sync correction.',
        SyncMode.lowLatency => '~100 ms extra buffer, minimal extra delay.',
        SyncMode.balanced => '~300 ms buffer — good for music & movies.',
        SyncMode.stability => '~500 ms buffer — best sync on poor networks.',
      };

  /// Extra buffer (ms) this mode adds on top of the measured network latency.
  double get extraBufferMs => switch (this) {
        SyncMode.off => 0,
        SyncMode.lowLatency => 100,
        SyncMode.balanced => 300,
        SyncMode.stability => 500,
      };
}

/// Quality of the current synchronisation based on jitter.
enum SyncQuality { synced, drifting, syncing }

extension SyncQualityExt on SyncQuality {
  String get label => switch (this) {
        SyncQuality.synced => 'SYNCED',
        SyncQuality.drifting => 'DRIFTING',
        SyncQuality.syncing => 'SYNCING…',
      };
}

/// Manages receiver-side playback buffering for synchronised audio output.
///
/// ### How it works
///
/// WebRTC delivers audio via [RTCVideoRenderer] → hardware pipeline directly.
/// Flutter / flutter_webrtc does **not** expose a Web Audio API on mobile, so
/// we cannot insert a browser-style DelayNode into the native render path.
///
/// Instead, [SyncPlaybackEngine] acts as a **metadata orchestrator**:
///
/// 1.  It reads the measured one-way latency + jitter from [ClockSyncService].
/// 2.  It computes a [recommendedBufferMs] that the source device should apply
///     (transmitted via the clock-sync data channel as a `sync-config` message,
///     which the extension's local monitor delay node then matches).
/// 3.  It continuously monitors jitter and updates [syncQuality].
/// 4.  It notifies listeners so the UI can show real-time sync status.
///
/// The *actual* audio delay on the receiver is provided by the WebRTC jitter
/// buffer inside flutter_webrtc itself.  We influence this indirectly by:
///   - Advertising the desired buffer to the source so it delays its own
///     local speaker output to match what we receive.
///   - (Future) Adjusting the renderer's `jitterBufferDelay` if/when
///     flutter_webrtc exposes that API.
class SyncPlaybackEngine extends ChangeNotifier {
  SyncMode _mode = SyncMode.balanced;
  SyncQuality _syncQuality = SyncQuality.syncing;
  Timer? _monitorTimer;

  // Smooth exponential average of jitter for quality classification
  double _smoothJitter = 0.0;
  static const double _jitterAlpha = 0.2;

  // Last source-buffer config received from the source device (ms).
  // null = not yet received.
  double? _sourceBufferMs;

  SyncMode get mode => _mode;
  SyncQuality get syncQuality => _syncQuality;

  /// The total target buffer (ms) = mode's extra buffer + measured latency.
  double recommendedBufferMs(ClockSyncService clockSync) {
    if (_mode == SyncMode.off) return 0;
    return (_mode.extraBufferMs + clockSync.emaLatencyMs).clamp(0, 1000);
  }

  /// Buffer in seconds (for display / data-channel broadcast).
  double recommendedBufferSeconds(ClockSyncService clockSync) =>
      recommendedBufferMs(clockSync) / 1000.0;

  /// Buffer announced by the source (ms), or the locally computed value
  /// if the source hasn't sent a config yet.
  double effectiveBufferMs(ClockSyncService clockSync) =>
      _sourceBufferMs ?? recommendedBufferMs(clockSync);

  double? get sourceBufferMs => _sourceBufferMs;

  /// Call when the source broadcasts its buffer config via the data channel.
  void applySourceConfig({required double bufferMs}) {
    _sourceBufferMs = bufferMs;
    debugPrint('[SyncEngine] Source buffer: ${bufferMs.toStringAsFixed(0)} ms');
    notifyListeners();
  }

  /// Set playback mode from the UI.
  void setMode(SyncMode mode) {
    _mode = mode;
    _sourceBufferMs = null; // re-compute on next update
    notifyListeners();
  }

  /// Start monitoring clock-sync quality.  Call this when connected.
  void startMonitoring(ClockSyncService clockSync) {
    stopMonitoring();
    _smoothJitter = clockSync.emaJitterMs;
    _monitorTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _update(clockSync);
    });
  }

  void _update(ClockSyncService clockSync) {
    // Smooth jitter with EMA
    _smoothJitter = _jitterAlpha * clockSync.emaJitterMs +
        (1 - _jitterAlpha) * _smoothJitter;

    final newQuality = _classify(_smoothJitter);
    if (newQuality != _syncQuality) {
      _syncQuality = newQuality;
      notifyListeners();
    }
  }

  SyncQuality _classify(double jitterMs) {
    if (_mode == SyncMode.off) return SyncQuality.syncing;
    if (jitterMs < 10) return SyncQuality.synced;
    if (jitterMs < 30) return SyncQuality.drifting;
    return SyncQuality.syncing;
  }

  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _syncQuality = SyncQuality.syncing;
    _sourceBufferMs = null;
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}
