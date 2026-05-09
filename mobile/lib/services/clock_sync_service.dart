import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Implements a lightweight NTP-style clock synchronisation over a WebRTC
/// data channel labelled "clock-sync".
///
/// Protocol (sender = Chrome extension, receiver = this app):
///   Sender → { "t": <sender_ms> }          every 500 ms
///   Receiver → { "t": <sender_ms>, "r": <receiver_ms> }   echo
///
/// From the sender's perspective:
///   RTT = now - t
///   one_way_latency ≈ RTT / 2
///
/// From the receiver's perspective (this class):
///   We receive { t } at local time r.
///   Estimated one-way latency = last known RTT / 2  (updated via stats).
///   Clock offset = r - t - one_way_latency
///   → positive offset means our clock is ahead of the sender's.
///
/// The [playbackDelay] getter returns the number of milliseconds the mobile
/// audio renderer should buffer ahead to absorb jitter and stay in sync.
class ClockSyncService extends ChangeNotifier {
  RTCDataChannel? _channel;
  Timer? _statsTimer;

  // Exponential moving average of one-way latency (ms)
  double _emaLatency = 40.0; // start with a 40 ms prior
  static const double _alpha = 0.15; // EMA smoothing factor

  // Jitter: EMA of |latency - emaLatency|
  double _emaJitter = 5.0;

  // How many samples we have collected
  int _sampleCount = 0;

  double get emaLatencyMs => _emaLatency;
  double get emaJitterMs => _emaJitter;

  /// Recommended playback buffer in milliseconds.
  /// = latency + 2× jitter, clamped to [20, 200] ms.
  double get playbackDelayMs =>
      (_emaLatency + 2 * _emaJitter).clamp(20.0, 200.0);

  /// Attach to the data channel opened by the extension.
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
      final senderT = (data['t'] as num).toDouble();
      final receiverR = DateTime.now().millisecondsSinceEpoch.toDouble();

      // Echo back so the sender can compute RTT
      if (_channel?.state == RTCDataChannelState.RTCDataChannelOpen) {
        _channel!.send(RTCDataChannelMessage(
          jsonEncode({'t': senderT, 'r': receiverR}),
        ));
      }

      // We can't compute one-way latency without knowing the sender's clock
      // relative to ours. Instead we use the RTT reported by WebRTC stats
      // (updated by WebRTCService) as a proxy. Here we just track the
      // inter-arrival jitter: variance in the gap between consecutive messages.
      _sampleCount++;
      if (_sampleCount > 1) {
        // Use the gap between sender timestamps as a jitter proxy
        // (if sender sends every 500ms, deviation from 500ms = jitter)
        final gap = receiverR - (_lastReceiverR ?? receiverR);
        final expectedGap = 500.0;
        final deviation = (gap - expectedGap).abs();
        _emaJitter = _alpha * deviation + (1 - _alpha) * _emaJitter;
        notifyListeners();
      }
      _lastReceiverR = receiverR;
    } catch (e) {
      debugPrint('[ClockSync] Parse error: $e');
    }
  }

  double? _lastReceiverR;

  /// Update the latency estimate from WebRTC stats RTT.
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
  }

  @override
  void dispose() {
    detach();
    super.dispose();
  }
}
