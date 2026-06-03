import 'dart:io';
import 'package:zyp_music/core/utils/app_logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../../domain/entities/video.dart';
import '../../domain/repositories/audio_repository.dart';
import '../datasources/remote/youtube_remote_datasource.dart';
import '../datasources/remote/tidal_remote_datasource.dart';
import '../datasources/remote/lyrics_remote_datasource.dart';
import '../datasources/local/playlist_database.dart';
import '../../service/audio_handler.dart';
import '../../core/services/audio_cache_service.dart';

  String _stripPrefixes(String id) {
    var stripped = id;
    if (stripped.startsWith('unified_')) {
      stripped = stripped.substring('unified_'.length);
    }
    if (stripped.startsWith('youtube_music_')) {
      stripped = stripped.substring('youtube_music_'.length);
    } else if (stripped.startsWith('youtube_')) {
      stripped = stripped.substring('youtube_'.length);
    } else if (stripped.startsWith('tidal_')) {
      stripped = stripped.substring('tidal_'.length);
    }
    return stripped;
  }

class AudioRepositoryImpl implements AudioRepository {
  final YoutubeRemoteDataSource remoteDataSource;
  final TidalRemoteDataSource tidalDataSource;
  final LyricsRemoteDataSource lyricsDataSource;
  final MusicAudioHandler _handler;
  final PlaylistDatabase _database;
  final AudioCacheService _cacheService = AudioCacheService();

  AudioRepositoryImpl({
    required this.remoteDataSource,
    required this.tidalDataSource,
    required this.lyricsDataSource,
    required MusicAudioHandler handler,
    required PlaylistDatabase database,
  }) : _handler = handler, _database = database;

  @override
  Future<String> getAudioUrl(
    Track track, {
    String quality = 'adaptive',
    TrackSource? preferredSource,
    bool enableFallback = false,
  }) async {
    // 1. Check for a local downloaded file first
    final localPath = await _database.getDownloadedFilePath(track.id);
    if (localPath != null && File(localPath).existsSync()) {
      return localPath;
    }

    // 2. Check for LRU cached file
    final cachedUri = await _cacheService.getCachedUri(track.id);
    if (cachedUri != null) {
      if (cachedUri.endsWith('/.mp3') || cachedUri == '.mp3') {
        AppLogger.log('Invalid cache path detected: $cachedUri. Skipping cache.', name: 'AudioRepository');
      } else {
        AppLogger.log('Playing from cache: $cachedUri', name: 'AudioRepository');
        return cachedUri;
      }
    }

    final targetSource = preferredSource ?? track.source;

    try {
      String? url;

      if (track.source == targetSource) {
        url = await _getUrlFromSource(track.id, targetSource, quality);
      } else {
        // Track is from a different source — search the target source
        final query = '${track.title} ${track.author ?? ''}'.trim();
        final results = await _searchSource(query, targetSource);
        if (results.isNotEmpty) {
          url = await _getUrlFromSource(results.first.id, targetSource, quality);
        }
      }

      if (url != null) return url;

      // Tidal returned null (no user token) — always fall back to YouTube
      AppLogger.log('Target source returned null URL, falling back to YouTube', name: 'AudioRepository');
      return await _getYouTubeUrl(track, quality);
    } catch (e) {
      if (enableFallback || true) {
        // Always try YouTube as last resort
        AppLogger.log('Primary source failed ($e), trying YouTube fallback', name: 'AudioRepository');
        try {
          return await _getYouTubeUrl(track, quality);
        } catch (ytError) {
          AppLogger.log('YouTube fallback also failed: $ytError', name: 'AudioRepository');
        }
      }
      rethrow;
    }
  }

  Future<String> _getYouTubeUrl(Track track, String quality) async {
    final rawId = _stripPrefixes(track.id);
    if (track.source == TrackSource.youtube && rawId.length == 11) {
      try {
        return await remoteDataSource.getAudioUrl(rawId, quality: quality);
      } catch (e) {
        AppLogger.log('Direct YT URL failed, falling back to search mapping: $e', name: 'AudioRepository');
      }
    }
    
    // Search YouTube for this track using linking algorithm
    final query = '${track.title} ${track.author ?? ''} ${track.album ?? ''} official audio'.trim();
    AppLogger.log('Mapping track with search: $query', name: 'AudioRepository');
    final results = await remoteDataSource.search(query);
    if (results.isNotEmpty) {
      return await remoteDataSource.getAudioUrl(results.first.id, quality: quality);
    }
    throw Exception('Could not find "${track.title}" on YouTube');
  }

  Future<String?> _getUrlFromSource(String id, TrackSource source, String quality) async {
    final rawId = _stripPrefixes(id);
    if (source == TrackSource.tidal) {
      return await tidalDataSource.getTrackStreamUrl(rawId, quality: quality);
    } else {
      return await remoteDataSource.getAudioUrl(rawId, quality: quality);
    }
  }

  Future<List<dynamic>> _searchSource(String query, TrackSource source) async {
    if (source == TrackSource.tidal) {
      return await tidalDataSource.search(query);
    } else {
      return await remoteDataSource.search(query);
    }
  }


  @override
  Future<void> playTrack(Track track, String audioUrl) async {
    String finalUrl = audioUrl;

    // YouTube Stream URL Expiry Fix: Always re-fetch a fresh stream URL immediately before playback
    if (track.source == TrackSource.youtube || track.source == TrackSource.youtube_music) {
      try {
        AppLogger.log('Fetching fresh YouTube stream URL at play time', name: 'AudioRepository');
        final rawId = _stripPrefixes(track.id);
        final freshUrl = await remoteDataSource.getAudioUrl(rawId, quality: 'adaptive');
        if (freshUrl.isNotEmpty) {
          finalUrl = freshUrl;
        }
      } catch (e) {
        AppLogger.log('Fresh fetch failed: $e, falling back to original URL', name: 'AudioRepository');
      }
    }

    if (finalUrl.startsWith('http')) {
      // Start caching the stream in the background
      _cacheService.cacheStream(track.id, finalUrl);
    }
    
    final item = MediaItem(
      id: track.id,
      title: track.title,
      artist: track.author ?? '',
      album: track.album,
      artUri: track.thumbnailUrl != null
          ? Uri.tryParse(track.thumbnailUrl!)
          : null,
      duration: track.duration,
      extras: {
        'year': track.year,
        'source': track.source == TrackSource.tidal ? 'tidal' : 'youtube',
      },
    );

    // Never resolve redirects for signed URLs — the handler decides based on URL type
    final queue = _handler.queue.value;
    if (queue.isNotEmpty && queue.any((e) => e.id == track.id)) {
      _handler.mediaItem.add(item);
      await _handler.playTrack(finalUrl, item);
    } else {
      final newQueue = List<MediaItem>.from(queue);
      newQueue.add(item);
      _handler.queue.add(newQueue);
      await _handler.playTrack(finalUrl, item);
    }
  }

  @override
  Future<void> play(String url) async {
    final resolved = await _handler.resolveRedirects(url);
    await _handler.playTrack(resolved, const MediaItem(id: '', title: ''));
  }

  @override
  Future<void> pause() => _handler.pause();

  @override
  Future<void> resume() => _handler.play();

  @override
  Future<void> stop() => _handler.stop();

  @override
  Future<void> seek(Duration position) => _handler.seek(position);

  @override
  Future<Duration> getPosition() async => _handler.position;

  @override
  Future<Duration> getDuration() async => _handler.duration;

  @override
  Stream<Duration> get positionStream => _handler.positionStream;

  @override
  Stream<Duration> get bufferedPositionStream => _handler.bufferedPositionStream;

  @override
  Stream<Duration> get durationStream => _handler.durationStream;

  @override
  Future<bool> isPlaying() async => _handler.isPlaying;

  @override
  Stream<bool> get playingStream => _handler.playbackState.map((state) => state.playing);

  @override
  Stream<ProcessingState> get processingStateStream =>
      _handler.processingStateStream;

  @override
  bool get currentTrackCompleted => _handler.currentTrackCompleted;

  @override
  Stream<void> get onSkipNextRequested => _handler.skipNextRequested.stream;

  @override
  Stream<void> get onSkipPreviousRequested => _handler.skipPreviousRequested.stream;

  @override
  Future<String?> getLyrics(Track track) async {
    // 1. Try to read from local file first
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/${track.title}-lyrics.lrc');
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          return content;
        }
      }
    } catch (e) {
      AppLogger.log('Error reading local lyrics file: $e', name: 'AudioRepository');
    }

    // 2. Fallback to network fetch
    final lyrics = await _fetchLyricsFromNetwork(track);
    if (lyrics != null && lyrics.isNotEmpty) {
      try {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/${track.title}-lyrics.lrc');
        await file.writeAsString(lyrics);
      } catch (e) {
        AppLogger.log('Error caching fetched lyrics: $e', name: 'AudioRepository');
      }
    }
    return lyrics;
  }

  Future<String?> _fetchLyricsFromNetwork(Track track) async {
    // Attempt to fetch synced lyrics from LrcLib
    final lrclibLyrics = await lyricsDataSource.getSyncedLyrics(track.title, track.author ?? '');
    if (lrclibLyrics != null) {
      return lrclibLyrics;
    }

    // Fallback to Tidal lyrics
    if (track.source == TrackSource.tidal) {
      return tidalDataSource.getLyrics(track.id);
    }
    
    // Fallback: try searching Tidal for the YouTube track's title to find lyrics
    try {
      final searchResults = await tidalDataSource.search(track.title);
      if (searchResults.isNotEmpty) {
         return tidalDataSource.getLyrics(searchResults.first.id);
      }
    } catch (e) {
      AppLogger.log('Failed to find fallback lyrics: $e', name: 'AudioRepository');
    }
    
    return null;
  }

  @override
  Future<String?> refreshLyrics(Track track) async {
    final lyrics = await _fetchLyricsFromNetwork(track);
    if (lyrics != null) {
      try {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/${track.title}-lyrics.lrc');
        await file.writeAsString(lyrics);
      } catch (e) {
        AppLogger.log('Error saving lyrics file on refresh: $e', name: 'AudioRepository');
      }
    }
    return lyrics;
  }

  @override
  Future<List<Track>> getUpNexts(Track track) async {
    try {
      final upNexts = await remoteDataSource.getUpNexts(track.id);
      final tracks = upNexts.map((e) => Track(
        id: e.videoId ?? '',
        title: e.title ?? 'Unknown',
        author: e.artists?.name ?? 'Unknown',
        thumbnailUrl: e.thumbnails?.last.url,
        duration: Duration(seconds: e.duration ?? 0),
        source: TrackSource.youtube,
      )).where((t) => t.id.isNotEmpty).toList();
      if (tracks.isNotEmpty) return tracks;
    } catch (e) {
      AppLogger.log('Failed to fetch Up Nexts: $e', name: 'AudioRepository');
    }
    
    // Fallback logic
    try {
      final results = await remoteDataSource.searchTracks("${track.title} ${track.author ?? ''}");
      return results.where((t) => t.id != track.id).map((t) => t.toEntity()).toList();
    } catch (e) {
      AppLogger.log('Fallback search for Up Nexts failed: $e', name: 'AudioRepository');
      return [];
    }
  }

  @override
  Future<void> preloadTrack(Track track) async {
    try {
      final audioUrl = await getAudioUrl(track, enableFallback: true);
      if (audioUrl.startsWith('http')) {
        await _cacheService.cacheStream(track.id, audioUrl);
        AppLogger.log('Successfully preloaded track: ${track.id}', name: 'AudioRepository');
      }
    } catch (e) {
      AppLogger.log('Failed to preload next track: $e', name: 'AudioRepository');
    }
  }
}
