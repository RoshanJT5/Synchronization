import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// Handles deep links in the format:
/// syncronization://connect?id=SESSION_ID&server=http://192.168.1.5:3001
class DeepLinkService {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;

  /// Called when a deep link is received with a session ID and server URL.
  void Function(String sessionId, String serverUrl)? onDeepLink;

  /// Start listening for incoming deep links.
  Future<void> init() async {
    // Handle the initial link that launched the app
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleUri(initialUri);
      }
    } catch (e) {
      debugPrint('[DeepLink] Error getting initial link: $e');
    }

    // Listen for subsequent links while app is running
    _subscription = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (error) {
        debugPrint('[DeepLink] Stream error: $error');
      },
    );
  }

  void _handleUri(Uri uri) {
    debugPrint('[DeepLink] Received URI: $uri');

    // Expected: syncronization://connect?id=XXXX&server=http://...
    if (uri.scheme == 'syncronization' && uri.host == 'connect') {
      final sessionId = uri.queryParameters['id'];
      final serverUrl =
          uri.queryParameters['server'] ?? 'http://localhost:3001';

      if (sessionId != null && sessionId.isNotEmpty) {
        debugPrint(
          '[DeepLink] Session: $sessionId, Server: $serverUrl',
        );
        onDeepLink?.call(sessionId.toUpperCase(), serverUrl);
      }
    }
  }

  void dispose() {
    _subscription?.cancel();
  }
}
