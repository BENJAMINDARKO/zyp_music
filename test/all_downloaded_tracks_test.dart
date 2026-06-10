import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:zyp_music/data/datasources/local/playlist_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('getAllDownloadedTracks', () {
    late PlaylistDatabase db;
    late String dbPath;

    setUp(() async {
      dbPath = '${Directory.systemTemp.path}/test_all_dl_${DateTime.now().millisecondsSinceEpoch}.db';
      db = PlaylistDatabase.forTesting(dbPath);
      await db.database;
    });

    tearDown(() async {
      await db.close();
      try {
        await File(dbPath).delete();
      } catch (_) {}
    });

    test('returns empty list when downloaded_tracks is empty', () async {
      final result = await db.getAllDownloadedTracks();
      expect(result, isEmpty);
    });

    test('returns all rows ordered by downloadedAt descending', () async {
      final d = await db.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      await d.insert('downloaded_tracks', {
        'id': 't1',
        'playlistId': 'pl1',
        'title': 'Recent Track',
        'author': 'Artist A',
        'thumbnailUrl': null,
        'durationSeconds': 200,
        'filePath': '/tmp/t1.mp3',
        'downloadedAt': now,
      });
      await d.insert('downloaded_tracks', {
        'id': 't2',
        'playlistId': 'pl1',
        'title': 'Old Track',
        'author': 'Artist B',
        'thumbnailUrl': null,
        'durationSeconds': 180,
        'filePath': '/tmp/t2.mp3',
        'downloadedAt': now - 100000,
      });
      await d.insert('downloaded_tracks', {
        'id': 't3',
        'playlistId': 'pl2',
        'title': 'Middle Track',
        'author': 'Artist C',
        'thumbnailUrl': null,
        'durationSeconds': 150,
        'filePath': '/tmp/t3.mp3',
        'downloadedAt': now - 50000,
      });

      final result = await db.getAllDownloadedTracks();
      expect(result.length, equals(3));
      expect(result[0]['id'], equals('t1'));
      expect(result[1]['id'], equals('t3'));
      expect(result[2]['id'], equals('t2'));
    });

    test('returns rows with all schema fields populated', () async {
      final d = await db.database;
      await d.insert('downloaded_tracks', {
        'id': 't1',
        'playlistId': 'pl1',
        'title': 'Full Track',
        'author': 'Artist A',
        'album': 'Album Name',
        'albumId': 'al1',
        'year': 2024,
        'thumbnailUrl': 'http://example.com/thumb.jpg',
        'durationSeconds': 200,
        'filePath': '/tmp/t1.mp3',
        'downloadedAt': DateTime.now().millisecondsSinceEpoch,
        'source': 'youtube',
      });

      final result = await db.getAllDownloadedTracks();
      expect(result.length, equals(1));
      final row = result.first;
      expect(row['id'], equals('t1'));
      expect(row['title'], equals('Full Track'));
      expect(row['author'], equals('Artist A'));
      expect(row['album'], equals('Album Name'));
      expect(row['albumId'], equals('al1'));
      expect(row['year'], equals(2024));
      expect(row['thumbnailUrl'], equals('http://example.com/thumb.jpg'));
      expect(row['durationSeconds'], equals(200));
      expect(row['filePath'], equals('/tmp/t1.mp3'));
      expect(row['source'], equals('youtube'));
    });

    test('handles rows with null optional fields gracefully', () async {
      final d = await db.database;
      await d.insert('downloaded_tracks', {
        'id': 't1',
        'playlistId': 'pl1',
        'title': 'Minimal Track',
        'author': null,
        'album': null,
        'albumId': null,
        'year': null,
        'thumbnailUrl': null,
        'durationSeconds': null,
        'filePath': '/tmp/t1.mp3',
        'downloadedAt': DateTime.now().millisecondsSinceEpoch,
      });

      final result = await db.getAllDownloadedTracks();
      expect(result.length, equals(1));
      final row = result.first;
      expect(row['id'], equals('t1'));
      expect(row['title'], equals('Minimal Track'));
      expect(row['author'], isNull);
      expect(row['album'], isNull);
      expect(row['albumId'], isNull);
      expect(row['year'], isNull);
      expect(row['thumbnailUrl'], isNull);
      expect(row['durationSeconds'], isNull);
    });
  });
}
