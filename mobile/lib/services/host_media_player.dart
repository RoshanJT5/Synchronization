import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

class HostMediaPlayer {
  final AudioPlayer _player = AudioPlayer();
  bool _isLoaded = false;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  bool get isPlaying => _player.playing;

  Future<void> loadFile(String filePath) async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.music());
    await _player.setFilePath(filePath);
    _isLoaded = true;
  }

  Future<void> play() async {
    if (_isLoaded) await _player.play();
  }

  Future<void> pause() async {
    if (_isLoaded) await _player.pause();
  }

  Future<void> seekTo(int positionMs) async {
    if (_isLoaded) {
      await _player.seek(Duration(milliseconds: positionMs.clamp(0, 1 << 31)));
    }
  }

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 1.0));
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
