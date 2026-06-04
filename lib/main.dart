import 'package:flutter/material.dart';
import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app.dart';
import 'core/utils/app_logger.dart';
import 'data/datasources/local/playlist_database.dart';
import 'data/datasources/remote/youtube_remote_datasource.dart';
import 'data/datasources/remote/lyrics_remote_datasource.dart';
import 'data/repositories/audio_repository_impl.dart';
import 'data/repositories/playlist_repository_impl.dart';
import 'data/datasources/remote/charts_remote_datasource.dart';
import 'data/repositories/charts_repository_impl.dart';
import 'data/models/cache_tracker_model.dart';
import 'core/services/hybrid_cache_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/queue_manager.dart';
import 'service/auth_service.dart';
import 'service/audio_handler.dart';
import 'service/download_service.dart';
import 'presentation/providers/download_provider.dart';
import 'presentation/providers/settings_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.init();

  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(1)) {
    Hive.registerAdapter(CacheTrackerModelAdapter());
  }
  // The local SQLite database is opened before the Hive box so the cache
  // coordinator can be constructed with a reference to the permanent
  // library. The cross-database eviction guard needs that handle.
  final localDatabase = PlaylistDatabase();
  final hybridCache = HybridCacheService(libraryDatabase: localDatabase);
  await hybridCache.init();

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
    await remoteDataSource.init();
    final playlistRepository = PlaylistRepositoryImpl(
      remoteDataSource: remoteDataSource,
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
      lyricsDataSource: lyricsDataSource,
      handler: audioHandler,
      database: localDatabase,
      hybridCache: hybridCache,
    );

    final downloadService = DownloadService(
      audioRepository: audioRepository,
      database: localDatabase,
      settingsProvider: settingsProvider,
    );
    final downloadProvider = DownloadProvider(downloadService, hybridCache);
    await downloadProvider.init();

    // Construct the global connectivity listener after every collaborator
    // it needs to wake up is alive. `initialize` runs the synchronous
    // initial probe (so the system is locked to `offline` or `online`
    // from the very first frame) and then attaches the long-lived
    // `onConnectivityChanged` subscription.
    final connectivityService = ConnectivityService(
      audioRepository: audioRepository,
      remoteDataSource: remoteDataSource,
      lyricsDataSource: lyricsDataSource,
    );
    await connectivityService.initialize();

    // QueueManager coordinates the manual playback queue and the explicit
    // Auto DJ engine. It listens to the connectivity service so the offline
    // Hive-shuffle pool and the online AutoNext web service can be hot
    // swapped as the device transitions between states.
    final queueManager = QueueManager(
      audioRepository: audioRepository,
      hybridCache: hybridCache,
      connectivity: connectivityService,
      libraryDatabase: localDatabase,
    );
    queueManager.start();

    runApp(MonochromeApp(
      playlistRepository: playlistRepository,
      audioRepository: audioRepository,
      chartsRepository: chartsRepository,
      downloadProvider: downloadProvider,
      settingsProvider: settingsProvider,
      audioHandler: audioHandler,
      hybridCache: hybridCache,
      connectivityService: connectivityService,
      queueManager: queueManager,
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
