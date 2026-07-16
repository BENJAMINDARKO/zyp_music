import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import '../../../domain/entities/album.dart';
import '../../../presentation/providers/playlist_provider.dart';
import '../../../presentation/providers/download_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/thumbnail_url.dart';
import '../../screens/album_screen.dart';
import '../aurora_glass.dart';

class AuroraAlbumGrid extends StatelessWidget {
  final List<Album> albums;

  const AuroraAlbumGrid({
    super.key,
    required this.albums,
  });

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text(
            "No liked albums yet.",
            style: TextStyle(color: Colors.white.withOpacity(0.54), fontSize: 16),
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: albums.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.68,
      ),
      itemBuilder: (context, index) {
        final album = albums[index];
        return AuroraAlbumCard(album: album);
      },
    );
  }
}

class AuroraAlbumCard extends StatelessWidget {
  final Album album;

  const AuroraAlbumCard({
    super.key,
    required this.album,
  });

  @override
  Widget build(BuildContext context) {
    final playlists = context.watch<PlaylistProvider>();
    final downloads = context.watch<DownloadProvider>();
    final isLiked = playlists.isAlbumFavorite(album.id);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AlbumScreen(albumId: album.id),
          ),
        );
      },
      child: AuroraGlass(
        borderRadius: 20,
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Square Cover Artwork with heart overlay
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    (album.thumbnailUrl?.isNotEmpty ?? false)
                        ? CachedNetworkImage(
                            imageUrl: rewriteThumbnailSize(album.thumbnailUrl, 300),
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _fallbackCover(),
                          )
                        : _fallbackCover(),
                    // Optional Heart overlay
                    if (isLiked)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.4),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            PhosphorIconsFill.heart,
                            color: ZypAuroraColors.pink,
                            size: 14,
                          ),
                        ),
                      ),
                    // Subtle aurora glow at bottom-right of artwork
                    Positioned(
                      bottom: -15,
                      right: -15,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: ZypAuroraColors.cyan.withOpacity(0.4),
                              blurRadius: 15,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                album.title,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 2),
            // Artist
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                album.artistName ?? 'Unknown',
                style: TextStyle(
                  fontSize: 9.5,
                  color: Colors.white.withOpacity(0.58),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }

  Widget _fallbackCover() {
    return Container(
      color: Colors.white.withOpacity(0.08),
      child: const Icon(PhosphorIconsRegular.discoBall, color: Colors.white30, size: 24),
    );
  }
}
