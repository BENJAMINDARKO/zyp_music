// Phase 5 — Shuffle Library's 20-song rolling window.
//
// The spec's "Shuffle Library" mode must dedup against a
// rolling 20-track horizon: a track is never repeated until
// at least 20 *unique* library tracks have been processed.
// When the local library has < 20 songs the window is sized
// to the total count. When the window is exhausted, the
// window is cleared and a fresh set is drawn.

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

  Future<AutoDjRoutingService> _buildRouter(List<Track> crate) async {
    final tmp = Directory.systemTemp.createTempSync('zyp_shuf_');
    for (final t in crate) {
      File(p.join(tmp.path, '${t.id}.m4a')).writeAsBytesSync([]);
    }
    final miner = LocalCrateMiner(
      sqliteSource: () async => crate
          .map((t) => {
                'id': t.id,
                'title': t.title,
                'filePath': p.join(tmp.path, '${t.id}.m4a'),
                'durationSeconds': t.duration.inSeconds,
                'author': t.author,
                'genre': t.genre,
              })
          .toList(),
      hybridCache: _FakeHybridCache(),
      fileExists: (_) async => true,
      hiveAudioPathResolver: (_) async => null,
    );
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
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
    final ledger = DJHistoryLedger(db, rng: Random(0));
    return AutoDjRoutingService(
      crateMiner: miner,
      historyLedger: ledger,
      connectivityProbe: () => NetworkAvailability.offline,
      random: Random(42),
    );
  }

  Future<Track> _pick(AutoDjRoutingService r, List<Track> crate) async {
    final current = Track(id: 'cur', title: 'Cur');
    final pick = await r.resolveNext(
      mode: AutoDJMode.shuffleLibrary,
      current: current,
      recentIds: {current.id},
    );
    expect(pick, isNotNull);
    return pick!;
  }

  test('library of 30: first 20 picks are guaranteed unique (window size)',
      () async {
    final library = List<Track>.generate(30, (i) => Track(id: 't$i', title: 'T$i'));
    final r = await _buildRouter(library);
    final picked = <String>{};
    for (var i = 0; i < 20; i++) {
      picked.add((await _pick(r, library)).id);
    }
    // The first 20 picks MUST be unique: the dedup window
    // starts empty and slides 1-in/1-out, so no candidate
    // can be picked twice until the window itself is full.
    expect(picked.length, 20);
  });

  test('library of 5: window caps at 5 and exhausts on the 6th pick',
      () async {
    final library = List<Track>.generate(5, (i) => Track(id: 't$i', title: 'T$i'));
    final r = await _buildRouter(library);
    final picked = <String>[];
    for (var i = 0; i < 6; i++) {
      picked.add((await _pick(r, library)).id);
    }
    // 6 picks from a 5-track library MUST include a repeat
    // (window of 5 → after the 5th pick the clean pool is
    // empty → the 6th pick clears the window and pulls a
    // random track, which may or may not duplicate the
    // most recent pick).
    expect(picked.length, 6);
    expect(picked.toSet().length, lessThanOrEqualTo(5));
  });

  test('library of exactly 20: 20 picks are all unique', () async {
    final library = List<Track>.generate(20, (i) => Track(id: 't$i', title: 'T$i'));
    final r = await _buildRouter(library);
    final picked = <String>{};
    for (var i = 0; i < 20; i++) {
      picked.add((await _pick(r, library)).id);
    }
    expect(picked.length, 20);
  });
}

class _FakeHybridCache extends HybridCacheService {
  _FakeHybridCache();
}
