import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../core/utils/network_utils.dart';
import '../data/datasources/local/playlist_database.dart';
import '../data/datasources/remote/youtube_remote_datasource.dart';
import '../domain/entities/playlist.dart';
import '../domain/entities/video.dart';

class DownloadProgress {
  final String trackId;
  final String trackTitle;
  final int currentBytes;
  final int totalBytes;
  final int tracksCompleted;
  final int totalTracks;

  DownloadProgress({
    required this.trackId,
    required this.trackTitle,
    required this.currentBytes,
    required this.totalBytes,
    this.tracksCompleted = 0,
    this.totalTracks = 0,
  });

  double get fraction => totalBytes > 0 ? currentBytes / totalBytes : 0.0;
}

class DownloadService {
  late final YoutubeRemoteDataSource _remoteDataSource;
  late final PlaylistDatabase _database;
  final http.Client _client = http.Client();

  final _progressController = StreamController<DownloadProgress>.broadcast();
  final _completedController = StreamController<String>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  Stream<DownloadProgress> get progressStream => _progressController.stream;
  Stream<String> get completedStream => _completedController.stream;
  Stream<String> get errorStream => _errorController.stream;

  bool _cancelled = false;

  DownloadService({
    required YoutubeRemoteDataSource remoteDataSource,
    required PlaylistDatabase database,
  }) {
    _remoteDataSource = remoteDataSource;
    _database = database;
  }

  DownloadService.test() {
    // Test subclasses override all methods that use these fields.
  }

  Future<String> _getDownloadDir(String playlistId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'downloads', playlistId));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  Future<void> downloadTrack(Track track, String playlistId, {String quality = 'medium'}) async {
    if (await _database.isTrackDownloaded(track.id)) return;
    final dir = await _getDownloadDir(playlistId);
    final filePath = p.join(dir, '${track.id}.mp4');

    try {
      final audioUrl = await _remoteDataSource.getAudioUrl(track.id, quality: quality);
      final resolved = await _resolveRedirects(audioUrl);
      await _downloadFile(resolved, filePath, track, 0, 1);
      await _database.markTrackDownloaded(
        track.id,
        playlistId,
        filePath,
        title: track.title,
        thumbnailUrl: track.thumbnailUrl,
        durationSeconds: track.duration.inSeconds,
        author: track.author,
      );
      _completedController.add(track.id);
    } catch (e) {
      _errorController.add('Failed to download ${track.title}: $e');
      _progressController.add(DownloadProgress(
        trackId: track.id,
        trackTitle: track.title,
        currentBytes: 0,
        totalBytes: 0,
        tracksCompleted: 0,
        totalTracks: 1,
      ));
    }
  }

  Future<void> downloadPlaylist(Playlist playlist, {String quality = 'medium'}) async {
    _cancelled = false;
    final dir = await _getDownloadDir(playlist.id);
    final tracks = playlist.tracks;
    final total = tracks.length;

    for (var i = 0; i < total; i++) {
      if (_cancelled) break;
      final track = tracks[i];
      final filePath = p.join(dir, '${track.id}.mp4');

      if (await _database.isTrackDownloaded(track.id)) continue;

      try {
        final audioUrl = await _remoteDataSource.getAudioUrl(track.id, quality: quality);
        final resolved = await _resolveRedirects(audioUrl);
        await _downloadFile(resolved, filePath, track, i, total);
        await _database.markTrackDownloaded(
          track.id,
          playlist.id,
          filePath,
          title: track.title,
          thumbnailUrl: track.thumbnailUrl,
          durationSeconds: track.duration.inSeconds,
          author: track.author,
        );
        _completedController.add(track.id);
      } catch (e) {
        _errorController.add('Failed to download ${track.title}: $e');
        _progressController.add(DownloadProgress(
          trackId: track.id,
          trackTitle: track.title,
          currentBytes: 0,
          totalBytes: 0,
          tracksCompleted: i,
          totalTracks: total,
        ));
      }
    }
  }

  Future<void> _downloadFile(String url, String filePath, dynamic track,
      int trackIndex, int total) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request);
    final contentLength = response.contentLength ?? 0;
    final file = File(filePath);
    final sink = file.openWrite();
    var received = 0;

    await for (final chunk in response.stream) {
      if (_cancelled) {
        await sink.close();
        await file.delete();
        return;
      }
      sink.add(chunk);
      received += chunk.length;
      _progressController.add(DownloadProgress(
        trackId: track.id,
        trackTitle: track.title,
        currentBytes: received,
        totalBytes: contentLength,
        tracksCompleted: trackIndex,
        totalTracks: total,
      ));
    }
    await sink.close();
  }

  Future<String> _resolveRedirects(String url) {
    return NetworkUtils.resolveRedirects(_client, url);
  }

  void cancelDownload() {
    _cancelled = true;
  }

  Future<bool> isTrackDownloaded(String trackId) async {
    return _database.isTrackDownloaded(trackId);
  }

  Future<String?> getLocalFilePath(String trackId) async {
    return _database.getDownloadedFilePath(trackId);
  }

  Future<Set<String>> getAllDownloadedIds() async {
    return _database.getAllDownloadedTrackIds();
  }

  Future<Set<String>> getFullyDownloadedPlaylistIds() async {
    return _database.getFullyDownloadedPlaylistIds();
  }

  Future<void> deleteDownloadedPlaylist(String playlistId) async {
    final paths = await _database.getDownloadedFilePaths(playlistId);
    for (final path in paths) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
    await _database.removeDownloadedPlaylist(playlistId);
  }

  void dispose() {
    _client.close();
    _progressController.close();
    _completedController.close();
    _errorController.close();
  }
}
