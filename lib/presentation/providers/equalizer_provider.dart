import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../service/equalizer_service.dart';

class EqualizerPreset {
  final String id;
  final String name;
  final String description;
  final List<double> bandGains;
  final double preamp;
  final double bassBoost;
  final double virtualizer;

  const EqualizerPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.bandGains,
    required this.preamp,
    required this.bassBoost,
    required this.virtualizer,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'bandGains': bandGains,
        'preamp': preamp,
        'bassBoost': bassBoost,
        'virtualizer': virtualizer,
      };

  factory EqualizerPreset.fromMap(Map<String, dynamic> m) => EqualizerPreset(
        id: m['id'] as String,
        name: m['name'] as String,
        description: m['description'] as String,
        bandGains: (m['bandGains'] as List<dynamic>).map((e) => (e as num).toDouble()).toList(),
        preamp: (m['preamp'] as num).toDouble(),
        bassBoost: (m['bassBoost'] as num).toDouble(),
        virtualizer: (m['virtualizer'] as num).toDouble(),
      );
}

class EqualizerSettings {
  final bool enabled;
  final String selectedPresetId;
  final List<double> bandGains;
  final double preamp;
  final double bassBoost;
  final double virtualizer;
  final bool limiterEnabled;
  final bool perDeviceEnabled;

  const EqualizerSettings({
    required this.enabled,
    required this.selectedPresetId,
    required this.bandGains,
    required this.preamp,
    required this.bassBoost,
    required this.virtualizer,
    required this.limiterEnabled,
    required this.perDeviceEnabled,
  });

  factory EqualizerSettings.defaults() => EqualizerSettings(
        enabled: true,
        selectedPresetId: 'prism',
        bandGains: const [3, 2, 1, 0, 1, 2, 1, 0, 0, 1, 2, 3, 3, 2, 1, 2],
        preamp: 0,
        bassBoost: 24,
        virtualizer: 18,
        limiterEnabled: true,
        perDeviceEnabled: true,
      );

  EqualizerSettings copyWith({
    bool? enabled,
    String? selectedPresetId,
    List<double>? bandGains,
    double? preamp,
    double? bassBoost,
    double? virtualizer,
    bool? limiterEnabled,
    bool? perDeviceEnabled,
  }) =>
      EqualizerSettings(
        enabled: enabled ?? this.enabled,
        selectedPresetId: selectedPresetId ?? this.selectedPresetId,
        bandGains: bandGains ?? this.bandGains,
        preamp: preamp ?? this.preamp,
        bassBoost: bassBoost ?? this.bassBoost,
        virtualizer: virtualizer ?? this.virtualizer,
        limiterEnabled: limiterEnabled ?? this.limiterEnabled,
        perDeviceEnabled: perDeviceEnabled ?? this.perDeviceEnabled,
      );
}

class EqualizerProvider extends ChangeNotifier {
  static const _keyEnabled = 'equalizer.enabled';
  static const _keySelectedPresetId = 'equalizer.selectedPresetId';
  static const _keyCustomBandGains = 'equalizer.customBandGains';
  static const _keyPreamp = 'equalizer.preamp';
  static const _keyBassBoost = 'equalizer.bassBoost';
  static const _keyVirtualizer = 'equalizer.virtualizer';
  static const _keyLimiterEnabled = 'equalizer.limiterEnabled';
  static const _keyPerDeviceEnabled = 'equalizer.perDeviceEnabled';

  EqualizerSettings _settings = EqualizerSettings.defaults();
  EqualizerSettings get settings => _settings;

  final List<EqualizerPreset> presets = const [
    EqualizerPreset(
      id: 'prism',
      name: 'ZYP Prism',
      description: 'Balanced glass shine',
      bandGains: [3, 2, 1, 0, 1, 2, 1, 0, 0, 1, 2, 3, 3, 2, 1, 2],
      preamp: 0,
      bassBoost: 24,
      virtualizer: 18,
    ),
    EqualizerPreset(
      id: 'flat',
      name: 'Flat',
      description: 'Neutral response',
      bandGains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      preamp: 0,
      bassBoost: 0,
      virtualizer: 0,
    ),
    EqualizerPreset(
      id: 'bass',
      name: 'Bass Bloom',
      description: 'Heavy low-end',
      bandGains: [7, 7, 6, 5, 4, 3, 2, 1, 0, -1, -1, 0, 1, 2, 2, 1],
      preamp: -2,
      bassBoost: 68,
      virtualizer: 12,
    ),
    EqualizerPreset(
      id: 'vocal',
      name: 'Vocal Glass',
      description: 'Clear voices',
      bandGains: [-2, -1, 0, 1, 2, 3, 4, 5, 4, 3, 3, 2, 1, 0, -1, -2],
      preamp: 0,
      bassBoost: 10,
      virtualizer: 8,
    ),
    EqualizerPreset(
      id: 'afrobeats',
      name: 'Afrobeats Punch',
      description: 'Warm rhythm',
      bandGains: [5, 5, 4, 3, 2, 1, 0, 1, 2, 2, 3, 4, 4, 3, 2, 1],
      preamp: -1,
      bassBoost: 48,
      virtualizer: 22,
    ),
    EqualizerPreset(
      id: 'night',
      name: 'Night Drive',
      description: 'Wide and deep',
      bandGains: [4, 3, 2, 1, 0, -1, -1, 0, 1, 2, 3, 4, 5, 4, 3, 4],
      preamp: -1,
      bassBoost: 36,
      virtualizer: 42,
    ),
    EqualizerPreset(
      id: 'acoustic',
      name: 'Acoustic Warm',
      description: 'Soft instruments',
      bandGains: [1, 1, 2, 3, 3, 2, 1, 1, 0, 1, 2, 3, 2, 1, 0, 0],
      preamp: 0,
      bassBoost: 18,
      virtualizer: 16,
    ),
    EqualizerPreset(
      id: 'podcast',
      name: 'Podcast Clarity',
      description: 'Speech focused',
      bandGains: [-4, -4, -3, -2, 0, 2, 4, 5, 5, 4, 3, 1, 0, -1, -2, -3],
      preamp: 1,
      bassBoost: 4,
      virtualizer: 0,
    ),
  ];

  List<double> _customGains = const [2, 2, 3, 2, 1, 0, 0, 1, 2, 3, 3, 2, 1, 0, 1, 2];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final enabled = prefs.getBool(_keyEnabled) ?? true;
    final selectedPresetId = prefs.getString(_keySelectedPresetId) ?? 'prism';
    final preamp = prefs.getDouble(_keyPreamp) ?? 0.0;
    final bassBoost = prefs.getDouble(_keyBassBoost) ?? 24.0;
    final virtualizer = prefs.getDouble(_keyVirtualizer) ?? 18.0;
    final limiterEnabled = prefs.getBool(_keyLimiterEnabled) ?? true;
    final perDeviceEnabled = prefs.getBool(_keyPerDeviceEnabled) ?? true;

    final customGainsStr = prefs.getString(_keyCustomBandGains);
    if (customGainsStr != null) {
      try {
        final List<dynamic> decoded = jsonDecode(customGainsStr);
        _customGains = decoded.map((e) => (e as num).toDouble()).toList();
      } catch (_) {}
    }

    List<double> activeGains = List.from(settings.bandGains);
    if (selectedPresetId == 'custom') {
      activeGains = List.from(_customGains);
    } else {
      final preset = presets.firstWhere((p) => p.id == selectedPresetId, orElse: () => presets.first);
      activeGains = List.from(preset.bandGains);
    }

    _settings = EqualizerSettings(
      enabled: enabled,
      selectedPresetId: selectedPresetId,
      bandGains: activeGains,
      preamp: preamp,
      bassBoost: bassBoost,
      virtualizer: virtualizer,
      limiterEnabled: limiterEnabled,
      perDeviceEnabled: perDeviceEnabled,
    );

    EqualizerService.init(_settings);
    notifyListeners();
  }

  Future<void> setEnabled(bool enabled) async {
    _settings = _settings.copyWith(enabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, enabled);
    EqualizerService.update(_settings);
    notifyListeners();
  }

  Future<void> selectPreset(String presetId) async {
    List<double> gains;
    double preampVal = _settings.preamp;
    double bassVal = _settings.bassBoost;
    double virtVal = _settings.virtualizer;

    if (presetId == 'custom') {
      gains = List.from(_customGains);
    } else {
      final preset = presets.firstWhere((p) => p.id == presetId, orElse: () => presets.first);
      gains = List.from(preset.bandGains);
      preampVal = preset.preamp;
      bassVal = preset.bassBoost;
      virtVal = preset.virtualizer;
    }

    _settings = _settings.copyWith(
      selectedPresetId: presetId,
      bandGains: gains,
      preamp: preampVal,
      bassBoost: bassVal,
      virtualizer: virtVal,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySelectedPresetId, presetId);
    await prefs.setDouble(_keyPreamp, preampVal);
    await prefs.setDouble(_keyBassBoost, bassVal);
    await prefs.setDouble(_keyVirtualizer, virtVal);

    EqualizerService.update(_settings);
    notifyListeners();
  }

  Future<void> setBandGain(int index, double gain) async {
    final List<double> newGains = List.from(_settings.bandGains);
    newGains[index] = gain;

    _settings = _settings.copyWith(
      selectedPresetId: 'custom',
      bandGains: newGains,
    );

    _customGains = List.from(newGains);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySelectedPresetId, 'custom');
    await prefs.setString(_keyCustomBandGains, jsonEncode(_customGains));

    EqualizerService.update(_settings);
    notifyListeners();
  }

  Future<void> saveCustomCurve() async {
    _customGains = List.from(_settings.bandGains);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCustomBandGains, jsonEncode(_customGains));
    notifyListeners();
  }

  Future<void> setPreamp(double preamp) async {
    _settings = _settings.copyWith(preamp: preamp);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyPreamp, preamp);
    EqualizerService.update(_settings);
    notifyListeners();
  }

  Future<void> setBassBoost(double boost) async {
    _settings = _settings.copyWith(bassBoost: boost);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyBassBoost, boost);
    EqualizerService.update(_settings);
    notifyListeners();
  }

  Future<void> setVirtualizer(double virt) async {
    _settings = _settings.copyWith(virtualizer: virt);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyVirtualizer, virt);
    EqualizerService.update(_settings);
    notifyListeners();
  }

  Future<void> setLimiterEnabled(bool enabled) async {
    _settings = _settings.copyWith(limiterEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyLimiterEnabled, enabled);
    EqualizerService.update(_settings);
    notifyListeners();
  }

  Future<void> setPerDeviceEnabled(bool enabled) async {
    _settings = _settings.copyWith(perDeviceEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPerDeviceEnabled, enabled);
    EqualizerService.update(_settings);
    notifyListeners();
  }
}
