import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'core/theme/app_theme.dart';
import 'core/audio/dsp_crossfade_engine.dart';
import 'domain/repositories/audio_repository.dart';
import 'domain/repositories/playlist_repository.dart';
import 'presentation/providers/player_provider.dart';
import 'presentation/providers/playlist_provider.dart';
import 'presentation/providers/download_provider.dart';
import 'presentation/providers/home_feed_provider.dart';
import 'presentation/providers/settings_provider.dart';
import 'presentation/providers/miniplayer_visibility_provider.dart';
import 'presentation/providers/charts_provider.dart';
import 'data/repositories/charts_repository_impl.dart';
import 'ui/layout/main_layout.dart';
import 'ui/widgets/bottom_player.dart';
import 'ui/widgets/global_background.dart';
import 'core/navigation/navigator_key.dart';
import 'core/services/auto_dj_routing_service.dart';
import 'core/services/hybrid_cache_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/dj_history_ledger.dart';
import 'core/services/queue_manager.dart';
import 'core/services/genre_enrichment_service.dart';
import 'core/services/spotify_metadata_service.dart';
import 'data/datasources/local/playlist_database.dart';
import 'core/audio/gapless_queue_mixer.dart';

class ZYPMusic extends StatelessWidget {
  final PlaylistRepository playlistRepository;
  final AudioRepository audioRepository;
  final dynamic chartsRepository;
  final DownloadProvider downloadProvider;
  final SettingsProvider settingsProvider;
  final AudioHandler audioHandler;
  final HybridCacheService hybridCache;
  final ConnectivityService connectivityService;
  final QueueManager queueManager;
  final DJHistoryLedger historyLedger;
  final GaplessQueueMixer mixer;
  final DspCrossfadeEngine dspEngine;

  /// Smart-DJ bootstrap-fusion wiring: the routing service
  /// is built in `main.dart` and handed down here so the
  /// [PlayerProvider] can chain `setRoutingService(...)`
  /// after construction. Nullable so unit tests that
  /// exercise [ZYPMusic] in isolation can run without
  /// the AI DJ engine.
  final AutoDjRoutingService? routingService;

  /// Phase 6: MusicBrainz enrichment service. Built in
  /// `main.dart` and bound to [PlayerProvider] via the
  /// `setGenreEnrichmentService` setter so every successful
  /// track transition fires background enrichment.
  final GenreEnrichmentService genreEnrichmentService;
  final SpotifyMetadataService spotifyMetadata;

  /// Spec 2H: the [PlaylistDatabase] singleton is exposed
  /// to the widget tree so the Shuffle Library filter
  /// sub-menu can query `getGenreClusterCounts()` on open.
  final PlaylistDatabase playlistDatabase;
  final HomeFeedProvider homeFeedProvider;

  const ZYPMusic({
    super.key,
    required this.playlistRepository,
    required this.audioRepository,
    required this.chartsRepository,
    required this.downloadProvider,
    required this.settingsProvider,
    required this.audioHandler,
    required this.hybridCache,
    required this.connectivityService,
    required this.queueManager,
    required this.historyLedger,
    required this.mixer,
    required this.dspEngine,
    required this.genreEnrichmentService,
    required this.spotifyMetadata,
    required this.playlistDatabase,
    required this.homeFeedProvider,
    this.routingService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<PlaylistDatabase>.value(value: playlistDatabase),
        Provider<AudioRepository>.value(value: audioRepository),
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: hybridCache),
        ChangeNotifierProvider.value(value: connectivityService),
        ChangeNotifierProvider.value(value: queueManager),
        ChangeNotifierProvider(
          create: (_) {
            // Spec 2G Fix #6: wire the routing service into
            // the PlaylistProvider so debounced post-favorite
            // refreshes can reach [AutoDjRoutingService.refreshLikedSongsCache].
            final provider = PlaylistProvider(playlistRepository);
            if (routingService != null) {
              provider.setRoutingService(routingService!);
            }
            return provider;
          },
        ),
        ChangeNotifierProvider(
          create: (_) => ChartsProvider(chartsRepository),
        ),
        ChangeNotifierProvider(
          create: (_) {
            final provider = PlayerProvider(
              audioRepository,
              settingsProvider,
              hybridCache,
              queueManager: queueManager,
            )
              ..setAudioHandler(audioHandler)
              ..setHistoryLedger(historyLedger)
              ..setMixer(mixer)
              ..setDspEngine(dspEngine)
              ..setChartsRepository(chartsRepository)
              ..setConnectivityService(connectivityService)
              ..setGenreEnrichmentService(genreEnrichmentService)
              ..setSpotifyMetadataService(spotifyMetadata);
            // Smart-DJ bootstrap-fusion: bind the routing
            // service and the playlist repository AFTER the
            // base wiring so the bootstrap method's
            // ordering guard fires only after both
            // dependencies are in place. The chain-call
            // pattern is split out here because we need
            // explicit null handling on the routing service
            // (it's optional in [ZYPMusic]).
            if (routingService != null) {
              provider.setRoutingService(routingService!);
            }
            provider.setPlaylistRepository(playlistRepository);
            return provider;
          },
        ),
        ChangeNotifierProvider.value(
          value: downloadProvider,
        ),
        ChangeNotifierProvider.value(
          value: homeFeedProvider,
        ),
        ChangeNotifierProvider(
          create: (_) => MiniplayerVisibilityProvider(),
        ),
      ],
      child: MaterialApp(
        title: 'ZYPMusic',
        theme: AppTheme.darkTheme,
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        builder: (context, child) {
          return Stack(
            children: [
              const GlobalBackground(),
              if (child != null) child,
            ],
          );
        },
        home: const MainLayout(),
      ),
    );
  }
}
