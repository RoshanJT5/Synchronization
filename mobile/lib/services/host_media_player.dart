import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

enum HostPlaybackMode { audioOnly, videoWithAudio }

class HostMediaPlayer {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final StreamController<Duration> _videoPositionController =
      StreamController<Duration>.broadcast();
  VideoPlayerController? _videoController;
  Timer? _videoPositionTimer;
  HostPlaybackMode _mode = HostPlaybackMode.audioOnly;
  bool _isLoaded = false;

  Stream<Duration> get positionStream =>
      _mode == HostPlaybackMode.videoWithAudio
          ? _videoPositionController.stream
          : _audioPlayer.positionStream;
  Duration get position => _mode == HostPlaybackMode.videoWithAudio
      ? _videoController?.value.position ?? Duration.zero
      : _audioPlayer.position;
  Duration? get duration => _mode == HostPlaybackMode.videoWithAudio
      ? _videoController?.value.duration
      : _audioPlayer.duration;
  bool get isPlaying => _mode == HostPlaybackMode.videoWithAudio
      ? _videoController?.value.isPlaying ?? false
      : _audioPlayer.playing;
  bool get isVideoPlayback => _mode == HostPlaybackMode.videoWithAudio;
  VideoPlayerController? get videoController => _videoController;

  Future<void> loadFile(
    String filePath, {
    HostPlaybackMode mode = HostPlaybackMode.audioOnly,
  }) async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.music());
    _mode = mode;
    _isLoaded = false;
    _stopVideoTicker();
    await _videoController?.dispose();
    _videoController = null;
    await _audioPlayer.stop();

    if (_mode == HostPlaybackMode.videoWithAudio) {
      final controller = VideoPlayerController.file(File(filePath));
      await controller.initialize();
      _videoController = controller;
      _startVideoTicker();
    } else {
      await _audioPlayer.setFilePath(filePath);
    }
    _isLoaded = true;
  }

  Future<void> play() async {
    if (!_isLoaded) return;
    if (_mode == HostPlaybackMode.videoWithAudio) {
      await _videoController?.play();
      return;
    }
    await _audioPlayer.play();
  }

  Future<void> pause() async {
    if (!_isLoaded) return;
    if (_mode == HostPlaybackMode.videoWithAudio) {
      await _videoController?.pause();
      return;
    }
    await _audioPlayer.pause();
  }

  Future<void> seekTo(int positionMs) async {
    if (!_isLoaded) return;
    final position = Duration(milliseconds: positionMs.clamp(0, 1 << 31));
    if (_mode == HostPlaybackMode.videoWithAudio) {
      await _videoController?.seekTo(position);
      _videoPositionController.add(this.position);
      return;
    }
    await _audioPlayer.seek(position);
  }

  Future<void> setVolume(double volume) async {
    final value = volume.clamp(0.0, 1.0);
    if (_mode == HostPlaybackMode.videoWithAudio) {
      await _videoController?.setVolume(value);
      return;
    }
    await _audioPlayer.setVolume(value);
  }

  void _startVideoTicker() {
    _videoPositionTimer =
        Timer.periodic(const Duration(milliseconds: 250), (_) {
      final position = _videoController?.value.position;
      if (position != null && !_videoPositionController.isClosed) {
        _videoPositionController.add(position);
      }
    });
  }

  void _stopVideoTicker() {
    _videoPositionTimer?.cancel();
    _videoPositionTimer = null;
  }

  Future<void> dispose() async {
    _stopVideoTicker();
    await _videoController?.dispose();
    await _audioPlayer.dispose();
    await _videoPositionController.close();
  }
}
