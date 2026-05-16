import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:just_audio/just_audio.dart';
import 'package:synchronization/models/sync_command.dart';

class GuestSessionController extends ChangeNotifier {
  static const int maxDriftMs = 1000;

  final AudioPlayer _player = AudioPlayer();
  RTCDataChannel? _hostChannel;
  bool _isLoaded = false;
  String? _streamUrl;

  Stream<Duration> get positionStream => _player.positionStream;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  bool get isPlaying => _player.playing;
  bool get isLoaded => _isLoaded;
  String? get streamUrl => _streamUrl;

  void setHostChannel(RTCDataChannel channel) {
    _hostChannel = channel;
    channel.onMessage = (message) => _handleHostCommand(message.text);
  }

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 1.0));
  }

  Future<void> _handleHostCommand(String raw) async {
    try {
      final command = SyncCommand.fromJson(raw);
      final transitMs =
          DateTime.now().millisecondsSinceEpoch - command.sentAtMs;

      switch (command.action) {
        case SyncAction.streamReady:
          if (command.streamUrl != null) {
            await _connectToStream(command.streamUrl!);
          }
          break;
        case SyncAction.play:
          if (!_isLoaded) break;
          await _player.seek(
            Duration(milliseconds: command.positionMs + transitMs),
          );
          await _player.play();
          break;
        case SyncAction.pause:
          if (!_isLoaded) break;
          await _player.pause();
          await _player.seek(Duration(milliseconds: command.positionMs));
          break;
        case SyncAction.seek:
          if (!_isLoaded) break;
          await _player.seek(Duration(milliseconds: command.positionMs));
          break;
        case SyncAction.syncCheck:
          if (!_isLoaded) break;
          final expectedMs = command.positionMs + transitMs;
          final actualMs = _player.position.inMilliseconds;
          final drift = (actualMs - expectedMs).abs();
          _sendToHost(SyncCommand(
            action: SyncAction.syncResponse,
            positionMs: actualMs,
            sentAtMs: DateTime.now().millisecondsSinceEpoch,
          ));
          if (drift > maxDriftMs) {
            await _player.seek(Duration(milliseconds: expectedMs));
            if (!_player.playing) await _player.play();
          }
          break;
        case SyncAction.syncResponse:
          break;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Guest command error: $e');
    }
  }

  Future<void> _connectToStream(String url) async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.music());
    _streamUrl = url;
    await _player.setUrl(url);
    _isLoaded = true;
    notifyListeners();
  }

  void _sendToHost(SyncCommand command) {
    final channel = _hostChannel;
    if (channel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      channel!.send(RTCDataChannelMessage(command.toJson()));
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
