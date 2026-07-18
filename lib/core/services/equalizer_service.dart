import 'package:flutter/services.dart';
import '../../presentation/providers/equalizer_provider.dart';

class EqualizerService {
  static const MethodChannel _channel = MethodChannel('com.benjamindarko.monochrome/equalizer_control');
  static EqualizerSettings _currentSettings = EqualizerSettings.defaults();

  static Future<void> init(EqualizerSettings settings) async {
    _currentSettings = settings;
    await applyToNative();
  }

  static Future<void> update(EqualizerSettings settings) async {
    _currentSettings = settings;
    await applyToNative();
  }

  static Future<void> applyToNative() async {
    try {
      await _channel.invokeMethod('setEqualizerConfig', {
        'enabled': _currentSettings.enabled,
        'bandGains': _currentSettings.bandGains,
        'preamp': _currentSettings.preamp,
        'bassBoost': _currentSettings.bassBoost,
        'virtualizer': _currentSettings.virtualizer,
        'limiterEnabled': _currentSettings.limiterEnabled,
      });
    } on PlatformException catch (e) {
      print('[EqualizerService] Failed to update native DSP: ${e.message}');
    }
  }
}
