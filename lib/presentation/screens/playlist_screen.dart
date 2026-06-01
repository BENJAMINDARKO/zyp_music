import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/video.dart';
import '../providers/playlist_provider.dart';
import '../providers/player_provider.dart';
import '../providers/download_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/player_bar.dart';
import '../widgets/video_tile.dart';
import 'player_screen.dart';

class PlaylistScreen extends StatefulWidget {
  final Playlist playlist;
  final bool autoDownload;

  const PlaylistScreen({super.key, required this.playlist, this.autoDownload = false});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  bool _autoDownloadStarted = false;
  VoidCallback? _trackChangedHandler;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final player = context.read<PlayerProvider>();
      _trackChangedHandler = () {
        if (!mounted) return;
        if (player.currentPlaylistId != widget.playlist.id) return;
        final dl = context.read<DownloadProvider>();
        final settings = context.read<SettingsProvider>();
        dl.preDownloadUpcoming(player.queue, player.currentIndex, widget.playlist.id,
            prebufferCount: settings.prebufferCount);
      };
      player.addTrackChangedListener(_trackChangedHandler!);
      context.read<PlaylistProvider>().loadCachedPlaylist(widget.playlist.id);
    });
  }

  @override
  void dispose() {
    if (_trackChangedHandler != null) {
      try {
        context.read<PlayerProvider>().removeTrackChangedListener(_trackChangedHandler!);
      } catch (_) {}
      _trackChangedHandler = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlist.title),
      ),
      body: Consumer3<PlaylistProvider, PlayerProvider, DownloadProvider>(
        builder: (context, playlistProvider, playerProvider, downloadProvider, _) {
          final playlist = playlistProvider.currentPlaylist?.id == widget.playlist.id
              ? playlistProvider.currentPlaylist!
              : widget.playlist;
          final tracks = playlist.tracks;
          final currentTrackId = playerProvider.currentTrack?.id;
          final isDownloading = downloadProvider.isDownloadingPlaylist(widget.playlist.id);
          final favoriteIds = playlistProvider.favoriteIds;

          if (widget.autoDownload && !_autoDownloadStarted && tracks.isNotEmpty && !isDownloading) {
            _autoDownloadStarted = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                context.read<DownloadProvider>().downloadPlaylist(playlist);
              }
            });
          }

          return Column(
            children: [
              _buildHeader(context, playlist, tracks, playerProvider, downloadProvider, isDownloading, playlistProvider),
              if (isDownloading) _buildDownloadProgress(downloadProvider, tracks),
              Expanded(
                child: tracks.isEmpty
                    ? const Center(child: Text('No tracks found'))
                    : RefreshIndicator(
                        onRefresh: () async {
                          final provider = context.read<PlaylistProvider>();
                          await provider.fetchPlaylist(widget.playlist.id);
                        },
                        child: ReorderableListView.builder(
                          onReorderItem: (oldIndex, newIndex) {
                            final updatedTracks = List<Track>.from(tracks);
                            final item = updatedTracks.removeAt(oldIndex);
                            updatedTracks.insert(newIndex, item);
                            playerProvider.setQueue(updatedTracks, startIndex: playerProvider.currentIndex, playlistId: widget.playlist.id);
                            final trackIds = updatedTracks.map((t) => t.id).toList();
                            playlistProvider.reorderTracks(widget.playlist.id, trackIds);
                          },
                          itemCount: tracks.length,
                          itemBuilder: (context, index) {
                            final track = tracks[index];
                            return Dismissible(
                              key: ValueKey('${track.id}-${widget.playlist.id}'),
                              direction: DismissDirection.endToStart,
                              confirmDismiss: (_) async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Remove track'),
                                    content: Text('Remove "${track.title}" from this playlist?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Remove', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true) {
                                  playlistProvider.removeTrackFromPlaylist(widget.playlist.id, track.id);
                                }
                                return false;
                              },
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 24),
                                color: Colors.red,
                                child: const Icon(Icons.delete, color: Colors.white),
                              ),
                              child: TrackTile(
                                track: track,
                                isCurrent: currentTrackId == track.id,
                                isDownloaded: downloadProvider.downloadedTrackIds.contains(track.id),
                                isDownloading: downloadProvider.activeDownloads.containsKey(track.id),
                                isFavorite: favoriteIds.contains(track.id),
                                onDownload: downloadProvider.downloadedTrackIds.contains(track.id)
                                    ? null
                                    : () => downloadProvider.downloadTrack(track, widget.playlist.id),
                                onToggleFavorite: () => playlistProvider.toggleFavorite(track),
                                onTap: () {
                                  final quality = context.read<SettingsProvider>().audioQuality;
                                  playerProvider.setQueue(tracks, startIndex: index, playlistId: widget.playlist.id);
                                  playerProvider.playTrack(track, quality: quality);
                                },
                              ),
                            );
                          },
                        ),
                      ),
              ),
              PlayerBar(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PlayerScreen()),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDownloadProgress(DownloadProvider downloadProvider, List<Track> tracks) {
    final completed = tracks.where((t) => downloadProvider.downloadedTrackIds.contains(t.id)).length;
    final activeProgress = downloadProvider.activeDownloads.values.isNotEmpty
        ? downloadProvider.activeDownloads.values.last
        : null;
    return Column(
      children: [
        if (activeProgress != null && activeProgress.totalBytes > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Downloading: ${activeProgress.trackTitle}',
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${(activeProgress.fraction * 100).toInt()}%',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: LinearProgressIndicator(
            value: tracks.isEmpty ? 0 : completed / tracks.length,
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, Playlist playlist, List<Track> tracks,
      PlayerProvider playerProvider, DownloadProvider downloadProvider, bool isDownloading,
      PlaylistProvider playlistProvider) {
    final isFullyDownloaded = tracks.isNotEmpty &&
        tracks.every((t) => downloadProvider.downloadedTrackIds.contains(t.id));
    final anyDownloaded = tracks.any((t) => downloadProvider.downloadedTrackIds.contains(t.id));
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  widget.playlist.thumbnailUrl ?? '',
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  errorBuilder: (_, e, s) => Container(
                    width: 80,
                    height: 80,
                    color: Colors.grey[800],
                    child: const Icon(Icons.music_note),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.playlist.title,
                            style: Theme.of(context).textTheme.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Rename',
                          onPressed: () => _showRenameDialog(context, widget.playlist.id, widget.playlist.title, playlistProvider),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${tracks.length} tracks',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              if (anyDownloaded)
                IconButton(
                  icon: const Icon(Icons.delete_sweep, size: 20),
                  tooltip: 'Clear downloads',
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Clear downloaded tracks?'),
                        content: const Text('Remove all downloaded files for this playlist?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                    if (confirmed == true && context.mounted) {
                      await downloadProvider.deleteDownloadedPlaylist(widget.playlist.id);
                    }
                  },
                ),
              if (isDownloading)
                IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.red),
                  onPressed: () => downloadProvider.cancelDownload(),
                )
              else
                IconButton(
                  icon: Icon(
                    Icons.download,
                    color: isFullyDownloaded ? Colors.green : null,
                  ),
                  onPressed: tracks.isEmpty || isFullyDownloaded
                      ? null
                      : () => downloadProvider.downloadPlaylist(playlist),
                ),
              _PlayPauseButton(
                tracks: tracks,
                playerProvider: playerProvider,
                playlistId: widget.playlist.id,
              ),
              if (tracks.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.shuffle),
                  onPressed: () {
                    final quality = context.read<SettingsProvider>().audioQuality;
                    playerProvider.setQueue(tracks, startIndex: 0, playlistId: widget.playlist.id);
                    playerProvider.toggleShuffle();
                    playerProvider.playTrack(tracks.first, quality: quality);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, String playlistId, String currentTitle, PlaylistProvider provider) {
    final controller = TextEditingController(text: currentTitle);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            prefixIcon: Icon(Icons.edit),
          ),
          onSubmitted: (value) {
            final trimmed = value.trim();
            if (trimmed.isNotEmpty && trimmed != currentTitle) {
              provider.renamePlaylist(playlistId, trimmed);
            }
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isNotEmpty && trimmed != currentTitle) {
                provider.renamePlaylist(playlistId, trimmed);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final List<Track> tracks;
  final PlayerProvider playerProvider;
  final String playlistId;

  const _PlayPauseButton({
    required this.tracks,
    required this.playerProvider,
    required this.playlistId,
  });

  bool get _isPlayingFromThisPlaylist {
    return playerProvider.currentPlaylistId == playlistId;
  }

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();

    if (!_isPlayingFromThisPlaylist) {
      return IconButton(
        icon: const Icon(Icons.play_arrow),
        onPressed: () {
          final quality = context.read<SettingsProvider>().audioQuality;
        playerProvider.setQueue(tracks, startIndex: 0, playlistId: playlistId);
        playerProvider.playTrack(tracks.first, quality: quality);
        },
      );
    }

    return IconButton(
      icon: Icon(
        playerProvider.isPlaying ? Icons.pause : Icons.play_arrow,
      ),
      onPressed: () => playerProvider.togglePlayPause(),
    );
  }
}
