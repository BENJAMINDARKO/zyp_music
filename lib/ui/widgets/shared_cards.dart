import 'package:flutter/material.dart';
import 'explicit_icon.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../presentation/providers/player_provider.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/download_provider.dart';
import '../../domain/entities/video.dart';
import '../../domain/entities/album.dart';
import '../../domain/entities/artist.dart';
import 'track_context_menu.dart';
import 'album_context_menu.dart';
import '../screens/album_screen.dart';
import '../../ui/widgets/track_download_icon.dart';
import '../../ui/widgets/album_download_icon.dart';
import '../../ui/widgets/track_export_icon.dart';
import '../../ui/widgets/album_export_icon.dart';
import '../../ui/screens/playlist_screen.dart';
import "../screens/artist_screen.dart";
import "../../core/utils/thumbnail_url.dart";
import 'playing_track_mask.dart';

class TrackCard extends StatelessWidget {
  final Track track;
  final VoidCallback? onTap;

  const TrackCard({required this.track, this.onTap});

  @override
  Widget build(BuildContext context) {
    return PlayingTrackMask(
      track: track,
      child: Material(
        color: Colors.transparent,
      child: InkWell(
        onTap: onTap ?? () {
          final player = context.read<PlayerProvider>();
          player.setQueue([track]);
          player.playFromQueue(0);
        },
        onLongPress: () {
          TrackContextMenu.show(context, track);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1F1F1F),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: track.thumbnailUrl != null
                          ? ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                              child: CachedNetworkImage(
                                imageUrl: rewriteThumbnailSize(track.thumbnailUrl),
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => _fallbackIcon(),
                              ),
                            )
                          : _fallbackIcon(),
                      ),
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Consumer<PlaylistProvider>(
                          builder: (context, pp, _) {
                            final isFav = pp.isFavorite(track.id);
                            return GestureDetector(
                              onTap: () {
                                pp.toggleFavorite(
                                  track,
                                  downloadProvider: context.read<DownloadProvider>(),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white12, width: 0.5),
                                ),
                                child: Icon(
                                  isFav ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                                  color: isFav ? Colors.red : Colors.white,
                                  size: 14,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white12, width: 0.5),
                          ),
                          child: Row(
                            children: [
                              TrackExportIcon(track: track, size: 14),
                              const SizedBox(width: 4),
                              TrackDownloadIcon(track: track, size: 14),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            track.title,
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (track.isExplicit) const ExplicitIcon(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.author ?? 'Unknown Artist',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _fallbackIcon() => const Center(child: Icon(PhosphorIconsRegular.musicNote, color: Colors.white24, size: 48));
}

class AlbumCard extends StatelessWidget {
  final Album album;

  const AlbumCard({required this.album});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AlbumScreen(albumId: album.id),
            ),
          );
        },
        onLongPress: () => AlbumContextMenu.show(context, album),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1F1F1F),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: album.thumbnailUrl != null
                          ? ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                              child: CachedNetworkImage(
                                imageUrl: rewriteThumbnailSize(album.thumbnailUrl),
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => _fallbackIcon(),
                              ),
                            )
                          : _fallbackIcon(),
                      ),
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Consumer<PlaylistProvider>(
                          builder: (context, pp, _) {
                            final isFav = pp.favoriteAlbums.any((a) => a.id == album.id);
                            return GestureDetector(
                              onTap: () {
                                pp.toggleFavoriteAlbum(
                                  album,
                                  downloadProvider: context.read<DownloadProvider>(),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white12, width: 0.5),
                                ),
                                child: Icon(
                                  isFav ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                                  color: isFav ? Colors.red : Colors.white,
                                  size: 14,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white12, width: 0.5),
                          ),
                          child: Row(
                            children: [
                              AlbumExportIcon(album: album, size: 14),
                              const SizedBox(width: 4),
                              AlbumDownloadIcon(album: album, size: 14),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.title,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      album.artistName ?? 'Unknown Artist',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackIcon() => const Center(child: Icon(PhosphorIconsRegular.discoBall, color: Colors.white24, size: 48));
}
