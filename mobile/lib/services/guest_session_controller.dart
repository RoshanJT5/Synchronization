import 'dart:async';
import 'dart:collection';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:just_audio/just_audio.dart';
import 'package:synchronization/models/sync_command.dart';

/// ---------------------------------------------------------------------------
/// GuestSessionController  —  Precision Sync Engine
/// ---------------------------------------------------------------------------
/// Inspired by AmpMe / SoundSeeSee / Rave sync architectures:
///
///  1.  **RTT calibration** (ping/pong) — computes median round-trip time and
///      derives one-way delay + clock offset between host and guest.
///  2.  **Smooth drift correction** — small drifts (< softSeekMs) are absorbed
///      by micro-adjusting playback speed (±5 %). Only large drifts trigger a
///      hard seek.
///  3.  **EMA drift filter** — exponential-moving-average filters out jitter
///      so individual noisy syncCheck samples don't cause unnecessary seeks.
///  4.  **Buffered stream load** — the guest pre-buffers the HTTP stream URL
///      before starting playback, preventing initial stutter.
/// ---------------------------------------------------------------------------
class GuestSessionController extends ChangeNotifier {
  // ── Sync tuning knobs ─────────────────────────────────────────────────────
  /// Drift above this triggers a hard seek (in ms).
  static const int hardSeekThresholdMs = 250;

  /// Drift below hardSeek but above this is corrected via speed adjustment.
  static const int softCorrectionMs = 40;

  /// How much to speed up / slow down for soft correction (5 %).
  static const double speedAdjustment = 0.05;

  /// Duration after a speed adjustment before reverting to 1.0×.
  static const int speedCorrectionWindowMs = 600;

  /// Maximum number of RTT samples kept for median calculation.
  static const int maxRttSamples = 20;

  /// EMA smoothing factor (0–1). Lower = smoother, slower reaction.
  static const double emaSmoothingFactor = 0.25;

  // ── State ─────────────────────────────────────────────────────────────────
  final AudioPlayer _player = AudioPlayer();
  RTCDataChannel? _hostChannel;
  bool _isLoaded = false;
  bool _hostIsPlaying = false;
  double _volume = 1.0;
  String? _streamUrl;
  SyncCommand? _pendingCommand;

  // RTT calibration
  final Queue<int> _rttSamples = Queue<int>();
  int _pingCounter = 0;
  int _lastPingSentAtMs = 0;
  int _clockOffsetMs = 0; // guestClock − hostClock (positive = guest ahead)

  // EMA filtered drift
  double _emaDriftMs = 0;

  // Speed correction state
  Timer? _speedResetTimer;

  // ── Public getters ────────────────────────────────────────────────────────
  Stream<Duration> get positionStream => _player.positionStream;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  bool get isPlaying => _player.playing;
  bool get isLoaded => _isLoaded;
  bool get hostIsPlaying => _hostIsPlaying;
  String? get streamUrl => _streamUrl;
  int get medianRttMs => _medianRtt();
  int get clockOffsetMs => _clockOffsetMs;
  double get filteredDriftMs => _emaDriftMs;

  void setHostChannel(RTCDataChannel channel) {
    _hostChannel = channel;
    channel.onMessage = (message) => _handleHostCommand(message.text);
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _player.setVolume(_volume);
  }

  // ── RTT calibration ──────────────────────────────────────────────────────

  /// Compute median RTT from collected samples.
  int _medianRtt() {
    if (_rttSamples.isEmpty) return 0;
    final sorted = _rttSamples.toList()..sort();
    return sorted[sorted.length ~/ 2];
  }

  /// Estimated one-way delay (half median RTT).
  int get _oneWayDelayMs => (_medianRtt() / 2).round();

  void _handlePing(SyncCommand command) {
    // Immediately pong back with the same pingId.
    _sendToHost(SyncCommand(
      action: SyncAction.pong,
      positionMs: 0,
      sentAtMs: DateTime.now().millisecondsSinceEpoch,
      pingId: command.pingId,
    ));
  }

  void _handlePong(SyncCommand command) {
    final rtt = DateTime.now().millisecondsSinceEpoch - _lastPingSentAtMs;
    if (rtt >= 0 && rtt < 5000) {
      _rttSamples.addLast(rtt);
      while (_rttSamples.length > maxRttSamples) {
        _rttSamples.removeFirst();
      }
      // Re-derive clock offset: hostClock ≈ guestClock − offset
      // offset = guestNow − (hostSentAt + oneWayDelay)
      _clockOffsetMs = DateTime.now().millisecondsSinceEpoch -
          (command.sentAtMs + _oneWayDelayMs);
    }
  }

  /// Send a ping to the host to measure RTT.
  void sendPing() {
    _pingCounter++;
    _lastPingSentAtMs = DateTime.now().millisecondsSinceEpoch;
    _sendToHost(SyncCommand(
      action: SyncAction.ping,
      positionMs: 0,
      sentAtMs: _lastPingSentAtMs,
      pingId: _pingCounter,
    ));
  }

  // ── Command handler ──────────────────────────────────────────────────────

  Future<void> _handleHostCommand(String raw) async {
    try {
      final command = SyncCommand.fromJson(raw);

      switch (command.action) {
        case SyncAction.ping:
          _handlePing(command);
          return; // pings don't need notifyListeners
        case SyncAction.pong:
          _handlePong(command);
          return;
        case SyncAction.streamReady:
          if (command.streamUrl != null) {
            final transitMs = _estimateOneWayDelay(command);
            await _connectToStream(
              command.streamUrl!,
              initialPositionMs: command.positionMs + transitMs,
            );
          }
          break;
        case SyncAction.play:
          if (!_isLoaded) {
            _pendingCommand = command;
            break;
          }
          _hostIsPlaying = true;
          final transitMs = _estimateOneWayDelay(command);
          final targetMs = command.positionMs + transitMs;
          await _player.seek(Duration(milliseconds: targetMs));
          // Wait for seek to complete, then play to avoid glitch.
          await _player.play();
          break;
        case SyncAction.pause:
          if (!_isLoaded) {
            _pendingCommand = command;
            break;
          }
          _hostIsPlaying = false;
          await _player.pause();
          await _player.seek(Duration(milliseconds: command.positionMs));
          break;
        case SyncAction.seek:
          if (!_isLoaded) {
            _pendingCommand = command;
            break;
          }
          await _player.seek(Duration(milliseconds: command.positionMs));
          if (!_hostIsPlaying) await _player.pause();
          break;
        case SyncAction.syncCheck:
          if (!_isLoaded) break;
          _hostIsPlaying = true;
          await _correctDrift(command);
          break;
        case SyncAction.syncResponse:
          break;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Guest command error: $e');
    }
  }

  /// Estimate the one-way delay for a given command.
  /// If we have RTT calibration data, use half-RTT. Otherwise fall back to
  /// wall-clock difference (which is fragile but better than nothing).
  int _estimateOneWayDelay(SyncCommand command) {
    if (_rttSamples.isNotEmpty) {
      return _oneWayDelayMs;
    }
    // Fallback: raw wall-clock transit (host sentAt → guest now).
    final raw = DateTime.now().millisecondsSinceEpoch - command.sentAtMs;
    return raw.clamp(0, 500);
  }

  // ── Drift correction (AmpMe-style) ───────────────────────────────────────

  Future<void> _correctDrift(SyncCommand command) async {
    final transitMs = _estimateOneWayDelay(command);
    final expectedMs = command.positionMs + transitMs;
    final actualMs = _player.position.inMilliseconds;
    final rawDrift = actualMs - expectedMs; // positive = guest ahead

    // EMA filter: smooth out jitter.
    _emaDriftMs =
        emaSmoothingFactor * rawDrift + (1 - emaSmoothingFactor) * _emaDriftMs;

    final drift = _emaDriftMs.round();
    final absDrift = drift.abs();

    // Send sync response to host.
    _sendToHost(SyncCommand(
      action: SyncAction.syncResponse,
      positionMs: actualMs,
      sentAtMs: DateTime.now().millisecondsSinceEpoch,
    ));

    if (absDrift > hardSeekThresholdMs) {
      // ── Hard seek: drift is too large, snap to correct position.
      debugPrint('[Sync] Hard seek: drift=${drift}ms');
      await _player.seek(Duration(milliseconds: expectedMs));
      _emaDriftMs = 0; // Reset EMA after hard correction.
      if (!_player.playing) await _player.play();
    } else if (absDrift > softCorrectionMs) {
      // ── Soft correction: adjust playback speed to catch up / slow down.
      final targetSpeed =
          drift > 0 ? (1.0 - speedAdjustment) : (1.0 + speedAdjustment);
      await _player.setSpeed(targetSpeed);
      debugPrint('[Sync] Soft correct: drift=${drift}ms → speed=$targetSpeed');
      // Schedule speed reset back to 1.0× after correction window.
      _speedResetTimer?.cancel();
      _speedResetTimer = Timer(
        Duration(milliseconds: speedCorrectionWindowMs),
        () async {
          try {
            await _player.setSpeed(1.0);
          } catch (_) {}
        },
      );
      if (!_player.playing) await _player.play();
    } else {
      // ── In sync — ensure speed is normal.
      if (_player.speed != 1.0) {
        await _player.setSpeed(1.0);
      }
      if (!_player.playing) await _player.play();
    }
  }

  // ── Stream connection ────────────────────────────────────────────────────

  Future<void> _connectToStream(
    String url, {
    required int initialPositionMs,
  }) async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.music());
    await session.setActive(true);
    _streamUrl = url;
    await _player.setVolume(_volume);
    await _player.setUrl(
      url,
      initialPosition: Duration(
        milliseconds: initialPositionMs.clamp(0, 1 << 31),
      ),
    );
    _isLoaded = true;
    final pending = _pendingCommand;
    _pendingCommand = null;
    if (pending != null) {
      await _handleHostCommand(pending.toJson());
    }
    // Start RTT calibration pings once connected.
    _startCalibration();
    notifyListeners();
  }

  /// Send a burst of pings to calibrate RTT.
  void _startCalibration() {
    // Send 5 pings spaced 200ms apart for quick calibration.
    for (int i = 0; i < 5; i++) {
      Future<void>.delayed(Duration(milliseconds: i * 200), () {
        if (_hostChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
          sendPing();
        }
      });
    }
  }

  void _sendToHost(SyncCommand command) {
    final channel = _hostChannel;
    if (channel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      channel!.send(RTCDataChannelMessage(command.toJson()));
    }
  }

  @override
  void dispose() {
    _speedResetTimer?.cancel();
    _player.dispose();
    super.dispose();
  }
}
