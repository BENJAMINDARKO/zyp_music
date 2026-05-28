import 'package:flutter/material.dart';
import 'app.dart';
import 'data/datasources/local/playlist_database.dart';
import 'data/datasources/remote/youtube_remote_datasource.dart';
import 'data/repositories/audio_repository_impl.dart';
import 'data/repositories/playlist_repository_impl.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final remoteDataSource = YoutubeRemoteDataSource();
  final localDatabase = PlaylistDatabase();
  final playlistRepository = PlaylistRepositoryImpl(
    remoteDataSource: remoteDataSource,
    localDatabase: localDatabase,
  );
  final audioRepository = AudioRepositoryImpl(
    remoteDataSource: remoteDataSource,
  );

  runApp(YTMusixApp(
    playlistRepository: playlistRepository,
    audioRepository: audioRepository,
  ));
}
