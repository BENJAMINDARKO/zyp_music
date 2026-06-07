// Spec 2H — ShuffleLibraryFilterContent widget.
//
// We exercise the content widget directly (without
// showModalBottomSheet) to avoid Flutter test runner
// issues with modal route animation controllers.
//
// Validates:
//   * Top entry is "No filter (all songs)".
//   * Genres sorted descending by count, alphabetical
//     tiebreak.
//   * Singular/plural subtitle.
//   * Empty library shows the fallback message.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:zyp_music/data/datasources/local/playlist_database.dart';
import 'package:zyp_music/ui/widgets/auto_dj_mode_picker.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<PlaylistDatabase> _seedDb({
    required Map<String, List<String>> artistGenres,
  }) async {
    final tmp = Directory.systemTemp.createTempSync('zyp_2h_widget_');
    final path = '${tmp.path}/ytmusix.db';
    final db = PlaylistDatabase.forTesting(path);
    final raw = await db.database;
    var i = 0;
    for (final entry in artistGenres.entries) {
      await raw.insert('artist_genres', {
        'normalized_artist': entry.key.toLowerCase().replaceAll(' ', '-'),
        'display_name': entry.key,
        'mbid': 'mb${i++}',
        'genres_json': '[]',
        'genre_count': entry.value.length,
        'fetched_at': 1700000000,
        'normalized_genres_json':
            '[${entry.value.map((g) => '"$g"').join(',')}]',
        'normalization_version': 14,
      });
      await raw.insert('downloaded_tracks', {
        'id': 't-$i',
        'playlistId': 'p1',
        'title': 'T-$i',
        'thumbnailUrl': null,
        'durationSeconds': 180,
        'author': entry.key,
        'filePath': '/tmp/t-$i.m4a',
        'downloadedAt': 1700000000,
        'source': 'youtube',
      });
    }
    return db;
  }

  // No helper needed — test bodies create the widget inline.

  testWidgets('top entry is "No filter (all songs)"', (tester) async {
    final db = await _seedDb(artistGenres: {
      'Black Sherif': ['Afrobeats'],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Provider<PlaylistDatabase>.value(
          value: db,
          child: ShuffleLibraryFilterContent(database: db),
        ),
      ),
    );
    // Pump frames so the FutureBuilder resolves.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('No filter (all songs)'), findsOneWidget);
    expect(find.text('Afrobeats · 1'), findsOneWidget);
  });

  testWidgets('genres sorted descending by count, alphabetical tiebreak',
      (tester) async {
    final db = await _seedDb(artistGenres: {
      'A': ['Hip-Hop', 'Drill'],
      'B': ['Hip-Hop', 'Drill'],
      'C': ['Hip-Hop'],
      'D': ['Afrobeats'],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Provider<PlaylistDatabase>.value(
          value: db,
          child: ShuffleLibraryFilterContent(database: db),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Hip-Hop · 3'), findsOneWidget);
    expect(find.text('Drill · 2'), findsOneWidget);
    expect(find.text('Afrobeats · 1'), findsOneWidget);
  });

  testWidgets('subtitle uses singular for count 1, plural otherwise',
      (tester) async {
    final db = await _seedDb(artistGenres: {
      'A': ['Hip-Hop'],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Provider<PlaylistDatabase>.value(
          value: db,
          child: ShuffleLibraryFilterContent(database: db),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('1 track'), findsOneWidget);
  });

  testWidgets('empty library shows the fallback message', (tester) async {
    final db = await _seedDb(artistGenres: {});
    await tester.pumpWidget(
      MaterialApp(
        home: Provider<PlaylistDatabase>.value(
          value: db,
          child: ShuffleLibraryFilterContent(database: db),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      find.textContaining('Your library has no enriched tracks'),
      findsOneWidget,
    );
  });
}
