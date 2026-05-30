import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/entities/playlist.dart';
import '../../service/download_service.dart';

class DownloadProvider extends ChangeNotifier {
  final DownloadService _downloadService;

  DownloadProvider(this._downloadService);

  Set<String> _downloadedTrackIds = {};
  final Map<String, DownloadProgress> _activeDownloads = {};
  final Set<String> _downloadingPlaylists = {};

  Set<String> get downloadedTrackIds => _downloadedTrackIds;
  Map<String, DownloadProgress> get activeDownloads => _activeDownloads;
  Set<String> get downloadingPlaylists => _downloadingPlaylists;

  StreamSubscription? _progressSub;
  StreamSubscription? _completedSub;

  bool isDownloadingPlaylist(String playlistId) =>
      _downloadingPlaylists.contains(playlistId);

  DownloadProgress? getProgress(String trackId) => _activeDownloads[trackId];

  Future<void> init() async {
    _downloadedTrackIds = await _downloadService.getAllDownloadedIds();
    notifyListeners();
  }

  Future<void> downloadPlaylist(Playlist playlist) async {
    if (_downloadingPlaylists.contains(playlist.id)) return;

    _downloadingPlaylists.add(playlist.id);
    notifyListeners();

    _progressSub?.cancel();
    _completedSub?.cancel();

    _progressSub = _downloadService.progressStream.listen((progress) {
      _activeDownloads[progress.trackId] = progress;
      notifyListeners();
    });

    _completedSub = _downloadService.completedStream.listen((trackId) {
      _downloadedTrackIds.add(trackId);
      _activeDownloads.remove(trackId);
      notifyListeners();
    });

    await _downloadService.downloadPlaylist(playlist);

    _downloadingPlaylists.remove(playlist.id);
    _activeDownloads.clear();
    _progressSub?.cancel();
    _completedSub?.cancel();
    notifyListeners();
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
    _downloadService.dispose();
    super.dispose();
  }
}
