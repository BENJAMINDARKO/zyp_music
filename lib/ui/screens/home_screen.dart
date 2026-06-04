import 'package:zyp_music/presentation/providers/playlist_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../presentation/providers/download_provider.dart';
import '../widgets/track_download_icon.dart';
import '../widgets/album_download_icon.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../presentation/providers/player_provider.dart';
import '../../presentation/providers/charts_provider.dart';
import '../../domain/entities/video.dart';
import '../../domain/entities/album.dart';
import '../../data/models/video_model.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/album_context_menu.dart';
import 'album_screen.dart'; // We'll need this for albums
import 'package:zyp_music/ui/screens/artist_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 0, // Hide the standard app bar space
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: [
              Tab(text: 'Home'),
              Tab(text: 'Global Hot'),
              Tab(text: 'Featured Albums'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _HomeTab(),
            _GlobalHotTab(),
            _FeaturedAlbumsTab(),
          ],
        ),
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRecentlyPlayed(context),
          const SizedBox(height: 32),
          _buildRecommendedSongs(context),
          const SizedBox(height: 32),
          _buildTopArtists(context),
          const SizedBox(height: 120), // Padding for the bottom player
        ],
      ),
    );
  }

  Widget _buildRecentlyPlayed(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, player, child) {
        final recent = player.recentlyPlayed.take(15).toList();
        if (recent.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Recently Played",
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: recent.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: SizedBox(
                      width: 140,
                      child: _TrackCard(track: recent[index]),
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

  Widget _buildRecommendedSongs(BuildContext context) {
    return Consumer<ChartsProvider>(
      builder: (context, charts, child) {
        if (charts.isLoadingGhana && charts.ghanaTopSongs.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        
        final songs = charts.ghanaTopSongs;
        if (songs.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Recommended Songs",
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 240, // 3 compact rows
              child: GridView.builder(
                scrollDirection: Axis.horizontal,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.25, // Adjust for width vs height
                ),
                itemCount: songs.length,
                itemBuilder: (context, index) {
                  return _CompactTrackTile(track: songs[index]);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTopArtists(BuildContext context) {
    return Consumer<ChartsProvider>(
      builder: (context, charts, child) {
        final artists = charts.ghanaTopArtists;
        if (artists.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Top Artists",
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: artists.length,
                itemBuilder: (context, index) {
                  final artistName = artists[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 24),
                    child: GestureDetector(
                      onTap: () async {
                        final id = await context.read<ChartsProvider>().searchArtistId(artistName);
                        if (id != null && context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ArtistScreen(artistId: id),
                            ),
                          );
                        }
                      },
                      onLongPress: () async {
                        final id = await context.read<ChartsProvider>().searchArtistId(artistName);
                        if (id != null && context.mounted) {
                          final results = await context.read<PlaylistProvider>().searchArtists(artistName);
                          if (results.isNotEmpty && context.mounted) {
                            await context.read<PlaylistProvider>().toggleFavoriteArtist(results.first);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Added $artistName to favorites')),
                            );
                          }
                        }
                      },
                      child: Column(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF1F1F1F),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: const Center(
                              child: Icon(Icons.person, color: Colors.white54, size: 40),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: 80,
                            child: Text(
                              artistName,
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
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
}

class _GlobalHotTab extends StatelessWidget {
  const _GlobalHotTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<ChartsProvider>(
      builder: (context, charts, child) {
        if (charts.isLoadingGlobal && charts.globalTopSongs.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        
        final songs = charts.globalTopSongs;
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 580, // Taller Grid for the main view
                child: GridView.builder(
                  scrollDirection: Axis.horizontal,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1.3, // standard vertical card ratio
                  ),
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    return _TrackCard(track: songs[index]);
                  },
                ),
              ),
              const SizedBox(height: 120),
            ],
          ),
        );
      },
    );
  }
}

class _FeaturedAlbumsTab extends StatelessWidget {
  const _FeaturedAlbumsTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<ChartsProvider>(
      builder: (context, charts, child) {
        if (charts.isLoadingAlbums && charts.featuredAlbums.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        
        final albums = charts.featuredAlbums;
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 580,
                child: GridView.builder(
                  scrollDirection: Axis.horizontal,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1.3,
                  ),
                  itemCount: albums.length,
                  itemBuilder: (context, index) {
                    return _AlbumCard(album: albums[index]);
                  },
                ),
              ),
              const SizedBox(height: 120),
            ],
          ),
        );
      },
    );
  }
}

// Reusable track tile for compact list
class _CompactTrackTile extends StatelessWidget {
  final Track track;
  const _CompactTrackTile({required this.track});

  @override
  Widget build(BuildContext context) {
    return Material(
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
                        imageUrl: track.thumbnailUrl!,
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
                    Text(
                      track.title,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                      isFav ? Icons.favorite : Icons.favorite_border,
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
    );
  }

  Widget _fallbackIcon() => Container(
        width: 56,
        height: 56,
        color: const Color(0xFF1F1F1F),
        child: const Icon(Icons.music_note, color: Colors.white24),
      );
}


class _TrackCard extends StatelessWidget {
  final Track track;
  const _TrackCard({required this.track});

  @override
  Widget build(BuildContext context) {
    return Material(
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
                                imageUrl: track.thumbnailUrl!,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => _fallbackIcon(),
                              ),
                            )
                          : _fallbackIcon(),
                      ),
                      // Favorite Overlay Icon
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
                                  isFav ? Icons.favorite : Icons.favorite_border,
                                  color: isFav ? Colors.red : Colors.white,
                                  size: 14,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      // Download Status Overlay
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
                    Text(
                      track.title,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
    );
  }

  Widget _fallbackIcon() => const Center(child: Icon(Icons.music_note, color: Colors.white24, size: 48));
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
          // Push to AlbumScreen
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
                                imageUrl: album.thumbnailUrl!,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => _fallbackIcon(),
                              ),
                            )
                          : _fallbackIcon(),
                      ),
                      // Favorite Overlay Icon
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
                                  isFav ? Icons.favorite : Icons.favorite_border,
                                  color: isFav ? Colors.red : Colors.white,
                                  size: 14,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      // Download Status Overlay
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

  Widget _fallbackIcon() => const Center(child: Icon(Icons.album, color: Colors.white24, size: 48));
}
