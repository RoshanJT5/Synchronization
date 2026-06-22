/// Central server configuration for Synchronization.
///
/// To switch servers, change [useBackup]:
///   - [useBackup] = false → uses the primary VM (http://34.68.33.91:3001)
///   - [useBackup] = true  → uses the Render backup (https://synchronization-807q.onrender.com)
///
/// Nothing else in the codebase should hardcode a server URL.
class ServerConfig {
  /// Primary signaling server — GCP VM.
  static const String primaryServer = 'http://34.68.33.91:3001';

  /// Backup signaling server — Render cloud (used during VM maintenance).
  static const String backupServer =
      'https://synchronization-807q.onrender.com';

  /// Set to [true] when the VM is down and Render should be used instead.
  static const bool useBackup = false;

  /// The active signaling server URL used by the entire app.
  static String get signalingServer =>
      useBackup ? backupServer : primaryServer;

  /// The active server host (without scheme/port) used for deep link validation.
  static String get signalingHost => Uri.parse(signalingServer).host;
}
