import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../../presentation/providers/download_provider.dart';
import '../../domain/entities/artist.dart';
import '../../core/utils/thumbnail_url.dart';
import '../../core/theme/app_theme.dart';

import '../widgets/global_background.dart';
import '../widgets/aurora_glass.dart';
import '../widgets/prism_loader.dart';
import '../widgets/library/detail_track_row.dart';
import '../widgets/library/artist_hero.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/track_download_icon.dart';
import '../widgets/playing_track_mask.dart';
import '../widgets/explicit_icon.dart';
import 'album_screen.dart';

enum _ArtistViewMode {
  dashboard,
  allSongs,
  allAlbums,
}

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
  _ArtistViewMode _viewMode = _ArtistViewMode.dashboard;

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
    final track = _artist!.topTracks[index];
    player.playTrackWithNewSession(track);
  }

  void _playAll() {
    if (_artist == null || _artist!.topTracks.isEmpty) return;
    final player = context.read<PlayerProvider>();
    player.playQueueWithNewSession(_artist!.topTracks, startIndex: 0, playlistId: _artist!.id);
  }

  Widget _buildPersistentHeader() {
    if (_viewMode != _ArtistViewMode.dashboard) {
      // Small simple header when viewing all songs or all albums
      return SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(PhosphorIconsRegular.caretLeft, color: Colors.white, size: 24),
                onPressed: () {
                  setState(() {
                    _viewMode = _ArtistViewMode.dashboard;
                  });
                },
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 48.0),
                  child: Text(
                    _viewMode == _ArtistViewMode.allSongs ? 'All Songs' : 'All Albums',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Otherwise, render our beautiful ArtistHero
    return ArtistHero(
      artist: _artist!,
      onPlayAll: _playAll,
      onBack: () => Navigator.of(context).pop(),
      onMore: () {
        // Toggle follow
        context.read<PlaylistProvider>().toggleFavoriteArtist(_artist!);
      },
    );
  }

  List<Widget> _buildDashboardSlivers() {
    final topTracks = _artist!.topTracks.take(5).toList();
    final albums = _artist!.albums;

    return [
      // 1. Top Songs Header
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Top Songs",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70),
              ),
              if (_artist!.topTracks.length > 5)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _viewMode = _ArtistViewMode.allSongs;
                    });
                  },
                  child: const Text(
                    "See All",
                    style: TextStyle(
                      color: ZypAuroraColors.cyan,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      // Top Songs List (glass rows)
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final track = topTracks[index];
              return DetailTrackRow(
                index: index + 1,
                track: track,
                onTap: () => _playTrack(index),
              );
            },
            childCount: topTracks.length,
          ),
        ),
      ),

      // 2. Top Albums Header
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Top Albums",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70),
              ),
              if (albums.length > 3)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _viewMode = _ArtistViewMode.allAlbums;
                    });
                  },
                  child: const Text(
                    "See All",
                    style: TextStyle(
                      color: ZypAuroraColors.cyan,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      // Horizontal circular album rail
      SliverToBoxAdapter(
        child: SizedBox(
          height: 155,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: albums.length,
            itemBuilder: (context, index) {
              final album = albums[index];
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
                  width: 96,
                  margin: const EdgeInsets.only(right: 14),
                  child: Column(
                    children: [
                      // Circular album cover with soft shadows and glow
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: ZypAuroraColors.cyan.withOpacity(0.2),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: (album.thumbnailUrl?.isNotEmpty ?? false)
                              ? CachedNetworkImage(
                                  imageUrl: rewriteThumbnailSize(album.thumbnailUrl, 200),
                                  width: 90,
                                  height: 90,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => _fallbackAlbumCoverCircular(),
                                )
                              : _fallbackAlbumCoverCircular(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        album.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        album.year ?? '',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: Colors.white.withOpacity(0.48),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildAllSongsSlivers() {
    final topTracks = _artist!.topTracks;

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final track = topTracks[index];
              return DetailTrackRow(
                index: index + 1,
                track: track,
                onTap: () => _playTrack(index),
              );
            },
            childCount: topTracks.length,
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildAllAlbumsSlivers() {
    final albums = _artist!.albums;

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final album = albums[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: GestureDetector(
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
                    padding: const EdgeInsets.all(9),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: (album.thumbnailUrl?.isNotEmpty ?? false)
                              ? CachedNetworkImage(
                                  imageUrl: rewriteThumbnailSize(album.thumbnailUrl, 150),
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => _fallbackAlbumCoverSquare(),
                                )
                              : _fallbackAlbumCoverSquare(),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                album.title,
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                album.year ?? 'Unknown Year',
                                style: TextStyle(color: Colors.white.withOpacity(0.58), fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const Icon(PhosphorIconsRegular.caretRight, color: Colors.white30),
                      ],
                    ),
                  ),
                ),
              );
            },
            childCount: albums.length,
          ),
        ),
      ),
    ];
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
              title: 'Loading Profile',
              subtitle: 'Analyzing artist signals and top tracks...',
            ),
          ],
        ),
      );
    }

    if (_error != null || _artist == null) {
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
                        _error ?? "Artist not found.",
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

    List<Widget> dynamicSlivers;
    switch (_viewMode) {
      case _ArtistViewMode.dashboard:
        dynamicSlivers = _buildDashboardSlivers();
        break;
      case _ArtistViewMode.allSongs:
        dynamicSlivers = _buildAllSongsSlivers();
        break;
      case _ArtistViewMode.allAlbums:
        dynamicSlivers = _buildAllAlbumsSlivers();
        break;
    }

    return PopScope(
      canPop: _viewMode == _ArtistViewMode.dashboard,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        setState(() {
          _viewMode = _ArtistViewMode.dashboard;
        });
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const GlobalBackground(),
            SafeArea(
              bottom: false,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _buildPersistentHeader(),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                  ...dynamicSlivers,
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 120), // Bottom padding for player
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackAlbumCoverCircular() {
    return Container(
      color: Colors.white.withOpacity(0.08),
      child: const Icon(PhosphorIconsRegular.discoBall, color: Colors.white30, size: 24),
    );
  }

  Widget _fallbackAlbumCoverSquare() {
    return Container(
      width: 50,
      height: 50,
      color: Colors.white.withOpacity(0.08),
      child: const Icon(PhosphorIconsRegular.discoBall, color: Colors.white30, size: 20),
    );
  }
}
