import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import '../../../domain/entities/playlist.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/thumbnail_url.dart';
import '../../../presentation/providers/playlist_provider.dart';
import '../../../presentation/providers/download_provider.dart';
import '../aurora_glass.dart';

class PlaylistHero extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onPlayAll;
  final VoidCallback onBack;
  final VoidCallback onMore;

  const PlaylistHero({
    super.key,
    required this.playlist,
    required this.onPlayAll,
    required this.onBack,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final playlists = context.watch<PlaylistProvider>();
    final downloads = context.watch<DownloadProvider>();
    
    // Extract first 4 tracks to build the collage
    final firstTracks = playlist.tracks.take(4).toList();

    return AuroraGlass(
      borderRadius: 32,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        height: 280,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Collage Background
            ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: _buildCollage(firstTracks),
            ),

            // 2. Dark Gradient Overlay
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.35),
                    Colors.black.withOpacity(0.65),
                    Colors.black.withOpacity(0.9),
                  ],
                ),
              ),
            ),

            // 3. Navigation Controls (Back, Options)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: onBack,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Icon(PhosphorIconsRegular.caretLeft, color: Colors.white, size: 20),
                    ),
                  ),
                  const Text(
                    'PLAYLIST',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: Colors.white70,
                    ),
                  ),
                  GestureDetector(
                    onTap: onMore,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Icon(PhosphorIconsRegular.dotsThreeVertical, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),

            // 4. Center Content (Title and Stats)
            Positioned(
              bottom: 24,
              left: 20,
              right: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    playlist.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                      height: 1.15,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${playlist.author ?? "ZYP playlist"} • updated today',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Stats pills row
                  Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildPill('${playlist.tracks.length} tracks'),
                      _buildPill(_calculateTotalDuration(playlist)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // Action Buttons (heart, play, download)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Play Button with cyan/lime gradient
                      GestureDetector(
                        onTap: onPlayAll,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: const LinearGradient(
                              colors: [ZypAuroraColors.cyan, ZypAuroraColors.lime],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: ZypAuroraColors.cyan.withOpacity(0.35),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(PhosphorIconsFill.play, color: Color(0xFF05040B), size: 16),
                              SizedBox(width: 8),
                              Text(
                                'PLAY ALL',
                                style: TextStyle(
                                  color: Color(0xFF05040B),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollage(List<dynamic> tracks) {
    if (tracks.isEmpty) {
      return Container(color: ZypAuroraColors.ink2);
    }
    
    if (tracks.length < 4) {
      return CachedNetworkImage(
        imageUrl: rewriteThumbnailSize(tracks[0].thumbnailUrl, 800),
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => Container(color: ZypAuroraColors.ink2),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildTile(tracks[0].thumbnailUrl)),
              Expanded(child: _buildTile(tracks[1].thumbnailUrl)),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildTile(tracks[2].thumbnailUrl)),
              Expanded(child: _buildTile(tracks[3].thumbnailUrl)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTile(String? url) {
    if (url == null || url.isEmpty) {
      return Container(color: ZypAuroraColors.ink2);
    }
    return CachedNetworkImage(
      imageUrl: rewriteThumbnailSize(url, 300),
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => Container(color: ZypAuroraColors.ink2),
    );
  }

  Widget _buildPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: Colors.white.withOpacity(0.85),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  String _calculateTotalDuration(Playlist p) {
    int secs = 0;
    for (var track in p.tracks) {
      secs += track.duration?.inSeconds ?? 0;
    }
    if (secs == 0) return '0m';
    final duration = Duration(seconds: secs);
    final hours = duration.inHours;
    final mins = duration.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }
}
