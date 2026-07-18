import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import '../config/metadata_sync_config.dart';

class CountryBonusService {
  static const String _assetPath = 'assets/data/country_to_region.json';
  Map<String, String> _countryToRegion = const <String, String>{};

  bool get isReady => _countryToRegion.isNotEmpty;

  Future<void> initialize() async {
    if (isReady) return;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final dynamicFile =
          File('${docDir.path}/${MetadataSyncConfig.countryRegionFilename}');

      String raw;
      if (await dynamicFile.exists()) {
        raw = await dynamicFile.readAsString();
      } else {
        raw = await rootBundle.loadString(_assetPath);
      }

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final cleaned = <String, String>{};
      for (final entry in decoded.entries) {
        if (entry.key.startsWith('_')) continue;
        final region = entry.value;
        if (region is! String) continue;
        cleaned[entry.key.toUpperCase()] = region.trim();
      }
      _countryToRegion = Map<String, String>.unmodifiable(cleaned);
    } catch (e) {
      _countryToRegion = {};
      print('[CountryBonusService] Failed to load mapping: $e');
    }
  }

  void loadMapForTesting(Map<String, String> map) {
    _countryToRegion = Map<String, String>.unmodifiable(
      map.map((k, v) => MapEntry(k.toUpperCase(), v.trim())),
    );
  }

  double scoreFor(String? seedCountry, String? candidateCountry) {
    final seed = _normalise(seedCountry);
    final cand = _normalise(candidateCountry);
    if (seed == null || cand == null) return 1.0;
    if (seed == cand) return 1.0;

    final seedRegion = _countryToRegion[seed];
    final candRegion = _countryToRegion[cand];
    if (seedRegion == null || candRegion == null) return 1.0;
    if (seedRegion == candRegion) return 0.85;
    return 0.70;
  }

  String? _normalise(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.toUpperCase();
  }
}
