// lib/core/services/country_bonus_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import '../config/metadata_sync_config.dart';

class CountryBonusService {
  static const String _assetPath = 'assets/data/country_to_region.json';
  
  /// Map of uppercase ISO 3166-1 alpha-2 country code -> region string.
  Map<String, String> _countryToRegion = const <String, String>{};
  
  /// 🌍 Fallback: Synced in real-time with the user's selected "preferredGl" preference
  String? preferredFallbackGl;

  bool get isReady => _countryToRegion.isNotEmpty;

  /// Async initializer. Loads dynamic overrides before falling back to asset seed
  Future<void> initialize() async {
    if (isReady) return;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final dynamicFile = File('${docDir.path}/${MetadataSyncConfig.countryRegionFilename}');
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
    }
  }

  /// Computes the regional matching multiplier (Spec 2E §4).
  /// If the seed track's country is null, defaults to the user's active geographic region.
  double scoreFor(String? seedCountry, String? candidateCountry) {
    // Fall back to preferredFallbackGl (e.g. GH) if the seed is untagged
    final seed = _normalise(seedCountry) ?? _normalise(preferredFallbackGl);
    final cand = _normalise(candidateCountry);
    
    if (seed == null || cand == null) return 1.0;
    if (seed == cand) return 1.0;
    
    final seedRegion = _countryToRegion[seed];
    final candRegion = _countryToRegion[cand];
    if (seedRegion == null || candRegion == null) return 1.0;
    if (seedRegion == candRegion) return 0.85;
    return 0.70;
  }

  /// Reverse lookup used by test suites and diagnostic utilities
  String? regionFor(String? country) {
    final normalised = _normalise(country);
    if (normalised == null) return null;
    return _countryToRegion[normalised];
  }

  /// Test seam — replaces the loaded map without round-tripping assets
  void loadMapForTesting(Map<String, String> map) {
    final cleaned = <String, String>{};
    for (final entry in map.entries) {
      final code = entry.key.toUpperCase();
      final region = entry.value.trim();
      if (code.isEmpty || region.isEmpty) continue;
      cleaned[code] = region;
    }
    _countryToRegion = Map<String, String>.unmodifiable(cleaned);
  }

  String? _normalise(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.toUpperCase();
  }
}
