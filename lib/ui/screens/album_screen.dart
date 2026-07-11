import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../../domain/entities/album.dart';
import '../../core/utils/format_duration.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/track_download_icon.dart';
import '../widgets/album_download_icon.dart';
import '../widgets/track_export_icon.dart';
import '../widgets/album_export_icon.dart';
import '../widgets/bottom_player.dart';
import '../../presentation/providers/download_provider.dart';
import "../../core/utils/thumbnail_url.dart";
import '../widgets/playing_track_mask.dart';
import '../widgets/explicit_icon.dart';

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
  Color? _themeColor;

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
      if (album.thumbnailUrl != null) {
        _extractColor(album.thumbnailUrl);
      }
    } catch (e) {
      setState(() {
        _error = "Failed to load album: $e";
        _isLoading = false;
      });
    }
  }

  Future<void> _extractColor(String? url) async {
    if (url == null || url.isEmpty) return;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(rewriteThumbnailSize(url, 400)),
        maximumColorCount: 5,
      );
      if (mounted) {
        setState(() {
          _themeColor = palette.dominantColor?.color ?? palette.vibrantColor?.color;
        });
      }
    } catch (_) {}
  }

  void _playTrack(int index) {
    if (_album == null) return;
    final player = context.read<PlayerProvider>();
    player.playQueueWithNewSession(_album!.tracks, startIndex: index, playlistId: _album!.id);
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
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background cover art
          if (_album!.thumbnailUrl != null)
            CachedNetworkImage(
              imageUrl: rewriteThumbnailSize(_album!.thumbnailUrl, 1200),
              fit: BoxFit.cover,
            ),
          // Dark gradient overlay spanning the entire screen
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.2),
                  Colors.black.withOpacity(0.5),
                  Colors.black.withOpacity(0.85),
                  Colors.black.withOpacity(0.95),
                ],
              ),
            ),
          ),
          // Main scrollable content
          CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.black.withOpacity(0.85), // collapsed color
                elevation: 0,
                expandedHeight: 320,
                pinned: true,
                centerTitle: true,
                title: const Text(
                  'Album',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.white,
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(PhosphorIconsRegular.queue, color: Colors.white),
                    onPressed: () {
                      final player = context.read<PlayerProvider>();
                      player.appendToQueue(_album!.tracks);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Added ${_album!.tracks.length} tracks to queue')),
                      );
                    },
                  ),
                ],
                leading: IconButton(
                  icon: Icon(PhosphorIconsRegular.arrowLeft, color: Theme.of(context).colorScheme.onSurface),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Center play button
                      Align(
                        alignment: Alignment.center,
                        child: GestureDetector(
                          onTap: _playAll,
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: (_themeColor ?? const Color(0xFFE91E63)).withOpacity(0.65),
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              PhosphorIconsFill.play,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                      // Bottom Left: Album Favourite (A love)
                      Positioned(
                        bottom: 12,
                        left: 16,
                        child: Consumer<PlaylistProvider>(
                          builder: (context, provider, _) {
                            final isFavorite = provider.isAlbumFavorite(_album!.id);
                            return IconButton(
                              icon: Icon(
                                isFavorite ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                                color: isFavorite ? Colors.red : Colors.white,
                                size: 28,
                              ),
                              onPressed: () => provider.toggleFavoriteAlbum(
                                _album!,
                                downloadProvider: context.read<DownloadProvider>(),
                              ),
                            );
                          },
                        ),
                      ),
                      // Bottom Center: Album Title
                      Positioned(
                        bottom: 24, // vertical center offset alignment
                        left: 64,
                        right: 64,
                        child: Text(
                          _album!.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: Colors.black87,
                                offset: Offset(0, 2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Bottom Right: Download Icon
                      Positioned(
                        bottom: 16,
                        right: 20,
                        child: AlbumDownloadIcon(album: _album!, size: 28),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 120),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final track = _album!.tracks[index];
                      return PlayingTrackMask(
                        track: track,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: (_album!.thumbnailUrl != null)
                                ? CachedNetworkImage(
                                    imageUrl: rewriteThumbnailSize(_album!.thumbnailUrl, 200),
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(
                                      width: 40,
                                      height: 40,
                                      color: Colors.grey[850],
                                      child: const Icon(PhosphorIconsRegular.musicNote, size: 20, color: Colors.white30),
                                    ),
                                  )
                                : Container(
                                    width: 40,
                                    height: 40,
                                    color: Colors.grey[850],
                                    child: const Icon(PhosphorIconsRegular.musicNote, size: 20, color: Colors.white30),
                                  ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  track.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (track.isExplicit) const ExplicitIcon(),
                            ],
                          ),
                          subtitle: Text(
                            '${track.author ?? 'Unknown Artist'} - ${_album!.title}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TrackDownloadIcon(track: track, size: 20),
                              const SizedBox(width: 12),
                              Consumer<PlaylistProvider>(
                                builder: (context, playlistProvider, _) {
                                  final isFav = playlistProvider.isFavorite(track.id);
                                  return IconButton(
                                    icon: Icon(
                                      isFav ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                                      color: isFav ? const Color(0xFF22C55E) : Colors.white.withOpacity(0.5),
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
                            ],
                          ),
                          onTap: () => _playTrack(index),
                          onLongPress: () => TrackContextMenu.show(context, track),
                        ),
                      );
                    },
                    childCount: _album!.tracks.length,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      extendBody: true,
    );
  }
}
