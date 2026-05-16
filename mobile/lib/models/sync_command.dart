import 'dart:convert';

enum SyncAction { play, pause, seek, syncCheck, syncResponse, streamReady }

class SyncCommand {
  const SyncCommand({
    required this.action,
    required this.positionMs,
    required this.sentAtMs,
    this.streamUrl,
  });

  final SyncAction action;
  final int positionMs;
  final int sentAtMs;
  final String? streamUrl;

  String toJson() => jsonEncode({
        'action': action.name,
        'positionMs': positionMs,
        'sentAtMs': sentAtMs,
        if (streamUrl != null) 'streamUrl': streamUrl,
      });

  factory SyncCommand.fromJson(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return SyncCommand(
      action: SyncAction.values.byName(map['action'] as String),
      positionMs: ((map['positionMs'] ?? 0) as num).toInt(),
      sentAtMs: ((map['sentAtMs'] ?? DateTime.now().millisecondsSinceEpoch)
              as num)
          .toInt(),
      streamUrl: map['streamUrl'] as String?,
    );
  }
}
