import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../../presentation/providers/download_provider.dart';
import '../../domain/entities/album.dart';
import '../../core/utils/thumbnail_url.dart';
import '../../core/theme/app_theme.dart';

import '../widgets/global_background.dart';
import '../widgets/aurora_glass.dart';
import '../widgets/prism_loader.dart';
import '../widgets/library/detail_track_row.dart';
import '../widgets/library/album_hero.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/track_download_icon.dart';
import '../widgets/playing_track_mask.dart';

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

  void _showAlbumOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: ZypAuroraColors.glass,
      barrierColor: Colors.black26,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => AuroraGlass(
        borderRadius: 28,
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(PhosphorIconsRegular.queue, color: Colors.white),
                title: const Text('Add Album to Queue', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.read<PlayerProvider>().appendToQueue(_album!.tracks);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Added ${_album!.tracks.length} tracks to queue')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(PhosphorIconsRegular.downloadSimple, color: Colors.white),
                title: const Text('Download Album', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.read<DownloadProvider>().downloadAlbum(_album!, context.read<PlaylistProvider>());
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Starting album download...')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(PhosphorIconsRegular.heart, color: Colors.white),
                title: const Text('Favorite Album', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.read<PlaylistProvider>().toggleFavoriteAlbum(
                    _album!,
                    downloadProvider: context.read<DownloadProvider>(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: ZypAuroraColors.ink,
        body: Stack(
          children: [
            GlobalBackground(),
            PrismLoader(
              title: 'Reading Album',
              subtitle: 'Analyzing tracks, extracting year, and caching artwork...',
            ),
          ],
        ),
      );
    }

    if (_error != null || _album == null) {
      return Scaffold(
        backgroundColor: ZypAuroraColors.ink,
        body: Stack(
          children: [
            const GlobalBackground(),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    icon: const Icon(PhosphorIconsRegular.caretLeft, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        _error ?? "Album not found.",
                        style: const TextStyle(color: Colors.red, fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Blurs and Gradients Backdrop based on Album art dominant color
          if (_album!.thumbnailUrl != null) ...[
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: rewriteThumbnailSize(_album!.thumbnailUrl, 1200),
                fit: BoxFit.cover,
              ),
            ),
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 45.0, sigmaY: 45.0),
                child: const SizedBox.shrink(),
              ),
            ),
            Positioned.fill(
              child: _themeColor != null
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            _themeColor!.withOpacity(0.65),
                            _themeColor!.withOpacity(0.2),
                            ZypAuroraColors.ink.withOpacity(0.9),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    )
                  : ColoredBox(color: Colors.black.withOpacity(0.75)),
            ),
          ] else ...[
            const GlobalBackground(),
          ],

          // 2. Main Scrollable Content
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                // Album Header Hero Card
                SliverToBoxAdapter(
                  child: AlbumHero(
                    album: _album!,
                    onPlayAll: _playAll,
                    onBack: () => Navigator.of(context).pop(),
                    onMore: () => _showAlbumOptions(context),
                  ),
                ),
                
                // Track list (glass rows)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final track = _album!.tracks[index];
                        return PlayingTrackMask(
                          track: track,
                          child: DetailTrackRow(
                            index: index + 1,
                            track: track,
                            onTap: () => _playTrack(index),
                          ),
                        );
                      },
                      childCount: _album!.tracks.length,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
