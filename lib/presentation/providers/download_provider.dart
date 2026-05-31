import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/video.dart';
import '../../service/download_service.dart';

class DownloadProvider extends ChangeNotifier {
  final DownloadService _downloadService;

  DownloadProvider(this._downloadService);

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

  double? getPlaylistDownloadProgress(String playlistId) =>
      _playlistDownloadProgress[playlistId];

  DownloadProgress? getProgress(String trackId) => _activeDownloads[trackId];

  Future<void> init() async {
    _downloadedTrackIds = await _downloadService.getAllDownloadedIds();
    _downloadedPlaylists.addAll(await _downloadService.getFullyDownloadedPlaylistIds());
    notifyListeners();
  }

  Future<void> downloadPlaylist(Playlist playlist) async {
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

    await _downloadService.downloadPlaylist(playlist);

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

  Future<void> downloadTrack(Track track, String playlistId) async {
    if (_downloadedTrackIds.contains(track.id)) return;
    if (_activeDownloads.containsKey(track.id)) return;
    await _downloadService.downloadTrack(track, playlistId);
  }

  Future<void> preDownloadUpcoming(List<Track> queue, int currentIndex, String playlistId) async {
    if (queue.isEmpty) return;
    final start = (currentIndex + 1).clamp(0, queue.length);
    final end = (start + 3).clamp(0, queue.length);
    for (var i = start; i < end; i++) {
      final track = queue[i];
      if (_downloadedTrackIds.contains(track.id)) continue;
      if (_activeDownloads.containsKey(track.id)) continue;
      try {
        await _downloadService.downloadTrack(track, playlistId);
      } catch (e) {
        dev.log('Pre-download failed for ${track.id}: $e', name: 'DownloadProvider');
      }
    }
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
