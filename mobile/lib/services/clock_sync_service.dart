import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Implements a lightweight NTP-style clock synchronisation over a WebRTC
/// data channel labelled "clock-sync".
///
/// Protocol (sender = Chrome extension / mobile source, receiver = this app):
///   Sender → { "t": <sender_ms> }                       every 500 ms (ping)
///   Receiver → { "t": <sender_ms>, "r": <receiver_ms> } echo (pong)
///
/// Additionally, the sender may broadcast:
///   Sender → { "type": "sync-config", "bufferMs": <ms> }
///
/// From the receiver's perspective:
///   We receive { t } at local time r.
///   Estimated one-way latency = last known RTT / 2  (updated via stats).
///   Clock offset = r - t - one_way_latency
///   → positive offset means our clock is ahead of the sender's.
///
/// The [playbackDelayMs] getter returns the number of milliseconds the mobile
/// audio renderer should buffer ahead to absorb jitter and stay in sync.
class ClockSyncService extends ChangeNotifier {
  RTCDataChannel? _channel;
  Timer? _statsTimer;
  double _offsetMs = 0.0;

  // Exponential moving average of one-way latency (ms)
  double _emaLatency = 40.0; // start with a 40 ms prior
  static const double _alpha = 0.15; // EMA smoothing factor

  // Jitter: EMA of |latency - emaLatency|
  double _emaJitter = 5.0;

  // How many samples we have collected
  int _sampleCount = 0;

  // Source-advertised buffer (ms) — null until first sync-config received
  double? _sourceBufferMs;

  // Sequence number for ping messages
  int _pingSeq = 0;

  double get emaLatencyMs => _emaLatency;
  double get emaJitterMs => _emaJitter;

  /// Source-advertised playback buffer in ms, or null if not yet received.
  double? get sourceBufferMs => _sourceBufferMs;

  /// True once we have received a sync-config from the source.
  bool get hasSyncConfig => _sourceBufferMs != null;

  /// Recommended playback buffer in milliseconds.
  /// = latency + 2× jitter, clamped to [20, 500] ms.
  double get playbackDelayMs =>
      (_emaLatency + 2 * _emaJitter).clamp(20.0, 500.0);

  /// Attach to the data channel opened by the extension / mobile source.
  void attach(RTCDataChannel channel) {
    _channel = channel;
    _channel!.onMessage = (RTCDataChannelMessage msg) {
      _handleMessage(msg.text);
    };
    debugPrint('[ClockSync] Attached to data channel');
  }

  void _handleMessage(String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;

      // ── Handle sync-config broadcast from source ──────────────────────────
      if (data['type'] == 'sync-config') {
        final bufferMs = (data['bufferMs'] as num?)?.toDouble();
        if (bufferMs != null) {
          _sourceBufferMs = bufferMs;
          debugPrint(
              '[ClockSync] Received sync-config: bufferMs=${bufferMs.toStringAsFixed(0)}');
          notifyListeners();
        }
        return;
      }

      // ── Handle clock ping from source ─────────────────────────────────────
      final senderT = (data['t'] as num?)?.toDouble();
      if (senderT == null) return;

      final receiverR = DateTime.now().millisecondsSinceEpoch.toDouble();

      // Echo back so the sender can compute RTT
      if (_channel?.state == RTCDataChannelState.RTCDataChannelOpen) {
        _channel!.send(RTCDataChannelMessage(
          jsonEncode({'t': senderT, 'r': receiverR, 'seq': data['seq']}),
        ));
      }

      // Track inter-arrival jitter: variance in the gap between consecutive pings.
      _sampleCount++;
      if (_sampleCount > 1) {
        final gap = receiverR - (_lastReceiverR ?? receiverR);
        const expectedGap = 500.0; // sender sends every 500 ms
        final deviation = (gap - expectedGap).abs();
        _emaJitter = _alpha * deviation + (1 - _alpha) * _emaJitter;
        notifyListeners();
      }
      _lastReceiverR = receiverR;
    } catch (e) {
      debugPrint('[ClockSync] Parse error: $e');
    }
  }

  void handlePing(double senderT) {
    // We already handle this in _handleMessage if attached, 
    // but this allows manual use.
    // Logic: Sender T received at local R
  }

  void handlePong(double senderT, double receiverR) {
    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    final rtt = now - senderT;
    
    // NTP formula: offset = senderT - receiverR + (RTT / 2)
    // But we want: senderT = receiverR + offset
    _offsetMs = senderT - receiverR + (rtt / 2);
    
    updateRtt(rtt / 1000.0);
  }

  double syncedNow() {
    return DateTime.now().millisecondsSinceEpoch.toDouble() + _offsetMs;
  }

  double? _lastReceiverR;

  /// Update the latency estimate from WebRTC stats RTT (in seconds).
  void updateRtt(double rttSeconds) {
    final oneWayMs = (rttSeconds * 1000) / 2;
    _emaLatency = _alpha * oneWayMs + (1 - _alpha) * _emaLatency;
    notifyListeners();
  }

  void detach() {
    _channel = null;
    _statsTimer?.cancel();
    _statsTimer = null;
    _sampleCount = 0;
    _lastReceiverR = null;
    _emaLatency = 40.0;
    _emaJitter = 5.0;
    _sourceBufferMs = null;
    _pingSeq = 0;
  }

  @override
  void dispose() {
    detach();
    super.dispose();
  }
}
