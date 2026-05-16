import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:just_audio/just_audio.dart';
import 'package:synchronization/models/sync_command.dart';

class GuestSessionController extends ChangeNotifier {
  static const int maxDriftMs = 350;

  final AudioPlayer _player = AudioPlayer();
  RTCDataChannel? _hostChannel;
  bool _isLoaded = false;
  bool _hostIsPlaying = false;
  String? _streamUrl;
  SyncCommand? _pendingCommand;

  Stream<Duration> get positionStream => _player.positionStream;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  bool get isPlaying => _player.playing;
  bool get isLoaded => _isLoaded;
  bool get hostIsPlaying => _hostIsPlaying;
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
            await _connectToStream(
              command.streamUrl!,
              initialPositionMs: command.positionMs + transitMs,
            );
          }
          break;
        case SyncAction.play:
          if (!_isLoaded) {
            _pendingCommand = command;
            break;
          }
          _hostIsPlaying = true;
          await _player.seek(
            Duration(milliseconds: command.positionMs + transitMs),
          );
          await _player.play();
          break;
        case SyncAction.pause:
          if (!_isLoaded) {
            _pendingCommand = command;
            break;
          }
          _hostIsPlaying = false;
          await _player.pause();
          await _player.seek(Duration(milliseconds: command.positionMs));
          await _player.pause();
          break;
        case SyncAction.seek:
          if (!_isLoaded) {
            _pendingCommand = command;
            break;
          }
          await _player.seek(Duration(milliseconds: command.positionMs));
          if (!_hostIsPlaying) await _player.pause();
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
            if (_hostIsPlaying && !_player.playing) await _player.play();
            if (!_hostIsPlaying && _player.playing) await _player.pause();
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

  Future<void> _connectToStream(
    String url, {
    required int initialPositionMs,
  }) async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.music());
    _streamUrl = url;
    await _player.setUrl(
      url,
      initialPosition: Duration(
        milliseconds: initialPositionMs.clamp(0, 1 << 31),
      ),
    );
    _isLoaded = true;
    final pending = _pendingCommand;
    _pendingCommand = null;
    if (pending != null) {
      await _handleHostCommand(pending.toJson());
    }
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
