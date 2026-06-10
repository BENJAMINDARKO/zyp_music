import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:zyp_music/data/datasources/local/playlist_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('getTopArtistsFromHistory', () {
    late PlaylistDatabase db;
    late String dbPath;

    setUp(() async {
      dbPath = '${Directory.systemTemp.path}/test_top_artists_${DateTime.now().millisecondsSinceEpoch}.db';
      db = PlaylistDatabase.forTesting(dbPath);
      await db.database;
    });

    tearDown(() async {
      await db.close();
      try {
        await File(dbPath).delete();
      } catch (_) {}
    });

    Future<void> _insertHistory({
      required String trackId,
      required String artistName,
      int count = 1,
      String genre = 'Pop',
    }) async {
      final d = await db.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < count; i++) {
        await d.insert('dj_listening_history', {
          'track_id': trackId,
          'artist_name': artistName,
          'primary_genre': genre,
          'timestamp': now + i,
        });
      }
    }

    Future<void> _insertDownloadedTrack({
      required String trackId,
      String title = 'Sample Track',
      String? thumbnailUrl,
      String author = 'Artist',
    }) async {
      final d = await db.database;
      await d.insert('downloaded_tracks', {
        'id': trackId,
        'playlistId': 'pl_test',
        'title': title,
        'thumbnailUrl': thumbnailUrl,
        'durationSeconds': 200,
        'author': author,
        'filePath': '/fake/path/$trackId.mp3',
        'downloadedAt': DateTime.now().millisecondsSinceEpoch,
      });
    }

    test('returns empty for empty history', () async {
      final result = await db.getTopArtistsFromHistory();
      expect(result, isEmpty);
    });

    test('returns top N artists sorted by play count', () async {
      await _insertHistory(trackId: 't1', artistName: 'ArtistA', count: 10);
      await _insertHistory(trackId: 't2', artistName: 'ArtistB', count: 7);
      await _insertHistory(trackId: 't3', artistName: 'ArtistC', count: 5);
      await _insertHistory(trackId: 't4', artistName: 'ArtistD', count: 3);

      final result = await db.getTopArtistsFromHistory(limit: 3);
      expect(result.length, equals(3));
      expect(result[0].artistName, equals('ArtistA'));
      expect(result[0].playCount, equals(10));
      expect(result[1].artistName, equals('ArtistB'));
      expect(result[1].playCount, equals(7));
      expect(result[2].artistName, equals('ArtistC'));
      expect(result[2].playCount, equals(5));
    });

    test('returns at most limit entries', () async {
      for (var i = 0; i < 15; i++) {
        await _insertHistory(
          trackId: 't$i',
          artistName: 'Artist$i',
          count: 1,
        );
      }

      final result = await db.getTopArtistsFromHistory(limit: 10);
      expect(result.length, equals(10));
    });

    test('excludes Unknown artists', () async {
      await _insertHistory(trackId: 't1', artistName: 'ArtistA', count: 5);
      await _insertHistory(trackId: 't2', artistName: 'Unknown', count: 10);
      await _insertHistory(trackId: 't3', artistName: 'ArtistB', count: 3);

      final result = await db.getTopArtistsFromHistory();
      expect(result.where((a) => a.artistName == 'Unknown'), isEmpty);
      expect(result.any((a) => a.artistName == 'ArtistA'), isTrue);
      expect(result.any((a) => a.artistName == 'ArtistB'), isTrue);
    });

    test('populates sample track and thumbnail when downloaded_tracks row exists', () async {
      await _insertHistory(trackId: 't1', artistName: 'ArtistA', count: 5);
      await _insertDownloadedTrack(
        trackId: 't1',
        title: 'Big Hit',
        thumbnailUrl: 'http://example.com/thumb.jpg',
        author: 'ArtistA',
      );

      final result = await db.getTopArtistsFromHistory();
      expect(result.first.sampleTrackId, isNotNull);
      expect(result.first.sampleTrackId, equals('t1'));
      expect(result.first.thumbnailUrl, isNotNull);
      expect(result.first.thumbnailUrl, equals('http://example.com/thumb.jpg'));
    });

    test('returns null thumbnail when no downloaded_tracks row exists', () async {
      await _insertHistory(trackId: 't1', artistName: 'ArtistA', count: 5);

      final result = await db.getTopArtistsFromHistory();
      expect(result.first.sampleTrackId, isNotNull);
      expect(result.first.thumbnailUrl, isNull);
    });
  });
}
