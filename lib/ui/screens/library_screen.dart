import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/album.dart';
import '../../domain/entities/artist.dart';
import '../../domain/entities/video.dart';
import '../../core/utils/format_duration.dart';
import '../widgets/track_context_menu.dart';
import 'playlist_screen.dart';
import 'album_screen.dart';
import 'artist_screen.dart';
import '../../presentation/providers/download_provider.dart';
import '../widgets/track_download_icon.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: Color(0xFFEAB308),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            dividerColor: Color(0xFF2A2A2A),
            tabs: [
              Tab(text: "Tracks"),
              Tab(text: "Albums"),
              Tab(text: "Artists"),
              Tab(text: "Playlists"),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildLikedSongsTab(context),
                _buildLikedAlbumsTab(context),
                _buildLikedArtistsTab(context),
                _buildPlaylistsTab(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLikedSongsTab(BuildContext context) {
    return Consumer<PlaylistProvider>(
      builder: (context, provider, child) {
        final favorites = provider.favoriteTracks;

        if (favorites.isEmpty) {
          return const Center(
            child: Text(
              "No liked songs yet.\nFavorite a song to see it here.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 120, top: 16),
          itemCount: favorites.length,
          itemBuilder: (context, index) {
            final track = favorites[index];
            
            return ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: track.thumbnailUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: CachedNetworkImage(
                        imageUrl: track.thumbnailUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => const Icon(Icons.music_note, color: Colors.white54),
                      ),
                    )
                  : const Icon(Icons.music_note, color: Colors.white54),
              ),
              title: Text(
                track.title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                track.author ?? 'Unknown Artist',
                style: const TextStyle(color: Colors.white54),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.favorite, color: Color(0xFFEAB308)),
                    onPressed: () {
                      final dl = context.read<DownloadProvider>();
                      provider.toggleFavorite(track, downloadProvider: dl);
                    },
                  ),
                  TrackDownloadIcon(track: track, size: 20),
                  IconButton(
                    icon: const Icon(Icons.more_vert, color: Colors.white54),
                    onPressed: () => TrackContextMenu.show(context, track),
                  ),
                ],
              ),
              onTap: () {
                final player = context.read<PlayerProvider>();
                player.setQueue(favorites);
                player.playFromQueue(index);
              },
              onLongPress: () => TrackContextMenu.show(context, track),
            );
          },
        );
      },
    );
  }

  Widget _buildLikedAlbumsTab(BuildContext context) {
    return Consumer<PlaylistProvider>(
      builder: (context, provider, child) {
        final albums = provider.favoriteAlbums;

        if (albums.isEmpty) {
          return const Center(
            child: Text(
              "No liked albums yet.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 120, top: 16),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            return ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: (album.thumbnailUrl?.isNotEmpty ?? false)
                    ? CachedNetworkImage(
                        imageUrl: album.thumbnailUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => Container(
                          width: 48, height: 48, color: Colors.grey[800],
                          child: const Icon(Icons.album, color: Colors.white54),
                        ),
                      )
                    : Container(
                        width: 48, height: 48, color: Colors.grey[800],
                        child: const Icon(Icons.album, color: Colors.white54),
                      ),
              ),
              title: Text(album.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${album.artistName ?? 'Unknown'} • ${album.year ?? ''}', style: const TextStyle(color: Colors.white54), maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                icon: const Icon(Icons.favorite, color: Colors.red),
                onPressed: () {
                  final dl = context.read<DownloadProvider>();
                  provider.toggleFavoriteAlbum(album, downloadProvider: dl);
                },
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AlbumScreen(albumId: album.id),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildLikedArtistsTab(BuildContext context) {
    return Consumer<PlaylistProvider>(
      builder: (context, provider, child) {
        final artists = provider.favoriteArtists;

        if (artists.isEmpty) {
          return const Center(
            child: Text(
              "No liked artists yet.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 120, top: 16),
          itemCount: artists.length,
          itemBuilder: (context, index) {
            final artist = artists[index];
            return ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: (artist.thumbnailUrl?.isNotEmpty ?? false)
                    ? CachedNetworkImage(
                        imageUrl: artist.thumbnailUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => Container(
                          width: 48, height: 48, color: Colors.grey[800],
                          child: const Icon(Icons.person, color: Colors.white54),
                        ),
                      )
                    : Container(
                        width: 48, height: 48, color: Colors.grey[800],
                        child: const Icon(Icons.person, color: Colors.white54),
                      ),
              ),
              title: Text(artist.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                icon: const Icon(Icons.favorite, color: Colors.red),
                onPressed: () {
                  provider.toggleFavoriteArtist(artist);
                },
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ArtistScreen(artistId: artist.id),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildPlaylistsTab(BuildContext context) {
    return Consumer<PlaylistProvider>(
      builder: (context, provider, child) {
        final playlists = provider.playlists;

        if (playlists.isEmpty) {
          return Stack(
            children: [
              const Center(
                child: Text(
                  "You don't have any playlists yet.\nTap + to create one.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 16),
                ),
              ),
              Positioned(
                bottom: 120, // Padding for bottom player
                right: 24,
                child: FloatingActionButton(
                  backgroundColor: const Color(0xFFEAB308),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Playlist creation coming soon!')),
                    );
                  },
                  child: const Icon(Icons.add, color: Colors.black),
                ),
              ),
            ],
          );
        }

        return Stack(
          children: [
            ListView.builder(
              padding: const EdgeInsets.only(bottom: 120, top: 16),
              itemCount: playlists.length,
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: (playlist.thumbnailUrl?.isNotEmpty ?? false)
                        ? CachedNetworkImage(
                            imageUrl: playlist.thumbnailUrl!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) => Container(
                              width: 48, height: 48, color: Colors.grey[800],
                              child: const Icon(Icons.queue_music, color: Colors.white54),
                            ),
                          )
                        : Container(
                            width: 48, height: 48, color: Colors.grey[800],
                            child: const Icon(Icons.queue_music, color: Colors.white54),
                          ),
                  ),
                  title: Text(playlist.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(playlist.author ?? 'Local Playlist', style: const TextStyle(color: Colors.white54), maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlaylistScreen(playlistId: playlist.id),
                      ),
                    );
                  },
                );
              },
            ),
            Positioned(
              bottom: 120,
              right: 24,
              child: FloatingActionButton(
                backgroundColor: const Color(0xFFEAB308),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Playlist creation coming soon!')),
                  );
                },
                child: const Icon(Icons.add, color: Colors.black),
              ),
            ),
          ],
        );
      },
    );
  }
}
