import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/video.dart';
import '../../presentation/providers/home_feed_provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../../core/utils/format_duration.dart';
import 'playing_track_mask.dart';
import 'explicit_icon.dart';

class DownloadedView extends StatefulWidget {
  const DownloadedView({super.key});

  @override
  State<DownloadedView> createState() => _DownloadedViewState();
}

class _DownloadedViewState extends State<DownloadedView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeFeedProvider>().loadAllDownloadedTracks();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeFeedProvider>(
      builder: (context, feed, _) {
        final tracks = feed.allDownloadedTracks;

        if (feed.isLoadingAllDownloadedTracks && tracks == null) {
          return const Center(child: CircularProgressIndicator());
        }

        if (tracks == null || tracks.isEmpty) {
          return _buildEmptyState(context);
        }

        return _buildList(context, tracks);
      },
    );
  }

  Widget _buildList(BuildContext context, List<Track> tracks) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: tracks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        return _buildTrackRow(context, tracks[index]);
      },
    );
  }

  Widget _buildTrackRow(BuildContext context, Track track) {
    final theme = Theme.of(context);
    return PlayingTrackMask(
      track: track,
      child: InkWell(
        onTap: () => _playTrack(context, track),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty
                  ? Image.network(
                      track.thumbnailUrl!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholderThumbnail(context),
                    )
                  : _placeholderThumbnail(context),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          track.title,
                          style: theme.textTheme.bodyLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (track.isExplicit) const ExplicitIcon(),
                    ],
                  ),
                  if (track.author != null && track.author!.isNotEmpty)
                    Text(
                      track.author!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (track.duration != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  formatDuration(track.duration!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
          ],
        ),
      ),
    ));
  }

  Widget _placeholderThumbnail(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 48,
      height: 48,
      color: theme.colorScheme.surface,
      child: Icon(
        Icons.music_note,
        color: theme.colorScheme.onSurface.withOpacity(0.3),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'No downloads yet',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tracks you cache or download will appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _playTrack(BuildContext context, Track track) {
    final player = context.read<PlayerProvider>();
    player.setQueue([track]);
    player.playFromQueue(0);
  }
}
