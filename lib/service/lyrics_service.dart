import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import '../domain/entities/video.dart';

class LyricsResult {
  final String trackName;
  final String artistName;
  final String? plainLyrics;
  final List<LyricLine> syncedLines;

  const LyricsResult({
    required this.trackName,
    required this.artistName,
    this.plainLyrics,
    this.syncedLines = const [],
  });

  bool get hasSyncedLyrics => syncedLines.isNotEmpty;
  bool get hasAnyLyrics =>
      syncedLines.isNotEmpty ||
      (plainLyrics != null && plainLyrics!.isNotEmpty);
}

class LyricLine {
  final Duration time;
  final String text;

  const LyricLine({required this.time, required this.text});
}

class LyricsService {
  final http.Client _client;
  final Map<String, LyricsResult?> _cache = {};

  LyricsService({http.Client? client}) : _client = client ?? http.Client();

  Future<LyricsResult?> getLyrics(Track track) async {
    final cacheKey = track.id;
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

    final title = _cleanTitle(track.title);
    final artist = _cleanArtist(track.author);
    final duration = track.duration.inSeconds;

    try {
      final exact = await _fetchExact(title, artist, duration);
      if (exact != null && exact.hasAnyLyrics) {
        _cache[cacheKey] = exact;
        return exact;
      }

      final search = await _search(title, artist, duration);
      _cache[cacheKey] = search;
      return search;
    } catch (e) {
      dev.log(
        'Lyrics lookup failed for ${track.id}: $e',
        name: 'LyricsService',
      );
      _cache[cacheKey] = null;
      return null;
    }
  }

  Future<LyricsResult?> _fetchExact(
    String title,
    String artist,
    int duration,
  ) async {
    final uri = Uri.https('lrclib.net', '/api/get', {
      'track_name': title,
      if (artist.isNotEmpty) 'artist_name': artist,
      if (duration > 0) 'duration': '$duration',
    });
    final response = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _fromJson(json);
  }

  Future<LyricsResult?> _search(
    String title,
    String artist,
    int duration,
  ) async {
    final uri = Uri.https('lrclib.net', '/api/search', {
      'track_name': title,
      if (artist.isNotEmpty) 'artist_name': artist,
    });
    final response = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;

    final results = jsonDecode(response.body) as List<dynamic>;
    if (results.isEmpty) return null;

    final parsed = results
        .whereType<Map<String, dynamic>>()
        .map(_fromJson)
        .where((result) => result.hasAnyLyrics)
        .toList();
    if (parsed.isEmpty) return null;

    parsed.sort((a, b) {
      if (a.hasSyncedLyrics != b.hasSyncedLyrics) {
        return a.hasSyncedLyrics ? -1 : 1;
      }
      if (duration <= 0) return 0;
      final aScore =
          _titleScore(a.trackName, title) + _artistScore(a.artistName, artist);
      final bScore =
          _titleScore(b.trackName, title) + _artistScore(b.artistName, artist);
      return bScore.compareTo(aScore);
    });
    return parsed.first;
  }

  LyricsResult _fromJson(Map<String, dynamic> json) {
    final synced = json['syncedLyrics'] as String?;
    final plain = json['plainLyrics'] as String?;
    return LyricsResult(
      trackName: json['trackName'] as String? ?? '',
      artistName: json['artistName'] as String? ?? '',
      plainLyrics: plain?.trim(),
      syncedLines: _parseSyncedLyrics(synced),
    );
  }

  List<LyricLine> _parseSyncedLyrics(String? lyrics) {
    if (lyrics == null || lyrics.trim().isEmpty) return const [];
    final lines = <LyricLine>[];
    final regex = RegExp(r'^\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]\s*(.*)$');
    for (final raw in lyrics.split('\n')) {
      final match = regex.firstMatch(raw.trim());
      if (match == null) continue;
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final fraction = (match.group(3) ?? '0').padRight(3, '0');
      final millis = int.parse(fraction.substring(0, 3));
      final text = match.group(4)?.trim() ?? '';
      if (text.isEmpty) continue;
      lines.add(
        LyricLine(
          time: Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: millis,
          ),
          text: text,
        ),
      );
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  String _cleanTitle(String title) {
    return title
        .replaceAll(
          RegExp(
            r'\([^)]*(official|visualizer|video|audio|lyrics?)[^)]*\)',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\[[^\]]*(official|visualizer|video|audio|lyrics?)[^\]]*\]',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\s+(official|music|lyric|lyrics?)\s+(video|audio)$',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _cleanArtist(String? artist) {
    return (artist ?? '')
        .replaceAll(RegExp(r'\s+-\s+Topic$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  int _titleScore(String candidate, String title) {
    final a = candidate.toLowerCase();
    final b = title.toLowerCase();
    if (a == b) return 4;
    if (a.contains(b) || b.contains(a)) return 2;
    return 0;
  }

  int _artistScore(String candidate, String artist) {
    if (artist.isEmpty) return 0;
    final a = candidate.toLowerCase();
    final b = artist.toLowerCase();
    if (a == b) return 3;
    if (a.contains(b) || b.contains(a)) return 1;
    return 0;
  }

  void dispose() => _client.close();
}
