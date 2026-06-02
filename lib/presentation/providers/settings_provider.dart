import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/audio_quality.dart';

class SettingsProvider extends ChangeNotifier {
  static const _keyPrebufferCount = 'prebufferCount';
  static const _keyAudioQuality = 'audioQuality';

  static const defaultPrebufferCount = 2;

  int _prebufferCount = defaultPrebufferCount;
  AudioQuality _audioQuality = AudioQuality.low;

  int get prebufferCount => _prebufferCount;
  AudioQuality get audioQuality => _audioQuality;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _prebufferCount = prefs.getInt(_keyPrebufferCount) ?? defaultPrebufferCount;
    final qualityStr = prefs.getString(_keyAudioQuality);
    _audioQuality = qualityStr != null
        ? AudioQuality.values.firstWhere(
            (q) => q.name == qualityStr,
            orElse: () => AudioQuality.low,
          )
        : AudioQuality.low;
    notifyListeners();
  }

  Future<void> setPrebufferCount(int count) async {
    _prebufferCount = count;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPrebufferCount, count);
    notifyListeners();
  }

  Future<void> setAudioQuality(AudioQuality quality) async {
    _audioQuality = quality;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAudioQuality, quality.name);
    notifyListeners();
  }
}
