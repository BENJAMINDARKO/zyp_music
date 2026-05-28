import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'app.dart';
import 'data/datasources/local/playlist_database.dart';
import 'data/datasources/remote/youtube_remote_datasource.dart';
import 'data/repositories/audio_repository_impl.dart';
import 'data/repositories/playlist_repository_impl.dart';
import 'service/audio_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final audioHandler = await AudioService.init(
    builder: () => YTMusixAudioHandler(),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.ytmusix.audio',
      androidNotificationChannelName: 'YTMusix Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  final remoteDataSource = YoutubeRemoteDataSource();
  final localDatabase = PlaylistDatabase();
  final playlistRepository = PlaylistRepositoryImpl(
    remoteDataSource: remoteDataSource,
    localDatabase: localDatabase,
  );
  final audioRepository = AudioRepositoryImpl(
    remoteDataSource: remoteDataSource,
    handler: audioHandler,
  );

  runApp(YTMusixApp(
    playlistRepository: playlistRepository,
    audioRepository: audioRepository,
  ));
}
