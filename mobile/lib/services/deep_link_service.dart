import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// Handles two deep link formats:
///
/// 1. Custom scheme (fallback, from connect page):
///    syncronization://connect?id=SESSION_ID&server=https://...
///
/// 2. HTTPS App Link (preferred, Android intercepts QR scan directly):
///    https://syncronization.vercel.app/connect?id=SESSION_ID&server=https://...
///
/// Both carry the same query parameters — the handler is identical.
class DeepLinkService {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;

  /// Called when a valid deep link is received.
  void Function(String sessionId, String serverUrl)? onDeepLink;

  /// Start listening for incoming deep links.
  Future<void> init() async {
    // Handle the link that cold-started the app
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleUri(initialUri);
      }
    } catch (e) {
      debugPrint('[DeepLink] Error getting initial link: $e');
    }

    // Listen for links while the app is already running
    _subscription = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (error) => debugPrint('[DeepLink] Stream error: $error'),
    );
  }

  void _handleUri(Uri uri) {
    debugPrint('[DeepLink] Received URI: $uri');

    final bool isCustomScheme =
        uri.scheme == 'syncronization' && uri.host == 'connect';

    final bool isAppLink =
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host == 'syncronization.vercel.app' &&
        uri.path.startsWith('/connect');

    if (!isCustomScheme && !isAppLink) return;

    final sessionId = uri.queryParameters['id'];
    final serverUrl = uri.queryParameters['server'] ??
        'https://syncronization-server.onrender.com';

    if (sessionId != null && sessionId.isNotEmpty) {
      debugPrint('[DeepLink] Session: $sessionId  Server: $serverUrl');
      onDeepLink?.call(sessionId.toUpperCase(), serverUrl);
    }
  }

  void dispose() {
    _subscription?.cancel();
  }
}
