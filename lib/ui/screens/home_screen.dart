import 'package:zyp_music/presentation/providers/playlist_provider.dart';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import '../../presentation/providers/download_provider.dart';
import '../widgets/track_download_icon.dart';
import '../widgets/album_download_icon.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../presentation/providers/player_provider.dart';
import '../../presentation/providers/charts_provider.dart';
import '../../domain/entities/video.dart';
import '../../domain/entities/album.dart';
import '../../domain/entities/artist.dart';
import '../../data/models/video_model.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/album_context_menu.dart';
import 'album_screen.dart';
import 'artist_screen.dart';
import "../../core/utils/thumbnail_url.dart";
import '../widgets/playing_track_mask.dart';
import '../widgets/explicit_icon.dart';

import '../widgets/global_top_bar.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSuggestedSongs(context),
          _buildLikedSongs(context),
          _buildFeaturedAlbums(context),
            _buildFavouriteArtists(context),
            _buildGlobalHot(context),
          ],
        ),
      ),
    );
  }
}

Widget _buildSectionHeader(BuildContext context, String title) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

Widget _buildEmptyState(BuildContext context, String message) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
      ),
    ),
  );
}

Widget _buildSuggestedSongs(BuildContext context) {
  return Consumer<ChartsProvider>(
    builder: (context, charts, child) {
      if (charts.isLoadingGhana && charts.ghanaTopSongs.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: CircularProgressIndicator(color: Theme.of(context).colorScheme.onSurface),
          ),
        );
      }

      final songs = charts.ghanaTopSongs;
      if (songs.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(context, 'Suggested Songs'),
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: songs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                return SizedBox(
                  width: 140,
                  child: _TrackCard(track: songs[index]),
                );
              },
            ),
          ),
        ],
      );
    },
  );
}

Widget _buildLikedSongs(BuildContext context) {
  return Consumer<PlaylistProvider>(
    builder: (context, pp, child) {
      final tracks = pp.favoriteTracks;
      if (tracks.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(context, 'Liked Songs'),
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: tracks.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                return SizedBox(
                  width: 140,
                  child: _TrackCard(track: tracks[index]),
                );
              },
            ),
          ),
        ],
      );
    },
  );
}

Widget _buildFeaturedAlbums(BuildContext context) {
  return Consumer<ChartsProvider>(
    builder: (context, charts, child) {
      if (charts.isLoadingAlbums && charts.featuredAlbums.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: CircularProgressIndicator(color: Theme.of(context).colorScheme.onSurface),
          ),
        );
      }

      final albums = charts.featuredAlbums;
      if (albums.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(context, 'Featured Albums'),
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: albums.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                return SizedBox(
                  width: 140,
                  child: _AlbumCard(album: albums[index]),
                );
              },
            ),
          ),
        ],
      );
    },
  );
}

Widget _buildFavouriteArtists(BuildContext context) {
  return Consumer<PlaylistProvider>(
    builder: (context, pp, child) {
      final artists = pp.favoriteArtists;
      if (artists.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(context, 'Favourite Artists'),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: artists.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final artist = artists[index];
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ArtistScreen(artistId: artist.id),
                      ),
                    );
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                        backgroundImage: artist.thumbnailUrl != null
                            ? CachedNetworkImageProvider(
                                rewriteThumbnailSize(artist.thumbnailUrl),
                              )
                            : null,
                        child: artist.thumbnailUrl == null
                            ? Text(
                                artist.name.isNotEmpty
                                    ? artist.name[0].toUpperCase()
                                    : '?',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 72,
                        child: Text(
                          artist.name,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
    },
  );
}

Widget _buildGlobalHot(BuildContext context) {
  return Consumer<ChartsProvider>(
    builder: (context, charts, child) {
      if (charts.isLoadingGlobal && charts.globalTopSongs.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: CircularProgressIndicator(color: Theme.of(context).colorScheme.onSurface),
          ),
        );
      }

      final songs = charts.globalTopSongs;
      if (songs.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(context, 'Global Hot'),
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: songs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                return SizedBox(
                  width: 140,
                  child: _TrackCard(track: songs[index]),
                );
              },
            ),
          ),
        ],
      );
    },
  );
}

// Reusable track tile for compact list
class _CompactTrackTile extends StatelessWidget {
  final Track track;
  const _CompactTrackTile({required this.track});

  @override
  Widget build(BuildContext context) {
    return PlayingTrackMask(
      track: track,
      child: Material(
        color: Colors.transparent,
      child: InkWell(
        onTap: () {
          final player = context.read<PlayerProvider>();
          player.setQueue([track]);
          player.playFromQueue(0);
        },
        onLongPress: () {
          TrackContextMenu.show(context, track);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: track.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: rewriteThumbnailSize(track.thumbnailUrl),
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _fallbackIcon(),
                      )
                    : _fallbackIcon(),
              ),
              const SizedBox(width: 12),
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
              Consumer<PlaylistProvider>(
                builder: (context, pp, _) {
                  final isFav = pp.isFavorite(track.id);
                  return IconButton(
                    icon: Icon(
                      isFav ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                      color: isFav ? const Color(0xFFEAB308) : Colors.white54,
                      size: 20,
                    ),
                    onPressed: () {
                      pp.toggleFavorite(
                        track,
                        downloadProvider: context.read<DownloadProvider>(),
                      );
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  );
                },
              ),
              const SizedBox(width: 8),
              TrackDownloadIcon(track: track, size: 20),
            ],
          ),
          ),
        ),
      ),
    );
  }

  Widget _fallbackIcon() => Container(
        width: 56,
        height: 56,
        color: const Color(0xFF1F1F1F),
        child: const Icon(PhosphorIconsRegular.musicNote, color: Colors.white24),
      );
}


class _TrackCard extends StatelessWidget {
  final Track track;
  const _TrackCard({required this.track});

  @override
  Widget build(BuildContext context) {
    return PlayingTrackMask(
      track: track,
      child: Material(
        color: Colors.transparent,
      child: InkWell(
        onTap: () {
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
                          child: TrackDownloadIcon(track: track, size: 14),
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

class _AlbumCard extends StatelessWidget {
  final Album album;
  const _AlbumCard({required this.album});

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
                          child: AlbumDownloadIcon(album: album, size: 14),
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
