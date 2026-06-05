import 'dart:async';
import 'package:zyp_music/core/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/video.dart';
import '../../domain/entities/album.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../service/download_service.dart';
import '../../core/services/hybrid_cache_service.dart';

class DownloadProvider extends ChangeNotifier {
  final DownloadService _downloadService;
  final HybridCacheService _hybridCache;

  DownloadProvider(this._downloadService, this._hybridCache);

  Set<String> _downloadedTrackIds = {};
  final Map<String, DownloadProgress> _activeDownloads = {};
  final Set<String> _downloadingPlaylists = {};
  final Set<String> _downloadedPlaylists = {};
  final Map<String, double> _playlistDownloadProgress = {};

  Set<String> get downloadedTrackIds => _downloadedTrackIds;
  Map<String, DownloadProgress> get activeDownloads => _activeDownloads;
  Set<String> get downloadingPlaylists => _downloadingPlaylists;
  Set<String> get downloadedPlaylists => _downloadedPlaylists;
  Map<String, double> get playlistDownloadProgress => _playlistDownloadProgress;

  StreamSubscription? _progressSub;
  StreamSubscription? _completedSub;

  bool isDownloadingPlaylist(String playlistId) =>
      _downloadingPlaylists.contains(playlistId);

  bool isPlaylistFullyDownloaded(String playlistId) =>
      _downloadedPlaylists.contains(playlistId);

  bool isDownloaded(String trackId) => _downloadedTrackIds.contains(trackId);

  bool isDownloading(String trackId) => _activeDownloads.containsKey(trackId);

  double? getPlaylistDownloadProgress(String playlistId) =>
      _playlistDownloadProgress[playlistId];

  DownloadProgress? getProgress(String trackId) => _activeDownloads[trackId];

  Future<void> init() async {
    _downloadedTrackIds = await _downloadService.getAllDownloadedIds();
    _downloadedPlaylists.addAll(await _downloadService.getFullyDownloadedPlaylistIds());

    // Listen globally to progress & completed streams to sync single-track states.
    // `markCaching` fires the first time we see real bytes for a track; this
    // keeps the download icon spinner bound to the actual write loop instead
    // of a pre-flight placeholder, which fixes the indefinite-spinner bug.
    _downloadService.progressStream.listen((progress) {
      _activeDownloads[progress.trackId] = progress;
      if (progress.currentBytes > 0) {
        _hybridCache.markCaching(progress.trackId);
      }
      notifyListeners();
    });

    _downloadService.completedStream.listen((trackId) async {
      _downloadedTrackIds.add(trackId);
      _activeDownloads.remove(trackId);
      final localPath = await _downloadService.getLocalFilePath(trackId);
      if (localPath != null) {
        await _hybridCache.markSuccessAfterWrite(
          trackId,
          expectedFilePath: localPath,
        );
      } else {
        _hybridCache.markNotCaching(trackId);
      }
      notifyListeners();
    });

    _downloadService.errorStream.listen((_) {
      // On error, any tracks that were actively caching must clear the
      // transient state so the spinner stops looping.
      for (final id in _activeDownloads.keys.toList()) {
        _hybridCache.markNotCaching(id);
      }
    });

    notifyListeners();
  }

  Future<void> downloadPlaylist(Playlist playlist, {String quality = 'medium'}) async {
    if (_downloadingPlaylists.contains(playlist.id)) return;

    _downloadingPlaylists.add(playlist.id);
    _playlistDownloadProgress[playlist.id] = 0.0;
    notifyListeners();

    _progressSub?.cancel();
    _completedSub?.cancel();

    _progressSub = _downloadService.progressStream.listen((progress) {
      _activeDownloads[progress.trackId] = progress;
      if (progress.totalTracks > 0) {
        _playlistDownloadProgress[playlist.id] =
            (progress.tracksCompleted + progress.fraction) / progress.totalTracks;
      }
      notifyListeners();
    });

    _completedSub = _downloadService.completedStream.listen((trackId) {
      _downloadedTrackIds.add(trackId);
      _activeDownloads.remove(trackId);
      notifyListeners();
    });

    await _downloadService.downloadPlaylist(playlist, quality: quality);

    _downloadingPlaylists.remove(playlist.id);
    _playlistDownloadProgress.remove(playlist.id);
    final allDownloaded =
        playlist.tracks.every((t) => _downloadedTrackIds.contains(t.id));
    if (allDownloaded) {
      _downloadedPlaylists.add(playlist.id);
    }
    _activeDownloads.clear();
    _progressSub?.cancel();
    _completedSub?.cancel();
    notifyListeners();
  }

  Future<void> downloadTrack(Track track, String playlistId, {String quality = 'medium'}) async {
    if (_downloadedTrackIds.contains(track.id)) return;
    if (_activeDownloads.containsKey(track.id)) return;

    // Flip the cache state to `caching` on tap so the icon switches to the
    // spinner in the same frame the user pressed it. The byte stream (and
    // the error stream) gate the transition out of `caching` — see init().
    _hybridCache.markCaching(track.id);
    _activeDownloads[track.id] = DownloadProgress(
      trackId: track.id,
      trackTitle: track.title,
      currentBytes: 0,
      totalBytes: 0,
      tracksCompleted: 0,
      totalTracks: 1,
    );
    notifyListeners();

    try {
      await _downloadService.downloadTrack(track, playlistId, quality: quality);
    } catch (e) {
      _activeDownloads.remove(track.id);
      _hybridCache.markNotCaching(track.id);
      notifyListeners();
    }
  }

  Future<void> downloadAlbum(Album album, PlaylistProvider playlistProvider) async {
    if (_downloadingPlaylists.contains(album.id)) return;
    _downloadingPlaylists.add(album.id);
    _playlistDownloadProgress[album.id] = 0.0;
    notifyListeners();

    _progressSub?.cancel();
    _completedSub?.cancel();

    _progressSub = _downloadService.progressStream.listen((progress) {
      _activeDownloads[progress.trackId] = progress;
      if (progress.totalTracks > 0) {
        _playlistDownloadProgress[album.id] =
            (progress.tracksCompleted + progress.fraction) / progress.totalTracks;
      }
      notifyListeners();
    });

    _completedSub = _downloadService.completedStream.listen((trackId) {
      _downloadedTrackIds.add(trackId);
      _activeDownloads.remove(trackId);
      notifyListeners();
    });

    await _downloadService.downloadPlaylist(album.toPlaylist());

    _downloadingPlaylists.remove(album.id);
    _playlistDownloadProgress.remove(album.id);
    final allDownloaded =
        album.tracks.every((t) => _downloadedTrackIds.contains(t.id));
    if (allDownloaded) {
      _downloadedPlaylists.add(album.id);
    }
    _activeDownloads.clear();
    _progressSub?.cancel();
    _completedSub?.cancel();
    notifyListeners();
  }

  Future<void> preDownloadUpcoming(List<Track> queue, int currentIndex, String playlistId,
      {int prebufferCount = 3}) async {
    if (queue.isEmpty) return;
    final start = (currentIndex + 1).clamp(0, queue.length);
    final end = (start + prebufferCount).clamp(0, queue.length);
    final futures = <Future<void>>[];
    for (var i = start; i < end; i++) {
      final track = queue[i];
      if (_downloadedTrackIds.contains(track.id)) continue;
      if (_activeDownloads.containsKey(track.id)) continue;
      if (_hybridCache.isCached(track.id)) continue;
      futures.add(_downloadService.downloadTrack(track, playlistId)
          .catchError((e) => AppLogger.log('Pre-download failed for ${track.id}: $e', name: 'DownloadProvider')));
    }
    await Future.wait(futures);
  }

  void cancelDownload() {
    _downloadService.cancelDownload();
    _downloadingPlaylists.clear();
    _activeDownloads.clear();
    notifyListeners();
  }

  Future<bool> isTrackDownloaded(String trackId) async {
    return _downloadService.isTrackDownloaded(trackId);
  }

  Future<String?> getLocalFilePath(String trackId) async {
    return _downloadService.getLocalFilePath(trackId);
  }

  Future<void> deleteDownloadedPlaylist(String playlistId) async {
    await _downloadService.deleteDownloadedPlaylist(playlistId);
    await _refreshDownloadedIds();
    notifyListeners();
  }

  Future<void> deleteDownloadedTrack(String trackId) async {
    await _downloadService.deleteDownloadedTrack(trackId);
    await _refreshDownloadedIds();
    notifyListeners();
  }

  /// Removes [track] from every cache tier — the on-disk audio file,
  /// the lyrics file, the Hive tracker, and the SQLite
  /// `downloaded_tracks` row. Wires the dual-source state
  /// (provider-side `_downloadedTrackIds` and `HybridCacheService`
  /// mirror) back to the unsatisfied state. The single call into
  /// `HybridCacheService.removeTrackCompletely` is the source of
  /// truth for the purge pipeline; this method exists so context
  /// menus and any other UI can route through the standard provider
  /// notification path.
  Future<void> removeTrackFromCache(Track track) async {
    await _hybridCache.removeTrackCompletely(track.id);
    _downloadedTrackIds.remove(track.id);
    _activeDownloads.remove(track.id);
    notifyListeners();
  }

  /// Removes every downloadable track belonging to [album] from the
  /// cache. We iterate via the album's `tracks` list because there is
  /// no album-level aggregate in the SQLite schema — the unit of
  /// storage is the track. A album with no tracks falls back to the
  /// single placeholder `Track` synthesised in the album context
  /// menu, which is safe (removeTrackCompletely is idempotent).
  Future<int> removeAlbumFromCache(Album album) async {
    final ids = album.tracks.map((t) => t.id).toSet();
    int removed = 0;
    for (final id in ids) {
      if (_hybridCache.isCached(id) || _downloadedTrackIds.contains(id)) {
        await _hybridCache.removeTrackCompletely(id);
        _downloadedTrackIds.remove(id);
        _activeDownloads.remove(id);
        removed++;
      }
    }
    notifyListeners();
    return removed;
  }

  /// Returns true if any track in [album] is currently held in the
  /// cache (Hive tracker or SQLite row). The context menu uses this
  /// to decide whether to show the "Remove from Cache" entry.
  bool isAlbumCached(Album album) {
    for (final t in album.tracks) {
      if (_hybridCache.isCached(t.id)) return true;
      if (_downloadedTrackIds.contains(t.id)) return true;
    }
    return false;
  }

  Future<int> getTotalCacheSize() => _downloadService.getTotalCacheSize();

  Future<int> getPlaylistCacheSize(String playlistId) =>
      _downloadService.getPlaylistCacheSize(playlistId);

  Future<void> _refreshDownloadedIds() async {
    _downloadedTrackIds = await _downloadService.getAllDownloadedIds();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _completedSub?.cancel();
    _activeDownloads.clear();
    _downloadingPlaylists.clear();
    _playlistDownloadProgress.clear();
    _downloadService.dispose();
    super.dispose();
  }
}
