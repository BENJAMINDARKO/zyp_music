import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'domain/repositories/audio_repository.dart';
import 'domain/repositories/playlist_repository.dart';
import 'presentation/providers/player_provider.dart';
import 'presentation/providers/playlist_provider.dart';
import 'presentation/screens/home_screen.dart';

class YTMusixApp extends StatelessWidget {
  final PlaylistRepository playlistRepository;
  final AudioRepository audioRepository;

  const YTMusixApp({
    super.key,
    required this.playlistRepository,
    required this.audioRepository,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => PlaylistProvider(playlistRepository),
        ),
        ChangeNotifierProvider(
          create: (_) => PlayerProvider(audioRepository),
        ),
      ],
      child: MaterialApp(
        title: 'YTMusix',
        theme: AppTheme.darkTheme,
        debugShowCheckedModeBanner: false,
        home: const HomeScreen(),
      ),
    );
  }
}
