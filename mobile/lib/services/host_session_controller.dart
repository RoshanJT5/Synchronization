import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:synchronization/models/sync_command.dart';
import 'package:synchronization/services/host_media_player.dart';
import 'package:synchronization/services/network_service.dart';
import 'package:synchronization/services/stream_server.dart';
import 'package:video_player/video_player.dart';

class HostSessionController extends ChangeNotifier {
  final HostMediaPlayer _player = HostMediaPlayer();
  final StreamServer _streamServer = StreamServer();
  final NetworkService _networkService = NetworkService();
  final List<RTCDataChannel> _guestChannels = [];
  Timer? _syncTimer;
  SyncCommand? _lastPlaybackCommand;

  String? _streamUrl;   // full /stream URL (used by host for its own playback)
  String? _audioUrl;    // /audio URL sent to guests (always audio-only)
  PlatformFile? _file;

  Stream<Duration> get positionStream => _player.positionStream;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  bool get isPlaying => _player.isPlaying;
  bool get isVideoPlayback => _player.isVideoPlayback;
  VideoPlayerController? get videoController => _player.videoController;
  String? get streamUrl => _streamUrl;
  PlatformFile? get file => _file;
  int get guestCount => _guestChannels
      .where(
          (channel) => channel.state == RTCDataChannelState.RTCDataChannelOpen)
      .length;

  Future<String> setupSession(
    PlatformFile file, {
    HostPlaybackMode playbackMode = HostPlaybackMode.audioOnly,
  }) async {
    if (file.path == null) {
      throw Exception('Could not read selected file path.');
    }
    _file = file;
    final localIp = await _networkService.getLocalIP();
    if (localIp == null || localIp.isEmpty) {
      throw Exception(
        'Not connected to WiFi. Connect to WiFi or create a hotspot first.',
      );
    }

    _streamUrl = await _streamServer.start(file.path!, localIp);
    // Replace the host IP in the audio URL so guests can reach it.
    _audioUrl = _streamUrl?.replaceFirst('/stream', '/audio');
    await _player.loadFile(file.path!, mode: playbackMode);
    notifyListeners();
    return _streamUrl!;
  }

  void onGuestConnected(RTCDataChannel channel) {
    if (!_guestChannels.contains(channel)) _guestChannels.add(channel);
    channel.onMessage = (message) => _handleGuestMessage(message.text);
    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _guestChannels.remove(channel);
      }
      notifyListeners();
    };
    _sendStreamReady(channel);
    final last = _lastPlaybackCommand;
    if (last != null) {
      Future<void>.delayed(const Duration(milliseconds: 150), () {
        _sendToChannel(channel, last);
      });
    }
    notifyListeners();
  }

  Future<void> play() async {
    await _player.play();
    _broadcastPlayback(SyncCommand(
      action: SyncAction.play,
      positionMs: _player.position.inMilliseconds,
      sentAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
    notifyListeners();
  }

  Future<void> pause() async {
    await _player.pause();
    _broadcastPlayback(SyncCommand(
      action: SyncAction.pause,
      positionMs: _player.position.inMilliseconds,
      sentAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
    notifyListeners();
  }

  Future<void> seekTo(int positionMs) async {
    await _player.seekTo(positionMs);
    _broadcastPlayback(SyncCommand(
      action: SyncAction.seek,
      positionMs: positionMs,
      sentAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
    notifyListeners();
  }

  Future<void> setVolume(double volume) => _player.setVolume(volume);

  void startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_player.isPlaying) {
        _broadcast(SyncCommand(
          action: SyncAction.syncCheck,
          positionMs: _player.position.inMilliseconds,
          sentAtMs: DateTime.now().millisecondsSinceEpoch,
        ));
      }
    });
  }

  void _sendStreamReady(RTCDataChannel channel) {
    // Send the /audio URL to guests — they always play audio-only.
    final url = _audioUrl;
    if (url == null ||
        channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    _sendToChannel(
        channel,
        SyncCommand(
          action: SyncAction.streamReady,
          positionMs: _player.position.inMilliseconds,
          sentAtMs: DateTime.now().millisecondsSinceEpoch,
          streamUrl: url,
        ));
  }

  void _handleGuestMessage(String raw) {
    try {
      final command = SyncCommand.fromJson(raw);
      if (command.action != SyncAction.syncResponse) return;
      final drift =
          (_player.position.inMilliseconds - command.positionMs).abs();
      if (drift > 700) {
        _broadcast(SyncCommand(
          action: SyncAction.seek,
          positionMs: _player.position.inMilliseconds,
          sentAtMs: DateTime.now().millisecondsSinceEpoch,
        ));
      }
    } catch (e) {
      debugPrint('Error handling guest message: $e');
    }
  }

  void _broadcast(SyncCommand command) {
    final json = command.toJson();
    for (final channel in List<RTCDataChannel>.from(_guestChannels)) {
      if (channel.state == RTCDataChannelState.RTCDataChannelOpen) {
        channel.send(RTCDataChannelMessage(json));
      }
    }
  }

  void _broadcastPlayback(SyncCommand command) {
    _lastPlaybackCommand = command;
    _broadcast(command);

    // A short replay protects pause/seek/play from DataChannel open races and
    // transient packet loss around mobile network changes.
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      _broadcast(command);
    });
  }

  void _sendToChannel(RTCDataChannel channel, SyncCommand command) {
    if (channel.state == RTCDataChannelState.RTCDataChannelOpen) {
      channel.send(RTCDataChannelMessage(command.toJson()));
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _streamServer.stop();
    _player.dispose();
    _guestChannels.clear();
    super.dispose();
  }
}
