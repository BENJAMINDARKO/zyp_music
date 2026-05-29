import 'package:flutter/material.dart';
import 'package:audio_session/audio_session.dart';
import 'app.dart';
import 'data/datasources/local/playlist_database.dart';
import 'data/datasources/remote/youtube_remote_datasource.dart';
import 'data/repositories/audio_repository_impl.dart';
import 'data/repositories/playlist_repository_impl.dart';
import 'service/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playback,
    androidAudioAttributes: AndroidAudioAttributes(
      contentType: AndroidAudioContentType.music,
      usage: AndroidAudioUsage.media,
    ),
    androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
    androidWillPauseWhenDucked: false,
  ));

  final authService = AuthService();
  final remoteDataSource = YoutubeRemoteDataSource(authService: authService);
  await remoteDataSource.init();
  final localDatabase = PlaylistDatabase();
  final playlistRepository = PlaylistRepositoryImpl(
    remoteDataSource: remoteDataSource,
    localDatabase: localDatabase,
  );
  final audioRepository = AudioRepositoryImpl(
    remoteDataSource: remoteDataSource,
    authService: authService,
  );

  runApp(YTMusixApp(
    playlistRepository: playlistRepository,
    audioRepository: audioRepository,
  ));
}
