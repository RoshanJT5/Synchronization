import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// ---------------------------------------------------------------------------
/// LocationService
/// ---------------------------------------------------------------------------
/// Provides GPS coordinates for the 50-metre session proximity filter.
///
/// **Why this is mandatory:**
/// Without GPS the signaling server cannot filter sessions by proximity —
/// a user anywhere in the world would see your session. To keep the app
/// working as designed (same-room only), location permission is required.
///
/// **Usage:**
/// ```dart
/// // On app start — gates the entire app
/// final ok = await LocationService.checkAndRequest();
/// if (!ok) { showBlockingScreen(); return; }
///
/// // When hosting or discovering sessions
/// final pos = await LocationService.getPosition();
/// // pos is null only if called before permission was granted
/// ```
/// ---------------------------------------------------------------------------
class LocationService {
  LocationService._();

  static Position? _cachedPosition;
  static bool _permissionGranted = false;

  /// Whether location permission has been granted in this session.
  static bool get permissionGranted => _permissionGranted;

  // ── Permission gate ────────────────────────────────────────────────────────

  /// Checks and requests location permission.
  ///
  /// Returns `true` if permission is granted (app can proceed).
  /// Returns `false` if the user denied — the app must block further use.
  static Future<bool> checkAndRequest() async {
    try {
      // 1. Is GPS hardware available at all?
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[Location] GPS hardware disabled on device');
        _permissionGranted = false;
        return false;
      }

      // 2. Check current permission status.
      LocationPermission permission = await Geolocator.checkPermission();

      // 3. If not yet asked, request now.
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      // 4. Permanently denied — must go to Settings manually.
      if (permission == LocationPermission.deniedForever) {
        debugPrint('[Location] Permission permanently denied');
        _permissionGranted = false;
        return false;
      }

      // 5. Still denied after the prompt.
      if (permission == LocationPermission.denied) {
        debugPrint('[Location] Permission denied by user');
        _permissionGranted = false;
        return false;
      }

      // 6. Granted (whileInUse or always).
      debugPrint('[Location] Permission granted ✓');
      _permissionGranted = true;
      return true;
    } catch (e) {
      debugPrint('[Location] checkAndRequest error: $e');
      _permissionGranted = false;
      return false;
    }
  }

  /// Open the device's app settings page so the user can manually enable
  /// location (called after `deniedForever`).
  static Future<void> openSettings() async {
    await Geolocator.openAppSettings();
  }

  // ── Position ───────────────────────────────────────────────────────────────

  /// Returns the current GPS position, or `null` on failure.
  ///
  /// Uses a cached position (refreshed every 30 seconds) to avoid
  /// hammering the GPS hardware on every socket emit.
  static Future<({double lat, double lng})?> getPosition() async {
    if (!_permissionGranted) {
      debugPrint('[Location] getPosition called without permission');
      return null;
    }

    try {
      // Return cached value if it's fresh (< 30 seconds old)
      if (_cachedPosition != null) {
        final age = DateTime.now().difference(
          _cachedPosition!.timestamp,
        );
        if (age.inSeconds < 30) {
          return (lat: _cachedPosition!.latitude, lng: _cachedPosition!.longitude);
        }
      }

      // Fetch a fresh position with a 10-second timeout.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _cachedPosition = pos;
      debugPrint('[Location] Position: ${pos.latitude}, ${pos.longitude}');
      return (lat: pos.latitude, lng: pos.longitude);
    } catch (e) {
      debugPrint('[Location] getPosition error: $e');
      // Return cached position if available, even if stale, as fallback
      if (_cachedPosition != null) {
        return (lat: _cachedPosition!.latitude, lng: _cachedPosition!.longitude);
      }
      return null;
    }
  }

  /// Clear the cached position (call after a long idle period).
  static void clearCache() {
    _cachedPosition = null;
  }
}
