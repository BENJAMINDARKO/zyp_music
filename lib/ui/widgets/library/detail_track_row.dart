import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import '../../../domain/entities/video.dart';
import '../../../presentation/providers/player_provider.dart';
import '../../../presentation/providers/playlist_provider.dart';
import '../../../presentation/providers/download_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/thumbnail_url.dart';
import '../../../core/utils/format_duration.dart';
import '../playing_track_mask.dart';
import '../explicit_icon.dart';
import '../track_download_icon.dart';
import '../track_export_icon.dart';
import '../track_context_menu.dart';
import '../aurora_glass.dart';

class DetailTrackRow extends StatelessWidget {
  final int index;
  final Track track;
  final Color glowColor;
  final VoidCallback? onTap;
  final Widget? trailingActions;

  const DetailTrackRow({
    super.key,
    required this.index,
    required this.track,
    this.glowColor = ZypAuroraColors.cyan,
    this.onTap,
    this.trailingActions,
  });

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final playlists = context.watch<PlaylistProvider>();
    final downloads = context.watch<DownloadProvider>();

    final isPlaying = player.currentTrack?.id == track.id;
    final isLiked = playlists.isFavorite(track.id);
    final isDownloaded = downloads.isDownloaded(track.id);

    return PlayingTrackMask(
      track: track,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: GestureDetector(
          onTap: onTap ?? () => player.playTrackWithNewSession(track),
          onLongPress: () => TrackContextMenu.show(context, track),
          child: AuroraGlass(
            borderRadius: 24,
            padding: const EdgeInsets.all(9),
            child: Row(
              children: [
                // 1. Number Indicator
                SizedBox(
                  width: 28,
                  child: Center(
                    child: Text(
                      '$index',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isPlaying ? ZypAuroraColors.cyan : Colors.white.withOpacity(0.35),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),

                // 2. Artwork (size 54, radius 18)
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    children: [
                      (track.thumbnailUrl?.isNotEmpty ?? false)
                          ? CachedNetworkImage(
                              imageUrl: rewriteThumbnailSize(track.thumbnailUrl, 150),
                              width: 50,
                              height: 50,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => _fallbackArt(),
                            )
                          : _fallbackArt(),
                      // Subtle glow on active track
                      if (isPlaying)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: ZypAuroraColors.cyan.withOpacity(0.15),
                              border: Border.all(color: ZypAuroraColors.cyan, width: 1.5),
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // 3. Title + Artist
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              track.title,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: isPlaying ? ZypAuroraColors.cyan : Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (track.isExplicit) const ExplicitIcon(),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        track.author ?? 'Unknown Artist',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.58),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // 4. Actions
                if (trailingActions != null)
                  trailingActions!
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          isLiked ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                          color: isLiked ? ZypAuroraColors.pink : Colors.white.withOpacity(0.54),
                          size: 20,
                        ),
                        onPressed: () {
                          playlists.toggleFavorite(track, downloadProvider: downloads);
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 10),
                      TrackDownloadIcon(track: track, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        formatDuration(track.duration),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.48),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: Icon(
                          PhosphorIconsRegular.dotsThreeVertical,
                          color: Colors.white.withOpacity(0.54),
                          size: 20,
                        ),
                        onPressed: () => TrackContextMenu.show(context, track),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fallbackArt() {
    return Container(
      width: 50,
      height: 50,
      color: Colors.white.withOpacity(0.08),
      child: const Icon(PhosphorIconsRegular.musicNote, color: Colors.white30, size: 20),
    );
  }
}
