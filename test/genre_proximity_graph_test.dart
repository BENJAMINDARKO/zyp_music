// Phase 2 — Genre Proximity Graph
// Validation gate coverage:
//   * Spec excerpt sanity (known genres + adjacency weights match
//     the spec JSON verbatim).
//   * Descending-order traversal.
//   * Symmetric edges in the spec (Rock <-> Alternative Rock: 0.90
//     in both directions) are mirrored.
//   * Graceful degradation for unknown / null genres.

import 'package:flutter_test/flutter_test.dart';

import 'package:zyp_music/core/services/genre_proximity_graph.dart';

void main() {
  const graph = GenreProximityGraph();

  group('GenreProximityGraph.spec', () {
    test('contains the canonical 80+ source genres', () {
      // A non-exhaustive but representative set. Failing this
      // means we lost a section of the spec during transcription.
      for (final g in const [
        'Rock',
        'Alternative Rock',
        'Indie Rock',
        'Classic Rock',
        'Hard Rock',
        'Metal',
        'Heavy Metal',
        'Thrash Metal',
        'Death Metal',
        'Black Metal',
        'Doom Metal',
        'Stoner Metal',
        'Psychedelic Rock',
        'Progressive Rock',
        'Art Rock',
        'Post-Punk',
        'New Wave',
        'Goth Rock',
        'Darkwave',
        'Shoegaze',
        'Dream Pop',
        'Indie Pop',
        'Pop',
        'Dance Pop',
        'Electropop',
        'Synthpop',
        'K-Pop',
        'J-Pop',
        'Anime OST',
        'Hip-Hop',
        'Rap',
        'Trap',
        'Drill',
        'EDM Trap',
        'R&B',
        'Neo-Soul',
        'Soul',
        'Funk',
        'Disco',
        'House',
        'Deep House',
        'Chill House',
        'Ambient House',
        'EDM',
        'Trance',
        'Techno',
        'Minimal Techno',
        'Ambient Techno',
        'Dubstep',
        'Drum & Bass',
        'Jungle',
        'Breakbeat',
        'UK Garage',
        '2-Step',
        'Future Garage',
        'Ambient',
        'Chillout',
        'Lo-Fi',
        'Jazzhop',
        'Jazz',
        'Smooth Jazz',
        'Blues',
        'Folk',
        'Folk Rock',
        'Country',
        'Bluegrass',
        'Reggae',
        'Ska',
        'Dancehall',
        'Afrobeats',
        'Amapiano',
        'Latin Pop',
        'Reggaeton',
        'Salsa',
        'Merengue',
        'Bachata',
        'Latin Jazz',
        'Soundtrack',
        'Post-Rock',
        'Instrumental',
        'Classical',
      ]) {
        expect(graph.knownGenres.contains(g), isTrue,
            reason: 'Missing genre: $g');
      }
    });

    test('Rock neighbours match the spec', () {
      final n = graph.neighborsOf('Rock');
      expect(n['Alternative Rock'], 0.90);
      expect(n['Classic Rock'], 0.85);
      expect(n['Hard Rock'], 0.80);
      expect(n['Indie Rock'], 0.75);
      expect(n['Blues Rock'], 0.70);
    });

    test('Hip-Hop neighbours match the spec', () {
      final n = graph.neighborsOf('Hip-Hop');
      expect(n['Rap'], 0.95);
      expect(n['Trap'], 0.85);
      expect(n['Drill'], 0.80);
      expect(n['R&B'], 0.75);
      expect(n['Afrobeats'], 0.55);
    });

    test('symmetric edges mirror across the matrix', () {
      // The spec lists Rock <-> Alternative Rock as 0.90 in both
      // directions. This is the canonical same-weight pair.
      expect(
        graph.neighborsOf('Rock')['Alternative Rock'],
        graph.neighborsOf('Alternative Rock')['Rock'],
      );
      expect(
        graph.neighborsOf('Hip-Hop')['Rap'],
        graph.neighborsOf('Rap')['Hip-Hop'],
      );
      expect(
        graph.neighborsOf('House')['Deep House'],
        graph.neighborsOf('Deep House')['House'],
      );
    });

    test('unknown genre returns an empty neighbour map', () {
      expect(graph.neighborsOf('Unknown'), isEmpty);
      expect(graph.neighborsOf('Made-Up Genre'), isEmpty);
      expect(graph.neighborsOf(null), isEmpty);
    });
  });

  group('GenreProximityGraph.sorting', () {
    test('neighborsByDescendingProximity is in descending weight order',
        () async {
      final sorted = graph.neighborsByDescendingProximity('Rock');
      for (var i = 1; i < sorted.length; i++) {
        expect(
          sorted[i - 1].value >= sorted[i].value,
          isTrue,
          reason:
              'Sort order violated at index $i: ${sorted[i - 1]} -> ${sorted[i]}',
        );
      }
      // The first entry should be the highest-weight neighbour.
      expect(sorted.first.key, 'Alternative Rock');
      expect(sorted.first.value, 0.90);
    });

    test('searchBreadth starts with the seed genre', () {
      final list = graph.searchBreadth('Rock').toList();
      expect(list.first, 'Rock');
    });

    test('searchBreadth visits neighbours in descending weight order', () {
      final list = graph.searchBreadth('Rock').toList();
      // Position 0 = Rock (exact match). Positions 1..5 = first-
      // degree neighbours in descending weight order.
      expect(list[1], 'Alternative Rock'); // 0.90
      expect(list[2], 'Classic Rock'); // 0.85
      expect(list[3], 'Hard Rock'); // 0.80
      expect(list[4], 'Indie Rock'); // 0.75
      expect(list[5], 'Blues Rock'); // 0.70
    });

    test('searchBreadth on an unknown genre yields nothing', () {
      expect(graph.searchBreadth('Unknown').toList(), isEmpty);
      expect(graph.searchBreadth(null).toList(), isEmpty);
    });

    test('searchBreadth expands to second-degree neighbours', () {
      // 'Metal' is reachable from 'Rock' only at depth 2 (via
      // Rock -> Hard Rock -> Metal). 'Indie Rock' is also a direct
      // Rock neighbour (depth 1), so it's not a useful depth-2
      // canary. 'Metal' is.
      final list = graph.searchBreadth('Rock').toList();
      expect(list.contains('Metal'), isTrue);
      // All of Rock's first-degree neighbours (Alternative Rock,
      // Classic Rock, Hard Rock, Indie Rock, Blues Rock) should
      // appear before Metal.
      final idxMetal = list.indexOf('Metal');
      final idxBluesRock = list.indexOf('Blues Rock');
      expect(idxBluesRock < idxMetal, isTrue,
          reason: 'Metal (depth 2) should be explored after Blues Rock (depth 1)');
    });
  });
}
