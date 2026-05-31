import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/playlist_sort_mode.dart';
import '../../domain/entities/playlist.dart';
import '../providers/playlist_provider.dart';
import '../providers/player_provider.dart';
import '../providers/download_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/playlist_card.dart';
import '../widgets/pixel_logo.dart';
import '../widgets/now_playing_card.dart';
import 'playlist_screen.dart';
import 'player_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PlaylistProvider>().loadSavedPlaylists();
      context.read<PlayerProvider>().loadRecentlyPlayed();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LogoWithHeadset(size: 40),
            const SizedBox(width: 10),
            const Text(AppConstants.appName, style: TextStyle(fontSize: 20)),
          ],
        ),
        actions: [
          Consumer<PlaylistProvider>(
            builder: (context, provider, _) => PopupMenuButton<PlaylistSortMode>(
              onSelected: provider.setSortMode,
              initialValue: provider.sortMode,
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: PlaylistSortMode.dateAdded,
                  child: Row(
                    children: [
                      if (provider.sortMode == PlaylistSortMode.dateAdded)
                        const Icon(Icons.check, size: 18),
                      const SizedBox(width: 8),
                      const Text('Date added'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: PlaylistSortMode.title,
                  child: Row(
                    children: [
                      if (provider.sortMode == PlaylistSortMode.title)
                        const Icon(Icons.check, size: 18),
                      const SizedBox(width: 8),
                      const Text('Title'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: PlaylistSortMode.trackCount,
                  child: Row(
                    children: [
                      if (provider.sortMode == PlaylistSortMode.trackCount)
                        const Icon(Icons.check, size: 18),
                      const SizedBox(width: 8),
                      const Text('Track count'),
                    ],
                  ),
                ),
              ],
              icon: const Icon(Icons.sort),
              tooltip: 'Sort playlists',
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search YouTube',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SettingsScreen(),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildErrorBanner(),
          _buildNowPlaying(context),
          _buildRecentlyPlayed(context),
          Expanded(child: _buildContent(context)),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Consumer<PlaylistProvider>(
      builder: (context, provider, _) {
        if (provider.error == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withAlpha(100)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    provider.error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => provider.clearError(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNowPlaying(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, player, _) {
        if (player.currentTrack == null) return const SizedBox.shrink();
        return NowPlayingCard(
          track: player.currentTrack!,
          isPlaying: player.isPlaying,
          isLoading: player.isLoading,
          position: player.position,
          duration: player.duration,
          onPlayPause: player.togglePlayPause,
          onPrevious: player.currentIndex > 0 ? player.previous : null,
          onNext: player.currentIndex + 1 < player.queue.length ? player.next : null,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PlayerScreen()),
          ),
        );
      },
    );
  }

  Widget _buildRecentlyPlayed(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, player, _) {
        final recent = player.recentlyPlayed;
        if (recent.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.history, size: 18, color: Colors.grey[400]),
                  const SizedBox(width: 6),
                  Text('Recently played', style: TextStyle(color: Colors.grey[400], fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            SizedBox(
              height: 72,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: recent.length,
                itemBuilder: (context, index) {
                  final track = recent[index];
                  return GestureDetector(
                    onTap: () {
                      player.setQueue([track], startIndex: 0);
                      final settings = context.read<SettingsProvider>();
                      player.playTrack(track, quality: settings.audioQuality);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen()));
                    },
                    child: Container(
                      width: 180,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.network(
                              track.thumbnailUrl ?? '',
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                width: 48, height: 48,
                                color: Colors.grey[800],
                                child: const Icon(Icons.music_note, size: 24),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
          ],
        );
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    return Consumer3<PlaylistProvider, PlayerProvider, DownloadProvider>(
      builder: (context, provider, playerProvider, downloadProvider, _) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.playlists.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
                  children: [
                const LogoWithHeadset(size: 120),
                const SizedBox(height: 16),
                Text(
                  'No playlists yet',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[400],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Search YouTube or paste a link to get started',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => provider.loadSavedPlaylists(),
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: provider.playlists.length,
            itemBuilder: (context, index) {
              final playlist = provider.playlists[index];
              final isCurrentPlaylist = playerProvider.currentPlaylistId == playlist.id;
              final isDownloading = downloadProvider.isDownloadingPlaylist(playlist.id);
              final isDownloaded = downloadProvider.isPlaylistFullyDownloaded(playlist.id);
              final dlProgress = downloadProvider.getPlaylistDownloadProgress(playlist.id);

              return PlaylistCard(
                playlist: playlist,
                isCurrentPlaylist: isCurrentPlaylist,
                isPlaying: playerProvider.isPlaying,
                isDownloaded: isDownloaded,
                isDownloading: isDownloading,
                downloadProgress: dlProgress,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlaylistScreen(playlist: playlist),
                    ),
                  );
                },
                onPlay: () async {
                  if (isCurrentPlaylist) {
                    playerProvider.togglePlayPause();
                    return;
                  }
                  final cachedTracks = await provider.getCachedTracks(playlist.id);
                  if (cachedTracks != null && cachedTracks.isNotEmpty && context.mounted) {
                    playerProvider.setQueue(cachedTracks, startIndex: 0, playlistId: playlist.id);
                    final settings = context.read<SettingsProvider>();
                    await playerProvider.playTrack(cachedTracks.first, quality: settings.audioQuality);
                  } else if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Open the playlist first to cache tracks')),
                    );
                  }
                },
                onDownload: () async {
                  if (isDownloading) {
                    downloadProvider.cancelDownload();
                    return;
                  }
                  if (isDownloaded) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Playlist is already downloaded')),
                    );
                    return;
                  }
                  final cachedTracks = await provider.getCachedTracks(playlist.id);
                  if (cachedTracks != null && cachedTracks.isNotEmpty && context.mounted) {
                    final fullPlaylist = Playlist(
                      id: playlist.id,
                      title: playlist.title,
                      author: playlist.author,
                      thumbnailUrl: playlist.thumbnailUrl,
                      videoCount: cachedTracks.length,
                      tracks: cachedTracks,
                    );
                    final settings = context.read<SettingsProvider>();
                    downloadProvider.downloadPlaylist(fullPlaylist, quality: settings.audioQuality.name);
                  } else if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Open the playlist first to load tracks, then download')),
                    );
                  }
                },
                onDelete: () => provider.deletePlaylist(playlist.id),
              );
            },
          ),
        );
      },
    );
  }

}
