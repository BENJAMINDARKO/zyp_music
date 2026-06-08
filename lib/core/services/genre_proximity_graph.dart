import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// Genre adjacency weights loaded from the asset file at
/// `assets/data/genre_proximity_matrix.json`.  Weights are
/// floating-point proximity scores in the range `[0.0, 1.0]` and a
/// higher number means a closer neighbour.
///
/// The graph is **directional but largely symmetric**: every edge
/// in the asset appears under both endpoints' `neighbors` map.
/// The routing service treats the matrix as the source of truth and
/// does not assume symmetry.
///
/// Usage:
/// ```dart
/// final graph = GenreProximityGraph();
/// await graph.initialize();
/// for (final genre in graph.searchBreadth('Rock')) { ... }
/// ```
class GenreProximityGraph {
  static const String _assetPath =
      'assets/data/genre_proximity_matrix.json';

  Map<String, Map<String, double>>? _matrix;

  /// Must be called once before any `neighborsOf()` or
  /// `searchBreadth()` call.  Idempotent — safe to call multiple
  /// times.
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
      _matrix = {};
      // ignore: avoid_print
      print('[GenreProximityGraph] Failed to load matrix: $e\n$st');
    }
  }

  /// Test-only hook: inject a pre-parsed matrix so unit tests
  /// don't have to spin up the asset bundle. Mirrors the production
  /// [initialize] parse path exactly. Never call this from
  /// production code — use [initialize] for that.
  void loadMatrixForTesting(Map<String, Map<String, double>> matrix) {
    _matrix = Map<String, Map<String, double>>.from(
      matrix.map(
        (k, v) => MapEntry(k, Map<String, double>.from(v)),
      ),
    );
  }

  /// All genres registered in the matrix.  Returns an empty set if
  /// [initialize] has not been called.
  Set<String> get knownGenres =>
      _matrix?.keys.toSet() ?? <String>{};

  /// Returns the raw neighbour map for [genre]. Returns an empty
  /// (unmodifiable) map if [genre] is not in the matrix — this is
  /// the graceful-degradation path for tracks whose primary_genre
  /// column is `'Unknown'` or any other unrecognised value.
  Map<String, double> neighborsOf(String? genre) {
    if (genre == null) return const <String, double>{};
    final matrix = _matrix;
    if (matrix == null) return const <String, double>{};
    return matrix[genre] ?? const <String, double>{};
  }

  /// Returns the neighbours of [genre] sorted in **descending** order
  /// of proximity score, ties broken alphabetically for deterministic
  /// iteration. The caller iterates this list to drive the
  /// "iterate down through the neighbourhood by descending proximity
  /// scores" branch of the spec.
  List<MapEntry<String, double>> neighborsByDescendingProximity(
      String? genre) {
    final raw = neighborsOf(genre);
    final entries = raw.entries.toList()
      ..sort((a, b) {
        final byScore = b.value.compareTo(a.value);
        if (byScore != 0) return byScore;
        return a.key.compareTo(b.key);
      });
    return entries;
  }

  /// Breadth-expanding search yielding genres in priority order:
  ///
  /// 1. [startGenre] itself (closest possible match — exact), but
  ///    only if [startGenre] is a key in the matrix. An unknown
  ///    seed (e.g. `'Unknown'` from the schema default) yields
  ///    nothing on the first hop and falls through to the
  ///    (empty) neighbour list, so the caller observes an empty
  ///    iterable.
  /// 2. First-degree neighbours sorted by descending proximity.
  /// 3. Second-degree neighbours (neighbours of neighbours that
  ///    have not already been yielded), sorted by the **minimum**
  ///    proximity of the two-step path (so a 0.90 → 0.80 hop beats
  ///    a 0.95 → 0.55 hop).
  /// 4. The same for third-degree, etc., until the graph is
  ///    exhausted.
  ///
  /// The returned iterable is lazy and finite — the graph is small
  /// enough (< 150 vertices) to fully expand.
  ///
  /// Passing `null` yields nothing.
  Iterable<String> searchBreadth(String? startGenre) sync* {
    if (startGenre == null) return;
    final matrix = _matrix;
    if (matrix == null) return;
    // Only yield the seed if it's a known genre in the matrix.
    // The schema default for primary_genre is the literal string
    // 'Unknown' which is not a real genre — yielding it would
    // match the schema-default track and shadow the legitimate
    // neighbours.
    final seedIsKnown = matrix.containsKey(startGenre);
    final seen = <String>{};
    if (seedIsKnown) {
      seen.add(startGenre);
      yield startGenre;
    }
    // BFS queue: (genre, depth, pathProximityMin).
    final queue = <_BfsNode>[
      for (final entry in neighborsByDescendingProximity(startGenre))
        _BfsNode(entry.key, 1, entry.value),
    ];
    while (queue.isNotEmpty) {
      // Pick the next node: smallest depth first (BFS), then
      // descending path-proximity, then alphabetical.
      queue.sort((a, b) {
        final byDepth = a.depth.compareTo(b.depth);
        if (byDepth != 0) return byDepth;
        final byProx = b.pathProximity.compareTo(a.pathProximity);
        if (byProx != 0) return byProx;
        return a.genre.compareTo(b.genre);
      });
      final node = queue.removeAt(0);
      if (!seen.add(node.genre)) continue;
      yield node.genre;
      if (node.depth >= 3) continue; // Cap BFS depth at 3 hops.
      for (final entry in neighborsByDescendingProximity(node.genre)) {
        if (seen.contains(entry.key)) continue;
        final minProx = entry.value < node.pathProximity
            ? entry.value
            : node.pathProximity;
        queue.add(_BfsNode(entry.key, node.depth + 1, minProx));
      }
    }
  }
}

class _BfsNode {
  final String genre;
  final int depth;
  final double pathProximity;
  const _BfsNode(this.genre, this.depth, this.pathProximity);
}
