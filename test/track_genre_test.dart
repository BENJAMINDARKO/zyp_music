// Phase 5 — track_metadata.genre persistence and lookup.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:zyp_music/data/datasources/local/playlist_database.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('PlaylistDatabase.setTrackGenre / getTrackGenre (Phase 5)', () {
    late PlaylistDatabase db;
    late String dbPath;

    setUp(() async {
      dbPath = '/tmp/zyp_genre_${DateTime.now().microsecondsSinceEpoch}.db';
      await deleteDatabase(dbPath);
      db = PlaylistDatabase.forTesting(dbPath);
      await db.database;
    });

    tearDown(() async {
      await db.close();
      await deleteDatabase(dbPath);
    });

    test('getTrackGenre returns null for an unknown track', () async {
      expect(await db.getTrackGenre('unknown'), isNull);
    });

    test('setTrackGenre → getTrackGenre round-trip', () async {
      await db.setTrackGenre('t1', 'House');
      expect(await db.getTrackGenre('t1'), 'House');
    });

    test('setTrackGenre overwrites the previous value', () async {
      await db.setTrackGenre('t1', 'House');
      await db.setTrackGenre('t1', 'Techno');
      expect(await db.getTrackGenre('t1'), 'Techno');
    });

    test('setTrackGenre(null) clears the per-track reading', () async {
      await db.setTrackGenre('t1', 'House');
      await db.setTrackGenre('t1', null);
      expect(await db.getTrackGenre('t1'), isNull);
    });
  });
}
