import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../../domain/entities/artist.dart';
import '../widgets/track_context_menu.dart';
import 'album_screen.dart';
import '../widgets/track_download_icon.dart';
import '../../presentation/providers/download_provider.dart';
import "../../core/utils/thumbnail_url.dart";
import '../widgets/playing_track_mask.dart';
import '../widgets/explicit_icon.dart';

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

  Widget _buildBlurredBackground() {
    final hasImage = _artist?.thumbnailUrl != null;
    final baseColor = const Color(0xFF0A0A0A);

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: baseColor),
        if (hasImage) ...[
          CachedNetworkImage(
            imageUrl: rewriteThumbnailSize(_artist!.thumbnailUrl, 800),
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(color: baseColor),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Container(
                color: Colors.black.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPersistentHeader() {
    final hasImage = _artist!.thumbnailUrl != null;
    final stats = "${_artist!.albums.length} Album${_artist!.albums.length == 1 ? '' : 's'}";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title Bar
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    PhosphorIconsRegular.arrowLeft,
                    color: Theme.of(context).colorScheme.onSurface,
                    size: 24,
                  ),
                  onPressed: () {
                    if (_viewMode != _ArtistViewMode.dashboard) {
                      setState(() {
                        _viewMode = _ArtistViewMode.dashboard;
                      });
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 48.0),
                      child: Text(
                        "Artist's Profile",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Artist Card
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasImage)
                    CachedNetworkImage(
                      imageUrl: rewriteThumbnailSize(_artist!.thumbnailUrl, 1200),
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Colors.grey[900],
                        child: const Center(
                          child: CircularProgressIndicator(color: Color(0xFFEAB308)),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: Colors.grey[900],
                        child: const Icon(PhosphorIconsRegular.user, size: 64, color: Colors.white24),
                      ),
                    )
                  else
                    Container(
                      color: Colors.grey[900],
                      child: const Icon(PhosphorIconsRegular.user, size: 64, color: Colors.white24),
                    ),
                  // Dark translucent gradient overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.3),
                          Colors.black.withValues(alpha: 0.8),
                        ],
                      ),
                    ),
                  ),
                  // Artist Name & Stats Overlay
                  Positioned(
                    bottom: 20,
                    left: 16,
                    right: 16,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _artist!.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                offset: Offset(0, 2),
                                blurRadius: 4,
                                color: Colors.black54,
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          stats,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            shadows: const [
                              Shadow(
                                offset: Offset(0, 1),
                                blurRadius: 2,
                                color: Colors.black54,
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildDashboardSlivers() {
    final topTracks = _artist!.topTracks.take(3).toList();
    final albums = _artist!.albums;

    return [
      if (topTracks.isNotEmpty) ...[
        // Top Songs Header Row
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Top Songs",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _viewMode = _ArtistViewMode.allSongs;
                    });
                  },
                  child: Text(
                    "See All",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Top Songs List (3 tracks)
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final track = topTracks[index];
              return PlayingTrackMask(
                track: track,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  leading: ClipOval(
                    child: (track.thumbnailUrl?.isNotEmpty ?? false)
                        ? CachedNetworkImage(
                            imageUrl: rewriteThumbnailSize(track.thumbnailUrl, 200),
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              width: 48,
                              height: 48,
                              color: Colors.grey[850],
                              child: const Icon(PhosphorIconsRegular.musicNote, size: 20, color: Colors.white30),
                            ),
                          )
                        : Container(
                            width: 48,
                            height: 48,
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
                    '${track.title} - ${track.author ?? _artist!.name}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TrackDownloadIcon(track: track, size: 20),
                      const SizedBox(width: 16),
                      Consumer<PlaylistProvider>(
                        builder: (context, playlistProvider, _) {
                          final isFav = playlistProvider.isFavorite(track.id);
                          return IconButton(
                            icon: Icon(
                              isFav ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                              color: isFav ? const Color(0xFF22C55E) : Colors.white.withValues(alpha: 0.5),
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
            childCount: topTracks.length,
          ),
        ),
      ],
      if (albums.isNotEmpty) ...[
        // Top Albums Header Row
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Top Albums",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _viewMode = _ArtistViewMode.allAlbums;
                    });
                  },
                  child: Text(
                    "See All",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Horizontal Albums list (using circular artwork)
        SliverToBoxAdapter(
          child: SizedBox(
            height: 145,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
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
                    width: 100,
                    margin: const EdgeInsets.only(right: 20),
                    child: Column(
                      children: [
                        ClipOval(
                          child: (album.thumbnailUrl?.isNotEmpty ?? false)
                              ? CachedNetworkImage(
                                  imageUrl: rewriteThumbnailSize(album.thumbnailUrl, 200),
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) => Container(
                                    width: 100,
                                    height: 100,
                                    color: Colors.grey[850],
                                    child: const Icon(PhosphorIconsRegular.discoBall, size: 28, color: Colors.white30),
                                  ),
                                )
                              : Container(
                                  width: 100,
                                  height: 100,
                                  color: Colors.grey[850],
                                  child: const Icon(PhosphorIconsRegular.discoBall, size: 28, color: Colors.white30),
                                ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          album.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildAllSongsSlivers() {
    final topTracks = _artist!.topTracks;

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          child: Row(
            children: [
              Text(
                "All Songs",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "(${topTracks.length})",
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                ),
              ),
            ],
          ),
        ),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final track = topTracks[index];
            return PlayingTrackMask(
              track: track,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                leading: ClipOval(
                  child: (track.thumbnailUrl?.isNotEmpty ?? false)
                      ? CachedNetworkImage(
                          imageUrl: rewriteThumbnailSize(track.thumbnailUrl, 200),
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
                  '${track.author ?? _artist!.name} - ${track.album ?? ""}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
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
                            color: isFav ? const Color(0xFF22C55E) : Colors.white.withValues(alpha: 0.5),
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
          childCount: topTracks.length,
        ),
      ),
    ];
  }

  List<Widget> _buildAllAlbumsSlivers() {
    final albums = _artist!.albums;

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          child: Row(
            children: [
              Text(
                "All Albums",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "(${albums.length})",
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                ),
              ),
            ],
          ),
        ),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final album = albums[index];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: (album.thumbnailUrl?.isNotEmpty ?? false)
                    ? CachedNetworkImage(
                        imageUrl: rewriteThumbnailSize(album.thumbnailUrl, 200),
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          width: 56,
                          height: 56,
                          color: Colors.grey[850],
                          child: const Icon(PhosphorIconsRegular.discoBall, size: 24, color: Colors.white30),
                        ),
                      )
                    : Container(
                        width: 56,
                        height: 56,
                        color: Colors.grey[850],
                        child: const Icon(PhosphorIconsRegular.discoBall, size: 24, color: Colors.white30),
                      ),
              ),
              title: Text(
                album.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                album.year ?? 'Unknown Year',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              trailing: Icon(
                PhosphorIconsRegular.caretRight,
                color: Colors.white.withValues(alpha: 0.5),
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
          childCount: albums.length,
        ),
      ),
    ];
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

    if (_error != null || _artist == null) {
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
            _error ?? "Artist not found.",
            style: const TextStyle(color: Colors.red),
          ),
        ),
        extendBody: true,
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
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildBlurredBackground(),
            CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _buildPersistentHeader(),
                ),
                ...dynamicSlivers,
                const SliverToBoxAdapter(
                  child: SizedBox(height: 120), // Bottom padding for player
                ),
              ],
            ),
          ],
        ),
        extendBody: true,
      ),
    );
  }
}
