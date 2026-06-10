import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../../domain/entities/album.dart';
import '../../core/utils/format_duration.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/track_download_icon.dart';
import '../widgets/album_download_icon.dart';
import '../widgets/bottom_player.dart';
import '../../presentation/providers/download_provider.dart';
import "../../core/utils/thumbnail_url.dart";

class AlbumScreen extends StatefulWidget {
  final String albumId;

  const AlbumScreen({super.key, required this.albumId});

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  Album? _album;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAlbum();
  }

  Future<void> _loadAlbum() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final provider = context.read<PlaylistProvider>();
      final album = await provider.getAlbum(widget.albumId);
      setState(() {
        _album = album;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = "Failed to load album: $e";
        _isLoading = false;
      });
    }
  }

  void _playTrack(int index) {
    if (_album == null) return;
    final player = context.read<PlayerProvider>();
    player.setQueue(_album!.tracks);
    player.playFromQueue(index);
  }

  void _playAll() {
    if (_album == null || _album!.tracks.isEmpty) return;
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

    if (_error != null || _album == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(PhosphorIconsRegular.caretLeft, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: Text(
            _error ?? "Album not found.",
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
                  if (_album!.thumbnailUrl != null)
                    CachedNetworkImage(
                      imageUrl: rewriteThumbnailSize(_album!.thumbnailUrl, 1200),
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
                          _album!.title,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_album!.artistName ?? 'Unknown Artist'} • ${_album!.year ?? ''}',
                          style: const TextStyle(
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _playAll,
                              icon: const Icon(PhosphorIconsFill.play, color: Colors.black),
                              label: const Text("Play", style: TextStyle(color: Colors.black)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFEAB308),
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Favorite album button
                            Consumer<PlaylistProvider>(
                              builder: (context, pp, _) {
                                final isFav = pp.favoriteAlbums.any((a) => a.id == _album!.id);
                                return IconButton(
                                  icon: Icon(
                                    isFav ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                                    color: isFav ? Colors.red : Theme.of(context).colorScheme.onSurface.withOpacity(0.70),
                                    size: 28,
                                  ),
                                  onPressed: () => pp.toggleFavoriteAlbum(
                                    _album!,
                                    downloadProvider: context.read<DownloadProvider>(),
                                  ),
                                );
                              },
                            ),
                            // Download album button
                            AlbumDownloadIcon(album: _album!, size: 28),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            leading: IconButton(
              icon: Icon(PhosphorIconsRegular.caretLeft, color: Theme.of(context).colorScheme.onSurface),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 120),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = _album!.tracks[index];
                  return ListTile(
                    leading: SizedBox(
                      width: 40,
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                    title: Text(
                      track.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      track.author ?? 'Unknown Artist',
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
                                isFav ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                                color: isFav ? const Color(0xFFEAB308) : Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
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
                        TrackDownloadIcon(track: track, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          formatDuration(track.duration),
                        ),
                      ],
                    ),
                    onTap: () => _playTrack(index),
                    onLongPress: () => TrackContextMenu.show(context, track),
                  );
                },
                childCount: _album!.tracks.length,
              ),
            ),
          ),
        ],
      ),
      extendBody: true,
      bottomNavigationBar: const BottomPlayer(),
    );
  }
}
