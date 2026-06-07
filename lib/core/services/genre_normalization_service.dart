import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// Bridges MusicBrainz genre tags to proximity-matrix canonical keys.
///
/// MusicBrainz returns tags like "ghanaian hip hop", "afro-fusion", "uk drill".
/// The proximity matrix uses canonical cluster keys like "Hip-Hop", "Afrobeats",
/// "Drill". This service maps the former to the latter via a static dictionary
/// loaded from assets at app startup.
///
/// Unmapped tags are returned as null and logged so the dictionary can be
/// expanded based on observed data over time.
class GenreNormalizationService {
  static const String _assetPath = 'assets/data/genre_normalization.json';

  Map<String, String>? _dictionary;
  final Set<String> _unmappedTagsThisSession = <String>{};

  /// Must be called once at app startup before any normalize() call.
  /// Idempotent — calling multiple times is safe.
  Future<void> initialize() async {
    if (_dictionary != null) return;

    try {
      final raw = await rootBundle.loadString(_assetPath);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _dictionary = decoded.map((k, v) => MapEntry(k, v as String));
    } catch (e, st) {
      // If the asset fails to load, normalize() returns null for every tag.
      // This is degraded behavior, not a crash — Smart DJ falls back to
      // artist-diversity-only scoring per Spec 2C's cold-start path.
      _dictionary = {};
      // Replace with the project's logger if different.
      // ignore: avoid_print
      print('[GenreNormalization] Failed to load asset: $e\n$st');
    }
  }

  /// Test-only hook: inject a pre-loaded dictionary so unit tests
  /// don't have to spin up the asset bundle. Never call this from
  /// production code — use [initialize] for that.
  void loadDictionaryForTesting(Map<String, String> dict) {
    _dictionary = Map<String, String>.from(dict);
  }

  /// Maps a single MusicBrainz tag to its canonical matrix key.
  /// Returns null if the tag is empty or unmapped.
  /// Side effect: logs unmapped tags to the session set.
  String? normalize(String? rawTag) {
    if (rawTag == null) return null;
    final canonical = _canonicalize(rawTag);
    if (canonical.isEmpty) return null;

    final dict = _dictionary;
    if (dict == null) {
      throw StateError(
        'GenreNormalizationService.normalize called before initialize().',
      );
    }

    final mapped = dict[canonical];
    if (mapped == null) {
      _unmappedTagsThisSession.add(canonical);
      return null;
    }
    return mapped;
  }

  /// Maps a list of MusicBrainz tags to their canonical matrix keys.
  /// Drops nulls (unmapped tags). Deduplicates the result.
  /// Returns empty list if input is empty or all tags unmapped.
  List<String> normalizeAll(List<String> rawTags) {
    final result = <String>{};
    for (final tag in rawTags) {
      final mapped = normalize(tag);
      if (mapped != null) result.add(mapped);
    }
    return result.toList();
  }

  /// Returns the set of tags encountered this session that had no mapping.
  /// Read by diagnostics tooling to drive dictionary expansion.
  Set<String> get unmappedTagsThisSession =>
      Set.unmodifiable(_unmappedTagsThisSession);

  /// Lowercase, trim, collapse internal whitespace to single spaces.
  /// "  Hip Hop  " → "hip hop"
  /// "UK DRILL" → "uk drill"
  /// "Afro-Fusion" → "afro-fusion"
  String _canonicalize(String input) {
    return input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
