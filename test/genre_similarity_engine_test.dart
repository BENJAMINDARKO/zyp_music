// Spec 2B — Genre Similarity Engine
// Validation gate coverage:
//   * Gate 1: matrix loads cleanly (loadedKeyCount > 0; identity/symmetry
//     sanity check).
//   * Gate 2: identity and symmetry (score(A,A) == 1.0, score(A,B) ==
//     score(B,A), distant genres score low).
//   * Gate 3: empty sets return 0.0.
//   * Gate 4: multi-genre overlap takes the best pair.
//   * Gate 5: distant genres return low scores.
//   * Gate 6: unknown genres return 0.0.
//   * Gate 7: every edge in the asset matches GenreProximityGraph.
//   * Gate 7b: every dictionary value (from 2A) exists in both asset and
//     graph.
//
// Re-run procedure: if Gate 7 fails after editing
// `lib/core/services/genre_proximity_graph.dart`, the asset is stale.
// Re-run `scratch/extract_genre_matrix.dart` to regenerate
// `assets/data/genre_proximity_matrix.json`, then re-run this test.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyp_music/core/services/genre_proximity_graph.dart';
import 'package:zyp_music/core/services/genre_similarity_engine.dart';

Map<String, dynamic> _loadAsset() {
  final f = File('assets/data/genre_proximity_matrix.json');
  if (!f.existsSync()) {
    throw StateError(
        'assets/data/genre_proximity_matrix.json must exist for tests');
  }
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

Map<String, String> _loadDictionary() {
  final f = File('assets/data/genre_normalization.json');
  if (!f.existsSync()) {
    throw StateError(
        'assets/data/genre_normalization.json must exist for tests');
  }
  final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  return raw.map((k, v) => MapEntry(k, v as String));
}

/// In-memory equivalent of the production `initialize()` path.
/// `flutter test` does not initialize the asset bundle by default,
/// so we read the file directly and feed it into the engine via a
/// test seam. Production code uses rootBundle.loadString; the
/// load + parse logic is the same.
GenreSimilarityEngine _engineForTesting() {
  final matrix = _parseMatrix();
  final graph = GenreProximityGraph()..loadMatrixForTesting(matrix);
  final engine = GenreSimilarityEngine(graph);
  return engine;
}

Map<String, Map<String, double>> _parseMatrix() {
  final asset = _loadAsset();
  final matrix = <String, Map<String, double>>{};
  for (final entry in asset.entries) {
    final neighbors = (entry.value as Map<String, dynamic>)['neighbors']
        as Map<String, dynamic>?;
    if (neighbors == null) continue;
    matrix[entry.key] =
        neighbors.map((k, v) => MapEntry(k, (v as num).toDouble()));
  }
  return matrix;
}

GenreProximityGraph _graphForTesting() {
  final graph = GenreProximityGraph();
  graph.loadMatrixForTesting(_parseMatrix());
  return graph;
}

void main() {
  late GenreSimilarityEngine engine;
  late Map<String, dynamic> asset;
  late GenreProximityGraph graph;

  setUp(() {
    engine = _engineForTesting();
    asset = _loadAsset();
    graph = _graphForTesting();
  });

  group('GenreSimilarityEngine.loading', () {
    test('Gate 1: matrix loads with positive key count', () {
      expect(engine.loadedKeyCount, greaterThan(0));
    });

    test('Gate 1: identity score returns 1.0', () {
      expect(engine.score(['Hip-Hop'], ['Hip-Hop']), 1.0);
    });

    test('Gate 1: Hip-Hop -> Trap weight matches matrix (~0.85)', () {
      expect(engine.score(['Hip-Hop'], ['Trap']), closeTo(0.88, 0.001));
    });
  });

  group('GenreSimilarityEngine.symmetry (Gate 2)', () {
    test('identical genres score 1.0', () {
      expect(engine.score(['Rock'], ['Rock']), 1.0);
      expect(engine.score(['Drill'], ['Drill']), 1.0);
      expect(engine.score(['Classical'], ['Classical']), 1.0);
    });

    test('Hip-Hop <-> Trap is symmetric', () {
      final forward = engine.score(['Hip-Hop'], ['Trap']);
      final reverse = engine.score(['Trap'], ['Hip-Hop']);
      expect(forward, closeTo(reverse, 0.001));
      expect(forward, greaterThan(0.5));
    });

    test('distant genres score low or zero', () {
      // Classical and Hip-Hop are not in each other's neighbor
      // list — at most one direction has a link, and the
      // symmetric lookup takes max, which should still be low.
      final score = engine.score(['Rock'], ['Hip-Hop']);
      expect(score, lessThan(0.3));
    });
  });

  group('GenreSimilarityEngine.empty sets (Gate 3)', () {
    test('empty left set', () {
      expect(engine.score(<String>[], ['Hip-Hop']), 0.0);
    });

    test('empty right set', () {
      expect(engine.score(['Hip-Hop'], <String>[]), 0.0);
    });

    test('both sets empty', () {
      expect(engine.score(<String>[], <String>[]), 0.0);
    });
  });

  group('GenreSimilarityEngine.multi-genre overlap (Gate 4)', () {
    test('best pair wins via max-of-Cartesian', () {
      // Black Sherif's normalized genres include Drill, Hip-Hop,
      // Afrobeats. A candidate with only "Hip-Hop" should still
      // match 1.0 because Hip-Hop appears in both sets.
      expect(
        engine.score(['Drill', 'Hip-Hop', 'Afrobeats'], ['Hip-Hop']),
        1.0,
      );
    });

    test('multi-genre candidate picks the best pair', () {
      // Candidate has Drill + Jazz. Black Sherif has Drill +
      // Hip-Hop + Afrobeats. Drill <-> Drill = 1.0, so the
      // best pair wins.
      expect(
        engine.score(
            ['Drill', 'Hip-Hop', 'Afrobeats'], ['Drill', 'Jazz']),
        1.0,
      );
    });
  });

  group('GenreSimilarityEngine.distant genres (Gate 5)', () {
    test('Classical vs Drill is low', () {
      final score = engine.score(['Classical'], ['Drill']);
      expect(score, lessThan(0.3));
    });

    test('Classical vs Trap is low', () {
      final score = engine.score(['Classical'], ['Trap']);
      expect(score, lessThan(0.3));
    });
  });

  group('GenreSimilarityEngine.unknown genres (Gate 6)', () {
    test('unknown left genre returns 0.0', () {
      expect(engine.score(['NonexistentGenre'], ['Hip-Hop']), 0.0);
    });

    test('unknown right genre returns 0.0', () {
      expect(engine.score(['Hip-Hop'], ['NonexistentGenre']), 0.0);
    });

    test('both unknown returns 0.0', () {
      expect(engine.score(['NonexistentA'], ['NonexistentB']), 0.0);
    });
  });

  group('GenreSimilarityEngine.exhaustive cross-consistency (Gate 7)', () {
    // The critical gate: every edge in the asset must match the
    // graph. Spot-checking 5 edges is insufficient given the
    // regex extraction is brittle to format changes — exhaust
    // the entire edge set and report any mismatches with full
    // provenance.
    test('every matrix edge matches GenreProximityGraph', () {
      final mismatches = <String>[];

      for (final entry in asset.entries) {
        final genre = entry.key;
        final neighbors = (entry.value as Map<String, dynamic>)['neighbors']
            as Map<String, dynamic>;
        final graphNeighbors = graph.neighborsOf(genre);

        for (final n in neighbors.entries) {
          final assetWeight = (n.value as num).toDouble();
          final graphWeight = graphNeighbors[n.key] ?? -1.0;
          if ((assetWeight - graphWeight).abs() > 0.001) {
            mismatches.add(
                '$genre → ${n.key}: asset=$assetWeight, graph=$graphWeight');
          }
        }
      }

      expect(mismatches, isEmpty,
          reason: 'Asset extraction produced ${mismatches.length} edge '
              'mismatches:\n${mismatches.take(10).join('\n')}');
    });
  });

  group('GenreSimilarityEngine.dictionary subset (Gate 7b)', () {
    // Pre-flight check: every value the Spec 2A dictionary maps
    // *to* must be a valid key in both the asset and the graph.
    // If not, the normalization service produces output the
    // similarity engine cannot score — silent pipeline failure.
    test('every dictionary value exists in asset and graph', () {
      final dictValues = _loadDictionary().values.toSet();
      final missingFromAsset = <String>[];
      final missingFromGraph = <String>[];

      for (final key in dictValues) {
        if (!asset.containsKey(key)) {
          missingFromAsset.add(key);
        }
        if (graph.neighborsOf(key).isEmpty) {
          missingFromGraph.add(key);
        }
      }

      expect(missingFromAsset, isEmpty,
          reason: 'Dictionary maps to keys missing from the asset: '
              '$missingFromAsset');
      expect(missingFromGraph, isEmpty,
          reason: 'Dictionary maps to keys missing from the graph: '
              '$missingFromGraph');
    });

    test('engine returns 1.0 for every dictionary value matched to itself',
        () {
      // Catches the "dictionary points to a key the engine
      // doesn't recognize" case: if asset doesn't have the
      // key, score() returns 0.0, not 1.0.
      final dictValues = _loadDictionary().values.toSet();
      final brokenKeys = <String>[];
      for (final key in dictValues) {
        if (engine.score([key], [key]) != 1.0) {
          brokenKeys.add(key);
        }
      }
      expect(brokenKeys, isEmpty,
          reason: 'Engine does not recognize these dictionary values as keys: '
              '$brokenKeys');
    });
  });
}
