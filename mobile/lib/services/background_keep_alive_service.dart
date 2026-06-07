import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// ---------------------------------------------------------------------------
/// BackgroundKeepAliveService
/// ---------------------------------------------------------------------------
/// Bridges Flutter to the native Android Foreground Service that keeps the
/// app alive when the screen is off.
///
/// **How it works (the Spotify approach):**
///
///  1.  When a session starts, [start] is called.
///  2.  It invokes the native `SyncForegroundService` via a MethodChannel.
///  3.  The native service:
///      - Shows a persistent notification ("Audio session is active")
///      - Acquires a PARTIAL_WAKE_LOCK (CPU on, screen off)
///      - Declares foregroundServiceType=mediaPlayback
///  4.  Android now treats this app as an active media app and will NOT
///      kill it under Doze mode — even with screen off for hours.
///  5.  A backup Dart-side heartbeat timer runs every 4 minutes as an
///      additional safety net to keep the Dart isolate active.
///  6.  On first session start, the service checks battery optimization
///      and prompts the user to disable it (critical for Oppo/Vivo/Xiaomi).
///
/// **Public API (unchanged from before):**
/// ```dart
/// await BackgroundKeepAliveService.start();   // when session begins
/// await BackgroundKeepAliveService.stop();     // when session ends
/// ```
/// ---------------------------------------------------------------------------
class BackgroundKeepAliveService {
  BackgroundKeepAliveService._();

  static const _channel =
      MethodChannel('com.synchronization.app/foreground_service');

  static Timer? _keepAliveTimer;
  static bool _isRunning = false;
  static bool _batteryOptimizationChecked = false;

  /// Whether the keep-alive service is currently active.
  static bool get isRunning => _isRunning;

  // ── Start ─────────────────────────────────────────────────────────────────

  /// Start the foreground service and background keep-alive.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  static Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    // 1. Start the native Android foreground service.
    try {
      await _channel.invokeMethod('startForegroundService');
      debugPrint('[KeepAlive] Foreground service started');
    } catch (e) {
      debugPrint('[KeepAlive] Failed to start foreground service: $e');
    }

    // 2. Check battery optimization once per app launch.
    //    Shows the system "Allow background activity?" dialog if needed.
    if (!_batteryOptimizationChecked) {
      _batteryOptimizationChecked = true;
      _promptBatteryOptimizationIfNeeded();
    }

    // 3. Dart-side heartbeat timer (additional safety net).
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(
      const Duration(minutes: 4),
      (_) {
        debugPrint(
          '[KeepAlive] heartbeat at ${DateTime.now().toIso8601String()}',
        );
      },
    );

    debugPrint('[KeepAlive] Background keep-alive fully started');
  }

  // ── Stop ──────────────────────────────────────────────────────────────────

  /// Stop the foreground service and release all resources.
  static Future<void> stop() async {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _isRunning = false;

    try {
      await _channel.invokeMethod('stopForegroundService');
      debugPrint('[KeepAlive] Foreground service stopped');
    } catch (e) {
      debugPrint('[KeepAlive] Failed to stop foreground service: $e');
    }

    debugPrint('[KeepAlive] Background keep-alive fully stopped');
  }

  // ── Battery optimization ──────────────────────────────────────────────────

  /// Check if battery optimization is disabled for this app.
  static Future<bool> isBatteryOptimizationDisabled() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('isBatteryOptimizationDisabled');
      return result ?? false;
    } catch (e) {
      debugPrint('[KeepAlive] Failed to check battery optimization: $e');
      return false;
    }
  }

  /// Open the system dialog to disable battery optimization.
  static Future<void> requestDisableBatteryOptimization() async {
    try {
      await _channel.invokeMethod('requestDisableBatteryOptimization');
    } catch (e) {
      debugPrint('[KeepAlive] Failed to request battery opt disable: $e');
    }
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  /// Checks battery optimization status and shows the system prompt if
  /// the app is not yet exempt.  Runs once per app launch, non-blocking.
  static Future<void> _promptBatteryOptimizationIfNeeded() async {
    try {
      final isDisabled = await isBatteryOptimizationDisabled();
      if (!isDisabled) {
        debugPrint('[KeepAlive] Battery optimization is ON — prompting user');
        await requestDisableBatteryOptimization();
      } else {
        debugPrint('[KeepAlive] Battery optimization already disabled ✓');
      }
    } catch (e) {
      debugPrint('[KeepAlive] Battery optimization check failed: $e');
    }
  }
}
