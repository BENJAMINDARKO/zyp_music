import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:zyp_music/data/datasources/local/playlist_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('getTopSongsPerTopGenre', () {
    late PlaylistDatabase db;
    late String dbPath;

    setUp(() async {
      dbPath = '${Directory.systemTemp.path}/test_top_songs_${DateTime.now().millisecondsSinceEpoch}.db';
      db = PlaylistDatabase.forTesting(dbPath);
      // Ensure the database is created
      await db.database;
    });

    tearDown(() async {
      await db.close();
      try {
        await File(dbPath).delete();
      } catch (_) {}
    });

    test('returns empty list for empty history', () async {
      final result = await db.getTopSongsPerTopGenre();
      expect(result, isEmpty);
    });

    test('returns top track per genre, sorted by genre play count', () async {
      final d = await db.database;
      // Insert 5 Hip-Hop plays, 3 Afrobeats plays, 1 Rock play
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < 5; i++) {
        await d.insert('dj_listening_history', {
          'track_id': 'hh_$i',
          'artist_name': 'HH Artist',
          'primary_genre': 'Hip-Hop',
          'timestamp': now - (i * 1000),
        });
      }
      for (var i = 0; i < 3; i++) {
        await d.insert('dj_listening_history', {
          'track_id': 'afro_$i',
          'artist_name': 'Afro Artist',
          'primary_genre': 'Afrobeats',
          'timestamp': now - (i * 1000),
        });
      }
      await d.insert('dj_listening_history', {
        'track_id': 'rock_1',
        'artist_name': 'Rock Artist',
        'primary_genre': 'Rock',
        'timestamp': now - 1000,
      });

      final result = await db.getTopSongsPerTopGenre();
      expect(result.length, equals(3));
      expect(result[0].primaryGenre, equals('Hip-Hop'));
      expect(result[1].primaryGenre, equals('Afrobeats'));
      expect(result[2].primaryGenre, equals('Rock'));
    });

    test('excludes Unknown genre rows', () async {
      final d = await db.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      await d.insert('dj_listening_history', {
        'track_id': 'known_1',
        'artist_name': 'Known',
        'primary_genre': 'Hip-Hop',
        'timestamp': now,
      });
      await d.insert('dj_listening_history', {
        'track_id': 'unknown_1',
        'artist_name': 'Unknown',
        'primary_genre': 'Unknown',
        'timestamp': now,
      });

      final result = await db.getTopSongsPerTopGenre();
      expect(result.length, equals(1));
      expect(result.first.primaryGenre, equals('Hip-Hop'));
    });

    test('respects genreLimit parameter', () async {
      final d = await db.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var g = 0; g < 10; g++) {
        await d.insert('dj_listening_history', {
          'track_id': 't_$g',
          'artist_name': 'Artist $g',
          'primary_genre': 'Genre $g',
          'timestamp': now - (g * 1000),
        });
      }

      final result = await db.getTopSongsPerTopGenre(genreLimit: 3);
      expect(result.length, equals(3));
    });
  });

  group('getMostPlayedAlbumsAndSingles', () {
    late PlaylistDatabase db;
    late String dbPath;

    setUp(() async {
      dbPath = '${Directory.systemTemp.path}/test_albums_${DateTime.now().millisecondsSinceEpoch}.db';
      db = PlaylistDatabase.forTesting(dbPath);
      await db.database;
    });

    tearDown(() async {
      await db.close();
      try {
        await File(dbPath).delete();
      } catch (_) {}
    });

    test('returns empty for empty history', () async {
      final result = await db.getMostPlayedAlbumsAndSingles();
      expect(result, isEmpty);
    });

    test('classifies singles correctly when album is null', () async {
      final d = await db.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      await d.insert('downloaded_tracks', {
        'id': 'track_1',
        'playlistId': 'pl',
        'title': 'Single Track',
        'author': 'Artist',
        'filePath': '/tmp/test',
        'downloadedAt': now,
      });
      await d.insert('dj_listening_history', {
        'track_id': 'track_1',
        'artist_name': 'Artist',
        'primary_genre': 'Pop',
        'timestamp': now,
      });

      final result = await db.getMostPlayedAlbumsAndSingles();
      expect(result.length, equals(1));
      expect(result.first.kind, equals('single'));
    });

    test('classifies singles correctly when album equals title', () async {
      final d = await db.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      await d.insert('downloaded_tracks', {
        'id': 'track_1',
        'playlistId': 'pl',
        'title': 'SWAGGA',
        'author': 'Artist',
        'album': 'SWAGGA',
        'filePath': '/tmp/test',
        'downloadedAt': now,
      });
      await d.insert('dj_listening_history', {
        'track_id': 'track_1',
        'artist_name': 'Artist',
        'primary_genre': 'Pop',
        'timestamp': now,
      });

      final result = await db.getMostPlayedAlbumsAndSingles();
      expect(result.length, equals(1));
      expect(result.first.kind, equals('single'));
    });

    test('aggregates album tracks by album_id', () async {
      final d = await db.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      // Three tracks in the same album
      for (var i = 0; i < 3; i++) {
        await d.insert('downloaded_tracks', {
          'id': 'track_$i',
          'playlistId': 'pl',
          'title': 'Track $i',
          'author': 'Artist',
          'album': 'The Album',
          'albumId': 'album_1',
          'filePath': '/tmp/test',
          'downloadedAt': now,
        });
        for (var j = 0; j < 2; j++) {
          await d.insert('dj_listening_history', {
            'track_id': 'track_$i',
            'artist_name': 'Artist',
            'primary_genre': 'Rock',
            'timestamp': now - (i * 1000),
          });
        }
      }

      final result = await db.getMostPlayedAlbumsAndSingles();
      expect(result.length, equals(1));
      expect(result.first.kind, equals('album'));
      expect(result.first.playCount, equals(6));
    });

    test('mixes albums and singles, sorted by play count', () async {
      final d = await db.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      // Album with 12 plays total
      await d.insert('downloaded_tracks', {
        'id': 'album_track_1',
        'playlistId': 'pl',
        'title': 'Album Track',
        'author': 'Album Artist',
        'album': 'Great Album',
        'albumId': 'album_a',
        'filePath': '/tmp/test',
        'downloadedAt': now,
      });
      for (var i = 0; i < 12; i++) {
        await d.insert('dj_listening_history', {
          'track_id': 'album_track_1',
          'artist_name': 'Album Artist',
          'primary_genre': 'Rock',
          'timestamp': now - (i * 1000),
        });
      }
      // Single with 15 plays
      await d.insert('downloaded_tracks', {
        'id': 'single_1',
        'playlistId': 'pl',
        'title': 'Hot Single',
        'author': 'Single Artist',
        'filePath': '/tmp/test',
        'downloadedAt': now,
      });
      for (var i = 0; i < 15; i++) {
        await d.insert('dj_listening_history', {
          'track_id': 'single_1',
          'artist_name': 'Single Artist',
          'primary_genre': 'Pop',
          'timestamp': now - (i * 1000),
        });
      }

      final result = await db.getMostPlayedAlbumsAndSingles();
      expect(result.length, equals(2));
      expect(result[0].kind, equals('single'));
      expect(result[0].playCount, equals(15));
      expect(result[1].kind, equals('album'));
      expect(result[1].playCount, equals(12));
    });

    test('respects limit parameter', () async {
      final d = await db.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < 8; i++) {
        await d.insert('downloaded_tracks', {
          'id': 'track_$i',
          'playlistId': 'pl',
          'title': 'Single $i',
          'author': 'Artist',
          'filePath': '/tmp/test',
          'downloadedAt': now,
        });
        await d.insert('dj_listening_history', {
          'track_id': 'track_$i',
          'artist_name': 'Artist',
          'primary_genre': 'Pop',
          'timestamp': now - (i * 1000),
        });
      }

      final result = await db.getMostPlayedAlbumsAndSingles(limit: 3);
      expect(result.length, equals(3));
    });
  });

  group('getListeningStats', () {
    late PlaylistDatabase db;
    late String dbPath;

    setUp(() async {
      dbPath = '${Directory.systemTemp.path}/test_stats_${DateTime.now().millisecondsSinceEpoch}.db';
      db = PlaylistDatabase.forTesting(dbPath);
      await db.database;
    });

    tearDown(() async {
      await db.close();
      try {
        await File(dbPath).delete();
      } catch (_) {}
    });

    test('returns empty for empty history', () async {
      final result = await db.getListeningStats();
      expect(result, equals(ListeningStats.empty));
    });

    test('returns empty for history with only data older than 30 days',
        () async {
      final d = await db.database;
      final oldTs = DateTime.now()
          .subtract(const Duration(days: 35))
          .millisecondsSinceEpoch;
      await d.insert('dj_listening_history', {
        'track_id': 'old',
        'artist_name': 'Old Artist',
        'primary_genre': 'Rock',
        'timestamp': oldTs,
      });

      final result = await db.getListeningStats();
      expect(result.distinctGenreCount, equals(0));
    });

    test('counts only rows within 30-day window', () async {
      final d = await db.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      final oldTs = DateTime.now()
          .subtract(const Duration(days: 35))
          .millisecondsSinceEpoch;
      for (var i = 0; i < 5; i++) {
        await d.insert('dj_listening_history', {
          'track_id': 'recent_$i',
          'artist_name': 'Recent Artist',
          'primary_genre': 'Hip-Hop',
          'timestamp': now - (i * 1000),
        });
      }
      for (var i = 0; i < 5; i++) {
        await d.insert('dj_listening_history', {
          'track_id': 'old_$i',
          'artist_name': 'Old Artist',
          'primary_genre': 'Rock',
          'timestamp': oldTs - (i * 1000),
        });
      }

      final result = await db.getListeningStats();
      expect(result.distinctGenreCount, equals(1));
      expect(result.distinctArtistCount, equals(1));
    });

    test('excludes Unknown genre from genre count', () async {
      final d = await db.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      await d.insert('dj_listening_history', {
        'track_id': 'hh_1',
        'artist_name': 'HH Artist',
        'primary_genre': 'Hip-Hop',
        'timestamp': now,
      });
      await d.insert('dj_listening_history', {
        'track_id': 'afro_1',
        'artist_name': 'Afro Artist',
        'primary_genre': 'Afrobeats',
        'timestamp': now,
      });
      await d.insert('dj_listening_history', {
        'track_id': 'unknown_1',
        'artist_name': 'Unknown',
        'primary_genre': 'Unknown',
        'timestamp': now,
      });

      final result = await db.getListeningStats();
      expect(result.distinctGenreCount, equals(2));
    });

    test('returns top 3 artists sorted by play count', () async {
      final d = await db.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < 10; i++) {
        await d.insert('dj_listening_history', {
          'track_id': 'a_$i',
          'artist_name': 'ArtistA',
          'primary_genre': 'Pop',
          'timestamp': now - (i * 1000),
        });
      }
      for (var i = 0; i < 7; i++) {
        await d.insert('dj_listening_history', {
          'track_id': 'b_$i',
          'artist_name': 'ArtistB',
          'primary_genre': 'Pop',
          'timestamp': now - (i * 1000),
        });
      }
      for (var i = 0; i < 5; i++) {
        await d.insert('dj_listening_history', {
          'track_id': 'c_$i',
          'artist_name': 'ArtistC',
          'primary_genre': 'Pop',
          'timestamp': now - (i * 1000),
        });
      }
      for (var i = 0; i < 3; i++) {
        await d.insert('dj_listening_history', {
          'track_id': 'd_$i',
          'artist_name': 'ArtistD',
          'primary_genre': 'Pop',
          'timestamp': now - (i * 1000),
        });
      }

      final result = await db.getListeningStats();
      expect(result.topArtists.length, equals(3));
      expect(result.topArtists[0].artistName, equals('ArtistA'));
      expect(result.topArtists[1].artistName, equals('ArtistB'));
      expect(result.topArtists[2].artistName, equals('ArtistC'));
    });

    test('returns fewer than 3 artists when history is sparse', () async {
      final d = await db.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < 5; i++) {
        await d.insert('dj_listening_history', {
          'track_id': 'a_$i',
          'artist_name': 'ArtistA',
          'primary_genre': 'Pop',
          'timestamp': now - (i * 1000),
        });
      }
      for (var i = 0; i < 3; i++) {
        await d.insert('dj_listening_history', {
          'track_id': 'b_$i',
          'artist_name': 'ArtistB',
          'primary_genre': 'Pop',
          'timestamp': now - (i * 1000),
        });
      }

      final result = await db.getListeningStats();
      expect(result.topArtists.length, equals(2));
    });
  });
}
