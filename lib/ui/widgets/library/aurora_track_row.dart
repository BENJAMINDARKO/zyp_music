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
import '../playing_track_mask.dart';
import '../explicit_icon.dart';
import '../track_context_menu.dart';
import '../track_download_icon.dart';
import '../track_export_icon.dart';
import '../aurora_glass.dart';

class AuroraTrackRow extends StatelessWidget {
  final Track track;
  final VoidCallback? onTap;

  const AuroraTrackRow({
    super.key,
    required this.track,
    this.onTap,
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
                // 1. Album art (54x54, radius 18)
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: (track.thumbnailUrl?.isNotEmpty ?? false)
                      ? CachedNetworkImage(
                          imageUrl: rewriteThumbnailSize(track.thumbnailUrl, 150),
                          width: 54,
                          height: 54,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _fallbackArt(),
                        )
                      : _fallbackArt(),
                ),
                const SizedBox(width: 12),

                // 2. Metadata & Badges
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
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (track.isExplicit) const ExplicitIcon(),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              track.author ?? 'Unknown Artist',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withOpacity(0.58),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Dynamic badges
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          if (isPlaying)
                            _buildBadge('NOW', ZypAuroraColors.success, Colors.black),
                          if (isLiked)
                            _buildBadge('LIKED', ZypAuroraColors.pink, Colors.white),
                          if (isDownloaded)
                            _buildBadge('OFFLINE', ZypAuroraColors.cyan, Colors.black),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // 3. Actions
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
                    const SizedBox(width: 8),
                    TrackExportIcon(track: track, size: 20),
                    const SizedBox(width: 8),
                    TrackDownloadIcon(track: track, size: 20),
                    const SizedBox(width: 8),
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

  Widget _buildBadge(String label, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor.withOpacity(0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: bgColor.withOpacity(0.35), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          color: bgColor,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _fallbackArt() {
    return Container(
      width: 54,
      height: 54,
      color: Colors.white.withOpacity(0.08),
      child: const Icon(PhosphorIconsRegular.musicNote, color: Colors.white30, size: 22),
    );
  }
}
