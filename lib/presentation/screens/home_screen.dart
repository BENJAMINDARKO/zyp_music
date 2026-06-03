import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/playlist_sort_mode.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/video.dart';
import '../providers/playlist_provider.dart';
import '../providers/player_provider.dart';
import '../providers/download_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/pixel_logo.dart';
import '../widgets/now_playing_card.dart';
import '../widgets/track_action_sheet.dart';
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
  static const _tabs = ['Recent', 'New', 'Trend', 'Podcasts', 'Favourites'];
  int _homeTab = 0;

  String? get _activeFeedKey {
    if (_homeTab == 1) return 'new';
    if (_homeTab == 2) return 'trend';
    if (_homeTab == 3) return 'podcasts';
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PlaylistProvider>().loadSavedPlaylists();
      context.read<PlaylistProvider>().loadFavoriteIds();
      context.read<PlayerProvider>().loadRecentlyPlayed();
    });
  }

  void _selectHomeTab(int index) {
    setState(() => _homeTab = index);
    final key = _activeFeedKey;
    if (key != null) {
      context.read<PlaylistProvider>().loadHomeFeed(key);
    }
  }

  Future<void> _showLinkDialog(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste YouTube link'),
        content: TextField(
          autofocus: true,
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Video, playlist, or mix link',
            prefixIcon: Icon(Icons.link),
          ),
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    final text = result?.trim();
    if (text == null || text.isEmpty) return;
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Loading $text...'),
        duration: const Duration(seconds: 2),
      ),
    );

    final provider = context.read<PlaylistProvider>();
    final playlist = await provider.fetchFromUrl(text);
    if (!context.mounted) return;

    if (playlist != null) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PlaylistScreen(playlist: playlist)),
      );
    } else {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Failed to load link'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            _buildErrorBanner(),
            _buildNowPlaying(context),
            Expanded(child: _buildContent(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          const PixelLogo(size: 40),
          const Spacer(),
          _roundIconButton(
            icon: Icons.search,
            tooltip: 'Search YouTube',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          const SizedBox(width: 8),
          _roundIconButton(
            icon: Icons.link_rounded,
            tooltip: 'Paste YouTube link',
            onPressed: () => _showLinkDialog(context),
          ),
          const SizedBox(width: 8),
          Consumer<PlaylistProvider>(
            builder: (context, provider, _) => _roundIconButton(
              icon: Icons.tune_rounded,
              tooltip: 'Sort playlists',
              onPressed: () => _showSortSheet(context, provider),
            ),
          ),
          const SizedBox(width: 8),
          _roundIconButton(
            icon: Icons.settings_rounded,
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }

  void _showSortSheet(BuildContext context, PlaylistProvider provider) {
    final options = [
      (PlaylistSortMode.dateAdded, 'Date added', Icons.schedule_rounded),
      (PlaylistSortMode.title, 'Title', Icons.sort_by_alpha_rounded),
      (PlaylistSortMode.trackCount, 'Track count', Icons.queue_music_rounded),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: const Color(0xFF171717),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withAlpha(14)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sort playlists',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              ...options.map((option) {
                final selected = provider.sortMode == option.$1;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white.withAlpha(12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      option.$3,
                      color: selected ? Colors.black : Colors.white,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    option.$2,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check_circle_rounded)
                      : null,
                  onTap: () {
                    provider.setSortMode(option.$1);
                    Navigator.pop(ctx);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 40,
        height: 40,
        child: IconButton(
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFF191919),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: Icon(icon, size: 20),
          onPressed: onPressed,
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
          onPrevious: player.previous,
          onNext: player.currentIndex + 1 < player.queue.length
              ? player.next
              : null,
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
        final feedKey = _activeFeedKey;
        final feedTracks = feedKey == null
            ? const <Track>[]
            : provider.homeFeed(feedKey);
        final isFeedLoading =
            feedKey != null && provider.isHomeFeedLoading(feedKey);

        if (provider.isLoading && feedKey == null) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.playlists.isEmpty &&
            provider.favoriteIds.isEmpty &&
            feedKey == null) {
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
          onRefresh: () {
            final key = _activeFeedKey;
            if (key != null) {
              return provider.loadHomeFeed(key, force: true);
            }
            return provider.loadSavedPlaylists();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              const Text(
                'Browse',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 18),
              _buildCategoryTabs(),
              const SizedBox(height: 22),
              if (feedKey != null)
                _buildTrackShelf(
                  context,
                  feedTracks,
                  isFeedLoading,
                  playerProvider,
                  feedKey,
                )
              else
                _buildPlaylistShelf(
                  context,
                  _filteredPlaylists(provider),
                  playerProvider,
                  downloadProvider,
                ),
              const SizedBox(height: 28),
              _buildTopHits(
                context,
                _filteredPlaylists(provider),
                feedTracks,
                playerProvider,
                _homeTab == 4 ? provider.favoriteIds : null,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryTabs() {
    return SizedBox(
      height: 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 18),
        itemBuilder: (context, index) {
          final active = index == _homeTab;
          return GestureDetector(
            onTap: () => _selectHomeTab(index),
            child: Center(
              child: Text(
                _tabs[index],
                style: TextStyle(
                  color: active ? Colors.white : Colors.white38,
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTrackShelf(
    BuildContext context,
    List<Track> tracks,
    bool isLoading,
    PlayerProvider playerProvider,
    String feedKey,
  ) {
    if (isLoading && tracks.isEmpty) {
      return const SizedBox(
        height: 184,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (tracks.isEmpty) {
      return _EmptyShelf(tabLabel: _tabs[_homeTab]);
    }
    return SizedBox(
      height: 184,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        itemCount: tracks.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final track = tracks[index];
          final isCurrent = playerProvider.currentTrack?.id == track.id;
          return SizedBox(
            width: 138,
            child: _HomeTrackCard(
              track: track,
              isCurrent: isCurrent,
              isPlaying: isCurrent && playerProvider.isPlaying,
              onTap: () {
                final quality = context.read<SettingsProvider>().audioQuality;
                playerProvider.setQueue(
                  tracks,
                  startIndex: index,
                  playlistId: '__feed_$feedKey',
                );
                playerProvider.playTrack(track, quality: quality);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PlayerScreen()),
                );
              },
              onPlay: () {
                if (isCurrent) {
                  playerProvider.togglePlayPause();
                  return;
                }
                final quality = context.read<SettingsProvider>().audioQuality;
                playerProvider.setQueue(
                  tracks,
                  startIndex: index,
                  playlistId: '__feed_$feedKey',
                );
                playerProvider.playTrack(track, quality: quality);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlaylistShelf(
    BuildContext context,
    List<Playlist> playlists,
    PlayerProvider playerProvider,
    DownloadProvider downloadProvider,
  ) {
    if (playlists.isEmpty) {
      return _EmptyShelf(tabLabel: _tabs[_homeTab]);
    }
    return SizedBox(
      height: 184,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        itemCount: playlists.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final playlist = playlists[index];
          final isCurrent = playerProvider.currentPlaylistId == playlist.id;
          final isDownloading = downloadProvider.isDownloadingPlaylist(
            playlist.id,
          );
          final isDownloaded = downloadProvider.isPlaylistFullyDownloaded(
            playlist.id,
          );
          return SizedBox(
            width: 138,
            child: _BrowsePlaylistCard(
              playlist: playlist,
              isCurrentPlaylist: isCurrent,
              isPlaying: playerProvider.isPlaying,
              isDownloaded: isDownloaded,
              isDownloading: isDownloading,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlaylistScreen(playlist: playlist),
                ),
              ),
              onPlay: () async {
                if (isCurrent) {
                  playerProvider.togglePlayPause();
                  return;
                }
                final provider = context.read<PlaylistProvider>();
                final cachedTracks = await provider.getCachedTracks(
                  playlist.id,
                );
                if (cachedTracks != null &&
                    cachedTracks.isNotEmpty &&
                    context.mounted) {
                  final settings = context.read<SettingsProvider>();
                  playerProvider.setQueue(
                    cachedTracks,
                    startIndex: 0,
                    playlistId: playlist.id,
                  );
                  await playerProvider.playTrack(
                    cachedTracks.first,
                    quality: settings.audioQuality,
                  );
                } else if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Open the playlist first to cache tracks'),
                    ),
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
                    const SnackBar(
                      content: Text('Playlist is already downloaded'),
                    ),
                  );
                  return;
                }
                final provider = context.read<PlaylistProvider>();
                final cachedTracks = await provider.getCachedTracks(
                  playlist.id,
                );
                if (cachedTracks != null &&
                    cachedTracks.isNotEmpty &&
                    context.mounted) {
                  final fullPlaylist = Playlist(
                    id: playlist.id,
                    title: playlist.title,
                    author: playlist.author,
                    thumbnailUrl: playlist.thumbnailUrl,
                    videoCount: cachedTracks.length,
                    tracks: cachedTracks,
                  );
                  final settings = context.read<SettingsProvider>();
                  downloadProvider.downloadPlaylist(
                    fullPlaylist,
                    quality: settings.audioQuality.name,
                  );
                } else if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Open the playlist first to load tracks, then download',
                      ),
                    ),
                  );
                }
              },
              onDelete: () =>
                  context.read<PlaylistProvider>().deletePlaylist(playlist.id),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopHits(
    BuildContext context,
    List<Playlist> playlists,
    List<Track> feedTracks,
    PlayerProvider playerProvider,
    Set<String>? favoriteIds,
  ) {
    final tracks = <String, Track>{};
    if (feedTracks.isNotEmpty) {
      for (final track in feedTracks) {
        tracks[track.id] = track;
      }
    } else {
      for (final track in playerProvider.recentlyPlayed) {
        if (favoriteIds == null || favoriteIds.contains(track.id)) {
          tracks[track.id] = track;
        }
      }
      for (final playlist in playlists) {
        for (final track in playlist.tracks) {
          if (favoriteIds == null || favoriteIds.contains(track.id)) {
            tracks[track.id] = track;
          }
        }
      }
    }
    final topTracks = tracks.values.take(6).toList();
    final title = switch (_homeTab) {
      1 => 'New from YouTube',
      2 => 'Trending on YouTube',
      3 => 'Ghana podcasts',
      4 => 'Favourite tracks',
      _ => 'Recent plays',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        if (topTracks.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF171717),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withAlpha(14)),
            ),
            child: Row(
              children: [
                const Icon(Icons.music_note_rounded, color: Colors.white54),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _homeTab == 4
                        ? 'Star tracks to fill your favourites chart.'
                        : _activeFeedKey != null
                        ? 'Pull to refresh YouTube results.'
                        : 'Open a playlist or play a track to fill your chart.',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            ),
          )
        else
          ...topTracks.indexed.map((item) {
            final index = item.$1;
            final track = item.$2;
            return _TopHitTile(
              rank: index + 1,
              track: track,
              onMore: () => showTrackActionSheet(
                context,
                track: track,
                queue: topTracks,
                index: index,
                playlistId: _activeFeedKey == null
                    ? null
                    : '__feed_${_activeFeedKey!}',
              ),
              onTap: () {
                final settings = context.read<SettingsProvider>();
                playerProvider.setQueue(
                  topTracks,
                  startIndex: index,
                  playlistId: _activeFeedKey == null
                      ? null
                      : '__feed_${_activeFeedKey!}',
                );
                playerProvider.playTrack(track, quality: settings.audioQuality);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PlayerScreen()),
                );
              },
            );
          }),
      ],
    );
  }

  List<Playlist> _filteredPlaylists(PlaylistProvider provider) {
    final playlists = List<Playlist>.from(provider.playlists);
    switch (_homeTab) {
      case 1:
      case 2:
      case 3:
        return playlists;
      case 4:
        final favoriteIds = provider.favoriteIds;
        return playlists
            .where(
              (playlist) => playlist.tracks.any(
                (track) => favoriteIds.contains(track.id),
              ),
            )
            .map(
              (playlist) => Playlist(
                id: playlist.id,
                title: playlist.title,
                description: playlist.description,
                thumbnailUrl: playlist.thumbnailUrl,
                author: playlist.author,
                videoCount: playlist.tracks
                    .where((track) => favoriteIds.contains(track.id))
                    .length,
                tracks: playlist.tracks
                    .where((track) => favoriteIds.contains(track.id))
                    .toList(),
              ),
            )
            .toList();
      default:
        return playlists;
    }
  }
}

class _EmptyShelf extends StatelessWidget {
  final String tabLabel;

  const _EmptyShelf({required this.tabLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 144,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withAlpha(14)),
      ),
      child: Row(
        children: [
          const Icon(Icons.library_music_rounded, color: Colors.white54),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No $tabLabel items yet.',
              style: const TextStyle(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeTrackCard extends StatelessWidget {
  final Track track;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onPlay;

  const _HomeTrackCard({
    required this.track,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 138,
                  height: 138,
                  child: Image.network(
                    track.thumbnailUrl ?? '',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: const Color(0xFF252525),
                      child: const Icon(
                        Icons.music_note_rounded,
                        color: Colors.white38,
                        size: 42,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: _MiniAction(
                  icon: isCurrent && isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  onPressed: onPlay,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: isCurrent ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            track.author ?? 'YouTube',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _BrowsePlaylistCard extends StatelessWidget {
  final Playlist playlist;
  final bool isCurrentPlaylist;
  final bool isPlaying;
  final bool isDownloaded;
  final bool isDownloading;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  const _BrowsePlaylistCard({
    required this.playlist,
    required this.isCurrentPlaylist,
    required this.isPlaying,
    required this.isDownloaded,
    required this.isDownloading,
    required this.onTap,
    required this.onPlay,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 138,
                  height: 138,
                  child: Image.network(
                    playlist.thumbnailUrl ?? '',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: const Color(0xFF252525),
                      child: const Icon(
                        Icons.album_rounded,
                        color: Colors.white38,
                        size: 42,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Row(
                  children: [
                    _MiniAction(
                      icon: isDownloaded
                          ? Icons.offline_pin_rounded
                          : isDownloading
                          ? Icons.downloading_rounded
                          : Icons.download_rounded,
                      onPressed: onDownload,
                    ),
                    const SizedBox(width: 6),
                    _MiniAction(
                      icon: isCurrentPlaylist && isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      onPressed: onPlay,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            playlist.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 3),
          Text(
            playlist.author ?? '${playlist.videoCount} tracks',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _MiniAction({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton(
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: Colors.black.withAlpha(180),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: Icon(icon, size: 18),
        onPressed: onPressed,
      ),
    );
  }
}

class _TopHitTile extends StatelessWidget {
  final int rank;
  final Track track;
  final VoidCallback onTap;
  final VoidCallback onMore;

  const _TopHitTile({
    required this.rank,
    required this.track,
    required this.onTap,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 8,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          width: 54,
          height: 54,
          child: Image.network(
            track.thumbnailUrl ?? '',
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              color: const Color(0xFF252525),
              child: const Icon(
                Icons.music_note_rounded,
                color: Colors.white38,
              ),
            ),
          ),
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      subtitle: Text(
        '#$rank  ${track.author ?? ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white54, fontSize: 11),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.more_vert_rounded, color: Colors.white38),
        onPressed: onMore,
      ),
      onTap: onTap,
    );
  }
}
