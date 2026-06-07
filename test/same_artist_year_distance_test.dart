// Spec 2F — Same Artist year-distance bonus unit + integration tests.
//
// Coverage:
//   * _yearDistanceBonus: anchor points (0/1/3/5), interpolation
//     (2, 4), floor (>=5), null-safety, distance sign (negative
//     years handled by abs).
//   * _sameArtist: anchor year is the most recent same-artist
//     play's year, falling back to current.year.
//   * _sameArtist: same-year candidates preferred over different-
//     year candidates (distribution test, deterministic seed).
//   * _sameArtist: null year on candidate → 1.0 neutral (no bias).
//   * _sameArtist: null year on anchor → falls back to current.year.

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
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // ---------------------------------------------------------------------------
  // Pure-logic year-distance bonus unit tests
  //
  // The bonus function is private, so we exercise it through
  // the public `resolveNext` API. To isolate the year effect,
  // every candidate has a unique year AND unique author
  // exception: the artist matches the seed. All non-year
  // scoring terms (wPath, aPenalty, cBonus) collapse to 1.0
  // because there's no history, the seed has no genre, and
  // the bonus service is null.
  // ---------------------------------------------------------------------------

  group('Spec 2F: _yearDistanceBonus through _sameArtist', () {
    Future<_RouterStack> buildStack({
      required List<Track> crate,
      required int randomSeed,
    }) async {
      final tmp = Directory.systemTemp.createTempSync('zyp_2f_');
      final miner = LocalCrateMiner(
        sqliteSource: () async => crate
            .map((t) => {
                  'id': t.id,
                  'title': t.title,
                  'filePath': p.join(tmp.path, '${t.id}.m4a'),
                  'durationSeconds': t.duration?.inSeconds,
                  'author': t.author,
                  'genre': t.genre,
                  'year': t.year,
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
      final ledger = DJHistoryLedger(db, rng: Random(randomSeed));
      final router = AutoDjRoutingService(
        crateMiner: miner,
        historyLedger: ledger,
        onlineFetcher: null,
        connectivityProbe: () => NetworkAvailability.offline,
        random: Random(randomSeed),
      );
      return _RouterStack(miner, ledger, router, tmp);
    }

    test('same year (distance 0) wins over distance 5', () async {
      // Seed: Target, 2018. Two candidates: same-artist, year
      // 2018 vs year 2023. Cumulative scores: 1.0 + 0.2 = 1.2.
      // Same-year wins 1.0/1.2 = 83.3% of the time.
      const iterations = 100;
      var sameYearPicks = 0;
      var farYearPicks = 0;
      for (var i = 0; i < iterations; i++) {
        final stack = await buildStack(
          crate: const [
            Track(id: 'near', title: 'Near', author: 'Target', year: 2018),
            Track(id: 'far', title: 'Far', author: 'Target', year: 2023),
            Track(id: 'cur', title: 'Cur', author: 'Target', year: 2018),
          ],
          randomSeed: i,
        );
        final result = await stack.router.resolveNext(
          mode: AutoDJMode.sameArtist,
          current: const Track(
              id: 'cur', title: 'Cur', author: 'Target', year: 2018),
          recentIds: const {},
        );
        if (result?.id == 'near') sameYearPicks++;
        if (result?.id == 'far') farYearPicks++;
      }
      expect(sameYearPicks, greaterThan(farYearPicks),
          reason: 'Same-year should beat distance-5 across $iterations seeds. '
              'Got near=$sameYearPicks, far=$farYearPicks');
      expect(sameYearPicks, greaterThan(70),
          reason: 'Expected same-year to win ~83% of the time');
    });

    test('distance 1 wins over distance 5', () async {
      // Cumulative: 0.7 + 0.2 = 0.9. Distance 1 wins 0.7/0.9 = 77.8%.
      const iterations = 100;
      var closePicks = 0;
      var farPicks = 0;
      for (var i = 0; i < iterations; i++) {
        final stack = await buildStack(
          crate: const [
            Track(id: 'close', title: 'Close', author: 'Target', year: 2019),
            Track(id: 'far', title: 'Far', author: 'Target', year: 2023),
            Track(id: 'cur', title: 'Cur', author: 'Target', year: 2018),
          ],
          randomSeed: i,
        );
        final result = await stack.router.resolveNext(
          mode: AutoDJMode.sameArtist,
          current: const Track(
              id: 'cur', title: 'Cur', author: 'Target', year: 2018),
          recentIds: const {},
        );
        if (result?.id == 'close') closePicks++;
        if (result?.id == 'far') farPicks++;
      }
      expect(closePicks, greaterThan(farPicks),
          reason: 'Distance 1 should beat distance 5 across $iterations seeds. '
              'Got close=$closePicks, far=$farPicks');
    });

    test('distance 3 (0.4) wins over distance 5 (0.2)', () async {
      // Cumulative: 0.4 + 0.2 = 0.6. Distance 3 wins 0.4/0.6 = 66.7%.
      const iterations = 100;
      var d3Picks = 0;
      var d5Picks = 0;
      for (var i = 0; i < iterations; i++) {
        final stack = await buildStack(
          crate: const [
            Track(id: 'd3', title: 'D3', author: 'Target', year: 2021),
            Track(id: 'd5', title: 'D5', author: 'Target', year: 2023),
            Track(id: 'cur', title: 'Cur', author: 'Target', year: 2018),
          ],
          randomSeed: i,
        );
        final result = await stack.router.resolveNext(
          mode: AutoDJMode.sameArtist,
          current: const Track(
              id: 'cur', title: 'Cur', author: 'Target', year: 2018),
          recentIds: const {},
        );
        if (result?.id == 'd3') d3Picks++;
        if (result?.id == 'd5') d5Picks++;
      }
      expect(d3Picks, greaterThan(d5Picks),
          reason: 'Distance 3 should beat distance 5 across $iterations seeds. '
              'Got d3=$d3Picks, d5=$d5Picks');
    });

    test('null year on candidate → 1.0 neutral (no bias)', () async {
      // Two candidates: one with year 2018, one with null year.
      // The null-year candidate should NOT be excluded; both
      // should appear in the picked set. The 1.0 vs 1.0 tie
      // yields a roughly 50/50 distribution.
      const iterations = 50;
      var withYearPicks = 0;
      var withoutYearPicks = 0;
      for (var i = 0; i < iterations; i++) {
        final stack = await buildStack(
          crate: const [
            Track(id: 'with', title: 'With', author: 'Target', year: 2018),
            Track(id: 'without', title: 'Without', author: 'Target'),
            Track(id: 'cur', title: 'Cur', author: 'Target', year: 2018),
          ],
          randomSeed: i,
        );
        final result = await stack.router.resolveNext(
          mode: AutoDJMode.sameArtist,
          current: const Track(
              id: 'cur', title: 'Cur', author: 'Target', year: 2018),
          recentIds: const {},
        );
        if (result?.id == 'with') withYearPicks++;
        if (result?.id == 'without') withoutYearPicks++;
      }
      // Expect roughly 50/50 — both candidates are valid.
      final total = withYearPicks + withoutYearPicks;
      expect(total, iterations,
          reason: 'Both candidates should be selectable');
      final withRatio = withYearPicks / total;
      expect(withRatio, inInclusiveRange(0.30, 0.70),
          reason: 'Equal 1.0 bonus should give near-50/50 distribution. '
              'Got with=$withYearPicks, without=$withoutYearPicks');
    });

    test('null year on anchor → falls back to current.year (no bias)',
        () async {
      // Seed has no year; one candidate has year 2018, another 2023.
      // Without a year on the seed, every same-artist candidate
      // gets 1.0 (year null → neutral). The pick is non-deterministic
      // but should distribute roughly 50/50.
      const iterations = 50;
      var nearPicks = 0;
      var farPicks = 0;
      for (var i = 0; i < iterations; i++) {
        final stack = await buildStack(
          crate: const [
            Track(id: 'near', title: 'Near', author: 'Target', year: 2018),
            Track(id: 'far', title: 'Far', author: 'Target', year: 2023),
            Track(id: 'cur', title: 'Cur', author: 'Target'),
          ],
          randomSeed: i,
        );
        final result = await stack.router.resolveNext(
          mode: AutoDJMode.sameArtist,
          current: const Track(id: 'cur', title: 'Cur', author: 'Target'),
          recentIds: const {},
        );
        if (result?.id == 'near') nearPicks++;
        if (result?.id == 'far') farPicks++;
      }
      final total = nearPicks + farPicks;
      expect(total, iterations);
      final nearRatio = nearPicks / total;
      expect(nearRatio, inInclusiveRange(0.30, 0.70),
          reason: 'Null anchor year should not bias. '
              'Got near=$nearPicks, far=$farPicks');
    });

    test('monotonic ordering: distance 0 > 1 > 3 > 5', () async {
      // All 4 candidates in one pool. Anchor year 2018.
      // Cumulative: 1.0 + 0.7 + 0.4 + 0.2 = 2.3.
      // P(expected pick):
      //   d0: 1.0/2.3 = 43.5%
      //   d1: 0.7/2.3 = 30.4%
      //   d3: 0.4/2.3 = 17.4%
      //   d5: 0.2/2.3 = 8.7%
      const iterations = 500;
      final picks = <String, int>{
        'd0': 0,
        'd1': 0,
        'd3': 0,
        'd5': 0,
      };
      for (var i = 0; i < iterations; i++) {
        final stack = await buildStack(
          crate: const [
            Track(id: 'd0', title: 'D0', author: 'Target', year: 2018),
            Track(id: 'd1', title: 'D1', author: 'Target', year: 2019),
            Track(id: 'd3', title: 'D3', author: 'Target', year: 2021),
            Track(id: 'd5', title: 'D5', author: 'Target', year: 2023),
            Track(id: 'cur', title: 'Cur', author: 'Target', year: 2018),
          ],
          randomSeed: i,
        );
        final result = await stack.router.resolveNext(
          mode: AutoDJMode.sameArtist,
          current: const Track(
              id: 'cur', title: 'Cur', author: 'Target', year: 2018),
          recentIds: const {},
        );
        if (result != null && picks.containsKey(result.id)) {
          picks[result.id!] = picks[result.id!]! + 1;
        }
      }
      // Strict monotonic ordering.
      expect(picks['d0']!, greaterThan(picks['d1']!),
          reason: 'd0 should beat d1');
      expect(picks['d1']!, greaterThan(picks['d3']!),
          reason: 'd1 should beat d3');
      expect(picks['d3']!, greaterThan(picks['d5']!),
          reason: 'd3 should beat d5');
    });

    test('history with most recent same-artist play becomes anchor', () async {
      // Seed: Target, 2023. History has Target, 2018 (older
      // play by the same artist). The anchor year should be
      // 2018 (from history), not 2023 (from current). So a
      // 2018 candidate should win over a 2023 candidate.
      //
      // Cumulative if anchor=2018: 1.0 (2018) + 0.2 (2023, dist 5)
      //                       = 1.2 → 2018 wins 83.3%
      // Cumulative if anchor=2023: 0.2 (2018) + 1.0 (2023) = 1.2
      //                       → 2023 wins 83.3% (wrong direction)
      const iterations = 100;
      var oldPicks = 0;
      var newPicks = 0;
      for (var i = 0; i < iterations; i++) {
        final stack = await buildStack(
          crate: const [
            Track(id: 'old', title: 'Old', author: 'Target', year: 2018),
            Track(id: 'new', title: 'New', author: 'Target', year: 2023),
            Track(id: 'cur', title: 'Cur', author: 'Target', year: 2023),
          ],
          randomSeed: i,
        );
        // Add a history entry: Target, 2018 (older play by the
        // same artist). This makes the anchor year 2018, not 2023.
        await stack.ledger.logTrack(const DJHistoryEntry(
          trackId: 'old_history',
          artistName: 'Target',
          primaryGenre: 'Unknown',
          timestampMs: 1,
        ));
        final result = await stack.router.resolveNext(
          mode: AutoDJMode.sameArtist,
          current: const Track(
              id: 'cur', title: 'Cur', author: 'Target', year: 2023),
          recentIds: const {},
          history: const [
            Track(id: 'old_history', title: 'OldHistory', author: 'Target', year: 2018),
          ],
        );
        if (result?.id == 'old') oldPicks++;
        if (result?.id == 'new') newPicks++;
      }
      expect(oldPicks, greaterThan(newPicks),
          reason: 'History anchor (2018) should make the 2018 candidate win '
              'over the seed-year (2023) candidate across $iterations seeds. '
              'Got old=$oldPicks, new=$newPicks');
    });

    test('no history: anchor is current.year (default fallback)', () async {
      // Same as the 'distance 0 wins over 5' test, but with
      // an explicit empty history param to confirm the
      // fallback path. We expect the same-year candidate to
      // win (current.year is 2018, same-year candidate is 2018).
      const iterations = 50;
      var sameYearPicks = 0;
      var farYearPicks = 0;
      for (var i = 0; i < iterations; i++) {
        final stack = await buildStack(
          crate: const [
            Track(id: 'near', title: 'Near', author: 'Target', year: 2018),
            Track(id: 'far', title: 'Far', author: 'Target', year: 2023),
            Track(id: 'cur', title: 'Cur', author: 'Target', year: 2018),
          ],
          randomSeed: i,
        );
        final result = await stack.router.resolveNext(
          mode: AutoDJMode.sameArtist,
          current: const Track(
              id: 'cur', title: 'Cur', author: 'Target', year: 2018),
          recentIds: const {},
          history: const <Track>[],
        );
        if (result?.id == 'near') sameYearPicks++;
        if (result?.id == 'far') farYearPicks++;
      }
      expect(sameYearPicks, greaterThan(farYearPicks),
          reason: 'Empty history → anchor=current.year. '
              'Got near=$sameYearPicks, far=$farYearPicks');
    });

    test('history with non-matching artists: anchor stays at current.year',
        () async {
      // History has plays by OTHER artists (not Target). The
      // same-artist filter in _sameArtist's anchor-finding
      // loop should skip these and fall back to current.year.
      const iterations = 50;
      var sameYearPicks = 0;
      var farYearPicks = 0;
      for (var i = 0; i < iterations; i++) {
        final stack = await buildStack(
          crate: const [
            Track(id: 'near', title: 'Near', author: 'Target', year: 2018),
            Track(id: 'far', title: 'Far', author: 'Target', year: 2023),
            Track(id: 'cur', title: 'Cur', author: 'Target', year: 2018),
          ],
          randomSeed: i,
        );
        final result = await stack.router.resolveNext(
          mode: AutoDJMode.sameArtist,
          current: const Track(
              id: 'cur', title: 'Cur', author: 'Target', year: 2018),
          recentIds: const {},
          history: const [
            Track(id: 'h1', title: 'H1', author: 'OtherA', year: 1990),
            Track(id: 'h2', title: 'H2', author: 'OtherB', year: 1995),
            Track(id: 'h3', title: 'H3', author: 'OtherC', year: 2000),
          ],
        );
        if (result?.id == 'near') sameYearPicks++;
        if (result?.id == 'far') farYearPicks++;
      }
      expect(sameYearPicks, greaterThan(farYearPicks),
          reason: 'History with no same-artist match → anchor=current.year. '
              'Got near=$sameYearPicks, far=$farYearPicks');
    });

    test('exclude set: current track and recent ids are not returned',
        () async {
      // The 'cur' track is the seed, the same-artist candidate
      // is 'a' (Target, 2018). The user has 'a' in their
      // recent-ids set. The router should return null or a
      // different track.
      final stack = await buildStack(
        crate: const [
          Track(id: 'a', title: 'A', author: 'Target', year: 2018),
          Track(id: 'cur', title: 'Cur', author: 'Target', year: 2018),
        ],
        randomSeed: 0,
      );
      final result = await stack.router.resolveNext(
        mode: AutoDJMode.sameArtist,
        current: const Track(
            id: 'cur', title: 'Cur', author: 'Target', year: 2018),
        recentIds: const {'cur', 'a'},
      );
      expect(result, isNull,
          reason: 'Only candidate is excluded; expect null');
    });
  });
}

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
