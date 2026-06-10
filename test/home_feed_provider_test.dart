import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:zyp_music/data/datasources/local/playlist_database.dart';
import 'package:zyp_music/presentation/providers/home_feed_provider.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('HomeFeedProvider', () {
    late PlaylistDatabase database;
    late String dbPath;

    setUp(() async {
      dbPath =
          '${Directory.systemTemp.path}/test_provider_${DateTime.now().millisecondsSinceEpoch}.db';
      database = PlaylistDatabase.forTesting(dbPath);
      await database.database;
    });

    tearDown(() async {
      await database.close();
      try {
        await File(dbPath).delete();
      } catch (_) {}
    });

    test('initial state is null for all results', () {
      final provider = HomeFeedProvider(database: database);
      expect(provider.topSongsPerTopGenre, isNull);
      expect(provider.popularAlbumsAndSingles, isNull);
      expect(provider.listeningStats, isNull);
    });

    test('loadTopSongsPerTopGenre populates result and notifies listeners',
        () async {
      // Seed one row so the query returns something
      final d = await database.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      await d.insert('dj_listening_history', {
        'track_id': 't1',
        'artist_name': 'Artist',
        'primary_genre': 'Rock',
        'timestamp': now,
      });

      final provider = HomeFeedProvider(database: database);
      var notified = false;
      provider.addListener(() => notified = true);

      await provider.loadTopSongsPerTopGenre();

      expect(provider.topSongsPerTopGenre, isNotNull);
      expect(provider.topSongsPerTopGenre!.length, equals(1));
      expect(notified, isTrue);
    });

    test('concurrent load calls are deduplicated', () async {
      final d = await database.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      await d.insert('dj_listening_history', {
        'track_id': 't1',
        'artist_name': 'Artist',
        'primary_genre': 'Rock',
        'timestamp': now,
      });

      final provider = HomeFeedProvider(database: database);
      // Fire 3 concurrent loads
      await Future.wait([
        provider.loadTopSongsPerTopGenre(),
        provider.loadTopSongsPerTopGenre(),
        provider.loadTopSongsPerTopGenre(),
      ]);

      expect(provider.topSongsPerTopGenre, isNotNull);
      expect(provider.topSongsPerTopGenre!.length, equals(1));
    });

    test('invalidate clears all cached results', () async {
      final d = await database.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      await d.insert('dj_listening_history', {
        'track_id': 't1',
        'artist_name': 'Artist',
        'primary_genre': 'Rock',
        'timestamp': now,
      });

      final provider = HomeFeedProvider(database: database);
      await provider.loadAll();

      expect(provider.listeningStats, isNotNull);

      provider.invalidate();
      expect(provider.listeningStats, isNull);
      expect(provider.topSongsPerTopGenre, isNull);
      expect(provider.popularAlbumsAndSingles, isNull);
    });

    test('loadAll runs all three queries in parallel', () async {
      final d = await database.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      await d.insert('dj_listening_history', {
        'track_id': 't1',
        'artist_name': 'Artist',
        'primary_genre': 'Rock',
        'timestamp': now,
      });

      final provider = HomeFeedProvider(database: database);
      await provider.loadAll();

      expect(provider.topSongsPerTopGenre, isNotNull);
      expect(provider.popularAlbumsAndSingles, isNotNull);
      expect(provider.listeningStats, isNotNull);
    });

    test('load failure produces empty result and does not crash', () async {
      // Close the database so queries throw
      await database.close();
      try {
        await File(dbPath).delete();
      } catch (_) {}

      final provider = HomeFeedProvider(database: database);
      // Should not throw
      await provider.loadTopSongsPerTopGenre();

      expect(provider.topSongsPerTopGenre, isNotNull);
      expect(provider.topSongsPerTopGenre, isEmpty);
    });
  });
}
