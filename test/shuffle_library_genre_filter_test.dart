// Spec 2D — Shuffle Library genre filter unit tests.
//
// The filter is a matrix key (e.g. "Afrobeats", "Hip-Hop")
// applied to the local crate via [GenreNormalizationService]
// so the comparison is matrix-key-to-matrix-key, not
// raw-MB-tag-to-matrix-key. The acceptance gates:
//
//   1. Filter matches: only tracks whose normalized genre
//      equals the filter are eligible.
//   2. <5 matches: silent fallback to unfiltered pool
//      (avoids degenerate single-track shuffle loops).
//   3. No filter set: full crate is used (regression gate
//      for the existing Shuffle Library behaviour).
//   4. Filter set but normalizer missing: silent fallback
//      with a warning (graceful degradation).
//   5. Unmapped raw genres: not included in the filtered
//      pool (and not in the crate's "all tracks" list for
//      filter purposes — only normalised matches count).

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:zyp_music/core/services/auto_dj_routing_service.dart';
import 'package:zyp_music/core/services/dj_history_ledger.dart';
import 'package:zyp_music/core/services/genre_normalization_service.dart';
import 'package:zyp_music/core/services/hybrid_cache_service.dart';
import 'package:zyp_music/core/services/local_crate_miner.dart';
import 'package:zyp_music/domain/entities/auto_dj_mode.dart';
import 'package:zyp_music/domain/entities/video.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // ---------------------------------------------------------------------------
  // Test fixture helpers
  // ---------------------------------------------------------------------------

  Future<_RouterStack> _buildStack({
    required List<Track> crate,
    GenreNormalizationService? genreNormalization,
    int randomSeed = 0,
  }) async {
    final tmp = Directory.systemTemp.createTempSync('zyp_shuffle_');
    final miner = LocalCrateMiner(
      sqliteSource: () async => crate
          .map((t) => {
                'id': t.id,
                'title': t.title,
                'filePath': p.join(tmp.path, '${t.id}.m4a'),
                'durationSeconds': t.duration?.inSeconds,
                'author': t.author,
                'genre': t.genre,
              })
          .toList(),
      hybridCache: _FakeHybridCache(const []),
      fileExists: (_) async => true,
      hiveAudioPathResolver: (_) async => null,
    );

    for (final t in crate) {
      File(p.join(tmp.path, '${t.id}.m4a')).writeAsBytesSync([]);
    }

    final dbPath = p.join(tmp.path, 'ledger.db');
    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE dj_listening_history (
              id           INTEGER PRIMARY KEY AUTOINCREMENT,
              track_id     TEXT    NOT NULL,
              artist_name  TEXT    NOT NULL,
              primary_genre TEXT   DEFAULT 'Unknown',
              bpm          REAL    DEFAULT 0.0,
              energy_level REAL    DEFAULT 0.5,
              timestamp    INTEGER NOT NULL
            )
          ''');
        },
      ),
    );
    final ledger = DJHistoryLedger(db, rng: Random(randomSeed));

    final router = AutoDjRoutingService(
      crateMiner: miner,
      historyLedger: ledger,
      onlineFetcher: null,
      connectivityProbe: () => NetworkAvailability.offline,
      random: Random(randomSeed),
      genreNormalization: genreNormalization,
    );

    return _RouterStack(miner, ledger, router, tmp);
  }

  /// Builds a normalisation service preloaded with a small
  /// inline dictionary (avoids the asset path so the test
  /// doesn't depend on the bundled `genre_normalization.json`).
  GenreNormalizationService _stubNormalizer() {
    final svc = GenreNormalizationService();
    svc.loadDictionaryForTesting(<String, String>{
      'afrobeats': 'Afrobeats',
      'afro-fusion': 'Afrobeats',
      'ghanaian hip hop': 'Hip-Hop',
      'hip hop': 'Hip-Hop',
      'rap': 'Hip-Hop',
      'rock': 'Rock',
      'pop': 'Pop',
    });
    return svc;
  }

  // ---------------------------------------------------------------------------
  // Spec 2D gates
  // ---------------------------------------------------------------------------

  group('AutoDjRoutingService.shuffleLibrary — genre filter (Spec 2D)', () {
    test('no filter set → all crate tracks are eligible', () async {
      final stack = await _buildStack(
        crate: const [
          Track(id: 'a1', title: 'A1', author: 'X', genre: 'Afrobeats'),
          Track(id: 'a2', title: 'A2', author: 'Y', genre: 'Hip-Hop'),
          Track(id: 'a3', title: 'A3', author: 'Z', genre: 'Rock'),
        ],
        genreNormalization: _stubNormalizer(),
      );
      final result = await stack.router.resolveNext(
        mode: AutoDJMode.shuffleLibrary,
        current: const Track(id: 'cur', title: 'Cur', author: 'Cur'),
        recentIds: const {},
      );
      expect(result, isNotNull);
      expect({'a1', 'a2', 'a3'}.contains(result!.id), isTrue);
    });

    test('filter "Hip-Hop" → only Hip-Hop-mapped tags are eligible '
        '(matrix-key-to-matrix-key match)', () async {
      // 5 Afrobeats tracks + 6 Hip-Hop tracks in the crate.
      // Filter "Hip-Hop" should select from the 6 Hip-Hop
      // tracks only (the canonical "Afrobeats" is a different
      // matrix key).
      final crate = <Track>[
        // Afrobeats (raw "afrobeats" → "Afrobeats" canonical)
        for (int i = 0; i < 5; i++)
          Track(id: 'af_$i', title: 'AF$i', author: 'BS', genre: 'afrobeats'),
        // Hip-Hop (raw "hip hop" → "Hip-Hop" canonical)
        for (int i = 0; i < 6; i++)
          Track(id: 'hh_$i', title: 'HH$i', author: 'Drake', genre: 'hip hop'),
      ];
      final stack = await _buildStack(
        crate: crate,
        genreNormalization: _stubNormalizer(),
      );
      stack.router.setShuffleLibraryGenreFilter('Hip-Hop');
      // Drive 6 picks; every one must be a Hip-Hop track
      // (id in {hh_0..hh_5}).
      final picks = <String>[];
      Track current =
          const Track(id: 'cur', title: 'Cur', author: 'Cur');
      for (int i = 0; i < 6; i++) {
        final pick = await stack.router.resolveNext(
          mode: AutoDJMode.shuffleLibrary,
          current: current,
          recentIds: const <String>{},
        );
        if (pick == null) break;
        picks.add(pick.id);
        current = pick;
      }
      // All picks must be Hip-Hop tracks.
      for (final id in picks) {
        expect({'hh_0', 'hh_1', 'hh_2', 'hh_3', 'hh_4', 'hh_5'}
            .contains(id), isTrue, reason: 'Filter "Hip-Hop" leaked $id');
      }
      // And we should have ≥2 distinct picks (the block is
      // 6 tracks; on exhaustion it regenerates from the
      // same pool).
      expect(picks.toSet().length, greaterThanOrEqualTo(2));
    });

    test('filter matches 0 tracks → silent fallback to unfiltered pool',
        () async {
      // Crate: 10 Pop tracks. Filter "Hip-Hop" → 0 matches.
      // Should silently fall back to the full crate.
      final crate = <Track>[
        for (int i = 0; i < 10; i++)
          Track(id: 'pop_$i', title: 'Pop$i', author: 'X', genre: 'pop'),
      ];
      final stack = await _buildStack(
        crate: crate,
        genreNormalization: _stubNormalizer(),
      );
      stack.router.setShuffleLibraryGenreFilter('Hip-Hop');
      final result = await stack.router.resolveNext(
        mode: AutoDJMode.shuffleLibrary,
        current: const Track(id: 'cur', title: 'Cur', author: 'Y'),
        recentIds: const {},
      );
      // Fallback fires: the pick must be a Pop track.
      expect(result, isNotNull);
      expect(
        {for (int i = 0; i < 10; i++) 'pop_$i'}.contains(result!.id),
        isTrue,
      );
    });

    test('filter matches 4 tracks (< 5) → silent fallback to unfiltered pool',
        () async {
      // 4 Afrobeats + 6 Rock in the crate. Filter "Afrobeats"
      // matches 4 (< 5 threshold) → silent fallback to
      // unfiltered pool. The pick should come from the full
      // 10-track crate, not just the 4 Afrobeats tracks.
      final crate = <Track>[
        for (int i = 0; i < 4; i++)
          Track(id: 'af_$i', title: 'AF$i', author: 'X', genre: 'afrobeats'),
        for (int i = 0; i < 6; i++)
          Track(id: 'rk_$i', title: 'RK$i', author: 'Y', genre: 'rock'),
      ];
      final stack = await _buildStack(
        crate: crate,
        genreNormalization: _stubNormalizer(),
      );
      stack.router.setShuffleLibraryGenreFilter('Afrobeats');
      // Drive 8 picks. If the filter were strictly applied
      // (block source = 4 tracks), we'd loop through the same
      // 4 tracks. With the fallback, picks should span the
      // full 10-track crate.
      final picks = <String>[];
      Track current =
          const Track(id: 'cur', title: 'Cur', author: 'Z');
      for (int i = 0; i < 8; i++) {
        final pick = await stack.router.resolveNext(
          mode: AutoDJMode.shuffleLibrary,
          current: current,
          recentIds: const <String>{},
        );
        if (pick == null) break;
        picks.add(pick.id);
        current = pick;
      }
      // Fallback: the union of picked ids must include a
      // Rock track (otherwise the filter wasn't loosened).
      expect(picks.any((id) => id.startsWith('rk_')), isTrue,
          reason:
              'Silent fallback failed — only Afrobeats tracks were picked: $picks');
    });

    test('filter matches ≥5 tracks → strictly applied', () async {
      // 8 Afrobeats + 2 Rock. Filter "Afrobeats" matches 8
      // (≥ 5) → strict application. Picks should NEVER be
      // a Rock track.
      final crate = <Track>[
        for (int i = 0; i < 8; i++)
          Track(id: 'af_$i', title: 'AF$i', author: 'X', genre: 'afrobeats'),
        for (int i = 0; i < 2; i++)
          Track(id: 'rk_$i', title: 'RK$i', author: 'Y', genre: 'rock'),
      ];
      final stack = await _buildStack(
        crate: crate,
        genreNormalization: _stubNormalizer(),
      );
      stack.router.setShuffleLibraryGenreFilter('Afrobeats');
      final picks = <String>[];
      Track current =
          const Track(id: 'cur', title: 'Cur', author: 'Z');
      for (int i = 0; i < 8; i++) {
        final pick = await stack.router.resolveNext(
          mode: AutoDJMode.shuffleLibrary,
          current: current,
          recentIds: const <String>{},
        );
        if (pick == null) break;
        picks.add(pick.id);
        current = pick;
      }
      // No Rock track should ever be picked.
      for (final id in picks) {
        expect(id.startsWith('af_'), isTrue,
            reason: 'Filter "Afrobeats" leaked $id (Rock track)');
      }
    });

    test('filter set but normalizer missing → silent fallback to '
        'unfiltered pool (graceful degradation)', () async {
      // No normalizer injected. The filter request must
      // not crash; it must log a warning and use the
      // unfiltered pool.
      final crate = <Track>[
        for (int i = 0; i < 5; i++)
          Track(id: 'a_$i', title: 'A$i', author: 'X', genre: 'afrobeats'),
        for (int i = 0; i < 5; i++)
          Track(id: 'b_$i', title: 'B$i', author: 'Y', genre: 'rock'),
      ];
      final stack = await _buildStack(
        crate: crate,
        // genreNormalization omitted → null
      );
      stack.router.setShuffleLibraryGenreFilter('Afrobeats');
      final picks = <String>[];
      Track current =
          const Track(id: 'cur', title: 'Cur', author: 'Z');
      for (int i = 0; i < 5; i++) {
        final pick = await stack.router.resolveNext(
          mode: AutoDJMode.shuffleLibrary,
          current: current,
          recentIds: const <String>{},
        );
        if (pick == null) break;
        picks.add(pick.id);
        current = pick;
      }
      // Fallback: picks span both pools.
      expect(picks.any((id) => id.startsWith('a_')), isTrue);
      expect(picks.any((id) => id.startsWith('b_')), isTrue,
          reason: 'No-normalizer fallback failed; only "a_" tracks picked');
    });

    test('getter exposes the active filter', () async {
      final stack = await _buildStack(
        crate: const [Track(id: 'a', title: 'A', author: 'X', genre: 'rock')],
      );
      expect(stack.router.shuffleLibraryGenreFilter, isNull);
      stack.router.setShuffleLibraryGenreFilter('Rock');
      expect(stack.router.shuffleLibraryGenreFilter, 'Rock');
      stack.router.setShuffleLibraryGenreFilter(null);
      expect(stack.router.shuffleLibraryGenreFilter, isNull);
    });

    test('unmapped raw genres are excluded from the filtered pool', () async {
      // "jazz" is in the dictionary check but NOT in our
      // test stub — normalize() will return null and the
      // track is excluded.
      final crate = <Track>[
        for (int i = 0; i < 5; i++)
          Track(id: 'af_$i', title: 'AF$i', author: 'X', genre: 'afrobeats'),
        for (int i = 0; i < 5; i++)
          Track(id: 'jz_$i', title: 'JZ$i', author: 'Y', genre: 'jazz'),
      ];
      final stack = await _buildStack(
        crate: crate,
        genreNormalization: _stubNormalizer(),
      );
      stack.router.setShuffleLibraryGenreFilter('Afrobeats');
      final picks = <String>[];
      Track current =
          const Track(id: 'cur', title: 'Cur', author: 'Z');
      for (int i = 0; i < 5; i++) {
        final pick = await stack.router.resolveNext(
          mode: AutoDJMode.shuffleLibrary,
          current: current,
          recentIds: const <String>{},
        );
        if (pick == null) break;
        picks.add(pick.id);
        current = pick;
      }
      for (final id in picks) {
        expect(id.startsWith('af_'), isTrue,
            reason: 'Unmapped "jazz" tag leaked into Afrobeats pool: $id');
      }
    });
  });
}

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class _RouterStack {
  final LocalCrateMiner miner;
  final DJHistoryLedger ledger;
  final AutoDjRoutingService router;
  final Directory tmp;
  _RouterStack(this.miner, this.ledger, this.router, this.tmp);
}

class _FakeHybridCache extends HybridCacheService {
  final List<String> _ids;
  _FakeHybridCache(this._ids);

  @override
  List<String> getCachedTrackIds() => _ids;
}
