import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/video.dart';
import '../providers/playlist_provider.dart';
import '../providers/player_provider.dart';
import '../providers/download_provider.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PlaylistProvider>().loadCachedPlaylist(widget.playlist.id);
    });
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
              _buildHeader(context, playlist, tracks, playerProvider, downloadProvider, isDownloading),
              if (isDownloading) _buildDownloadProgress(downloadProvider, tracks),
              Expanded(
                child: tracks.isEmpty
                    ? const Center(child: Text('No tracks found'))
                    : ListView.builder(
                        itemCount: tracks.length,
                        itemBuilder: (context, index) {
                          final track = tracks[index];
                          return TrackTile(
                            track: track,
                            isCurrent: currentTrackId == track.id,
                            isDownloaded: downloadProvider.downloadedTrackIds.contains(track.id),
                            onTap: () {
                              playerProvider.setQueue(tracks, startIndex: index);
                              playerProvider.playTrack(track);
                            },
                          );
                        },
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
      PlayerProvider playerProvider, DownloadProvider downloadProvider, bool isDownloading) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
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
                Text(
                  widget.playlist.title,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${tracks.length} tracks',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if (isDownloading)
            IconButton(
              icon: const Icon(Icons.cancel, color: Colors.red),
              onPressed: () => downloadProvider.cancelDownload(),
            )
          else
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: tracks.isEmpty
                  ? null
                  : () => downloadProvider.downloadPlaylist(playlist),
            ),
          _PlayPauseButton(
            tracks: tracks,
            playerProvider: playerProvider,
          ),
          if (tracks.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.shuffle),
              onPressed: () {
                playerProvider.setQueue(tracks, startIndex: 0);
                playerProvider.playTrack(tracks.first);
              },
            ),
        ],
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final List<Track> tracks;
  final PlayerProvider playerProvider;

  const _PlayPauseButton({
    required this.tracks,
    required this.playerProvider,
  });

  bool get _isPlayingFromThisPlaylist {
    final current = playerProvider.currentTrack;
    return current != null && tracks.any((t) => t.id == current.id);
  }

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();

    if (!_isPlayingFromThisPlaylist) {
      return IconButton(
        icon: const Icon(Icons.play_arrow),
        onPressed: () {
          playerProvider.setQueue(tracks, startIndex: 0);
          playerProvider.playTrack(tracks.first);
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
