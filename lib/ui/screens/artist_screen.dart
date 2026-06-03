import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../../domain/entities/artist.dart';
import '../../core/utils/format_duration.dart';
import '../widgets/track_context_menu.dart';
import 'album_screen.dart';
import '../widgets/track_download_icon.dart';
import '../widgets/bottom_player.dart';
import '../../presentation/providers/download_provider.dart';

class ArtistScreen extends StatefulWidget {
  final String artistId;

  const ArtistScreen({super.key, required this.artistId});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  Artist? _artist;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadArtist();
  }

  Future<void> _loadArtist() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final provider = context.read<PlaylistProvider>();
      final artist = await provider.getArtist(widget.artistId);
      setState(() {
        _artist = artist;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = "Failed to load artist: $e";
        _isLoading = false;
      });
    }
  }

  void _playTrack(int index) {
    if (_artist == null) return;
    final player = context.read<PlayerProvider>();
    player.setQueue(_artist!.topTracks);
    player.playFromQueue(index);
  }

  void _playAll() {
    if (_artist == null || _artist!.topTracks.isEmpty) return;
    _playTrack(0);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Color(0xFFEAB308))),
        extendBody: true,
        bottomNavigationBar: BottomPlayer(),
      );
    }

    if (_error != null || _artist == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: Text(
            _error ?? "Artist not found.",
            style: const TextStyle(color: Colors.red),
          ),
        ),
        extendBody: true,
        bottomNavigationBar: const BottomPlayer(),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: Colors.black,
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (_artist!.thumbnailUrl != null)
                    CachedNetworkImage(
                      imageUrl: _artist!.thumbnailUrl!,
                      fit: BoxFit.cover,
                    ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.5),
                          Colors.black,
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 24,
                    left: 24,
                    right: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _artist!.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _playAll,
                              icon: const Icon(Icons.play_arrow, color: Colors.black),
                              label: const Text("Play Top Tracks", style: TextStyle(color: Colors.black)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFEAB308),
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Consumer<PlaylistProvider>(
                              builder: (context, pp, _) {
                                final isFav = pp.favoriteArtists.any((a) => a.id == _artist!.id);
                                return IconButton(
                                  icon: Icon(
                                    isFav ? Icons.favorite : Icons.favorite_border,
                                    color: isFav ? Colors.red : Colors.white70,
                                    size: 28,
                                  ),
                                  onPressed: () => pp.toggleFavoriteArtist(_artist!),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          
          if (_artist!.topTracks.isNotEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Text(
                  "Top Tracks",
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final track = _artist!.topTracks[index];
                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: (track.thumbnailUrl?.isNotEmpty ?? false)
                        ? CachedNetworkImage(
                            imageUrl: track.thumbnailUrl!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) => Container(
                              width: 48, height: 48, color: Colors.grey[800],
                              child: const Icon(Icons.music_note, color: Colors.white54),
                            ),
                          )
                        : Container(
                            width: 48, height: 48, color: Colors.grey[800],
                            child: const Icon(Icons.music_note, color: Colors.white54),
                          ),
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
                      Consumer<PlaylistProvider>(
                        builder: (context, playlistProvider, _) {
                          final isFav = playlistProvider.isFavorite(track.id);
                          return IconButton(
                            icon: Icon(
                              isFav ? Icons.favorite : Icons.favorite_border,
                              color: isFav ? const Color(0xFFEAB308) : Colors.white54,
                              size: 20,
                            ),
                            onPressed: () {
                              playlistProvider.toggleFavorite(
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
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: TrackDownloadIcon(track: track, size: 20),
                      ),
                      Text(
                        formatDuration(track.duration),
                        style: const TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                  onTap: () => _playTrack(index),
                  onLongPress: () => TrackContextMenu.show(context, track),
                );
              },
              childCount: _artist!.topTracks.length,
            ),
          ),

          if (_artist!.albums.isNotEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 32, 16, 16),
                child: Text(
                  "Albums",
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ),

          if (_artist!.albums.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 220,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _artist!.albums.length,
                  itemBuilder: (context, index) {
                    final album = _artist!.albums[index];
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AlbumScreen(albumId: album.id),
                          ),
                        );
                      },
                      child: Container(
                        width: 140,
                        margin: const EdgeInsets.only(right: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: (album.thumbnailUrl?.isNotEmpty ?? false)
                                  ? CachedNetworkImage(
                                      imageUrl: album.thumbnailUrl!,
                                      width: 140,
                                      height: 140,
                                      fit: BoxFit.cover,
                                      errorWidget: (context, url, error) => Container(
                                        width: 140, height: 140, color: Colors.grey[800],
                                        child: const Icon(Icons.album, color: Colors.white54, size: 40),
                                      ),
                                    )
                                  : Container(
                                      width: 140, height: 140, color: Colors.grey[800],
                                      child: const Icon(Icons.album, color: Colors.white54, size: 40),
                                    ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              album.title,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (album.year != null)
                              Text(
                                album.year!,
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                                maxLines: 1,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          const SliverToBoxAdapter(
            child: SizedBox(height: 120), // Bottom padding for player
          ),
        ],
      ),
      extendBody: true,
      bottomNavigationBar: const BottomPlayer(),
    );
  }
}
