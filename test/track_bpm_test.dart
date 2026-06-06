// Phase 4 — track_metadata.bpm persistence and lookup.
// Validation gate coverage: getTrackBpm returns the per-track
// authoritative reading first, then falls back to the history
// ledger, then null.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:zyp_music/data/datasources/local/playlist_database.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('PlaylistDatabase.getTrackBpm (Phase 4)', () {
    late PlaylistDatabase db;
    late String dbPath;

    setUp(() async {
      dbPath = '/tmp/zyp_bpm_${DateTime.now().microsecondsSinceEpoch}.db';
      await deleteDatabase(dbPath);
      db = PlaylistDatabase.forTesting(dbPath);
      await db.database; // force open + migrate
    });

    tearDown(() async {
      await db.close();
      await deleteDatabase(dbPath);
    });

    test('returns null for a track with no metadata and no history',
        () async {
      final bpm = await db.getTrackBpm('unknown');
      expect(bpm, isNull);
    });

    test('returns track_metadata.bpm when set', () async {
      await db.setTrackBpm('t1', 124.5);
      final bpm = await db.getTrackBpm('t1');
      expect(bpm, 124.5);
    });

    test('overwrites track_metadata.bpm on subsequent set', () async {
      await db.setTrackBpm('t1', 120.0);
      await db.setTrackBpm('t1', 128.0);
      final bpm = await db.getTrackBpm('t1');
      expect(bpm, 128.0);
    });

    test('setTrackBpm(null) clears the per-track reading', () async {
      await db.setTrackBpm('t1', 120.0);
      await db.setTrackBpm('t1', null);
      final bpm = await db.getTrackBpm('t1');
      // No history row → still null.
      expect(bpm, isNull);
    });

    test('falls back to MAX(history.bpm) when track_metadata.bpm is null',
        () async {
      // Seed the history ledger directly.
      final raw = await db.database;
      await raw.insert('dj_listening_history', {
        'track_id': 't1',
        'artist_name': 'Artist',
        'primary_genre': 'House',
        'bpm': 120.0,
        'energy_level': 0.5,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      await raw.insert('dj_listening_history', {
        'track_id': 't1',
        'artist_name': 'Artist',
        'primary_genre': 'House',
        'bpm': 128.0,
        'energy_level': 0.6,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      final bpm = await db.getTrackBpm('t1');
      expect(bpm, 128.0);
    });

    test('ignores zero/negative BPM rows in history', () async {
      final raw = await db.database;
      await raw.insert('dj_listening_history', {
        'track_id': 't1',
        'artist_name': 'Artist',
        'primary_genre': 'House',
        'bpm': 0.0,
        'energy_level': 0.5,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      final bpm = await db.getTrackBpm('t1');
      expect(bpm, isNull);
    });

    test('per-track reading wins over history', () async {
      final raw = await db.database;
      await raw.insert('dj_listening_history', {
        'track_id': 't1',
        'artist_name': 'Artist',
        'primary_genre': 'House',
        'bpm': 140.0,
        'energy_level': 0.5,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      await db.setTrackBpm('t1', 122.0);
      final bpm = await db.getTrackBpm('t1');
      expect(bpm, 122.0);
    });
  });
}
