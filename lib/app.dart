import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'domain/repositories/audio_repository.dart';
import 'domain/repositories/playlist_repository.dart';
import 'presentation/providers/player_provider.dart';
import 'presentation/providers/playlist_provider.dart';
import 'presentation/providers/download_provider.dart';
import 'presentation/providers/settings_provider.dart';
import 'presentation/providers/miniplayer_visibility_provider.dart';
import 'presentation/providers/charts_provider.dart';
import 'data/repositories/charts_repository_impl.dart';
import 'service/audio_handler.dart';
import 'ui/layout/main_layout.dart';
import 'ui/widgets/bottom_player.dart';
import 'ui/widgets/global_background.dart';
import 'core/navigation/navigator_key.dart';

class MonochromeApp extends StatelessWidget {
  final PlaylistRepository playlistRepository;
  final AudioRepository audioRepository;
  final dynamic chartsRepository;
  final DownloadProvider downloadProvider;
  final SettingsProvider settingsProvider;
  final MusicAudioHandler audioHandler;

  const MonochromeApp({
    super.key,
    required this.playlistRepository,
    required this.audioRepository,
    required this.chartsRepository,
    required this.downloadProvider,
    required this.settingsProvider,
    required this.audioHandler,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider(
          create: (_) => PlaylistProvider(playlistRepository),
        ),
        ChangeNotifierProvider(
          create: (_) => ChartsProvider(chartsRepository),
        ),
        ChangeNotifierProvider(
          create: (_) => PlayerProvider(audioRepository, settingsProvider)..setAudioHandler(audioHandler),
        ),
        ChangeNotifierProvider.value(
          value: downloadProvider,
        ),
        ChangeNotifierProvider(
          create: (_) => MiniplayerVisibilityProvider(),
        ),
      ],
      child: MaterialApp(
        title: 'Monochrome',
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
