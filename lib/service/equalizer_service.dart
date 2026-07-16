import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../presentation/providers/equalizer_provider.dart';

class EqualizerService {
  static final Map<AudioPlayer, _PlayerEffects> _activePlayers = {};
  static EqualizerSettings _currentSettings = EqualizerSettings.defaults();

  static void init(EqualizerSettings settings) {
    _currentSettings = settings;
    _applyToAll();
  }

  static void update(EqualizerSettings settings) {
    _currentSettings = settings;
    _applyToAll();
  }

  static AudioPlayer createPlayer() {
    if (!kIsWeb && Platform.isAndroid) {
      final eq = AndroidEqualizer();
      final preamp = AndroidLoudnessEnhancer();
      final pipeline = AudioPipeline(androidAudioEffects: [eq, preamp]);
      final player = AudioPlayer(audioPipeline: pipeline);
      _activePlayers[player] = _PlayerEffects(eq: eq, preamp: preamp);
      _applyToPlayer(eq, preamp);
      return player;
    } else {
      return AudioPlayer();
    }
  }

  static void removePlayer(AudioPlayer player) {
    _activePlayers.remove(player);
  }

  static void _applyToAll() {
    _activePlayers.forEach((player, effects) {
      _applyToPlayer(effects.eq, effects.preamp);
    });
  }

  static Future<void> _applyToPlayer(AndroidEqualizer eq, AndroidLoudnessEnhancer preamp) async {
    try {
      await eq.setEnabled(_currentSettings.enabled);
      await preamp.setEnabled(_currentSettings.enabled);

      if (!_currentSettings.enabled) return;

      // targetGain is in decibels. AndroidLoudnessEnhancer accepts targetGain in decibels.
      await preamp.setTargetGain(_currentSettings.preamp);

      final params = await eq.parameters;
      for (var band in params.bands) {
        final centerFreq = band.centerFrequency;
        double targetGain = _interpolateGain(centerFreq, _currentSettings.bandGains);

        // Apply software bass boost simulation below 150 Hz
        if (_currentSettings.bassBoost > 0 && centerFreq < 150) {
          final factor = (150 - centerFreq) / 120.0; // 1.0 at 30Hz, 0.0 at 150Hz
          final boostDb = (_currentSettings.bassBoost / 100.0) * 8.0 * factor.clamp(0.0, 1.0);
          targetGain += boostDb;
        }

        final clampedGain = targetGain.clamp(params.minDecibels, params.maxDecibels);
        await band.setGain(clampedGain);
      }
    } catch (e) {
      debugPrint('[EqualizerService] Error applying effects: $e');
    }
  }

  static double _interpolateGain(double centerFreq, List<double> uiGains) {
    final uiFreqs = [31, 45, 63, 90, 125, 180, 250, 355, 500, 710, 1000, 1400, 2000, 4000, 8000, 16000];
    if (centerFreq <= uiFreqs.first) return uiGains.first;
    if (centerFreq >= uiFreqs.last) return uiGains.last;

    for (int i = 0; i < uiFreqs.length - 1; i++) {
      if (centerFreq >= uiFreqs[i] && centerFreq <= uiFreqs[i + 1]) {
        final t = (centerFreq - uiFreqs[i]) / (uiFreqs[i + 1] - uiFreqs[i]);
        return uiGains[i] + t * (uiGains[i + 1] - uiGains[i]);
      }
    }
    return 0.0;
  }
}

class _PlayerEffects {
  final AndroidEqualizer eq;
  final AndroidLoudnessEnhancer preamp;
  _PlayerEffects({required this.eq, required this.preamp});
}
