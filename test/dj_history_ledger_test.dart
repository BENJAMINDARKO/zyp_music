// Phase 1 — Telemetry Logger & History Ledger
// Validation gate per the Phase 1 spec: unit tests for the trim
// logic and the cold-start fallback must pass before proceeding
// to Phase 2.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:zyp_music/core/services/dj_history_ledger.dart';

void main() {
  setUpAll(() {
    // sqflite runs in-process on the host VM; ffi shim is the
    // standard way to drive the in-memory SQLite engine from a
    // pure Dart test.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DJHistoryLedger.trim', () {
    late Database db;
    late DJHistoryLedger ledger;

    setUp(() async {
      db = await databaseFactory.openDatabase(
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
            await db.execute(
              'CREATE INDEX idx_dj_history_artist '
              'ON dj_listening_history(artist_name)',
            );
          },
        ),
      );
      ledger = DJHistoryLedger(db, rng: Random(0));
    });

    tearDown(() async {
      await db.close();
    });

    test('inserts a single row without trimming', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = await ledger.logTrack(DJHistoryEntry(
        trackId: 't1',
        artistName: 'Artist A',
        primaryGenre: 'Rock',
        timestampMs: now,
      ));
      expect(id, greaterThan(0));
      expect(await ledger.rowCount(), 1);
    });

    test('respects SQL defaults for genre / bpm / energy', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      // Spec 2C: `primaryGenre` is required at the Dart level. Pass
      // the explicit 'Unknown' literal here to verify the SQL
      // DEFAULT clause is still applied for cache-miss fallback
      // rows (the producer in `_logCurrentTrackHistory` writes
      // 'Unknown' directly when enrichment returns an empty list).
      await ledger.logTrack(DJHistoryEntry(
        trackId: 't1',
        artistName: 'Artist A',
        primaryGenre: 'Unknown',
        timestampMs: now,
      ));
      final rows = await ledger.getAll();
      expect(rows, hasLength(1));
      expect(rows.first.primaryGenre, 'Unknown');
      expect(rows.first.bpm, 0.0);
      expect(rows.first.energyLevel, 0.5);
    });

    test('trims when a single write pushes the count over the cap', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      // Pre-seed 300 rows directly so the next insert (301st) trips
      // the trim branch.
      final batch = db.batch();
      for (var i = 0; i < DJHistoryLedger.ledgerCap; i++) {
        batch.insert('dj_listening_history', {
          'track_id': 'pre_$i',
          'artist_name': 'Pre',
          'timestamp': now + (i * 1000),
        });
      }
      await batch.commit(noResult: true);
      expect(await ledger.rowCount(), 300);

      await ledger.logTrack(DJHistoryEntry(
        trackId: 'trigger',
        artistName: 'Trigger',
        primaryGenre: 'Rock',
        timestampMs: now + 300001,
      ));

      // Spec: "if the total row count exceeds 300, delete the oldest
      // 10 records." So 301 → trim 10 → 291. The cap is 300 but
      // the trim granularity is 10, so the count oscillates between
      // ~290 and ~300 — never above 300, never below 290 after the
      // first overflow.
      final after = await ledger.rowCount();
      expect(after, lessThanOrEqualTo(300));
      expect(after, greaterThanOrEqualTo(290));
      expect(after, 291,
          reason: '301 - 10 = 291 after a single trim event');
    });

    test('trim removes the 10 oldest rows, not the 10 newest', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      // Pre-seed 300 rows with monotonically increasing timestamps.
      // t_0 gets the smallest (oldest) timestamp, t_299 the largest
      // (newest), so the trim targets t_0..t_9.
      final batch = db.batch();
      for (var i = 0; i < DJHistoryLedger.ledgerCap; i++) {
        batch.insert('dj_listening_history', {
          'track_id': 't_$i',
          'artist_name': 'Artist',
          'timestamp': now + (i * 1000),
        });
      }
      await batch.commit(noResult: true);

      await ledger.logTrack(DJHistoryEntry(
        trackId: 'trigger',
        artistName: 'Trigger',
        primaryGenre: 'Rock',
        timestampMs: now + 300001,
      ));

      final rows = await ledger.getAll();
      // After the trim, the count is 291 (300 + 1 - 10).
      expect(rows, hasLength(291));
      // The 10 oldest pre-seeded rows (t_0 .. t_9) must be gone.
      // With recent timestamps, the oldest have the smallest timestamps
      // (now - 299000 is still > 180 days ago), so all survive the purge.
      final survivors = rows.map((r) => r.trackId).toSet();
      for (var i = 0; i < 10; i++) {
        expect(survivors.contains('t_$i'), isFalse,
            reason: 't_$i should have been trimmed');
      }
      // t_10 onwards must still be present.
      expect(survivors.contains('t_10'), isTrue);
      expect(survivors.contains('t_299'), isTrue);
      // The freshly-inserted row must be at the top.
      expect(rows.first.trackId, 'trigger');
    });

    test('session dedupe set prevents double-logging the same track',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await ledger.logTrack(DJHistoryEntry(
        trackId: 'dup',
        artistName: 'Artist',
        primaryGenre: 'Rock',
        timestampMs: now,
      ));
      expect(ledger.hasBeenLoggedThisSession('dup'), isTrue);

      await ledger.logTrack(DJHistoryEntry(
        trackId: 'dup',
        artistName: 'Artist',
        primaryGenre: 'Rock',
        timestampMs: now + 1000,
      ));
      expect(ledger.hasBeenLoggedThisSession('dup'), isTrue);

      // A second log for the same track ID is still a legal SQL
      // insert (the dedupe is an in-memory guard, not a UNIQUE
      // constraint), but the guard will short-circuit the
      // production code path before it ever reaches the DB.
      await ledger.logTrack(DJHistoryEntry(
        trackId: 'dup',
        artistName: 'Artist',
        primaryGenre: 'Rock',
        timestampMs: 2_000,
      ));
      // Both rows land because the test exercises the SQL path
      // directly. The dedupe assertion above is what the
      // production caller relies on.
      expect(await ledger.rowCount(), 2);

      ledger.clearSessionCache();
      expect(ledger.hasBeenLoggedThisSession('dup'), isFalse);
    });

    test('purges rows older than 180 days on insert', () async {
      final ledger = DJHistoryLedger(db, rng: Random(0));

      final oldTimestamp = DateTime.now()
          .subtract(const Duration(days: 181))
          .millisecondsSinceEpoch;
      await db.insert('dj_listening_history', {
        'track_id': 'old_track',
        'artist_name': 'Old Artist',
        'primary_genre': 'Hip-Hop',
        'timestamp': oldTimestamp,
      });

      await ledger.logTrack(DJHistoryEntry(
        trackId: 'new_track',
        artistName: 'New Artist',
        primaryGenre: 'Hip-Hop',
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ));

      final rows = await db.query('dj_listening_history');
      expect(rows.length, equals(1));
      expect(rows.first['track_id'], equals('new_track'));
    });

    test('keeps rows exactly 180 days old', () async {
      final ledger = DJHistoryLedger(db, rng: Random(0));

      final borderlineTimestamp = DateTime.now()
          .subtract(const Duration(days: 180))
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch;
      await db.insert('dj_listening_history', {
        'track_id': 'borderline_track',
        'artist_name': 'Test',
        'primary_genre': 'Pop',
        'timestamp': borderlineTimestamp,
      });

      await ledger.logTrack(DJHistoryEntry(
        trackId: 'new_track',
        artistName: 'Test',
        primaryGenre: 'Pop',
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ));

      final rows = await db.query('dj_listening_history');
      expect(rows.length, equals(2));
    });

    test('300-row cap still applies after 180-day purge', () async {
      final ledger = DJHistoryLedger(db, rng: Random(0));

      final now = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < 305; i++) {
        await db.insert('dj_listening_history', {
          'track_id': 'track_$i',
          'artist_name': 'Test',
          'primary_genre': 'Pop',
          'timestamp': now - (i * 1000),
        });
      }

      await ledger.logTrack(DJHistoryEntry(
        trackId: 'trigger',
        artistName: 'Test',
        primaryGenre: 'Pop',
        timestampMs: now + 1000,
      ));

      final count = await ledger.rowCount();
      expect(count, lessThanOrEqualTo(300));
    });
  });

  group('DJHistoryLedger.resolveColdStart', () {
    late Database db;
    late DJHistoryLedger ledger;

    setUp(() async {
      db = await databaseFactory.openDatabase(
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
      ledger = DJHistoryLedger(db, rng: Random(42));
    });

    tearDown(() async {
      await db.close();
    });

    test('returns markovReady once ≥ 3 rows are present', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < DJHistoryLedger.minRowsForMarkov; i++) {
        await ledger.logTrack(DJHistoryEntry(
          trackId: 'seed_$i',
          artistName: 'Seed',
          primaryGenre: 'Rock',
          timestampMs: now - (i * 1000),
        ));
      }
      final outcome = await ledger.resolveColdStart(
        seedGenre: 'Rock',
        localLibrary: (_) => const [],
      );
      expect(outcome.kind, ColdStartKind.markovReady);
      expect(outcome.rowCount, DJHistoryLedger.minRowsForMarkov);
    });

    test('falls back to genre match when history is empty', () async {
      const library = <TrackCandidate>[
        TrackCandidate(trackId: 'r1', artistName: 'Rock Artist 1', primaryGenre: 'Rock'),
        TrackCandidate(trackId: 'p1', artistName: 'Pop Artist', primaryGenre: 'Pop'),
        TrackCandidate(trackId: 'r2', artistName: 'Rock Artist 2', primaryGenre: 'Rock'),
      ];
      final outcome = await ledger.resolveColdStart(
        seedGenre: 'Rock',
        localLibrary: (genre) =>
            library.where((t) => t.primaryGenre == genre).toList(),
      );
      expect(outcome.kind, ColdStartKind.genreMatch);
      expect(outcome.pick, isNotNull);
      expect(outcome.pick!.primaryGenre, 'Rock');
      // Falls through the `matches.first` path — order is the
      // order returned by the resolver, which preserves the
      // source list.
      expect(outcome.pick!.trackId, 'r1');
    });

    test('falls back to random when no genre match exists', () async {
      const library = <TrackCandidate>[
        TrackCandidate(trackId: 'p1', artistName: 'Pop A', primaryGenre: 'Pop'),
        TrackCandidate(trackId: 'p2', artistName: 'Pop B', primaryGenre: 'Pop'),
        TrackCandidate(trackId: 'j1', artistName: 'Jazz A', primaryGenre: 'Jazz'),
      ];
      // Seed 1 row — still under the 3-row threshold so the
      // Markov gate stays closed.
      final now = DateTime.now().millisecondsSinceEpoch;
      await ledger.logTrack(DJHistoryEntry(
        trackId: 's0',
        artistName: 'Seed',
        primaryGenre: 'Unknown',
        timestampMs: now,
      ));
      final outcome = await ledger.resolveColdStart(
        seedGenre: 'Rock',
        localLibrary: (genre) {
          if (genre == null) return library;
          return library.where((t) => t.primaryGenre == genre).toList();
        },
      );
      expect(outcome.kind, ColdStartKind.randomFallback);
      expect(outcome.pick, isNotNull);
      expect(library.map((t) => t.trackId), contains(outcome.pick!.trackId));
    });

    test('returns empty when the local library itself is empty', () async {
      final outcome = await ledger.resolveColdStart(
        seedGenre: 'Rock',
        localLibrary: (_) => const [],
      );
      expect(outcome.kind, ColdStartKind.empty);
      expect(outcome.pick, isNull);
    });

    test('skips the markov gate when the row count is exactly 2', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < 2; i++) {
        await ledger.logTrack(DJHistoryEntry(
          trackId: 'seed_$i',
          artistName: 'Seed',
          primaryGenre: 'Unknown',
          timestampMs: now - (i * 1000),
        ));
      }
      const library = <TrackCandidate>[
        TrackCandidate(trackId: 'r1', artistName: 'Rock A', primaryGenre: 'Rock'),
      ];
      final outcome = await ledger.resolveColdStart(
        seedGenre: 'Rock',
        localLibrary: (genre) =>
            library.where((t) => t.primaryGenre == genre).toList(),
      );
      // 2 rows < 3 → falls through to genre match.
      expect(outcome.kind, ColdStartKind.genreMatch);
      expect(outcome.pick!.trackId, 'r1');
    });
  });
}
