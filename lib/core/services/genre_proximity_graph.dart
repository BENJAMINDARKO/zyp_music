/// Hardcoded genre adjacency weights for the AI DJ Same-Genre and
/// Same-Artist routing modes. The map is the verbatim transcription
/// of the JSON matrix in the Phase 2 spec; weights are floating-point
/// proximity scores in the range `[0.55, 0.95]` and a higher number
/// means a closer neighbour.
///
/// The graph is **directional but largely symmetric**: every edge
/// defined in the spec appears under both endpoints' `neighbors` map
/// (e.g. `Rock -> Alternative Rock: 0.90` is mirrored by
/// `Alternative Rock -> Rock: 0.90`). The spec does not enforce
/// exact symmetry — a few pairs are not (e.g. `Folk -> Indie Rock: 0.60`
/// but `Indie Rock -> Folk Rock: 0.65` is a different genre). The
/// routing service treats the matrix as the source of truth and does
/// not assume symmetry.
///
/// Usage:
///
/// ```dart
/// final graph = const GenreProximityGraph();
/// for (final genre in graph.searchBreadth('Rock')) {
///   // 'Rock' first, then 'Alternative Rock' (0.90), then 'Classic Rock'
///   // (0.85), then 'Hard Rock' (0.80), then 'Indie Rock' (0.75),
///   // then 'Blues Rock' (0.70), then the second-degree neighbours of
///   // each in the same descending-order, and so on.
/// }
/// ```
class GenreProximityGraph {
  /// Compile-time const constructor. The graph data is a `const`
  /// map so a const instance is functionally identical to a
  /// runtime-built one.
  const GenreProximityGraph();

  /// Verbatim transcription of the spec JSON. Keys are the source
  /// genre; the inner map is `target genre -> proximity weight`.
  static const Map<String, Map<String, double>> _kRaw = {
    'Rock': {
      'Alternative Rock': 0.90,
      'Classic Rock': 0.85,
      'Indie Rock': 0.75,
      'Hard Rock': 0.80,
      'Blues Rock': 0.70,
    },
    'Alternative Rock': {
      'Rock': 0.90,
      'Indie Rock': 0.85,
      'Grunge': 0.80,
      'Post-Punk': 0.75,
      'Shoegaze': 0.70,
    },
    'Indie Rock': {
      'Alternative Rock': 0.85,
      'Indie Pop': 0.80,
      'Folk Rock': 0.65,
      'Synthpop': 0.55,
      'Dream Pop': 0.60,
    },
    'Classic Rock': {
      'Rock': 0.85,
      'Hard Rock': 0.80,
      'Blues Rock': 0.75,
      'Psychedelic Rock': 0.70,
    },
    'Hard Rock': {
      'Rock': 0.80,
      'Classic Rock': 0.80,
      'Metal': 0.85,
      'Heavy Metal': 0.80,
    },
    'Metal': {
      'Hard Rock': 0.85,
      'Heavy Metal': 0.90,
      'Thrash Metal': 0.80,
      'Industrial Metal': 0.70,
    },
    'Heavy Metal': {
      'Metal': 0.90,
      'Thrash Metal': 0.85,
      'Power Metal': 0.75,
    },
    'Thrash Metal': {
      'Heavy Metal': 0.85,
      'Metal': 0.80,
      'Death Metal': 0.70,
    },
    'Death Metal': {
      'Thrash Metal': 0.70,
      'Black Metal': 0.75,
      'Metal': 0.60,
    },
    'Black Metal': {
      'Death Metal': 0.75,
      'Doom Metal': 0.65,
    },
    'Doom Metal': {
      'Black Metal': 0.65,
      'Stoner Metal': 0.70,
    },
    'Stoner Metal': {
      'Doom Metal': 0.70,
      'Psychedelic Rock': 0.60,
    },
    'Psychedelic Rock': {
      'Classic Rock': 0.70,
      'Stoner Metal': 0.60,
      'Progressive Rock': 0.75,
    },
    'Progressive Rock': {
      'Psychedelic Rock': 0.75,
      'Art Rock': 0.80,
    },
    'Art Rock': {
      'Progressive Rock': 0.80,
      'Indie Rock': 0.60,
    },
    'Post-Punk': {
      'Alternative Rock': 0.75,
      'New Wave': 0.70,
      'Goth Rock': 0.65,
    },
    'New Wave': {
      'Post-Punk': 0.70,
      'Synthpop': 0.80,
      'Pop Rock': 0.60,
    },
    'Goth Rock': {
      'Post-Punk': 0.65,
      'Darkwave': 0.80,
    },
    'Darkwave': {
      'Goth Rock': 0.80,
      'Synthpop': 0.60,
    },
    'Shoegaze': {
      'Alternative Rock': 0.70,
      'Dream Pop': 0.85,
    },
    'Dream Pop': {
      'Shoegaze': 0.85,
      'Indie Rock': 0.60,
      'Indie Pop': 0.55,
    },
    'Indie Pop': {
      'Indie Rock': 0.80,
      'Dream Pop': 0.55,
      'Synthpop': 0.60,
      'Pop': 0.65,
    },
    'Pop': {
      'Dance Pop': 0.85,
      'Electropop': 0.80,
      'R&B': 0.70,
      'Indie Pop': 0.65,
      'K-Pop': 0.75,
    },
    'Dance Pop': {
      'Pop': 0.85,
      'EDM': 0.80,
      'House': 0.70,
    },
    'Electropop': {
      'Pop': 0.80,
      'Synthpop': 0.85,
      'EDM': 0.70,
    },
    'Synthpop': {
      'Electropop': 0.85,
      'New Wave': 0.80,
      'Indie Pop': 0.60,
    },
    'K-Pop': {
      'Pop': 0.75,
      'J-Pop': 0.70,
      'Dance Pop': 0.65,
    },
    'J-Pop': {
      'K-Pop': 0.70,
      'Anime OST': 0.80,
    },
    'Anime OST': {
      'J-Pop': 0.80,
      'Soundtrack': 0.60,
    },
    'Hip-Hop': {
      'Rap': 0.95,
      'Trap': 0.85,
      'R&B': 0.75,
      'Afrobeats': 0.55,
      'Drill': 0.80,
    },
    'Rap': {
      'Hip-Hop': 0.95,
      'Trap': 0.90,
      'Drill': 0.85,
    },
    'Trap': {
      'Rap': 0.90,
      'Hip-Hop': 0.85,
      'EDM Trap': 0.75,
    },
    'Drill': {
      'Rap': 0.85,
      'Hip-Hop': 0.80,
    },
    'EDM Trap': {
      'Trap': 0.75,
      'Dubstep': 0.70,
    },
    'R&B': {
      'Hip-Hop': 0.75,
      'Neo-Soul': 0.85,
      'Soul': 0.80,
      'Pop': 0.70,
    },
    'Neo-Soul': {
      'R&B': 0.85,
      'Soul': 0.80,
      'Jazz': 0.70,
    },
    'Soul': {
      'Neo-Soul': 0.80,
      'R&B': 0.80,
      'Funk': 0.75,
    },
    'Funk': {
      'Soul': 0.75,
      'Disco': 0.80,
    },
    'Disco': {
      'Funk': 0.80,
      'House': 0.75,
    },
    'House': {
      'EDM': 0.85,
      'Deep House': 0.90,
      'Amapiano': 0.70,
      'Disco': 0.75,
    },
    'Deep House': {
      'House': 0.90,
      'Chill House': 0.80,
      'Ambient House': 0.70,
    },
    'Chill House': {
      'Deep House': 0.80,
      'Chillout': 0.75,
    },
    'Ambient House': {
      'Deep House': 0.70,
      'Ambient': 0.80,
    },
    'EDM': {
      'House': 0.85,
      'Dance Pop': 0.80,
      'Trance': 0.75,
      'Dubstep': 0.60,
    },
    'Trance': {
      'EDM': 0.75,
      'Techno': 0.70,
      'Eurodance': 0.65,
    },
    'Techno': {
      'Trance': 0.70,
      'Industrial': 0.65,
      'Minimal Techno': 0.75,
    },
    'Minimal Techno': {
      'Techno': 0.75,
      'Ambient Techno': 0.70,
    },
    'Ambient Techno': {
      'Minimal Techno': 0.70,
      'Ambient': 0.75,
    },
    'Dubstep': {
      'EDM': 0.60,
      'Drum & Bass': 0.70,
      'EDM Trap': 0.70,
    },
    'Drum & Bass': {
      'Dubstep': 0.70,
      'Jungle': 0.80,
    },
    'Jungle': {
      'Drum & Bass': 0.80,
      'Breakbeat': 0.75,
    },
    'Breakbeat': {
      'Jungle': 0.75,
      'UK Garage': 0.70,
    },
    'UK Garage': {
      'Breakbeat': 0.70,
      '2-Step': 0.80,
    },
    '2-Step': {
      'UK Garage': 0.80,
      'Future Garage': 0.75,
    },
    'Future Garage': {
      '2-Step': 0.75,
      'Ambient': 0.60,
    },
    'Ambient': {
      'Chillout': 0.85,
      'Ambient House': 0.80,
      'Post-Rock': 0.70,
    },
    'Chillout': {
      'Ambient': 0.85,
      'Lo-Fi': 0.80,
      'Chill House': 0.75,
    },
    'Lo-Fi': {
      'Chillout': 0.80,
      'Hip-Hop': 0.55,
      'Jazzhop': 0.75,
    },
    'Jazzhop': {
      'Lo-Fi': 0.75,
      'Jazz': 0.60,
    },
    'Jazz': {
      'Blues': 0.60,
      'Neo-Soul': 0.70,
      'Smooth Jazz': 0.85,
    },
    'Smooth Jazz': {
      'Jazz': 0.85,
      'R&B': 0.55,
    },
    'Blues': {
      'Rock': 0.55,
      'Soul': 0.65,
      'Jazz': 0.60,
    },
    'Folk': {
      'Indie Rock': 0.60,
      'Folk Rock': 0.80,
    },
    'Folk Rock': {
      'Folk': 0.80,
      'Classic Rock': 0.60,
    },
    'Country': {
      'Folk': 0.70,
      'Bluegrass': 0.80,
    },
    'Bluegrass': {
      'Country': 0.80,
      'Folk': 0.75,
    },
    'Reggae': {
      'Dancehall': 0.85,
      'Afrobeats': 0.70,
      'Ska': 0.75,
    },
    'Ska': {
      'Reggae': 0.75,
      'Punk Rock': 0.60,
    },
    'Dancehall': {
      'Reggae': 0.85,
      'Afrobeats': 0.75,
    },
    'Afrobeats': {
      'Dancehall': 0.75,
      'Amapiano': 0.80,
      'Hip-Hop': 0.55,
    },
    'Amapiano': {
      'Afrobeats': 0.80,
      'House': 0.70,
      'Deep House': 0.60,
    },
    'Latin Pop': {
      'Reggaeton': 0.80,
      'Pop': 0.70,
    },
    'Reggaeton': {
      'Latin Pop': 0.80,
      'Dancehall': 0.70,
    },
    'Salsa': {
      'Latin Jazz': 0.80,
      'Merengue': 0.75,
    },
    'Merengue': {
      'Salsa': 0.75,
      'Bachata': 0.70,
    },
    'Bachata': {
      'Merengue': 0.70,
      'Latin Pop': 0.60,
    },
    'Latin Jazz': {
      'Salsa': 0.80,
      'Jazz': 0.70,
    },
    'Soundtrack': {
      'Classical': 0.75,
      'Ambient': 0.65,
      'Post-Rock': 0.70,
    },
    'Post-Rock': {
      'Ambient': 0.70,
      'Instrumental': 0.75,
    },
    'Instrumental': {
      'Post-Rock': 0.75,
      'Classical': 0.70,
    },
    'Classical': {
      'Instrumental': 0.70,
      'Soundtrack': 0.75,
    },
  };

  /// All genres registered in the matrix. Used by the crate miner
  /// to validate a track's genre string and by the routing service
  /// to decide whether a fallback to the graph is worth attempting.
  Set<String> get knownGenres => _kRaw.keys.toSet();

  /// Returns the raw neighbour map for [genre]. Returns an empty
  /// (unmodifiable) map if [genre] is not in the matrix — this is
  /// the graceful-degradation path for tracks whose primary_genre
  /// column is `'Unknown'` or any other unrecognised value.
  Map<String, double> neighborsOf(String? genre) {
    if (genre == null) return const <String, double>{};
    return _kRaw[genre] ?? const <String, double>{};
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
  /// enough (< 100 vertices) to fully expand.
  ///
  /// Passing `null` yields nothing.
  Iterable<String> searchBreadth(String? startGenre) sync* {
    if (startGenre == null) return;
    // Only yield the seed if it's a known genre in the matrix.
    // The schema default for primary_genre is the literal string
    // 'Unknown' which is not a real genre — yielding it would
    // match the schema-default track and shadow the legitimate
    // neighbours.
    final seedIsKnown = _kRaw.containsKey(startGenre);
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
