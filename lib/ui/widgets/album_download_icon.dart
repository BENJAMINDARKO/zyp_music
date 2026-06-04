import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/hybrid_cache_service.dart';
import '../../domain/entities/album.dart';
import '../../domain/entities/video.dart';
import '../../presentation/providers/download_provider.dart';
import '../../presentation/providers/playlist_provider.dart';

/// Reactive album download control. Aggregate state is derived from the
/// per-track Hive entries inside [HybridCacheService].
///
/// State machine (spec §2 applied at album granularity):
/// - idle    -> at least one track is not in Hive -> idle icon
/// - caching -> a playlist-level download is in flight (byte stream active)
///              OR any per-track `_activeCaching` flag is set -> spinner
/// - success -> every track is in Hive (or playlist is fully downloaded)
///              -> static checkmark
class AlbumDownloadIcon extends StatefulWidget {
  final Album album;
  final double size;

  const AlbumDownloadIcon({super.key, required this.album, this.size = 24.0});

  @override
  State<AlbumDownloadIcon> createState() => _AlbumDownloadIconState();
}

class _AlbumDownloadIconState extends State<AlbumDownloadIcon> {
  StreamSubscription<CachedStateEvent>? _stateSub;
  List<String> _lastTrackIds = const <String>[];

  @override
  void initState() {
    super.initState();
    _bindStream();
  }

  @override
  void didUpdateWidget(covariant AlbumDownloadIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentIds = widget.album.tracks.map((t) => t.id).toList();
    if (!_listEquals(currentIds, _lastTrackIds)) {
      _bindStream();
    }
  }

  void _bindStream() {
    _stateSub?.cancel();
    _lastTrackIds = widget.album.tracks.map((t) => t.id).toList();
    final cache = context.read<HybridCacheService>();
    _stateSub = cache.stateStream.listen((event) {
      if (!mounted) return;
      // Rebuild on any per-track transition that affects this album.
      if (!_lastTrackIds.contains(event.trackId)) return;
      setState(() {});
    });
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    super.dispose();
  }

  CachedState _aggregateState(
    BuildContext context,
    DownloadProvider downloadProvider,
    HybridCacheService hybridCache,
  ) {
    if (downloadProvider.isDownloadingPlaylist(widget.album.id)) {
      return CachedState.caching;
    }
    if (widget.album.tracks.isNotEmpty &&
        widget.album.tracks
            .every((Track t) => hybridCache.isCached(t.id))) {
      return CachedState.success;
    }
    if (widget.album.tracks
        .any((Track t) => hybridCache.isActivelyCaching(t.id))) {
      return CachedState.caching;
    }
    return CachedState.idle;
  }

  void _onTap(BuildContext context) {
    final downloadProvider = context.read<DownloadProvider>();
    final hybridCache = context.read<HybridCacheService>();
    final state = _aggregateState(context, downloadProvider, hybridCache);
    if (state != CachedState.idle) return;
    final playlistProvider = context.read<PlaylistProvider>();
    downloadProvider.downloadAlbum(widget.album, playlistProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<DownloadProvider, HybridCacheService>(
      builder: (context, downloadProvider, hybridCache, _) {
        final state = _aggregateState(context, downloadProvider, hybridCache);
        final isFullyDownloaded =
            downloadProvider.isPlaylistFullyDownloaded(widget.album.id);

        Widget icon;
        switch (state) {
          case CachedState.caching:
            icon = SizedBox(
              width: widget.size,
              height: widget.size,
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFEAB308),
              ),
            );
            break;
          case CachedState.success:
            icon = Icon(
              isFullyDownloaded ? Icons.download_done : Icons.check_circle,
              color: Colors.red,
              size: widget.size,
            );
            break;
          case CachedState.idle:
            icon = Icon(
              Icons.download_for_offline,
              color: Colors.white54,
              size: widget.size,
            );
            break;
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _onTap(context),
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: icon,
          ),
        );
      },
    );
  }
}
