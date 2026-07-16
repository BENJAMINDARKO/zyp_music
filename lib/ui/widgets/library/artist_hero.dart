import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import '../../../domain/entities/artist.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/thumbnail_url.dart';
import '../../../presentation/providers/playlist_provider.dart';
import '../aurora_glass.dart';

class ArtistHero extends StatelessWidget {
  final Artist artist;
  final VoidCallback onPlayAll;
  final VoidCallback onBack;
  final VoidCallback onMore;

  const ArtistHero({
    super.key,
    required this.artist,
    required this.onPlayAll,
    required this.onBack,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final playlists = context.watch<PlaylistProvider>();
    final isFollowed = playlists.isArtistFavorite(artist.id);

    return AuroraGlass(
      borderRadius: 32,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        height: 290,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Aurora Background Orbs
            Positioned(
              top: -40,
              left: -40,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ZypAuroraColors.violet.withOpacity(0.24),
                  boxShadow: [
                    BoxShadow(
                      color: ZypAuroraColors.violet.withOpacity(0.25),
                      blurRadius: 50,
                      spreadRadius: 20,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: -40,
              right: -40,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ZypAuroraColors.cyan.withOpacity(0.18),
                  boxShadow: [
                    BoxShadow(
                      color: ZypAuroraColors.cyan.withOpacity(0.25),
                      blurRadius: 50,
                      spreadRadius: 20,
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
                    'ARTIST PROFILE',
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

            // 3. Center Content (Avatar, Name, Stats, Controls)
            Align(
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 40),
                  // Circular Avatar with Aurora Glow Backdrop
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: ZypAuroraColors.violet.withOpacity(0.4),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ],
                      border: Border.all(color: Colors.white24, width: 2),
                    ),
                    child: ClipOval(
                      child: (artist.thumbnailUrl?.isNotEmpty ?? false)
                          ? CachedNetworkImage(
                              imageUrl: rewriteThumbnailSize(artist.thumbnailUrl, 300),
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => _fallbackAvatar(),
                            )
                          : _fallbackAvatar(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Artist Name
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      artist.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Stats subtext
                  Text(
                    '${artist.albums.length} Albums • ${artist.topTracks.length} tracks',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.58),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Controls Row (Follow, Play)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Follow Button (Pill card)
                      GestureDetector(
                        onTap: () {
                          playlists.toggleFavoriteArtist(artist);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: isFollowed ? Colors.transparent : Colors.white.withOpacity(0.15),
                            ),
                            color: isFollowed ? ZypAuroraColors.pink.withOpacity(0.18) : Colors.white.withOpacity(0.06),
                          ),
                          child: Text(
                            isFollowed ? 'FOLLOWING' : 'FOLLOW',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: isFollowed ? ZypAuroraColors.pink : Colors.white70,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Play Button
                      GestureDetector(
                        onTap: onPlayAll,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
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
                              Icon(PhosphorIconsFill.play, color: Color(0xFF05040B), size: 14),
                              SizedBox(width: 6),
                              Text(
                                'PLAY SONGS',
                                style: TextStyle(
                                  color: Color(0xFF05040B),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                  letterSpacing: 0.5,
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

  Widget _fallbackAvatar() {
    return Container(
      color: Colors.white.withOpacity(0.08),
      child: const Icon(PhosphorIconsRegular.user, color: Colors.white30, size: 36),
    );
  }
}
