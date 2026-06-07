// Spec 2H — getGenreClusterCounts query.
//
// Validates:
//   * INNER JOINs downloaded_tracks to artist_genres on
//     the lowercased author/display_name pair.
//   * Unpacks `normalized_genres_json` arrays and counts
//     each canonical genre.
//   * Excludes unenriched rows (null/empty genre JSON).
//   * Returns counts in a Map keyed by canonical genre.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:zyp_music/data/datasources/local/playlist_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late PlaylistDatabase db;
  late Database raw;

  setUp(() async {
    final tmp = Directory.systemTemp.createTempSync('zyp_2h_counts_');
    final path = '${tmp.path}/ytmusix.db';
    db = PlaylistDatabase.forTesting(path);
    raw = await db.database;

    // Seed 5 artists and 6 tracks.
    await raw.insert('artist_genres', {
      'normalized_artist': 'black-sherif',
      'display_name': 'Black Sherif',
      'mbid': 'mb1',
      'genres_json': '["afro-fusion"]',
      'genre_count': 1,
      'fetched_at': 1700000000,
      'normalized_genres_json': '["Afrobeats","Hip-Hop"]',
      'normalization_version': 14,
    });
    await raw.insert('artist_genres', {
      'normalized_artist': 'sarkodie',
      'display_name': 'Sarkodie',
      'mbid': 'mb2',
      'genres_json': '["hiplife"]',
      'genre_count': 1,
      'fetched_at': 1700000000,
      'normalized_genres_json': '["Afrobeats","Hiplife"]',
      'normalization_version': 14,
    });
    await raw.insert('artist_genres', {
      'normalized_artist': 'drake',
      'display_name': 'Drake',
      'mbid': 'mb3',
      'genres_json': '["hip hop"]',
      'genre_count': 1,
      'fetched_at': 1700000000,
      'normalized_genres_json': '["Hip-Hop"]',
      'normalization_version': 14,
    });
    await raw.insert('artist_genres', {
      'normalized_artist': 'metallica',
      'display_name': 'Metallica',
      'mbid': 'mb4',
      'genres_json': '["metal"]',
      'genre_count': 1,
      'fetched_at': 1700000000,
      'normalized_genres_json': '["Rock","Metal"]',
      'normalization_version': 14,
    });
    // Unenriched artist — no row in artist_genres.
    await raw.insert('artist_genres', {
      'normalized_artist': 'unenriched',
      'display_name': 'Unknown Artist',
      'mbid': 'mb5',
      'genres_json': '[]',
      'genre_count': 0,
      'fetched_at': 1700000000,
      'normalized_genres_json': '[]',
      'normalization_version': 14,
    });

    Future<void> insertTrack(String id, String author) async {
      await raw.insert('downloaded_tracks', {
        'id': id,
        'playlistId': 'p1',
        'title': 'T-$id',
        'thumbnailUrl': null,
        'durationSeconds': 180,
        'author': author,
        'filePath': '/tmp/$id.m4a',
        'downloadedAt': 1700000000,
        'source': 'youtube',
      });
    }

    await insertTrack('t1', 'Black Sherif');
    await insertTrack('t2', 'Black Sherif');
    await insertTrack('t3', 'Sarkodie');
    await insertTrack('t4', 'Drake');
    await insertTrack('t5', 'Metallica');
    await insertTrack('t6', 'Unknown Artist');
  });

  tearDown(() async {
    await db.close();
  });

  test('counts each canonical genre from joined downloaded tracks', () async {
    final counts = await db.getGenreClusterCounts();
    // Black Sherif × 2 → Afrobeats=2, Hip-Hop=2.
    // Sarkodie × 1 → Afrobeats +1, Hiplife +1 → Afrobeats=3, Hiplife=1.
    // Drake × 1 → Hip-Hop +1 → Hip-Hop=3.
    // Metallica × 1 → Rock=1, Metal=1.
    // Unknown Artist (empty `[]`) → contributes nothing.
    expect(counts['Afrobeats'], 3);
    expect(counts['Hip-Hop'], 3);
    expect(counts['Hiplife'], 1);
    expect(counts['Rock'], 1);
    expect(counts['Metal'], 1);
  });

  test('excludes unenriched artists via INNER JOIN', () async {
    final counts = await db.getGenreClusterCounts();
    // Unknown Artist has no overlap with [Afrobeats, Hip-Hop, Hiplife, Rock, Metal].
    expect(counts['[]'], isNull,
        reason: 'Empty arrays should not be counted as a genre');
    // Verify the 6th track contributed nothing.
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    // 2 BS × 2 + 1 Sark × 2 + 1 Drake × 1 + 1 Metallica × 2 = 4 + 2 + 1 + 2 = 9.
    expect(total, 9);
  });

  test('case-insensitive author/display_name match', () async {
    // Add a 7th track with lowercased author that should
    // still match "Black Sherif" via the LOWER() join.
    await raw.insert('downloaded_tracks', {
      'id': 't7',
      'playlistId': 'p1',
      'title': 'T-7',
      'thumbnailUrl': null,
      'durationSeconds': 180,
      'author': 'BLACK SHERIF',
      'filePath': '/tmp/t7.m4a',
      'downloadedAt': 1700000000,
      'source': 'youtube',
    });
    final counts = await db.getGenreClusterCounts();
    expect(counts['Afrobeats'], 4);
    expect(counts['Hip-Hop'], 4);
  });

  test('empty downloaded_tracks → empty map', () async {
    await raw.delete('downloaded_tracks');
    final counts = await db.getGenreClusterCounts();
    expect(counts, isEmpty);
  });
}
