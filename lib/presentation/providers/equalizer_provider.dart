import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audio_session/audio_session.dart';
import '../../core/services/equalizer_service.dart';

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
        bandGains: const [2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 1, 1],
        preamp: 0,
        bassBoost: 15,
        virtualizer: 15,
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

  StreamSubscription? _deviceChangeSub;
  String _currentDeviceKey = 'speaker';
  bool _disposed = false;

  EqualizerProvider() {
    _initDeviceListener();
  }

  void _initDeviceListener() async {
    try {
      final session = await AudioSession.instance;
      if (_disposed) return; // provider was disposed while await was pending
      _deviceChangeSub = session.devicesChangedEventStream.listen((_) {
        _onDeviceChanged();
      });
      _currentDeviceKey = await _getActiveDeviceKey();
    } catch (_) {}
  }

  Future<void> _onDeviceChanged() async {
    if (_disposed) return;
    final newKey = await _getActiveDeviceKey();
    if (_disposed) return; // re-check after the await
    if (newKey != _currentDeviceKey) {
      _currentDeviceKey = newKey;
      if (_settings.perDeviceEnabled) {
        await load();
      }
    }
  }

  Future<String> _getActiveDeviceKey() async {
    try {
      final session = await AudioSession.instance;
      final devices = await session.getDevices();
      final outputs = devices.where((d) => d.isOutput).toList();
      if (outputs.isEmpty) return 'speaker';

      for (final d in outputs) {
        final t = d.type;
        if (t == AudioDeviceType.bluetoothA2dp ||
            t == AudioDeviceType.bluetoothLe ||
            t == AudioDeviceType.bluetoothSco) {
          final name = d.name.trim().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
          return 'bluetooth_${name.isNotEmpty ? name : "device"}';
        }
      }

      for (final d in outputs) {
        final t = d.type;
        if (t == AudioDeviceType.wiredHeadset ||
            t == AudioDeviceType.wiredHeadphones ||
            t == AudioDeviceType.usbAudio) {
          return 'wired';
        }
      }

      return 'speaker';
    } catch (_) {
      return 'speaker';
    }
  }

  String _getPrefKey(String baseKey) {
    if (_settings.perDeviceEnabled) {
      return '$baseKey.$_currentDeviceKey';
    }
    return baseKey;
  }

  @override
  void dispose() {
    _disposed = true;
    _deviceChangeSub?.cancel();
    super.dispose();
  }

  final List<EqualizerPreset> presets = const [
    EqualizerPreset(
      id: 'prism',
      name: 'ZYP Prism',
      description: 'Balanced glass shine',
      bandGains: [2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 1, 1],
      preamp: 0,
      bassBoost: 15,
      virtualizer: 15,
    ),
    EqualizerPreset(
      id: 'bass',
      name: 'Subwoofer Rumble',
      description: 'Deep physical low-end thump',
      bandGains: [4, 3, 2, 1, 0, -1, -1, 0, 0, 0, 0, 0, -1, -1, 0, 1],
      preamp: -2,
      bassBoost: 60,
      virtualizer: 0,
    ),
    EqualizerPreset(
      id: 'acoustic',
      name: 'Acoustic Air',
      description: 'Clear vocals, breathy natural highs',
      bandGains: [-2, -1, -1, 0, 0, 1, 1, 1, 1, 2, 2, 3, 3, 3, 3, 2],
      preamp: 0,
      bassBoost: 5,
      virtualizer: 10,
    ),
    EqualizerPreset(
      id: 'afrobeats',
      name: 'Afrobeat',
      description: 'Warm punchy bass, percussion clarity',
      bandGains: [3, 3, 2, 1, 0, 0, 0, 0, 1, 1, 1, 2, 2, 2, 1, 1],
      preamp: -1,
      bassBoost: 35,
      virtualizer: 20,
    ),
    EqualizerPreset(
      id: 'night',
      name: 'Neon Club',
      description: 'Vibrant energetic V-shaped details',
      bandGains: [5, 4, 3, 1, 0, -2, -3, -2, -1, 0, 0, 1, 2, 3, 3, 3],
      preamp: -1,
      bassBoost: 45,
      virtualizer: 12,
    ),
    EqualizerPreset(
      id: 'ambient',
      name: 'Starlight Ambient',
      description: 'Lush, wide, immersive soundstage',
      bandGains: [2, 2, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 2],
      preamp: -1,
      bassBoost: 20,
      virtualizer: 55,
    ),
    EqualizerPreset(
      id: 'vocal',
      name: 'Pure Glass',
      description: 'Ultra-high-definition details',
      bandGains: [-1, -1, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 3, 2, 2, 3],
      preamp: -1,
      bassBoost: 8,
      virtualizer: 30,
    ),
    EqualizerPreset(
      id: 'podcast',
      name: 'Speech Clear',
      description: 'Cut rumble and hiss, voice focused',
      bandGains: [-6, -5, -4, -3, -1, 1, 3, 4, 4, 3, 2, 1, 0, -1, -2, -3],
      preamp: 1,
      bassBoost: 0,
      virtualizer: 0,
    ),
  ];

  List<double> _customGains = const [2, 2, 3, 2, 1, 0, 0, 1, 2, 3, 3, 2, 1, 0, 1, 2];
  List<double> get customGains => _customGains;
  set customGains(List<double> val) {
    _customGains = List.from(val);
    notifyListeners();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final perDeviceEnabled = prefs.getBool(_keyPerDeviceEnabled) ?? true;
    _settings = _settings.copyWith(perDeviceEnabled: perDeviceEnabled);

    if (perDeviceEnabled) {
      _currentDeviceKey = await _getActiveDeviceKey();
    } else {
      _currentDeviceKey = 'default';
    }

    final enabledKey = _getPrefKey(_keyEnabled);
    final presetIdKey = _getPrefKey(_keySelectedPresetId);
    final preampKey = _getPrefKey(_keyPreamp);
    final bassKey = _getPrefKey(_keyBassBoost);
    final virtKey = _getPrefKey(_keyVirtualizer);
    final limiterKey = _getPrefKey(_keyLimiterEnabled);
    final customGainsKey = _getPrefKey(_keyCustomBandGains);

    final enabled = prefs.getBool(enabledKey) ?? true;
    final selectedPresetId = prefs.getString(presetIdKey) ?? 'prism';
    final preamp = prefs.getDouble(preampKey) ?? 0.0;
    final bassBoost = prefs.getDouble(bassKey) ?? 24.0;
    final virtualizer = prefs.getDouble(virtKey) ?? 18.0;
    final limiterEnabled = prefs.getBool(limiterKey) ?? true;

    final customGainsStr = prefs.getString(customGainsKey);
    if (customGainsStr != null) {
      try {
        final List<dynamic> decoded = jsonDecode(customGainsStr);
        _customGains = decoded.map((e) => (e as num).toDouble()).toList();
      } catch (_) {}
    } else {
      _customGains = const [2, 2, 3, 2, 1, 0, 0, 1, 2, 3, 3, 2, 1, 0, 1, 2];
    }

    List<double> activeGains;
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

    await EqualizerService.init(_settings);
    notifyListeners();
  }

  Future<void> setEnabled(bool enabled) async {
    _settings = _settings.copyWith(enabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_getPrefKey(_keyEnabled), enabled);
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
    await prefs.setString(_getPrefKey(_keySelectedPresetId), presetId);
    await prefs.setDouble(_getPrefKey(_keyPreamp), preampVal);
    await prefs.setDouble(_getPrefKey(_keyBassBoost), bassVal);
    await prefs.setDouble(_getPrefKey(_keyVirtualizer), virtVal);

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
    await prefs.setString(_getPrefKey(_keySelectedPresetId), 'custom');
    await prefs.setString(_getPrefKey(_keyCustomBandGains), jsonEncode(_customGains));

    EqualizerService.update(_settings);
    notifyListeners();
  }

  Future<void> saveCustomCurve() async {
    _customGains = List.from(_settings.bandGains);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_getPrefKey(_keyCustomBandGains), jsonEncode(_customGains));
    notifyListeners();
  }

  Future<void> setPreamp(double preamp) async {
    _settings = _settings.copyWith(preamp: preamp);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_getPrefKey(_keyPreamp), preamp);
    EqualizerService.update(_settings);
    notifyListeners();
  }

  Future<void> setBassBoost(double boost) async {
    _settings = _settings.copyWith(bassBoost: boost);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_getPrefKey(_keyBassBoost), boost);
    EqualizerService.update(_settings);
    notifyListeners();
  }

  Future<void> setVirtualizer(double virt) async {
    _settings = _settings.copyWith(virtualizer: virt);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_getPrefKey(_keyVirtualizer), virt);
    EqualizerService.update(_settings);
    notifyListeners();
  }

  Future<void> setLimiterEnabled(bool enabled) async {
    _settings = _settings.copyWith(limiterEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_getPrefKey(_keyLimiterEnabled), enabled);
    EqualizerService.update(_settings);
    notifyListeners();
  }

  Future<void> setPerDeviceEnabled(bool enabled) async {
    _settings = _settings.copyWith(perDeviceEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPerDeviceEnabled, enabled);
    await load();
  }
}
