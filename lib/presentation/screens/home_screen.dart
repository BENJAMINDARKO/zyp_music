import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/playlist.dart';
import '../providers/playlist_provider.dart';
import '../providers/player_provider.dart';
import '../providers/download_provider.dart';
import '../widgets/playlist_card.dart';
import '../widgets/pixel_logo.dart';
import '../widgets/now_playing_card.dart';
import 'playlist_screen.dart';
import 'player_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _controller = TextEditingController();
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PlaylistProvider>().loadSavedPlaylists();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LogoWithHeadset(size: 32),
            const SizedBox(width: 8),
            const Text(AppConstants.appName),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SettingsScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showInfo(context),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(context),
          _buildErrorBanner(),
          _buildNowPlaying(context),
          Expanded(child: _buildContent(context)),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: _showSearch
            ? TextField(
                autofocus: true,
                controller: _controller,
                decoration: InputDecoration(
                  hintText: 'Paste a YouTube link (video, playlist, or mix)',
                  prefixIcon: const Icon(Icons.link),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_controller.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () {
                            _controller.clear();
                            setState(() {});
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () => _loadPlaylist(context),
                      ),
                    ],
                  ),
                ),
                onSubmitted: (_) {
                  _loadPlaylist(context);
                  setState(() => _showSearch = false);
                },
                onChanged: (_) => setState(() {}),
              )
            : Center(
                child: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => setState(() => _showSearch = true),
                  tooltip: 'Add YouTube link',
                ),
              ),
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
                const LogoWithHeadset(size: 100),
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
                  'Paste a YouTube playlist link above to get started',
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
                    await playerProvider.playTrack(cachedTracks.first);
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
                    downloadProvider.downloadPlaylist(fullPlaylist);
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

  Future<void> _loadPlaylist(BuildContext context) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Loading $text...'), duration: const Duration(seconds: 2)),
    );
    final provider = context.read<PlaylistProvider>();
    final playlist = await provider.fetchFromUrl(text);
    if (playlist != null && context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlaylistScreen(playlist: playlist),
        ),
      );
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Failed to load'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showInfo(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: AppConstants.appName,
      applicationVersion: '1.0.0',
      applicationLegalese: 'For personal, educational use only.\nNot affiliated with YouTube.',
    );
  }
}
