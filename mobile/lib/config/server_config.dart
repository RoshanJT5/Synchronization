/// Central server configuration for Synchronization.
///
/// The app connects to the Cloudflare signaling proxy, which automatically
/// routes to the GCP VM (primary) or Render free tier (fallback).
/// Nothing else in the codebase should hardcode a server URL.
class ServerConfig {
  /// Cloudflare signaling proxy — smart router between VM and Render fallback.
  static const String primaryServer = 'https://sync.synchronizationpro.app';

  /// The active signaling server URL used by the entire app.
  static String get signalingServer => primaryServer;

  /// The active server host (without scheme/port) used for deep link validation.
  static String get signalingHost => Uri.parse(signalingServer).host;
}
