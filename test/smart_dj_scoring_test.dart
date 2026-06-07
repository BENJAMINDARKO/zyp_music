// Spec 2C Section B.7 — Smart DJ scoring unit tests.
//
// These tests exercise [smartDjIsolateScore] directly (no
// isolate spawn, no ledger, no DB) so the new three-term
// formula can be validated in isolation. The full-stack
// integration test for the Black Sherif bug reproduction
// lives in [auto_dj_routing_service_test.dart].
//
// Bug reproduction gate: when the seed artist is "Black
// Sherif" and the candidate pool is dominated by Black
// Sherif tracks, the new artist_diversity term must push
// Sarkodie / Drake to the top — the pre-Spec-2C formula
// relied on exact-artist match (giving Black Sherif 0.5
// for `artistMatch` + 0.3 for genre) so the same-artist
// tracks were inflated, causing same-artist 5-in-a-row
// churn. The new formula gives the seed artist
// `diversity=0.0` (hard zero), so it cannot win unless
// the pool is exclusively the seed artist.

import 'package:flutter_test/flutter_test.dart';

import 'package:zyp_music/core/services/auto_dj_routing_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Map<String, dynamic> candidate({
    required String id,
    required String artist,
    String? genre,
  }) =>
      <String, dynamic>{
        'id': id,
        'title': 'T$id',
        'author': artist,
        'genre': genre,
      };

  Map<String, dynamic> historyEntry({
    required String trackId,
    required String artist,
    String primaryGenre = 'Hip-Hop',
    int timestampMs = 1000,
  }) =>
      <String, dynamic>{
        'trackId': trackId,
        'artistName': artist,
        'primaryGenre': primaryGenre,
        'timestampMs': timestampMs,
      };

  /// Identifies a candidate by id and returns its score from
  /// the scored results list. Throws if the id is missing.
  double scoreFor(
    List<Map<String, dynamic>> results,
    String id,
  ) {
    for (final r in results) {
      if (r['trackId'] == id) return (r['score'] as num).toDouble();
    }
    fail('No scored result for id="$id"');
  }

  // ---------------------------------------------------------------------------
  // Bug reproduction: Black Sherif must NOT win when the pool
  // is dominated by Black Sherif tracks.
  // ---------------------------------------------------------------------------

  group('smartDjIsolateScore — Black Sherif bug reproduction', () {
    test('seed=Black Sherif, 5 BS + 3 Sarkodie + 2 Drake → top is NOT Black Sherif',
        () {
      // Pool: 5 Black Sherif (same as seed), 3 Sarkodie, 2 Drake.
      // Genre similarity matrix: Hip-Hop ↔ Hiplife ≈ 0.7, Hip-Hop
      // ↔ Rap ≈ 0.8, Hip-Hop ↔ Afrobeats ≈ 0.5 (illustrative
      // numbers — the exact values don't matter for this gate;
      // what matters is that all non-seed candidates score
      // higher on `diversity` than the seed candidates).
      final candidates = <Map<String, dynamic>>[
        for (int i = 0; i < 5; i++)
          candidate(id: 'bs_$i', artist: 'Black Sherif', genre: 'Hip-Hop'),
        for (int i = 0; i < 3; i++)
          candidate(id: 'sark_$i', artist: 'Sarkodie', genre: 'Hiplife'),
        for (int i = 0; i < 2; i++)
          candidate(id: 'drake_$i', artist: 'Drake', genre: 'Rap'),
      ];

      // Seed is the most recent history row.
      final state = <Map<String, dynamic>>[
        historyEntry(trackId: 'seed', artist: 'Black Sherif'),
      ];

      // Recent artists (QueueManager session) — Black Sherif
      // was just played.
      final recentArtists = <String>['black sherif'];

      // Precomputed genre similarity: 0.7 for Hiplife, 0.8
      // for Rap, 0.5 for any unknown.
      final precomputed = <String, double>{
        for (int i = 0; i < 5; i++) 'bs_$i': 0.5,
        for (int i = 0; i < 3; i++) 'sark_$i': 0.7,
        for (int i = 0; i < 2; i++) 'drake_$i': 0.8,
      };

      final input = SmartDjScoreInput(
        candidates: candidates,
        stateEntries: state,
        fullHistory: state,
        topLikedArtists: const <String>[],
        topLikedGenres: const <String>[],
        beta: 0.0, // Disable Liked-Song bias — pure formula gate.
        precomputedGenreSimilarity: precomputed,
        recentArtists: recentArtists,
        useColdStart: false, // Full-history formula.
      );

      final results = smartDjIsolateScore(input);

      // The bug: pre-Spec-2C, the top pick was always the
      // seed artist (same-artist 5-in-a-row churn). The new
      // formula's `diversity=0.0` for the seed artist means
      // a Black Sherif candidate cannot win the sort.
      final blackSherifScores = [
        for (int i = 0; i < 5; i++) scoreFor(results, 'bs_$i'),
      ];
      final sarkodieScores = [
        for (int i = 0; i < 3; i++) scoreFor(results, 'sark_$i'),
      ];
      final drakeScores = [
        for (int i = 0; i < 2; i++) scoreFor(results, 'drake_$i'),
      ];

      // Bug gate: every Black Sherif candidate must score
      // LOWER than every non-seed candidate. (Seed gets
      // diversity=0.0 → max markov = 0.40·0.5 = 0.20, vs.
      // non-seed = 0.40·1.0 + 0.40·0.7 = 0.68.)
      final maxBlackSherif =
          blackSherifScores.reduce((a, b) => a > b ? a : b);
      final minNonSeed = [
        ...sarkodieScores,
        ...drakeScores,
      ].reduce((a, b) => a < b ? a : b);

      expect(
        maxBlackSherif < minNonSeed,
        isTrue,
        reason:
            'Bug: seed artist should be de-prioritised. '
            'max(BS)=$maxBlackSherif, min(non-seed)=$minNonSeed',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Formula correctness — three terms + cold-start path
  // ---------------------------------------------------------------------------

  group('smartDjIsolateScore — formula correctness', () {
    test('full-history formula = 0.40·diversity + 0.40·genre + 0.20·temporal', () {
      // One seed, one candidate. Seed = "X", candidate = "Y"
      // (different artist). Genre similarity = 0.6 (provided
      // via precomputed). History has X → Y once. With β=0
      // (no Liked-Song bias) the score should be exactly
      // 0.40·1.0 + 0.40·0.6 + 0.20·temporal.
      final candidates = <Map<String, dynamic>>[
        candidate(id: 'cand', artist: 'Y', genre: 'G'),
      ];
      final state = <Map<String, dynamic>>[
        historyEntry(trackId: 'seed', artist: 'X'),
      ];
      final fullHistory = <Map<String, dynamic>>[
        historyEntry(trackId: 'h1', artist: 'X', timestampMs: 200),
        historyEntry(trackId: 'h2', artist: 'Y', timestampMs: 100),
      ];
      final precomputed = <String, double>{'cand': 0.6};
      final input = SmartDjScoreInput(
        candidates: candidates,
        stateEntries: state,
        fullHistory: fullHistory,
        topLikedArtists: const <String>[],
        topLikedGenres: const <String>[],
        beta: 0.0,
        precomputedGenreSimilarity: precomputed,
        recentArtists: const <String>[],
        useColdStart: false,
      );

      final results = smartDjIsolateScore(input);
      final s = scoreFor(results, 'cand');

      // Temporal = (freq + 1) / (N + |S|) = (1 + 1) / (1 + 1) = 1.0
      // Markov = 0.40 + 0.24 + 0.20 = 0.84
      expect(s, closeTo(0.84, 1e-6));
    });

    test('cold-start formula = 0.50·diversity + 0.50·genre (no temporal)', () {
      // Identical setup, but useColdStart=true drops the
      // temporal term entirely.
      final candidates = <Map<String, dynamic>>[
        candidate(id: 'cand', artist: 'Y', genre: 'G'),
      ];
      final state = <Map<String, dynamic>>[
        historyEntry(trackId: 'seed', artist: 'X'),
      ];
      final precomputed = <String, double>{'cand': 0.6};
      final input = SmartDjScoreInput(
        candidates: candidates,
        stateEntries: state,
        fullHistory: state, // Empty history: still seeded with one row.
        topLikedArtists: const <String>[],
        topLikedGenres: const <String>[],
        beta: 0.0,
        precomputedGenreSimilarity: precomputed,
        recentArtists: const <String>[],
        useColdStart: true,
      );

      final results = smartDjIsolateScore(input);
      final s = scoreFor(results, 'cand');

      // Cold-start: 0.50·1.0 + 0.50·0.6 = 0.80
      expect(s, closeTo(0.80, 1e-6));
    });

    test('seed artist gets diversity=0.0 (hard zero, cannot win)', () {
      // Candidate IS the seed artist. Even with high genre
      // similarity and high temporal frequency, the
      // diversity term is 0.0, so the markov component
      // collapses to 0.40·0.0 + 0.40·1.0 + 0.20·1.0 = 0.60.
      // A non-seed candidate with the same genre sim would
      // score 0.40·1.0 + 0.40·1.0 + 0.20·1.0 = 1.00.
      final candidates = <Map<String, dynamic>>[
        candidate(id: 'cand', artist: 'X', genre: 'G'),
      ];
      final state = <Map<String, dynamic>>[
        historyEntry(trackId: 'seed', artist: 'X'),
      ];
      final fullHistory = <Map<String, dynamic>>[
        historyEntry(trackId: 'h1', artist: 'X', timestampMs: 200),
        historyEntry(trackId: 'h2', artist: 'X', timestampMs: 100),
      ];
      final precomputed = <String, double>{'cand': 1.0};
      final input = SmartDjScoreInput(
        candidates: candidates,
        stateEntries: state,
        fullHistory: fullHistory,
        topLikedArtists: const <String>[],
        topLikedGenres: const <String>[],
        beta: 0.0,
        precomputedGenreSimilarity: precomputed,
        recentArtists: const <String>[],
        useColdStart: false,
      );

      final results = smartDjIsolateScore(input);
      final s = scoreFor(results, 'cand');

      // diversity=0.0, genreSim=1.0, temporal=(2+1)/(2+1)=1.0
      // markov = 0.40·0.0 + 0.40·1.0 + 0.20·1.0 = 0.60
      expect(s, closeTo(0.60, 1e-6));
    });

    test('recent (but non-seed) artist gets diversity=0.3', () {
      // Seed is X, but the candidate is Y which appears in
      // the recent session history. diversity=0.3.
      // Note: with N=0 observed transitions, Laplace
      // smoothing gives temporal=1/(0+1)=1.0 for every
      // candidate — a property of the smoothing, not a bug.
      final candidates = <Map<String, dynamic>>[
        candidate(id: 'cand', artist: 'Y', genre: 'G'),
      ];
      final state = <Map<String, dynamic>>[
        historyEntry(trackId: 'seed', artist: 'X'),
      ];
      final precomputed = <String, double>{'cand': 0.0};
      final input = SmartDjScoreInput(
        candidates: candidates,
        stateEntries: state,
        fullHistory: state,
        topLikedArtists: const <String>[],
        topLikedGenres: const <String>[],
        beta: 0.0,
        precomputedGenreSimilarity: precomputed,
        recentArtists: const <String>['y'], // Y is recent.
        useColdStart: false,
      );

      final results = smartDjIsolateScore(input);
      final s = scoreFor(results, 'cand');

      // diversity=0.3, genreSim=0.0, temporal=1.0 (Laplace)
      // markov = 0.40·0.3 + 0.40·0.0 + 0.20·1.0 = 0.32
      expect(s, closeTo(0.32, 1e-6));
    });

    test('unknown artist (null) gets diversity=0.5 (neutral)', () {
      // Candidate has no artist. diversity=0.5.
      final candidates = <Map<String, dynamic>>[
        candidate(id: 'cand', artist: '', genre: 'G'),
      ];
      final state = <Map<String, dynamic>>[
        historyEntry(trackId: 'seed', artist: 'X'),
      ];
      final precomputed = <String, double>{'cand': 0.0};
      final input = SmartDjScoreInput(
        candidates: candidates,
        stateEntries: state,
        fullHistory: state,
        topLikedArtists: const <String>[],
        topLikedGenres: const <String>[],
        beta: 0.0,
        precomputedGenreSimilarity: precomputed,
        recentArtists: const <String>[],
        useColdStart: false,
      );

      final results = smartDjIsolateScore(input);
      final s = scoreFor(results, 'cand');

      // diversity=0.5, genreSim=0.0, temporal=1.0 (Laplace)
      // markov = 0.40·0.5 + 0.40·0.0 + 0.20·1.0 = 0.40
      expect(s, closeTo(0.40, 1e-6));
    });

    test('case-insensitive: "Black Sherif" and "black sherif" treated the same', () {
      // Bug-regression gate: spec flagged the case-sensitivity
      // trap. Seed stored as "Black Sherif" (capitalised),
      // candidate stored as "black sherif" (lowercase) — the
      // seed match must still trigger diversity=0.0.
      final candidates = <Map<String, dynamic>>[
        candidate(id: 'cand', artist: 'black sherif', genre: 'G'),
      ];
      final state = <Map<String, dynamic>>[
        historyEntry(trackId: 'seed', artist: 'Black Sherif'),
      ];
      final precomputed = <String, double>{'cand': 1.0};
      final input = SmartDjScoreInput(
        candidates: candidates,
        stateEntries: state,
        fullHistory: state,
        topLikedArtists: const <String>[],
        topLikedGenres: const <String>[],
        beta: 0.0,
        precomputedGenreSimilarity: precomputed,
        recentArtists: const <String>[],
        useColdStart: false,
      );

      final results = smartDjIsolateScore(input);
      final s = scoreFor(results, 'cand');

      // diversity=0.0 (case-insensitive match), genreSim=1.0,
      // temporal=1.0 (Laplace, no observed transitions).
      // markov = 0.40·0.0 + 0.40·1.0 + 0.20·1.0 = 0.60
      expect(s, closeTo(0.60, 1e-6));
    });

    test('Liked-Song bias (β=0.6) blends with markov when topLikedArtists matches', () {
      // β=0.6, candidate artist "Z" is in topLikedArtists.
      // markov = 0.40·1.0 + 0.40·0.0 + 0.20·1.0 = 0.60
      // affinity = 0.6 (artist match, no genre)
      // score = (1-0.6)·0.60 + 0.6·0.6 = 0.24 + 0.36 = 0.60
      final candidates = <Map<String, dynamic>>[
        candidate(id: 'cand', artist: 'Z', genre: 'G'),
      ];
      final state = <Map<String, dynamic>>[
        historyEntry(trackId: 'seed', artist: 'X'),
      ];
      final precomputed = <String, double>{'cand': 0.0};
      final input = SmartDjScoreInput(
        candidates: candidates,
        stateEntries: state,
        fullHistory: state,
        topLikedArtists: const <String>['Z'],
        topLikedGenres: const <String>[],
        beta: 0.6,
        precomputedGenreSimilarity: precomputed,
        recentArtists: const <String>[],
        useColdStart: false,
      );

      final results = smartDjIsolateScore(input);
      final s = scoreFor(results, 'cand');

      expect(s, closeTo(0.60, 1e-6));
    });

    test('Liked-Song genre reallocation: candidate with null genre + matching artist scores 1.0',
        () {
      // affinityFor() reallocation: if candidate.genre is
      // null, the 0.4 genre weight goes to the artist. A
      // matching artist therefore scores 1.0.
      // markov = 0.40·1.0 + 0.40·0.0 + 0.20·1.0 = 0.60
      // affinity = 1.0 (full reallocation)
      // score = (1-0.6)·0.60 + 0.6·1.0 = 0.24 + 0.60 = 0.84
      final candidates = <Map<String, dynamic>>[
        candidate(id: 'cand', artist: 'Z', genre: null),
      ];
      final state = <Map<String, dynamic>>[
        historyEntry(trackId: 'seed', artist: 'X'),
      ];
      final precomputed = <String, double>{'cand': 0.0};
      final input = SmartDjScoreInput(
        candidates: candidates,
        stateEntries: state,
        fullHistory: state,
        topLikedArtists: const <String>['Z'],
        topLikedGenres: const <String>[],
        beta: 0.6,
        precomputedGenreSimilarity: precomputed,
        recentArtists: const <String>[],
        useColdStart: false,
      );

      final results = smartDjIsolateScore(input);
      final s = scoreFor(results, 'cand');

      expect(s, closeTo(0.84, 1e-6));
    });

    test('temporal term discriminates: 3 observed X→Y transitions vs 0 X→Z', () {
      // With observed transitions, Laplace smoothing no
      // longer dominates — candidates that actually
      // followed the seed artist score higher.
      // History: X→Y three times, X→Z never. The temporal
      // denominator = (3 + 2) = 5 (Laplace over 2 distinct
      // successors). Y gets (3+1)/5 = 0.8, Z gets
      // (0+1)/5 = 0.2.
      final candidates = <Map<String, dynamic>>[
        candidate(id: 'y', artist: 'Y', genre: 'G'),
        candidate(id: 'z', artist: 'Z', genre: 'G'),
      ];
      final state = <Map<String, dynamic>>[
        historyEntry(trackId: 'seed', artist: 'X'),
      ];
      final fullHistory = <Map<String, dynamic>>[
        historyEntry(trackId: 'h0', artist: 'X', timestampMs: 700),
        historyEntry(trackId: 'h1', artist: 'Y', timestampMs: 600),
        historyEntry(trackId: 'h2', artist: 'X', timestampMs: 500),
        historyEntry(trackId: 'h3', artist: 'Y', timestampMs: 400),
        historyEntry(trackId: 'h4', artist: 'X', timestampMs: 300),
        historyEntry(trackId: 'h5', artist: 'Y', timestampMs: 200),
      ];
      final precomputed = <String, double>{'y': 0.0, 'z': 0.0};
      final input = SmartDjScoreInput(
        candidates: candidates,
        stateEntries: state,
        fullHistory: fullHistory,
        topLikedArtists: const <String>[],
        topLikedGenres: const <String>[],
        beta: 0.0,
        precomputedGenreSimilarity: precomputed,
        recentArtists: const <String>[],
        useColdStart: false,
      );

      final results = smartDjIsolateScore(input);
      final sY = scoreFor(results, 'y');
      final sZ = scoreFor(results, 'z');

      // Both have diversity=1.0 (Y and Z are not the seed,
      // not in recent). genreSim=0.0 for both.
      // distinctSuccessors=1 (only Y), denominator=3+1=4.
      // Y: temporal=(3+1)/4=1.0, markov=0.40+0+0.20·1.0=0.60
      // Z: temporal=(0+1)/4=0.25, markov=0.40+0+0.20·0.25=0.45
      expect(sY, closeTo(0.60, 1e-6));
      expect(sZ, closeTo(0.45, 1e-6));
      expect(sY, greaterThan(sZ));
    });
  });

  // ---------------------------------------------------------------------------
  // Spec 2G Fix #1 — cold-start guard removed from _smartDj.
  // The new formula's cold-start path (useColdStart=true) drops
  // the temporal term and uses 50/50 diversity + genre_similarity
  // weights. With an empty `recentArtists` list (simulating a
  // fresh session — no QueueManager session history yet), a
  // Black Sherif seed must not pick a Black Sherif candidate.
  // ---------------------------------------------------------------------------

  group('Spec 2G Fix #1 — cold-start formula path', () {
    test('seed=Black Sherif, empty recentArtists (fresh session), '
        'useColdStart=true → top pick is NOT Black Sherif', () {
      // Pool: 5 Black Sherif (same as seed), 3 Sarkodie, 2 Drake.
      // Empty recentArtists (fresh session). useColdStart=true.
      final candidates = <Map<String, dynamic>>[
        for (int i = 0; i < 5; i++)
          candidate(id: 'bs_$i', artist: 'Black Sherif', genre: 'Hip-Hop'),
        for (int i = 0; i < 3; i++)
          candidate(id: 'sark_$i', artist: 'Sarkodie', genre: 'Hiplife'),
        for (int i = 0; i < 2; i++)
          candidate(id: 'drake_$i', artist: 'Drake', genre: 'Rap'),
      ];

      // Seed only — no history rows.
      final state = <Map<String, dynamic>>[
        historyEntry(trackId: 'seed', artist: 'Black Sherif'),
      ];

      // Empty recentArtists — fresh session.
      final precomputed = <String, double>{
        for (int i = 0; i < 5; i++) 'bs_$i': 0.5,
        for (int i = 0; i < 3; i++) 'sark_$i': 0.7,
        for (int i = 0; i < 2; i++) 'drake_$i': 0.8,
      };

      final input = SmartDjScoreInput(
        candidates: candidates,
        stateEntries: state,
        fullHistory: state,
        topLikedArtists: const <String>[],
        topLikedGenres: const <String>[],
        beta: 0.0,
        precomputedGenreSimilarity: precomputed,
        recentArtists: const <String>[], // Fresh session.
        useColdStart: true, // Cold-start formula.
      );

      final results = smartDjIsolateScore(input);

      // Spec 2G Fix #1 gate: a Black Sherif candidate must
      // NEVER have the highest score in cold-start. The
      // pre-fix behaviour was to early-return to
      // `_attributeIntersection` which lacks the diversity
      // term — a Black Sherif candidate could win the sort.
      // The fix lets execution flow into the new formula,
      // which assigns diversity=0.0 to seed-artist
      // candidates and 1.0 to others (no recent match).
      final blackSherifScores = [
        for (int i = 0; i < 5; i++) scoreFor(results, 'bs_$i'),
      ];
      final sarkodieScores = [
        for (int i = 0; i < 3; i++) scoreFor(results, 'sark_$i'),
      ];
      final drakeScores = [
        for (int i = 0; i < 2; i++) scoreFor(results, 'drake_$i'),
      ];

      final maxBlackSherif =
          blackSherifScores.reduce((a, b) => a > b ? a : b);
      final maxNonSeed = [
        ...sarkodieScores,
        ...drakeScores,
      ].reduce((a, b) => a > b ? a : b);

      expect(maxBlackSherif, lessThan(maxNonSeed),
          reason: 'Spec 2G Fix #1: in cold-start, seed-artist candidates '
              'must NOT win. maxBlackSherif=$maxBlackSherif '
              'maxNonSeed=$maxNonSeed');

      // Stronger gate: the highest-scoring single track must
      // be a Sarkodie or Drake track — never Black Sherif.
      final allScored = <MapEntry<String, double>>[
        for (int i = 0; i < 5; i++)
          MapEntry('bs_$i', scoreFor(results, 'bs_$i')),
        for (int i = 0; i < 3; i++)
          MapEntry('sark_$i', scoreFor(results, 'sark_$i')),
        for (int i = 0; i < 2; i++)
          MapEntry('drake_$i', scoreFor(results, 'drake_$i')),
      ];
      allScored.sort((a, b) => b.value.compareTo(a.value));
      final topId = allScored.first.key;
      expect(topId, isNot(startsWith('bs_')),
          reason: 'Top-scored pick must not be a Black Sherif track; '
              'got trackId="$topId"');
      expect(topId.startsWith('sark_') || topId.startsWith('drake_'),
          isTrue,
          reason: 'Top-scored pick should be a Sarkodie or Drake track');
    });

    test('cold-start with no candidates and empty history: '
        'scoring returns empty results (no crash, no picks)', () {
      final input = SmartDjScoreInput(
        candidates: const <Map<String, dynamic>>[],
        stateEntries: const <Map<String, dynamic>>[],
        fullHistory: const <Map<String, dynamic>>[],
        topLikedArtists: const <String>[],
        topLikedGenres: const <String>[],
        beta: 0.0,
        precomputedGenreSimilarity: const <String, double>{},
        recentArtists: const <String>[],
        useColdStart: true,
      );
      // Must not throw.
      final results = smartDjIsolateScore(input);
      expect(results, isEmpty);
    });
  });
}
