import 'dart:async';

class SyncClock {
  double _offsetMs = 0.0;
  bool _isCalibrated = false;

  double get offsetMs => _offsetMs;
  bool get isCalibrated => _isCalibrated;

  /// Call once after WebRTC connection is established.
  /// [sendPing] should send a ping message to source via DataChannel.
  /// [pongStream] should emit source timestamps whenever a pong is received.
  Future<void> calibrate({
    required Function(int pingId) sendPing,
    required Stream<Map<String, dynamic>> pongStream,
  }) async {
    final offsets = <double>[];

    for (int i = 0; i < 5; i++) {
      final completer = Completer<double>();
      final int pingId = i;

      // Listen for matching pong
      late StreamSubscription sub;
      sub = pongStream.listen((pong) {
        if (pong['pingId'] == pingId && !completer.isCompleted) {
          completer.complete(pong['sourceTime'].toDouble());
          sub.cancel();
        }
      });

      final t1 = DateTime.now().millisecondsSinceEpoch.toDouble();
      sendPing(pingId);

      try {
        final sourceTime = await completer.future.timeout(Duration(seconds: 3));
        final t2 = DateTime.now().millisecondsSinceEpoch.toDouble();
        final rtt = t2 - t1;

        // NTP formula: offset = sourceTime - localTime - (RTT / 2)
        // This tells us: "source clock is X ms ahead of local clock"
        final offset = sourceTime - t1 - (rtt / 2);
        offsets.add(offset);

        print('Ping $i: RTT=${rtt.toStringAsFixed(1)}ms offset=${offset.toStringAsFixed(1)}ms');
      } catch (e) {
        print('Ping $i timed out, skipping');
        sub.cancel();
      }

      await Future.delayed(Duration(milliseconds: 200));
    }

    if (offsets.isEmpty) {
      print('Clock calibration failed, assuming 0 offset');
      _offsetMs = 0;
    } else {
      offsets.sort();
      _offsetMs = offsets[offsets.length ~/ 2]; // Use median to filter outliers
      print('Clock calibrated. Offset: ${_offsetMs.toStringAsFixed(2)}ms');
    }

    _isCalibrated = true;
  }

  /// Get current local time adjusted to match source clock
  double syncedNow() {
    return DateTime.now().millisecondsSinceEpoch.toDouble() + _offsetMs;
  }
}
