import 'dart:convert';

enum SyncAction {
  play,
  pause,
  seek,
  syncCheck,
  syncResponse,
  streamReady,
  /// Host → Guest: requests a pong for RTT calibration.
  ping,
  /// Guest → Host: answers a ping for RTT calibration.
  pong,
}

class SyncCommand {
  const SyncCommand({
    required this.action,
    required this.positionMs,
    required this.sentAtMs,
    this.streamUrl,
    this.pingId,
    this.hostClockMs,
  });

  final SyncAction action;
  final int positionMs;
  final int sentAtMs;
  final String? streamUrl;
  /// Monotonic ping counter used for RTT calibration.
  final int? pingId;
  /// Host wall-clock ms included in syncCheck so guest can compute offset.
  final int? hostClockMs;

  String toJson() => jsonEncode({
        'action': action.name,
        'positionMs': positionMs,
        'sentAtMs': sentAtMs,
        if (streamUrl != null) 'streamUrl': streamUrl,
        if (pingId != null) 'pingId': pingId,
        if (hostClockMs != null) 'hostClockMs': hostClockMs,
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
      pingId: (map['pingId'] as num?)?.toInt(),
      hostClockMs: (map['hostClockMs'] as num?)?.toInt(),
    );
  }
}
