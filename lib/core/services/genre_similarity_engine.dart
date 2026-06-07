import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// Computes continuous similarity scores between sets of canonical genre
/// cluster keys, using a static proximity matrix loaded from assets.
///
/// The matrix encodes pairwise distances between genre clusters as values
/// in [0.0, 1.0], where 1.0 is identical and 0.0 is unrelated. Identical
/// genres always score 1.0 (handled implicitly — a genre is its own
/// strongest neighbor).
///
/// For two genre sets, the similarity is the maximum pairwise score across
/// the Cartesian product. This is the standard "best match" approach for
/// multi-label similarity. Spec 2B.
class GenreSimilarityEngine {
  static const String _assetPath = 'assets/data/genre_proximity_matrix.json';

  // Internal representation: Map<genre_key, Map<neighbor_key, score>>
  Map<String, Map<String, double>>? _matrix;

  /// Must be called once at app startup before any score() call.
  /// Idempotent — safe to call multiple times.
  Future<void> initialize() async {
    if (_matrix != null) return;

    try {
      final raw = await rootBundle.loadString(_assetPath);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;

      _matrix = {};
      for (final entry in decoded.entries) {
        final neighborsMap =
            (entry.value as Map<String, dynamic>)['neighbors']
                as Map<String, dynamic>?;
        if (neighborsMap == null) continue;

        _matrix![entry.key] = neighborsMap.map(
          (k, v) => MapEntry(k, (v as num).toDouble()),
        );
      }
    } catch (e, st) {
      // Degraded path: a failed load produces an empty matrix
      // so score() always returns 0.0 rather than throwing.
      // Smart DJ falls back to artist-diversity-only scoring
      // per Spec 2C's cold-start path. Spec 2B §2A constraint
      // #3 (empty or null genre arrays return 0.0, never throw)
      // is preserved.
      _matrix = {};
      // ignore: avoid_print
      print('[GenreSimilarity] Failed to load matrix: $e\n$st');
    }
  }

  /// Computes similarity between two genre sets in [0.0, 1.0].
  ///
  /// Returns 0.0 if either set is empty (no signal).
  /// Returns 1.0 if any genre appears in both sets (exact match).
  /// Otherwise returns the max neighbor weight across all pairs, considering
  /// both directions in the matrix (symmetric lookup).
  double score(List<String> setA, List<String> setB) {
    if (setA.isEmpty || setB.isEmpty) return 0.0;

    final matrix = _matrix;
    if (matrix == null) {
      throw StateError(
        'GenreSimilarityEngine.score called before initialize().',
      );
    }

    double maxScore = 0.0;
    for (final a in setA) {
      for (final b in setB) {
        final s = _pairScore(a, b, matrix);
        if (s > maxScore) maxScore = s;
        if (maxScore >= 1.0) return 1.0; // early exit on exact match
      }
    }
    return maxScore;
  }

  /// Symmetric pairwise lookup.
  /// Identical genres return 1.0.
  /// Otherwise checks matrix[a][b] and matrix[b][a], returns the max.
  double _pairScore(
    String a,
    String b,
    Map<String, Map<String, double>> matrix,
  ) {
    if (a == b) return 1.0;

    final aToB = matrix[a]?[b] ?? 0.0;
    final bToA = matrix[b]?[a] ?? 0.0;
    return aToB > bToA ? aToB : bToA;
  }

  /// Test-only: returns the number of top-level genre keys in the loaded
  /// matrix. Used by Gate 1 and the cross-consistency check in Gate 7.
  int get loadedKeyCount => _matrix?.length ?? 0;

  /// Test-only hook: inject a pre-parsed matrix so unit tests
  /// don't have to spin up the asset bundle. Mirrors the
  /// production `initialize()` parse path exactly. Never call
  /// this from production code — use [initialize] for that.
  void loadMatrixForTesting(Map<String, Map<String, double>> matrix) {
    _matrix = Map<String, Map<String, double>>.from(
      matrix.map(
        (k, v) => MapEntry(
          k,
          Map<String, double>.from(v),
        ),
      ),
    );
  }
}
