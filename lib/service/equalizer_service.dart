import 'package:just_audio/just_audio.dart';

class EqualizerService {
  static AudioPlayer createPlayer() {
    return AudioPlayer();
  }

  static void removePlayer(AudioPlayer player) {
    // No-op: player resources are managed by AudioPlayer.dispose()
  }
}
