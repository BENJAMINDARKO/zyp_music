import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyp_music/data/datasources/remote/lyrics_remote_datasource.dart';

void main() {
  HttpOverrides.global = null;

  test('fetch lyrics for Swagga Like Us by T.I.', () async {
    final ds = LyricsRemoteDataSource();
    print('Fetching lyrics for Swagga Like Us by T.I....');
    final lyrics = await ds.getSyncedLyrics('Swagga Like Us', 'T.I.');
    print('Result: $lyrics');
    expect(lyrics, isNotNull);
  });

  test('fetch lyrics for The Victory Song by Black Sherif', () async {
    final ds = LyricsRemoteDataSource();
    print('Fetching lyrics for The Victory Song by Black Sherif....');
    final lyrics = await ds.getSyncedLyrics('The Victory Song', 'Black Sherif');
    print('Result: $lyrics');
    expect(lyrics, isNotNull);
  });
}
