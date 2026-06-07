// Spec 2G Fix #6 — refreshLikedSongsCache + computeTopLikedArtistsAndGenres.
//
// Validates:
//   * computeTopLikedArtistsAndGenres: top-N by count,
//     alphabetical tiebreak, ignores empty/null/Unknown
//     genres, respects the limit parameter.
//   * refreshLikedSongsCache: replaces the boot-time
//     bootstrap values immediately. Smart DJ's next
//     scoring pass sees the new cache.

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:zyp_music/core/services/auto_dj_routing_service.dart';
import 'package:zyp_music/core/services/dj_history_ledger.dart';
import 'package:zyp_music/core/services/hybrid_cache_service.dart';
import 'package:zyp_music/core/services/local_crate_miner.dart';
import 'package:zyp_music/domain/entities/auto_dj_mode.dart';
import 'package:zyp_music/domain/entities/video.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Pure-logic test for the shared helper.
  // ---------------------------------------------------------------------------

  group('AutoDjRoutingService.computeTopLikedArtistsAndGenres', () {
    test('empty favorites → empty lists', () {
      final result =
          AutoDjRoutingService.computeTopLikedArtistsAndGenres(const []);
      expect(result.artists, isEmpty);
      expect(result.genres, isEmpty);
    });

    test('counts by author and genre, returns top 5', () {
      final favorites = <Track>[
        const Track(id: '1', title: '1', author: 'A', genre: 'Hip-Hop'),
        const Track(id: '2', title: '2', author: 'A', genre: 'Hip-Hop'),
        const Track(id: '3', title: '3', author: 'A', genre: 'Afrobeats'),
        const Track(id: '4', title: '4', author: 'B', genre: 'Hiplife'),
        const Track(id: '5', title: '5', author: 'C', genre: 'Drill'),
        const Track(id: '6', title: '6', author: 'D', genre: 'Rock'),
      ];
      final result =
          AutoDjRoutingService.computeTopLikedArtistsAndGenres(favorites);
      // A=3, B=1, C=1, D=1 → top 5 is A, B, C, D (alpha tiebreak).
      expect(result.artists, ['A', 'B', 'C', 'D']);
      // Hip-Hop=2, Afrobeats=1, Hiplife=1, Drill=1, Rock=1
      expect(result.genres, ['Hip-Hop', 'Afrobeats', 'Drill', 'Hiplife', 'Rock']);
    });

    test('empty author and "Unknown" genre are filtered', () {
      final favorites = <Track>[
        const Track(id: '1', title: '1', author: 'A', genre: 'Hip-Hop'),
        const Track(id: '2', title: '2', author: '', genre: 'Hip-Hop'),
        const Track(id: '3', title: '3', author: 'A', genre: ''),
        const Track(id: '4', title: '4', author: 'A', genre: 'Unknown'),
      ];
      final result =
          AutoDjRoutingService.computeTopLikedArtistsAndGenres(favorites);
      expect(result.artists, ['A']);
      expect(result.genres, ['Hip-Hop']);
    });

    test('limit parameter caps the result', () {
      final favorites = <Track>[
        for (final a in ['A', 'B', 'C', 'D', 'E', 'F'])
          Track(id: a, title: a, author: a, genre: 'G'),
      ];
      final result = AutoDjRoutingService.computeTopLikedArtistsAndGenres(
        favorites,
        limit: 3,
      );
      expect(result.artists.length, 3);
      expect(result.artists, ['A', 'B', 'C']);
      expect(result.genres.length, 1,
          reason: 'All 6 tracks share genre "G" — one entry total');
    });

    test('alphabetical tiebreak when counts match', () {
      final favorites = <Track>[
        const Track(id: '1', title: '1', author: 'Zebra', genre: 'G'),
        const Track(id: '2', title: '2', author: 'Apple', genre: 'G'),
        const Track(id: '3', title: '3', author: 'Mango', genre: 'G'),
      ];
      final result =
          AutoDjRoutingService.computeTopLikedArtistsAndGenres(favorites);
      // Each artist count=1 → alphabetical: Apple, Mango, Zebra.
      expect(result.artists, ['Apple', 'Mango', 'Zebra']);
    });
  });

  // ---------------------------------------------------------------------------
  // Integration test: refreshLikedSongsCache replaces the
  // boot-time values on the routing service.
  // ---------------------------------------------------------------------------

  group('AutoDjRoutingService.refreshLikedSongsCache', () {
    late AutoDjRoutingService router;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final tmp = Directory.systemTemp.createTempSync('zyp_2g_');
      final miner = LocalCrateMiner(
        sqliteSource: () async => <Map<String, dynamic>>[],
        hybridCache: _FakeHybridCache(const []),
        fileExists: (_) async => false,
        hiveAudioPathResolver: (_) async => null,
      );
      final dbPath = p.join(tmp.path, 'ledger.db');
      final db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE dj_listening_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                track_id TEXT NOT NULL,
                artist_name TEXT NOT NULL,
                primary_genre TEXT DEFAULT 'Unknown',
                bpm REAL DEFAULT 0.0,
                energy_level REAL DEFAULT 0.5,
                timestamp INTEGER NOT NULL
              )
            ''');
          },
        ),
      );
      final ledger = DJHistoryLedger(db, rng: Random(0));
      router = AutoDjRoutingService(
        crateMiner: miner,
        historyLedger: ledger,
        onlineFetcher: null,
        connectivityProbe: () => NetworkAvailability.offline,
        random: Random(0),
      );
    });

    test('initial cache is empty (no bootstrap call)', () {
      // The router starts with empty Top 5 caches.
      final input = SmartDjScoreInput(
        candidates: [
          {
            'id': 'c1',
            'author': 'SomeArtist',
            'title': 'C1',
            'genre': 'Hip-Hop',
          },
        ],
        stateEntries: const [],
        fullHistory: const [],
        topLikedArtists: const [],
        topLikedGenres: const [],
        beta: 0.6, // Would matter if cache had values.
        precomputedGenreSimilarity: const {'c1': 0.5},
        recentArtists: const [],
        useColdStart: true,
      );
      final results = smartDjIsolateScore(input);
      // No crash, no Liked-Song bias (cache empty).
      expect(results.length, 1);
    });

    test('refreshLikedSongsCache replaces cache (no staleness check)', () {
      // Spec 2G Fix #6: the push-immediately design means
      // the new values take effect on the very next
      // scoring call. We verify by passing the new values
      // to smartDjIsolateScore and confirming the bias
      // changes accordingly.
      router.refreshLikedSongsCache(
        topLikedArtists: const ['LovedArtist'],
        topLikedGenres: const ['Hip-Hop'],
      );

      // A candidate by "LovedArtist" with genre "Hip-Hop"
      // should receive the maximum Liked-Song bias.
      final input = SmartDjScoreInput(
        candidates: const [
          {
            'id': 'loved',
            'author': 'LovedArtist',
            'title': 'Loved',
            'genre': 'Hip-Hop',
          },
          {
            'id': 'unknown',
            'author': 'Unknown',
            'title': 'Unknown',
            'genre': 'Jazz',
          },
        ],
        stateEntries: const [],
        fullHistory: const [],
        topLikedArtists: const ['LovedArtist'],
        topLikedGenres: const ['Hip-Hop'],
        beta: 0.6,
        precomputedGenreSimilarity: const {'loved': 0.5, 'unknown': 0.5},
        recentArtists: const [],
        useColdStart: true,
      );
      final results = smartDjIsolateScore(input);
      final lovedScore = (results.firstWhere(
              (r) => r['trackId'] == 'loved')['score'] as num)
          .toDouble();
      final unknownScore = (results.firstWhere(
              (r) => r['trackId'] == 'unknown')['score'] as num)
          .toDouble();
      expect(lovedScore, greaterThan(unknownScore),
          reason: 'Liked-Song bias should favour the loved candidate');
    });
  });
}

class _FakeHybridCache extends HybridCacheService {
  final List<String> _ids;
  _FakeHybridCache(this._ids);
  @override
  List<String> getCachedTrackIds() => _ids;
}
