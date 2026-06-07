import 'package:dart_ytmusic_api/types.dart' as ytm;

import '../../data/datasources/remote/lyrics_remote_datasource.dart';
import '../../data/datasources/remote/youtube_remote_datasource.dart';
import '../../data/repositories/audio_repository_impl.dart' show stripTrackIdPrefixes;
import '../../domain/entities/video.dart';
import '../utils/app_logger.dart';

/// Multi-tier lyrics fetch chain.
///
/// 1. The audio repository's persistent cache (LRC blob keyed
///    by the track's normalised ID). Hits are returned
///    immediately without any network call.
/// 2. The `YoutubeRemoteDataSource`'s authenticated [YTMusic]
///    client — `getTimedLyrics` first (the richest signal —
///    per-line timings that drive the karaoke view), then
///    `getLyrics` (plain-text, last-resort YTMusic tier).
/// 3. LrcLib — public metadata database, used as a final
///    fallback when YTMusic returns nothing.
///
/// YTMusic's `getTimedLyrics` and `getLyrics` methods are
/// both available in `dart_ytmusic_api` 1.3.6 and accept
/// `(String videoId)` as their only argument. The returned
/// `TimedLyricsRes` exposes `timedLyricsData: List<TimedLyricsData>`;
/// each `TimedLyricsData` carries `lyricLine: String?` and
/// `cueRange: CueRange?` (where `CueRange.startTimeMilliseconds`
/// gives the LRC timestamp).
class LyricsChainService {
  static const String _logTag = 'LyricsChainService';

  final YoutubeRemoteDataSource _youtube;
  final LyricsRemoteDataSource _lrclib;
  final LyricsCacheReader _cache;

  LyricsChainService({
    required YoutubeRemoteDataSource youtube,
    required LyricsRemoteDataSource lrclib,
    required LyricsCacheReader cache,
  })  : _youtube = youtube,
        _lrclib = lrclib,
        _cache = cache;

  /// Top-level entry point. Returns an LRC string (timed if
  /// available, plain otherwise) or `null` if every tier is
  /// empty. The caller is responsible for any on-disk /
  /// Hive persistence — the chain is a pure fetch + format
  /// layer. Tier 1 (the audio repository's on-disk LRC
  /// file) is consulted via [LyricsCacheReader] so the chain
  /// short-circuits on a cache hit without touching the
  /// network.
  Future<String?> fetchLyrics(Track track) async {
    if (_isYouTubeId(track.id) == false) {
      return _fetchFromLrcLib(track);
    }
    final videoId = _videoIdFor(track);

    final cached = await _cache.read(track.id);
    if (cached != null && cached.trim().isNotEmpty) {
      return cached;
    }

    final ytmTimed = await _fetchFromYtmTimed(videoId);
    if (ytmTimed != null) return ytmTimed;

    final ytmPlain = await _fetchFromYtmPlain(videoId);
    if (ytmPlain != null) return ytmPlain;

    return _fetchFromLrcLib(track);
  }

  Future<String?> _fetchFromYtmTimed(String videoId) async {
    try {
      final res = await _youtube.ytMusic.getTimedLyrics(videoId);
      if (res == null) return null;
      final lrc = _timedToLrc(res);
      if (lrc == null) return null;
      AppLogger.log(
        'YTMusic timed-lyrics hit for $videoId (${lrc.length} bytes).',
        name: _logTag,
      );
      return lrc;
    } catch (e) {
      AppLogger.log(
        'YTMusic timed-lyrics failed for $videoId: $e',
        name: _logTag,
      );
      return null;
    }
  }

  Future<String?> _fetchFromYtmPlain(String videoId) async {
    try {
      final plain = await _youtube.ytMusic.getLyrics(videoId);
      if (plain == null || plain.trim().isEmpty) return null;
      final lrc = _plainToLrc(plain);
      AppLogger.log(
        'YTMusic plain-lyrics hit for $videoId (${lrc.length} bytes).',
        name: _logTag,
      );
      return lrc;
    } catch (e) {
      AppLogger.log(
        'YTMusic plain-lyrics failed for $videoId: $e',
        name: _logTag,
      );
      return null;
    }
  }

  Future<String?> _fetchFromLrcLib(Track track) async {
    final title = track.title.trim();
    final author = (track.author ?? '').trim();
    if (title.isEmpty) return null;
    try {
      final result =
          await _lrclib.getSyncedLyrics(title, author);
      if (result == null || result.trim().isEmpty) return null;
      return result;
    } catch (e) {
      AppLogger.log(
        'LrcLib fetch failed for "$title": $e',
        name: _logTag,
      );
      return null;
    }
  }

  String? _timedToLrc(ytm.TimedLyricsRes res) {
    final lines = res.timedLyricsData;
    if (lines.isEmpty) return null;
    final buf = StringBuffer();
    var emitted = 0;
    for (final line in lines) {
      final text = line.lyricLine?.trim() ?? '';
      if (text.isEmpty) continue;
      final ms = line.cueRange?.startTimeMilliseconds ?? 0;
      buf.writeln('${_formatLrcTimestamp(ms)}$text');
      emitted++;
    }
    if (emitted == 0) return null;
    return buf.toString();
  }

  String _plainToLrc(String plain) {
    return '[00:00.00]${plain.trim()}';
  }

  String _formatLrcTimestamp(int ms) {
    if (ms < 0) ms = 0;
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final hundredths = (ms % 1000) ~/ 10;
    String two(int n) => n.toString().padLeft(2, '0');
    return '[${two(minutes)}:${two(seconds)}.${two(hundredths)}]';
  }

  bool _isYouTubeId(String? id) {
    if (id == null) return false;
    final stripped = stripTrackIdPrefixes(id);
    return stripped.length == 11;
  }

  String _videoIdFor(Track track) {
    return stripTrackIdPrefixes(track.id);
  }
}

/// Minimal interface over the audio repository's lyrics
/// cache so the chain service stays decoupled from the
/// concrete SQLite / Hive implementation. The
/// [AudioRepositoryImpl] implements this via its existing
/// on-disk LRC file read path; in tests the chain can be
/// driven by an in-memory map.
abstract class LyricsCacheReader {
  Future<String?> read(String trackId);
}
