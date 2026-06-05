import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/hybrid_cache_service.dart';
import '../../domain/entities/video.dart';
import '../../presentation/providers/download_provider.dart';

/// Reactive track download control.
///
/// Tap flow (spec §1):
/// 1. Read `trackId` from the current item context.
/// 2. Check Hive via `hybridCache.isCached(trackId)` — the spec's
///    `box.containsKey(trackId)` semantic — AND the SQLite library
///    tier via `isDownloadedInSqlite(trackId)`. The checkmark state
///    must honour both sources (spec §5), so the tap is a no-op when
///    the track is already in either tier.
/// 3. If not cached, fire `downloadProvider.downloadTrack(...)` which
///    commits both the audio stream and the timed lyrics to the cache and
///    flips the cache state to `caching` in the same frame.
/// 4. If already cached, the tap is ignored (per the spec's "you may choose
///    to ignore the tap" allowance).
///
/// State machine (spec §2):
/// - idle    -> not in Hive, not in SQLite, no active stream
///              -> download outline icon
/// - caching -> transient `_activeCaching` set -> CircularProgressIndicator
/// - success -> in Hive AND `File.exists()`, **or** already in SQLite
///              -> static checkmark
///
/// The widget rebuilds on three signals:
/// - `HybridCacheService` `notifyListeners` (Provider Consumer)
/// - `HybridCacheService.stateStream` events filtered to this trackId
///   (Stateful subscription, so per-track transitions are not lost when
///   many tracks change state in the same frame)
/// - `DownloadProvider` `notifyListeners` (download start / finish)
class TrackDownloadIcon extends StatefulWidget {
  final Track track;
  final double size;
  final String? playlistId;

  const TrackDownloadIcon({
    super.key,
    required this.track,
    this.size = 24.0,
    this.playlistId,
  });

  @override
  State<TrackDownloadIcon> createState() => _TrackDownloadIconState();
}

class _TrackDownloadIconState extends State<TrackDownloadIcon> {
  StreamSubscription<CachedStateEvent>? _stateSub;
  String? _lastTrackId;

  @override
  void initState() {
    super.initState();
    _bindStream();
  }

  @override
  void didUpdateWidget(covariant TrackDownloadIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _bindStream();
    }
  }

  void _bindStream() {
    _stateSub?.cancel();
    _lastTrackId = widget.track.id;
    final cache = context.read<HybridCacheService>();
    _stateSub = cache.stateStream.listen((event) {
      if (!mounted) return;
      if (event.trackId != _lastTrackId) return;
      // setState is enough to force a rebuild of the Consumer2 below
      // because HybridCacheService is also wired into the same provider tree.
      setState(() {});
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    super.dispose();
  }

  /// Spec §5 dual-source check: a track is considered "already
  /// satisfied" if it is in the Hive transient box OR in the SQLite
  /// permanent library. The tap is a no-op in either case.
  bool _isAlreadyDownloaded(HybridCacheService cache) {
    if (cache.isCached(widget.track.id)) return true;
    if (cache.isDownloadedInSqlite(widget.track.id)) return true;
    return false;
  }

  void _onTap() {
    final cache = context.read<HybridCacheService>();
    final downloadProvider = context.read<DownloadProvider>();

    // Spec §1 + §5: bail out if the track is already in the Hive
    // transient box or the SQLite permanent library.
    if (_isAlreadyDownloaded(cache)) {
      return;
    }
    final playlistId = widget.playlistId ?? widget.track.id;
    downloadProvider.downloadTrack(widget.track, playlistId);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<DownloadProvider, HybridCacheService>(
      builder: (context, downloadProvider, hybridCache, _) {
        final state = hybridCache.getCachedState(widget.track.id);

        switch (state) {
          case CachedState.success:
            return Icon(
              Icons.check_circle,
              color: Colors.red,
              size: widget.size,
            );

          case CachedState.caching:
            return SizedBox(
              width: widget.size,
              height: widget.size,
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEAB308)),
              ),
            );

          case CachedState.idle:
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onTap,
              child: Icon(
                Icons.download_for_offline_outlined,
                color: Colors.white54,
                size: widget.size,
              ),
            );
        }
      },
    );
  }
}
