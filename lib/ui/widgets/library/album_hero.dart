import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import '../../../domain/entities/album.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/thumbnail_url.dart';
import '../../../presentation/providers/playlist_provider.dart';
import '../../../presentation/providers/download_provider.dart';
import '../album_download_icon.dart';
import '../aurora_glass.dart';

class AlbumHero extends StatelessWidget {
  final Album album;
  final VoidCallback onPlayAll;
  final VoidCallback onBack;
  final VoidCallback onMore;

  const AlbumHero({
    super.key,
    required this.album,
    required this.onPlayAll,
    required this.onBack,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final playlists = context.watch<PlaylistProvider>();
    final downloads = context.watch<DownloadProvider>();
    final isLiked = playlists.isAlbumFavorite(album.id);

    return AuroraGlass(
      borderRadius: 32,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        height: 310,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Aurora Background Glow (Cyan and Pink Orbs)
            Positioned(
              top: -20,
              right: -20,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ZypAuroraColors.pink.withOpacity(0.12),
                  boxShadow: [
                    BoxShadow(
                      color: ZypAuroraColors.pink.withOpacity(0.2),
                      blurRadius: 40,
                      spreadRadius: 15,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: -20,
              left: -20,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ZypAuroraColors.cyan.withOpacity(0.12),
                  boxShadow: [
                    BoxShadow(
                      color: ZypAuroraColors.cyan.withOpacity(0.2),
                      blurRadius: 40,
                      spreadRadius: 15,
                    ),
                  ],
                ),
              ),
            ),

            // 2. Navigation bar on top
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
                    'ALBUM DETAILS',
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

            // 3. Center Content (Art, Title, Details, Actions)
            Align(
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 36),
                  // Boxy Album Cover with drop shadow and cyan glow
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: ZypAuroraColors.cyan.withOpacity(0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: (album.thumbnailUrl?.isNotEmpty ?? false)
                          ? CachedNetworkImage(
                              imageUrl: rewriteThumbnailSize(album.thumbnailUrl, 350),
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => _fallbackCover(),
                            )
                          : _fallbackCover(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Album Title
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Text(
                      album.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Artist Name & Year
                  Text(
                    '${album.artistName ?? "Unknown Artist"} • ${album.year ?? "Unknown"}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.58),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Action buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Like (Heart) button
                      IconButton(
                        icon: Icon(
                          isLiked ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                          color: isLiked ? ZypAuroraColors.pink : Colors.white.withOpacity(0.54),
                          size: 24,
                        ),
                        onPressed: () {
                          playlists.toggleFavoriteAlbum(album, downloadProvider: downloads);
                        },
                      ),
                      const SizedBox(width: 14),
                      // Play Button
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
                      const SizedBox(width: 14),
                      // Download Button
                      AlbumDownloadIcon(album: album, size: 24),
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

  Widget _fallbackCover() {
    return Container(
      color: Colors.white.withOpacity(0.08),
      child: const Icon(PhosphorIconsRegular.discoBall, color: Colors.white30, size: 36),
    );
  }
}
