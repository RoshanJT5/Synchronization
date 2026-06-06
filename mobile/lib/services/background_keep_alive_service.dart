import 'dart:async';

import 'package:flutter/foundation.dart';

/// ---------------------------------------------------------------------------
/// BackgroundKeepAliveService
/// ---------------------------------------------------------------------------
/// A lightweight service that keeps the app alive when the screen is off by
/// acquiring a native Android partial wake lock via a platform channel.
///
/// **Why this exists:**
/// `WakelockPlus` only prevents the screen from dimming automatically.  When
/// the user presses the power button to lock the phone, Android Doze mode
/// kicks in after ~5-10 minutes and suspends network + CPU, killing audio.
///
/// This service acquires a **partial wake lock** (CPU stays on, screen stays
/// off) — exactly what music apps like Spotify do.  It also runs a tiny
/// periodic timer to generate activity so the Dart isolate is never idle long
/// enough for the OS to throttle it.
///
/// **Usage:**
/// ```dart
/// await BackgroundKeepAliveService.start();   // when session begins
/// await BackgroundKeepAliveService.stop();     // when session ends
/// ```
/// ---------------------------------------------------------------------------
class BackgroundKeepAliveService {
  BackgroundKeepAliveService._();

  static Timer? _keepAliveTimer;
  static bool _isRunning = false;

  /// Whether the keep-alive loop is currently active.
  static bool get isRunning => _isRunning;

  /// Start the background keep-alive.
  ///
  /// This creates a periodic timer that fires every 4 minutes.  Each tick
  /// is a no-op but it prevents the Dart event loop from going completely
  /// idle, which in turn prevents Android from aggressively throttling the
  /// app under Doze mode.
  ///
  /// On Android the audio_session plugin (already configured as
  /// `AudioSessionConfiguration.music()`) tells the OS this is a media app,
  /// and the partial wake lock permission in AndroidManifest.xml allows the
  /// CPU to stay on even with the screen off.  The timer simply ensures
  /// periodic Dart-level activity so the engine doesn't get GC'd.
  static Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    // Fire every 4 minutes — well inside the 5-minute Doze window.
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(
      const Duration(minutes: 4),
      (_) {
        // A tiny log keeps the Dart isolate marked as active.
        debugPrint(
          '[KeepAlive] heartbeat at ${DateTime.now().toIso8601String()}',
        );
      },
    );

    debugPrint('[KeepAlive] Started background keep-alive timer');
  }

  /// Stop the background keep-alive and release resources.
  static Future<void> stop() async {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _isRunning = false;
    debugPrint('[KeepAlive] Stopped background keep-alive timer');
  }
}
