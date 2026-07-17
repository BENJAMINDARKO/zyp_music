import 'dart:async';

import 'package:flutter/material.dart';
import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'app.dart';
import 'core/utils/app_logger.dart';
import 'domain/entities/video.dart';
import 'data/datasources/local/playlist_database.dart';
import 'data/datasources/remote/musicbrainz_datasource.dart';
import 'data/datasources/remote/youtube_remote_datasource.dart';
import 'data/datasources/remote/lyrics_remote_datasource.dart';
import 'data/repositories/audio_repository_impl.dart';
import 'data/repositories/playlist_repository_impl.dart';
import 'data/datasources/remote/charts_remote_datasource.dart';
import 'data/repositories/charts_repository_impl.dart';
import 'data/models/cache_tracker_model.dart';
import 'core/services/audio_cache_service.dart';
import 'core/services/auto_dj_routing_service.dart';
import 'core/services/dj_history_ledger.dart';
import 'core/services/genre_enrichment_service.dart';
import 'core/services/country_bonus_service.dart';
import 'core/services/genre_normalization_service.dart';
import 'core/services/spotify_metadata_service.dart';
import 'core/services/genre_proximity_graph.dart';
import 'core/services/genre_similarity_engine.dart';
import 'core/services/hybrid_cache_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/local_crate_miner.dart';
import 'core/services/lyrics_chain_service.dart';
import 'core/services/local_http_proxy_server.dart';
import 'core/services/dynamic_metadata_sync_service.dart';
import 'core/services/queue_manager.dart';
import 'core/migrations/cache_metadata_backfill.dart';
import 'core/constants/network_state.dart';
import 'core/audio/gapless_queue_mixer.dart';
import 'core/audio/silence_scan_worker.dart';
import 'core/audio/dsp_crossfade_engine.dart';
import 'service/auth_service.dart';
import 'service/audio_handler.dart';
import 'service/download_service.dart';
import 'presentation/providers/download_provider.dart';
import 'presentation/providers/home_feed_provider.dart';
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

  // Phase 6: one-time metadata backfill. Hydrates the
  // title/author/thumbnailUrl fields on existing Hive
  // tracker entries from the SQLite downloaded_tracks
  // mirror. The migration is gated on a versioned
  // SharedPreferences flag and is idempotent — safe to
  // call on every launch, and a no-op after the first run.
  // Runs before the UI is shown so any subsequent synthesis
  // path sees the hydrated state.
  final box = hybridCache.box;
  if (box != null) {
    final backfill = CacheMetadataBackfill(
      trackerBox: box,
      database: localDatabase,
    );
    await backfill.runIfNeeded();
  }

  // Phase 6: MusicBrainz data source + the enrichment service
  // that fronts it. Both are app-lifetime singletons; the
  // service is the only collaborator the routing layer and
  // the playback loop need to know about. The data source is
  // owned by the service so the 1-req/sec rate gate is shared
  // between Auto DJ background enrichment and the per-track
  // enqueue fired by PlayerProvider.
  // Spec 2A: load the genre normalization dictionary before
  // constructing the enrichment service — the service
  // synchronously normalizes tags at write time, so a missing
  // dictionary would silently produce empty normalized lists.
  // Spec 2B: load the proximity matrix before any score()
  // call, same reasoning.
  final musicBrainz = MusicBrainzDataSource();
  final genreNormalization = GenreNormalizationService();
  await genreNormalization.initialize();
  final genreProximityGraph = GenreProximityGraph();
  await genreProximityGraph.initialize();
  final genreSimilarity = GenreSimilarityEngine(genreProximityGraph);
  // Spec 2E: load the country→region map before any
  // _sameGenre scoring runs. The asset is small (~5KB) and
  // the service is purely additive on the hot path.
  final countryBonus = CountryBonusService();
  await countryBonus.initialize();

  // Fire-and-forget: pull latest genre/country matrices from CDN
  // (silent no-op if the weekly throttle hasn't expired).
  final metadataSync = DynamicMetadataSyncService();
  unawaited(metadataSync.syncIfRequired());

  final spotifyMetadata = SpotifyMetadataService(db: localDatabase);
  
  final genreEnrichment = GenreEnrichmentService(
    mb: musicBrainz,
    spotify: spotifyMetadata,
    db: localDatabase,
    normalization: genreNormalization,
  );

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

    final audioHandler = await AudioService.init(
      builder: () => MusicAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'ytmusix_music',
        androidNotificationChannelName: 'Music Playback',
        androidNotificationIcon: 'mipmap/ic_launcher',
        androidNotificationOngoing: false,
        androidNotificationClickStartsActivity: true,
        androidStopForegroundOnPause: false,
      ),
    );
    debugPrint('[Main] audioHandler runtimeType=${audioHandler.runtimeType} hash=${identityHashCode(audioHandler)}');

    final lyricsDataSource = LyricsRemoteDataSource();

    // The audio cache service is constructed as a top-level singleton so
    // the audio repository, the playlist repository, and any future
    // collaborators (e.g. the non-playing downloader icon) can share
    // the same on-disk file layout and Hive tracker wiring. The
    // repository no longer instantiates its own copy.
    final audioCacheService = AudioCacheService();

    // Build the audio repository first with no live connectivity
    // reference; we patch it in via `attachConnectivity` after the
    // ConnectivityService is constructed. Until then the lyrics read
    // cascade defaults to the online path, which matches the previous
    // behaviour for the brief startup window.
    final audioRepository = AudioRepositoryImpl(
      remoteDataSource: remoteDataSource,
      lyricsDataSource: lyricsDataSource,
      handler: audioHandler,
      database: localDatabase,
      cacheService: audioCacheService,
      hybridCache: hybridCache,
    );

    // Phase 2: multi-tier lyrics fetch chain. Constructed
    // after the audio repository so it can borrow the
    // repository's on-disk LRC read path as tier 1 (the
    // "is the LRC already on disk?" check). The chain is
    // the network/format layer; the repository is still
    // responsible for the on-disk + Hive write-back.
    final lyricsChain = LyricsChainService(
      youtube: remoteDataSource,
      lrclib: lyricsDataSource,
      cache: audioRepository,
    );
    audioRepository.setLyricsChainService(lyricsChain);

    LocalHttpProxyServer.instance.attachRepository(audioRepository);
    await LocalHttpProxyServer.instance.start();

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
    // Late-bind: wire the live connectivity service into the repository
    // so the offline lyrics cascade can read its current state. After
    // this call every `getLyrics(track)` consults
    // `connectivityService.isOffline` before deciding whether to attempt
    // a network fetch.
    audioRepository.attachConnectivity(connectivityService);
    await connectivityService.initialize();

    final playlistRepository = PlaylistRepositoryImpl(
      remoteDataSource: remoteDataSource,
      localDatabase: localDatabase,
      audioRepository: audioRepository,
      audioCacheService: audioCacheService,
    );

    // Wire the collaborators required by the non-playing background
    // downloader (`downloadTrackIndependent`) and the Hive-to-SQLite
    // cache migration hook (`migrateToLibrary` /
    // `migrateAlbumToLibrary`). Both methods no-op when these
    // collaborators are unset, but the production wiring is the only
    // place they get attached.
    audioCacheService.attachDownloadCollaborators(
      audioRepository: audioRepository,
      hybridCache: hybridCache,
      libraryDatabase: localDatabase,
    );

    final chartsDataSource = ChartsRemoteDataSource(youtubeDataSource: remoteDataSource);
    final chartsRepository = ChartsRepositoryImpl(remoteDataSource: chartsDataSource);

    final settingsProvider = SettingsProvider();
    await settingsProvider.load();

    final downloadService = DownloadService(
      audioRepository: audioRepository,
      database: localDatabase,
      settingsProvider: settingsProvider,
      cacheService: audioCacheService,
    );
    final downloadProvider = DownloadProvider(downloadService, hybridCache);
    await downloadProvider.init();

    final homeFeedProvider = HomeFeedProvider(
      database: localDatabase,
      dataSource: remoteDataSource,
      cacheService: hybridCache,
    );

    // Set global geolocation on YTMusic from persisted preference.
    // All subsequent API calls (home sections, getUpNexts, search, etc.)
    // will be biased toward the user's chosen region.
    if (settingsProvider.preferredGl case final gl?) {
      remoteDataSource.setGl(gl);
    }

    // Listen for region changes at runtime — update YTMusic's gl
    // and refresh the home feed whenever the user picks a new country.
    settingsProvider.addListener(() {
      final gl = settingsProvider.preferredGl;
      if (gl != null) {
        remoteDataSource.setGl(gl);
        homeFeedProvider.refreshYTMusicHome();
      }
    });

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

    // Phase 1: AI DJ history ledger. Bound to the shared
    // PlaylistDatabase singleton so the 80% playback interceptor
    // inside PlayerProvider can persist listening events on
    // every track completion. The ledger is also the source of
    // truth for the cold-start fallback (rows < 3 → genre match
    // → random) queried by the Auto DJ engine.
    final historyLedger = await DJHistoryLedger.create();

    // Phase 2: assemble the 5-mode AI DJ routing stack. Each
    // collaborator is constructed in dependency order:
    //   * CrateMiner reads from SQLite (downloaded_tracks) + Hive
    //     (cache_tracker_box) with a strict File.exists() filter.
    //   * RoutingService wires the per-mode strategies on top of
    //     the miner + the genre-proximity graph + the history
    //     ledger. The online similar-songs path delegates to the
    //     existing AudioRepository.getUpNexts endpoint.
    final crateMiner = LocalCrateMiner(
      libraryDatabase: localDatabase,
      hybridCache: hybridCache,
      historyLedger: historyLedger,
    );
    final routingService = AutoDjRoutingService(
      graph: genreProximityGraph,
      crateMiner: crateMiner,
      historyLedger: historyLedger,
      genreEnrichment: genreEnrichment,
      similarityEngine: genreSimilarity,
      genreNormalization: genreNormalization,
      countryBonusService: countryBonus,
      onlineFetcher: (t) => audioRepository.getUpNexts(t),
      connectivityProbe: () {
        switch (connectivityService.state) {
          case NetworkState.online:
            return NetworkAvailability.online;
          case NetworkState.offline:
            return NetworkAvailability.offline;
          case NetworkState.unknown:
            return NetworkAvailability.unknown;
        }
      },
    );
    queueManager.setRouter(routingService);

    // Phase 3: silence-scan scheduler. Bound to the shared
    // PlaylistDatabase so the worker can persist scan results,
    // and registered on the database itself so
    // `markTrackDownloaded` can fire scans on download commit.
    final scanScheduler = await SilenceScanScheduler.create();
    PlaylistDatabase.setSilenceScanScheduler(scanScheduler);

    // Phase 3: gapless queue mixer. The mixer wraps the
    // just_audio player in a ConcatenatingAudioSource so the
    // PlayerProvider's 15-second-lookahead trigger can append
    // the next track to a pre-buffered timeline (gapless
    // handoff, no second decoder). The mixer is constructed
    // lazily once the MusicAudioHandler is ready; we wire it
    // into the player provider from `app.dart` after construction.
    final mixer = GaplessQueueMixer(
      player: audioHandler.player,
      sourceBuilder: (track) => audioRepository.buildAudioSource(track),
      nextTrackResolver: (current) => routingService.resolveNext(
        baseMode: queueManager.baseMode,
        smartMode: queueManager.smartMode,
        current: current,
        recentIds: const <String>{},
        // Spec 2G Fix #5: the gapless mixer's 15-second
        // lookahead now consumes the QueueManager's
        // session-history snapshot (capped at 3 tracks,
        // newest-first) instead of a hard-coded empty list.
        // The artist-diversity term in Smart DJ and the
        // artist-decay matrix in Same Genre therefore see
        // real recent-pick context when the lookahead
        // fires mid-track.
        history: queueManager.sessionHistory,
      ),
      silenceResolver: (trackId) => localDatabase.getSilenceStartMs(trackId),
      durationStream: (_) => audioHandler.player.durationStream,
    );
    await mixer.attach();

    // Phase 4: Smart DJ DSP engine. Subscribes to the
    // mixer's `crossfadeReadyStream` and, on each event,
    // drives the dual-player equal-power crossfade, the
    // bar-quantized beat alignment, and the post-crossfade
    // tempo normalization ramp. The engine takes over
    // playback of the next track (playerB) and hands it back
    // to the audio handler / mixer at the end of the window.
    final dspEngine = DspCrossfadeEngine(
      mixer: mixer,
      audioHandler: audioHandler,
      db: localDatabase,
    );
    dspEngine.start();

    runApp(ZYPMusic(
      mixer: mixer,
      dspEngine: dspEngine,
      playlistRepository: playlistRepository,
      audioRepository: audioRepository,
      chartsRepository: chartsRepository,
      downloadProvider: downloadProvider,
      settingsProvider: settingsProvider,
      audioHandler: audioHandler,
      hybridCache: hybridCache,
      connectivityService: connectivityService,
      queueManager: queueManager,
      historyLedger: historyLedger,
      genreEnrichmentService: genreEnrichment,
      playlistDatabase: localDatabase,
      homeFeedProvider: homeFeedProvider,
      routingService: routingService,
      spotifyMetadata: spotifyMetadata,
      genreProximityGraph: genreProximityGraph,
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
