import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../../domain/entities/playlist.dart';
import '../../core/utils/format_duration.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/bottom_player.dart';
import '../widgets/track_download_icon.dart';
import '../../presentation/providers/download_provider.dart';

class PlaylistScreen extends StatefulWidget {
  final String playlistId;

  const PlaylistScreen({super.key, required this.playlistId});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  Playlist? _playlist;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPlaylist();
  }

  Future<void> _loadPlaylist() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final provider = context.read<PlaylistProvider>();
      final playlist = await provider.getPlaylistFull(widget.playlistId);
      setState(() {
        _playlist = playlist;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = "Failed to load playlist: $e";
        _isLoading = false;
      });
    }
  }

  void _playTrack(int index) {
    if (_playlist == null) return;
    final player = context.read<PlayerProvider>();
    player.setQueue(_playlist!.tracks);
    player.playFromQueue(index);
  }

  void _playAll() {
    if (_playlist == null || _playlist!.tracks.isEmpty) return;
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

    if (_error != null || _playlist == null) {
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
            _error ?? "Playlist not found.",
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
                  if (_playlist!.thumbnailUrl != null)
                    CachedNetworkImage(
                      imageUrl: _playlist!.thumbnailUrl!,
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
                          _playlist!.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _playlist!.author ?? 'Unknown Author',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _playAll,
                          icon: const Icon(Icons.play_arrow, color: Colors.black),
                          label: const Text("Play", style: TextStyle(color: Colors.black)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEAB308),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          ),
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
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 120),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = _playlist!.tracks[index];
                  return ListTile(
                    leading: SizedBox(
                      width: 40,
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(color: Colors.white54, fontSize: 16),
                        ),
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
                        TrackDownloadIcon(track: track, size: 20),
                        const SizedBox(width: 8),
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
                childCount: _playlist!.tracks.length,
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
