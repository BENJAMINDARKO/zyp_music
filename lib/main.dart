import 'package:flutter/material.dart';
import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart';
import 'app.dart';
import 'core/utils/app_logger.dart';
import 'data/datasources/local/playlist_database.dart';
import 'data/datasources/remote/youtube_remote_datasource.dart';
import 'data/datasources/remote/tidal_remote_datasource.dart';
import 'data/datasources/remote/lyrics_remote_datasource.dart';
import 'data/repositories/audio_repository_impl.dart';
import 'data/repositories/playlist_repository_impl.dart';
import 'data/datasources/remote/charts_remote_datasource.dart';
import 'data/repositories/charts_repository_impl.dart';
import 'service/auth_service.dart';
import 'service/audio_handler.dart';
import 'service/download_service.dart';
import 'presentation/providers/download_provider.dart';
import 'presentation/providers/settings_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.init();

  try {
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
    final tidalDataSource = TidalRemoteDataSource();
    await remoteDataSource.init();
    final localDatabase = PlaylistDatabase();
    final playlistRepository = PlaylistRepositoryImpl(
      remoteDataSource: remoteDataSource,
      tidalDataSource: tidalDataSource,
      localDatabase: localDatabase,
    );

    final chartsDataSource = ChartsRemoteDataSource(youtubeDataSource: remoteDataSource);
    final chartsRepository = ChartsRepositoryImpl(remoteDataSource: chartsDataSource);

    final settingsProvider = SettingsProvider();
    await settingsProvider.load();

    final audioHandler = await AudioService.init(
      builder: () => MusicAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'ytmusix_music',
        androidNotificationChannelName: 'Music Playback',
        androidNotificationIcon: 'mipmap/ic_launcher',
        androidNotificationOngoing: true,
        androidNotificationClickStartsActivity: true,
      ),
    );

    final lyricsDataSource = LyricsRemoteDataSource();
    final audioRepository = AudioRepositoryImpl(
      remoteDataSource: remoteDataSource,
      tidalDataSource: tidalDataSource,
      lyricsDataSource: lyricsDataSource,
      handler: audioHandler,
      database: localDatabase,
    );

    final downloadService = DownloadService(
      audioRepository: audioRepository,
      database: localDatabase,
      settingsProvider: settingsProvider,
    );
    final downloadProvider = DownloadProvider(downloadService);
    await downloadProvider.init();

    runApp(MonochromeApp(
      playlistRepository: playlistRepository,
      audioRepository: audioRepository,
      chartsRepository: chartsRepository,
      downloadProvider: downloadProvider,
      settingsProvider: settingsProvider,
      audioHandler: audioHandler,
    ));
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Failed to initialize: $e',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ),
        theme: ThemeData.dark(),
      ),
    );
  }
}
