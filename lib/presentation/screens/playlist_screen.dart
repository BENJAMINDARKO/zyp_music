import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/video.dart';
import '../providers/playlist_provider.dart';
import '../providers/player_provider.dart';
import '../widgets/player_bar.dart';
import '../widgets/video_tile.dart';

class PlaylistScreen extends StatelessWidget {
  final Playlist playlist;

  const PlaylistScreen({super.key, required this.playlist});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.title),
      ),
      body: Consumer2<PlaylistProvider, PlayerProvider>(
        builder: (context, playlistProvider, playerProvider, _) {
          final tracks = playlistProvider.currentPlaylist?.tracks ?? playlist.tracks;
          final isCurrentlyPlaying = playerProvider.queue == tracks && tracks.isNotEmpty;

          return Column(
            children: [
              _buildHeader(context, tracks, isCurrentlyPlaying, playerProvider),
              Expanded(
                child: tracks.isEmpty
                    ? const Center(child: Text('No tracks found'))
                    : ListView.builder(
                        itemCount: tracks.length,
                        itemBuilder: (context, index) {
                          final track = tracks[index];
                          return TrackTile(
                            track: track,
                            isCurrent: isCurrentlyPlaying &&
                                playerProvider.currentTrack?.id == track.id,
                            onTap: () {
                              playerProvider.setQueue(tracks, startIndex: index);
                              playerProvider.playTrack(track);
                            },
                          );
                        },
                      ),
              ),
              const PlayerBar(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, List<Track> tracks, bool isCurrentlyPlaying, PlayerProvider playerProvider) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              playlist.thumbnailUrl ?? '',
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
                  playlist.title,
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
          IconButton(
            icon: const Icon(Icons.shuffle),
            onPressed: tracks.isEmpty
                ? null
                : () {
                    playerProvider.setQueue(tracks, startIndex: 0);
                    playerProvider.playTrack(tracks.first);
                  },
          ),
        ],
      ),
    );
  }
}
