import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../core/utils/network_utils.dart';
import '../core/services/audio_cache_service.dart';
import '../data/datasources/local/playlist_database.dart';
import '../domain/repositories/audio_repository.dart';
import '../domain/entities/playlist.dart';
import '../domain/entities/video.dart';
import '../presentation/providers/settings_provider.dart';
import 'package:audiotags/audiotags.dart';
import 'dart:typed_data';

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
  late final AudioRepository _audioRepository;
  late final PlaylistDatabase _database;
  late final SettingsProvider? _settingsProvider;
  /// Optional C2 backfill hook. Injected from `main.dart` so
  /// the same `AudioCacheService` singleton used by
  /// `AudioRepositoryImpl`'s `onCacheSuccess` hook also fires
  /// from the explicit download path. Nullable for unit
  /// tests that don't exercise the duration-probe path; the
  /// backfill call is skipped via `?.` in that case.
  late final AudioCacheService? _cacheService;
  final http.Client _client = http.Client();

  final _progressController = StreamController<DownloadProgress>.broadcast();
  final _completedController = StreamController<String>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  Stream<DownloadProgress> get progressStream => _progressController.stream;
  Stream<String> get completedStream => _completedController.stream;
  Stream<String> get errorStream => _errorController.stream;

  final _exportProgressController = StreamController<DownloadProgress>.broadcast();
  final _exportCompletedController = StreamController<String>.broadcast();
  final _exportErrorController = StreamController<String>.broadcast();

  Stream<DownloadProgress> get exportProgressStream => _exportProgressController.stream;
  Stream<String> get exportCompletedStream => _exportCompletedController.stream;
  Stream<String> get exportErrorStream => _exportErrorController.stream;

  bool _cancelled = false;

  DownloadService({
    required AudioRepository audioRepository,
    required PlaylistDatabase database,
    SettingsProvider? settingsProvider,
    AudioCacheService? cacheService,
  }) {
    _audioRepository = audioRepository;
    _database = database;
    _settingsProvider = settingsProvider;
    _cacheService = cacheService;
  }

  DownloadService.test() {
    // Test subclasses override all methods that use these fields.
  }

  Future<String> _getDownloadDir(String playlistId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final basePath = p.join(appDir.path, 'downloads');
    
    final dir = Directory(p.join(basePath, playlistId));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  Future<String> get _exportDir async {
    if (_settingsProvider != null && _settingsProvider!.androidDownloadFolder.isNotEmpty) {
      if (Platform.isAndroid) {
        if (await Permission.manageExternalStorage.isDenied) {
          await Permission.manageExternalStorage.request();
        }
        if (await Permission.storage.isDenied) {
          await Permission.storage.request();
        }
      }
      final folderPath = _settingsProvider!.androidDownloadFolder;
      if (folderPath.startsWith('content://')) {
        _settingsProvider!.setStringSetting('androidDownloadFolder', '');
      } else {
        final dir = Directory(folderPath);
        if (!dir.existsSync()) dir.createSync(recursive: true);
        return dir.path;
      }
    }
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'exports'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  Future<bool> isExported(Track track) async {
    final dir = await _exportDir;
    final safeTitle = _sanitizeFilename(track.title ?? track.id);
    final safeArtist = _sanitizeFilename(track.author ?? 'Unknown');
    if (File(p.join(dir, '$safeArtist - $safeTitle.m4a')).existsSync()) return true;
    if (File(p.join(dir, '$safeArtist - $safeTitle.flac')).existsSync()) return true;
    return false;
  }

  Future<void> exportTrack(Track track, {String quality = 'medium'}) async {
    if (track.id.startsWith('local_')) return;
    if (await isExported(track)) return;
    
    final safeTitle = _sanitizeFilename(track.title ?? track.id);
    final safeArtist = _sanitizeFilename(track.author ?? 'Unknown');
    final ext = quality.toLowerCase().contains('flac') ? '.flac' : '.m4a';
    final fileName = '$safeArtist - $safeTitle$ext';

    try {
      final dir = await _exportDir;
      final filePath = p.join(dir, fileName);
      final audioUrl = await _audioRepository.getAudioUrl(
        track,
        quality: quality,
      );
      final resolved = await _resolveRedirects(audioUrl);
      await _downloadFile(resolved, filePath, track, 0, 1, isExport: true);
      _exportCompletedController.add(track.id);
    } catch (e) {
      _exportErrorController.add('Failed to export ${track.title}: $e');
      _exportProgressController.add(DownloadProgress(
        trackId: track.id,
        trackTitle: track.title,
        currentBytes: 0,
        totalBytes: 0,
        tracksCompleted: 0,
        totalTracks: 1,
      ));
    }
  }

  Future<void> exportPlaylist(Playlist playlist, {String quality = 'medium'}) async {
    _cancelled = false;
    String dir;
    try {
      dir = await _exportDir;
    } catch (e) {
      _exportErrorController.add('Failed to export playlist: $e');
      return;
    }
    final tracks = playlist.tracks;
    final total = tracks.length;

    for (var i = 0; i < total; i++) {
      if (_cancelled) break;
      final track = tracks[i];
      if (await isExported(track)) continue;

      final safeTitle = _sanitizeFilename(track.title ?? track.id);
      final safeArtist = _sanitizeFilename(track.author ?? 'Unknown');
      final ext = quality.toLowerCase().contains('flac') ? '.flac' : '.m4a';
      final fileName = '$safeArtist - $safeTitle$ext';
      final filePath = p.join(dir, fileName);

      try {
        final audioUrl = await _audioRepository.getAudioUrl(
          track,
          quality: quality,
        );
        final resolved = await _resolveRedirects(audioUrl);
        await _downloadFile(resolved, filePath, track, i, total, isExport: true);
        _exportCompletedController.add(track.id);
      } catch (e) {
        _exportErrorController.add('Failed to export ${track.title}: $e');
        _exportProgressController.add(DownloadProgress(
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

  Future<void> _cacheLyrics(Track track) async {
    try {
      await _audioRepository.getLyrics(track);
    } catch (_) {
      // Don't crash the download process if lyric caching fails
    }
  }

  String _sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  Future<void> downloadTrack(Track track, String playlistId, {String quality = 'medium'}) async {
    if (track.id.startsWith('local_')) return;
    if (await _database.isTrackDownloaded(track.id)) return;
    final dir = await _getDownloadDir(playlistId);
    
    final safeTitle = _sanitizeFilename(track.title ?? track.id);
    final safeArtist = _sanitizeFilename(track.author ?? 'Unknown');
    final ext = quality.toLowerCase().contains('flac') ? '.flac' : '.m4a';
    final fileName = '$safeArtist - $safeTitle$ext';
    final filePath = p.join(dir, fileName);

    try {
      final audioUrl = await _audioRepository.getAudioUrl(
        track,
        quality: quality,
      );
      final resolved = await _resolveRedirects(audioUrl);
      await _downloadFile(resolved, filePath, track, 0, 1);
      
      // Cache lyrics with it
      await _cacheLyrics(track);

      await _database.markTrackDownloaded(
        track.id,
        playlistId,
        filePath,
        title: track.title,
        thumbnailUrl: track.thumbnailUrl,
        durationSeconds: track.duration?.inSeconds,
        author: track.author,
        album: track.album,
        year: track.year,
      );
      // C2: fire-and-forget duration backfill. If
      // `track.duration` was null (live stream / unlisted
      // video) the SQLite row was just written with `null`;
      // the probe may recover a real duration from the
      // on-disk file. Bounded to 5s; short-circuits when
      // `track.duration` was non-null.
      unawaited(
        _cacheService?.backfillDurationFromFile(track.id, filePath),
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
      final safeTitle = _sanitizeFilename(track.title ?? track.id);
      final safeArtist = _sanitizeFilename(track.author ?? 'Unknown');
      final ext = quality.toLowerCase().contains('flac') ? '.flac' : '.m4a';
      final fileName = '$safeArtist - $safeTitle$ext';
      final filePath = p.join(dir, fileName);

      if (await _database.isTrackDownloaded(track.id)) continue;

      try {
        final audioUrl = await _audioRepository.getAudioUrl(
          track,
          quality: quality,
        );
        final resolved = await _resolveRedirects(audioUrl);
        await _downloadFile(resolved, filePath, track, i, total);
        
        // Cache lyrics with it
        await _cacheLyrics(track);

        await _database.markTrackDownloaded(
          track.id,
          playlist.id,
          filePath,
          title: track.title,
          thumbnailUrl: track.thumbnailUrl,
          durationSeconds: track.duration?.inSeconds,
          author: track.author,
          album: track.album,
          year: track.year,
        );
        // C2: fire-and-forget duration backfill. See
        // `downloadTrack` above for the contract; this
        // site is the per-track inside the playlist-batch
        // download path.
        unawaited(
          _cacheService?.backfillDurationFromFile(track.id, filePath),
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

  Future<void> _downloadFile(
    String url,
    String savePath,
    Track track,
    int trackIndex,
    int totalTracks, {
    bool isExport = false,
  }) async {
    final file = File(savePath);
    if (file.existsSync()) return; // Already exists

    final tmpPath = '$savePath.tmp';
    final tmpFile = File(tmpPath);
    if (tmpFile.existsSync()) tmpFile.deleteSync();

    try {
      if (!url.startsWith('http')) {
        final localPath = url.replaceFirst('file://', '');
        final sourceFile = File(localPath);
        if (sourceFile.existsSync()) {
          sourceFile.copySync(savePath);
          if (isExport) {
            await _writeTags(savePath, track);
          }
          final size = sourceFile.lengthSync();
          final progress = DownloadProgress(
            trackId: track.id,
            trackTitle: track.title,
            currentBytes: size,
            totalBytes: size,
            tracksCompleted: trackIndex,
            totalTracks: totalTracks,
          );
          if (isExport) {
            _exportProgressController.add(progress);
          } else {
            _progressController.add(progress);
          }
          return;
        }
      }

      final response = await _client.send(http.Request('GET', Uri.parse(url)));
      final contentLength = response.contentLength ?? 0;
      var downloaded = 0;
      final sink = tmpFile.openWrite();

      await for (final chunk in response.stream) {
        if (_cancelled) {
          await sink.close();
          if (tmpFile.existsSync()) tmpFile.deleteSync();
          return;
        }
        sink.add(chunk);
        downloaded += chunk.length;
        
        final progress = DownloadProgress(
          trackId: track.id,
          trackTitle: track.title,
          currentBytes: downloaded,
          totalBytes: contentLength,
          tracksCompleted: trackIndex,
          totalTracks: totalTracks,
        );

        if (isExport) {
          _exportProgressController.add(progress);
        } else {
          _progressController.add(progress);
        }
      }

      await sink.close();
      if (!_cancelled) {
        await tmpFile.rename(savePath);
        if (isExport) {
          await _writeTags(savePath, track);
        }
      }
    } catch (e) {
      if (tmpFile.existsSync()) tmpFile.deleteSync();
      rethrow;
    }
  }

  Future<String> _resolveRedirects(String url) async {
    if (!url.startsWith('http')) return url;
    return await NetworkUtils.resolveRedirects(_client, url);
  }

  Future<void> _writeTags(String filePath, Track track) async {
    try {
      List<int>? imageBytes;
      if (track.thumbnailUrl != null) {
        try {
          final res = await _client.get(Uri.parse(track.thumbnailUrl!));
          if (res.statusCode == 200) {
            imageBytes = res.bodyBytes;
          }
        } catch (_) {}
      }
      
      final tag = Tag(
        title: track.title,
        trackArtist: track.author,
        album: track.album ?? track.title,
        pictures: imageBytes != null ? [
          Picture(
            bytes: Uint8List.fromList(imageBytes),
            mimeType: null,
            pictureType: PictureType.coverFront,
          )
        ] : [],
      );
      await AudioTags.write(filePath, tag);
    } catch (e) {
      print('Failed to write ID3 tags: $e');
    }
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

  Future<void> deleteDownloadedTrack(String trackId) async {
    if (trackId.startsWith('local_')) return;
    final path = await _database.getDownloadedFilePath(trackId);
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
    await _database.removeDownloadedTrack(trackId);
  }

  Future<int> getTotalCacheSize() async {
    final tracks = await _database.getAllDownloadedTrackIds();
    var total = 0;
    for (final id in tracks) {
      final path = await _database.getDownloadedFilePath(id);
      if (path != null) {
        try {
          total += File(path).lengthSync();
        } catch (_) {}
      }
    }
    return total;
  }

  Future<int> getPlaylistCacheSize(String playlistId) async {
    final paths = await _database.getDownloadedFilePaths(playlistId);
    var total = 0;
    for (final path in paths) {
      try {
        total += File(path).lengthSync();
      } catch (_) {}
    }
    return total;
  }

  void dispose() {
    _client.close();
    _progressController.close();
    _completedController.close();
    _errorController.close();
    _exportProgressController.close();
    _exportCompletedController.close();
    _exportErrorController.close();
  }
}
