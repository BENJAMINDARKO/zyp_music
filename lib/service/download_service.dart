import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../data/datasources/local/playlist_database.dart';
import '../data/datasources/remote/youtube_remote_datasource.dart';
import '../domain/entities/playlist.dart';

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
  final YoutubeRemoteDataSource _remoteDataSource;
  final PlaylistDatabase _database;
  final http.Client _client = http.Client();

  final _progressController = StreamController<DownloadProgress>.broadcast();
  final _completedController = StreamController<String>.broadcast();

  Stream<DownloadProgress> get progressStream => _progressController.stream;
  Stream<String> get completedStream => _completedController.stream;

  bool _cancelled = false;

  DownloadService({
    required this._remoteDataSource,
    required this._database,
  });

  Future<String> _getDownloadDir(String playlistId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'downloads', playlistId));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  Future<void> downloadPlaylist(Playlist playlist) async {
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
        final audioUrl = await _remoteDataSource.getAudioUrl(track.id);
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

  Future<String> _resolveRedirects(String url) async {
    var current = url;
    for (var i = 0; i < 10; i++) {
      final req = http.Request('GET', Uri.parse(current));
      req.followRedirects = false;
      final resp = await _client.send(req);
      final status = resp.statusCode;
      await resp.stream.drain();
      if (status >= 300 && status < 400) {
        final location = resp.headers['location'];
        if (location == null) break;
        current = Uri.parse(location).isAbsolute
            ? location
            : Uri.parse(current).resolve(location).toString();
      } else {
        return current;
      }
    }
    return current;
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
  }
}
