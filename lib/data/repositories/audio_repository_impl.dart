import 'dart:io';
import 'package:zyp_music/core/utils/app_logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../../domain/entities/video.dart';
import '../../domain/repositories/audio_repository.dart';
import '../datasources/remote/youtube_remote_datasource.dart';
import '../datasources/remote/lyrics_remote_datasource.dart';
import '../datasources/local/playlist_database.dart';

import '../../service/audio_handler.dart';
import '../../core/services/audio_cache_service.dart';
import '../../core/services/hybrid_cache_service.dart';

  String _stripPrefixes(String id) {
    var stripped = id;
    if (stripped.startsWith('unified_')) {
      stripped = stripped.substring('unified_'.length);
    }
    if (stripped.startsWith('youtube_music_')) {
      stripped = stripped.substring('youtube_music_'.length);
    } else if (stripped.startsWith('youtube_')) {
      stripped = stripped.substring('youtube_'.length);
    }
    return stripped;
  }

class AudioRepositoryImpl implements AudioRepository {
  final YoutubeRemoteDataSource remoteDataSource;
  final LyricsRemoteDataSource lyricsDataSource;
  final MusicAudioHandler _handler;
  final PlaylistDatabase _database;
  final HybridCacheService? _hybridCache;
  final AudioCacheService _cacheService = AudioCacheService();

  bool _isOffline = false;
  bool get isOffline => _isOffline;

  AudioRepositoryImpl({
    required this.remoteDataSource,
    required this.lyricsDataSource,
    required MusicAudioHandler handler,
    required PlaylistDatabase database,
    HybridCacheService? hybridCache,
  })  : _handler = handler,
        _database = database,
        _hybridCache = hybridCache {
    // Forward every successful on-disk write to the Hive cache tracker so
    // pre-buffered tracks register themselves in the box. This is what makes
    // the download icon flip to the checkmark for tracks that were cached
    // by the lookahead pre-buffer engine (not just user-initiated downloads).
    _cacheService.onCacheSuccess = (trackId, filePath) async {
      final cache = _hybridCache;
      if (cache == null) return;
      await cache.markSuccessAfterWrite(
        trackId,
        expectedFilePath: filePath,
      );
    };
  }

  /// Toggle driven exclusively by [ConnectivityService]. The flag itself
  /// is advisory — the existing local-cache fallback in [getAudioUrl] and
  /// the natural failure of network calls already produce the correct
  /// offline behaviour. The flag is exposed so future consumers (UI
  /// badges, queue logic) can `context.watch` it without re-implementing
  /// the connectivity probe.
  void setOfflineMode(bool isOffline) {
    if (_isOffline == isOffline) return;
    _isOffline = isOffline;
    AppLogger.log(
      'AudioRepository offline mode -> $isOffline',
      name: 'AudioRepository',
    );
  }

  @override
  Future<String> getAudioUrl(
    Track track, {
    String quality = 'adaptive',
  }) async {
    try {
      // 1. Local downloaded file takes priority over everything
      final localPath = await _database.getDownloadedFilePath(track.id);
      if (localPath != null && File(localPath).existsSync()) {
        return localPath;
      }

      // 2. LRU cache (skip obviously broken paths)
      final cachedUri = await _cacheService.getCachedUri(track.id);
      if (cachedUri != null) {
        if (cachedUri.endsWith('/.mp3') || cachedUri == '.mp3') {
          AppLogger.log('Invalid cache path detected: $cachedUri. Skipping.', name: 'AudioRepository');
        } else {
          AppLogger.log('Playing from cache: $cachedUri', name: 'AudioRepository');
          return cachedUri;
        }
      }

      // 3. YouTube-only stream retrieval (hardcoded).
      return await _getYouTubeUrl(track, quality);
    } catch (e) {
      throw Exception('YouTube stream failed: $e');
    }
  }

  /// Resolve a YouTube stream URL for [track].
  ///
  /// For native YouTube tracks with an 11-char ID, tries direct URL resolution first.
  /// Falls back to a search query for any other track or if the direct call fails.
  Future<String> _getYouTubeUrl(Track track, String quality) async {
    final rawId = _stripPrefixes(track.id);
    if ((track.source == TrackSource.youtube || track.source == TrackSource.youtube_music) &&
        rawId.length == 11) {
      try {
        return await remoteDataSource.getAudioUrl(rawId, quality: quality);
      } catch (e) {
        AppLogger.log('Direct YT URL failed, falling back to search: $e', name: 'AudioRepository');
      }
    }

    // Search YouTube by title + artist + album
    final query = '${track.title} ${track.author ?? ''} ${track.album ?? ''} official audio'.trim();
    AppLogger.log('Mapping track via YouTube search: $query', name: 'AudioRepository');
    final results = await remoteDataSource.search(query);
    if (results.isNotEmpty) {
      return await remoteDataSource.getAudioUrl(results.first.id, quality: quality);
    }
    throw Exception('Could not find "${track.title}" on YouTube');
  }

  @override
  Future<void> playTrack(Track track, String audioUrl) async {
    String finalUrl = audioUrl;

    // YouTube Stream URL Expiry Fix: Always re-fetch a fresh stream URL immediately before playback
    if ((track.source == TrackSource.youtube || track.source == TrackSource.youtube_music) &&
        finalUrl.contains('googlevideo.com')) {
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

    final actualSource = 'youtube';

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
        'source': actualSource,
      },
    );

    Future<void> executePlay(String url, MediaItem mediaItem) async {
      final queue = _handler.queue.value;
      if (queue.isNotEmpty && queue.any((e) => e.id == track.id)) {
        _handler.mediaItem.add(mediaItem);
        await _handler.playTrack(url, mediaItem);
      } else {
        final newQueue = List<MediaItem>.from(queue);
        newQueue.add(mediaItem);
        _handler.queue.add(newQueue);
        await _handler.playTrack(url, mediaItem);
      }
    }

    try {
      await executePlay(finalUrl, item);
    } catch (e) {
      if (finalUrl.startsWith('file://') || !finalUrl.startsWith('http')) {
        AppLogger.log('Local cached file failed to play: $e. Deleting cache and retrying from network...', name: 'AudioRepository');
        try {
          final filePath = finalUrl.startsWith('file://') ? Uri.parse(finalUrl).toFilePath() : finalUrl;
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (cleanupError) {
          AppLogger.log('Failed to delete corrupted cached file: $cleanupError', name: 'AudioRepository');
        }

        try {
          final networkUrl = await getAudioUrl(track, quality: 'adaptive');
          if (networkUrl.startsWith('http')) {
            final newItem = MediaItem(
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
                'source': 'youtube',
              },
            );
            await executePlay(networkUrl, newItem);
            return;
          }
        } catch (retryError) {
          AppLogger.log('Retry playback failed: $retryError', name: 'AudioRepository');
        }
      }
      rethrow;
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
    // Lyrics files are keyed by trackId so the Hive eviction pipeline can
    // find and purge them in lockstep with the audio cache entry.
    final lyricsPath = await _lyricsFilePathFor(track.id);

    // 1. Try to read from local file first
    try {
      final file = File(lyricsPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        // Only use the cached file if it has content.
        // If the timestamp regex doesn't match at all we might have a stale
        // file written by the old broken _formatLrcTimestamp — skip it so we
        // fetch fresh synced lyrics from the network.
        if (content.isNotEmpty) {
          final hasValidLrc = RegExp(r'\[\d{2}:\d{2}\.\d{2}').hasMatch(content);
          final isPlainLyrics = !content.contains('[');
          if (hasValidLrc || isPlainLyrics) {
            return content;
          }
          // Stale/broken file — fall through and re-fetch.
          AppLogger.log('Cached lyrics file appears corrupt, re-fetching', name: 'AudioRepository');
        }
      }
    } catch (e) {
      AppLogger.log('Error reading local lyrics file: \$e', name: 'AudioRepository');
    }

    // 2. Fallback to network fetch
    final lyrics = await _fetchLyricsFromNetwork(track);
    if (lyrics != null && lyrics.isNotEmpty) {
      try {
        final file = File(lyricsPath);
        await file.writeAsString(lyrics);
        // Mirror the lyrics into the Hive cache tracker so the eviction
        // pipeline knows the on-disk path of this track's lyrics.
        final cache = _hybridCache;
        if (cache != null) {
          await cache.setLyrics(track.id, lyrics, filePath: lyricsPath);
        }
      } catch (e) {
        AppLogger.log('Error caching fetched lyrics: \$e', name: 'AudioRepository');
      }
    }
    return lyrics;
  }

  Future<String?> _fetchLyricsFromNetwork(Track track) async {
    return await lyricsDataSource.getSyncedLyrics(track.title, track.author ?? '');
  }

  @override
  Future<String?> refreshLyrics(Track track) async {
    final lyricsPath = await _lyricsFilePathFor(track.id);
    final lyrics = await _fetchLyricsFromNetwork(track);
    if (lyrics != null) {
      try {
        final file = File(lyricsPath);
        await file.writeAsString(lyrics);
        final cache = _hybridCache;
        if (cache != null) {
          await cache.setLyrics(track.id, lyrics, filePath: lyricsPath);
        }
      } catch (e) {
        AppLogger.log('Error saving lyrics file on refresh: \$e', name: 'AudioRepository');
      }
    }
    return lyrics;
  }

  /// Resolves the deterministic trackId-keyed lyrics file path inside the
  /// application documents directory. Kept private to the repository so the
  /// Hive eviction pipeline can rely on the same naming convention.
  Future<String> _lyricsFilePathFor(String trackId) async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$trackId-lyrics.lrc';
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
      final audioUrl = await getAudioUrl(track);
      if (audioUrl.startsWith('http')) {
        await _cacheService.cacheStream(track.id, audioUrl);
        AppLogger.log('Successfully preloaded track: ${track.id}', name: 'AudioRepository');
      }
    } catch (e) {
      AppLogger.log('Failed to preload next track: $e', name: 'AudioRepository');
    }
  }
}
