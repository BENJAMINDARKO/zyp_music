import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../utils/app_logger.dart';

/// Spec 2E — country-aware Same-Genre bonus.
///
/// Loads a static ISO 3166-1 alpha-2 country-code → world-region
/// map from `assets/data/country_to_region.json` and exposes
/// [scoreFor], a pure function used by
/// `AutoDjRoutingService._sameGenre` to nudge candidates whose
/// artist's country is culturally closer to the seed's country
/// slightly higher. The bonus is multiplicative, applied AFTER
/// the existing path/artist-penalty, so the rest of the
/// scoring shape is preserved.
///
/// Bonus table (spec 2E §4):
///   same country      → 1.0
///   same region       → 0.85
///   different region  → 0.7
///   either side null  → 1.0  (no bias when we don't know)
///   unknown code      → 1.0  (region map miss → neutral)
///
/// This is intentionally NOT a penalty for "different" — 0.7 is
/// the floor. The intent is to gently reward cultural proximity
/// without locking out cross-cultural discovery. Smart DJ is
/// deliberately excluded (it consumes the genre similarity matrix
/// already; country bias would over-fit).
class CountryBonusService {
  static const String _logTag = 'CountryBonusService';
  static const String _assetPath = 'assets/data/country_to_region.json';

  /// Map of uppercase ISO 3166-1 alpha-2 country code → region
  /// string. Mutable for test seam; do not mutate from production
  /// code (use [loadMapForTesting] in tests only).
  Map<String, String> _countryToRegion = const <String, String>{};

  /// True after [initialize] has run and the asset is loaded.
  bool get isReady => _countryToRegion.isNotEmpty;

  /// Async initializer. Safe to call multiple times — subsequent
  /// calls are no-ops when the map is already populated.
  Future<void> initialize({String assetPath = _assetPath}) async {
    if (isReady) return;
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final cleaned = <String, String>{};
    for (final entry in decoded.entries) {
      if (entry.key.startsWith('_')) continue; // comment field
      final region = entry.value;
      if (region is! String) continue;
      final code = entry.key.toUpperCase();
      final regionStr = region.trim();
      if (code.isEmpty || regionStr.isEmpty) continue;
      cleaned[code] = regionStr;
    }
    _countryToRegion = Map<String, String>.unmodifiable(cleaned);
    AppLogger.log(
      'Loaded ${_countryToRegion.length} country→region entries',
      name: _logTag,
    );
  }

  /// Computes the multiplicative country bonus for [candidateCountry]
  /// against [seedCountry]. Both args are ISO 3166-1 alpha-2; either
  /// may be null/empty (treated as unknown). Case-insensitive — MB
  /// returns uppercase today, but the routing layer should not break
  /// if a future producer lower-cases the value.
  double scoreFor(String? seedCountry, String? candidateCountry) {
    final seed = _normalise(seedCountry);
    final cand = _normalise(candidateCountry);
    if (seed == null || cand == null) return 1.0;
    if (seed == cand) return 1.0;
    final seedRegion = _countryToRegion[seed];
    final candRegion = _countryToRegion[cand];
    if (seedRegion == null || candRegion == null) return 1.0;
    if (seedRegion == candRegion) return 0.85;
    return 0.7;
  }

  /// Reverse lookup — returns the region for a country code, or
  /// null when the code is missing from the asset. Used by tests
  /// and diagnostics. Case-insensitive.
  String? regionFor(String? country) {
    final normalised = _normalise(country);
    if (normalised == null) return null;
    return _countryToRegion[normalised];
  }

  /// Test seam — replaces the loaded map without round-tripping
  /// through the asset bundle. Production code MUST NOT call this.
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
