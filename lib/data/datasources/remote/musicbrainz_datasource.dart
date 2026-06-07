import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../core/utils/app_logger.dart';

class MusicBrainzArtistMatch {
  final String mbid;
  final String name;
  final int score;
  const MusicBrainzArtistMatch({
    required this.mbid,
    required this.name,
    required this.score,
  });
}

class MusicBrainzGenreEntry {
  final String name;
  final int count;
  const MusicBrainzGenreEntry({required this.name, required this.count});
}

class MusicBrainzDataSource {
  static const String _userAgent =
      'ZYP Music/1.0 ( https://musicbrainz.org/user/UnscriptedPoet )';

  static const String _baseUrl = 'https://musicbrainz.org/ws/2';
  static const Duration _throttle = Duration(milliseconds: 1100);

  final http.Client _client;
  Future<void> _gate = Future<void>.value();

  MusicBrainzDataSource({http.Client? client})
      : _client = client ?? http.Client();

  Future<T> _enqueue<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    final previous = _gate;
    _gate = previous.then((_) async {
      try {
        completer.complete(await task());
      } catch (e, st) {
        completer.completeError(e, st);
      }
      await Future<void>.delayed(_throttle);
    });
    return completer.future;
  }

  static String _escapeQuery(String raw) {
    final out = StringBuffer();
    for (final rune in raw.runes) {
      final ch = String.fromCharCode(rune);
      if ('+-&&||!(){}[]^"~*?:\\/. '.contains(ch)) {
        out.write('\\$ch');
      } else {
        out.write(ch);
      }
    }
    return out.toString();
  }

  Future<MusicBrainzArtistMatch?> searchArtist(
    String name, {
    int minScore = 85,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    return _enqueue(() async {
      final uri = Uri.parse(
        '$_baseUrl/artist/?query=artist:${Uri.encodeComponent(_escapeQuery(trimmed))}&fmt=json&limit=5',
      );
      final res = await _client.get(uri, headers: {'User-Agent': _userAgent});
      if (res.statusCode != 200) {
        AppLogger.log(
          'MusicBrainz searchArtist HTTP ${res.statusCode} for "$trimmed"',
          name: 'MusicBrainzDataSource',
        );
        return null;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final artists = (body['artists'] as List?) ?? const [];
      for (final raw in artists) {
        final entry = raw as Map<String, dynamic>;
        final score = (entry['score'] as num?)?.toInt() ?? 0;
        final mbid = entry['id'] as String?;
        final artistName = (entry['name'] as String?) ?? '';
        if (mbid == null || mbid.isEmpty) continue;
        if (score < minScore) break;
        if (artistName.toLowerCase() != trimmed.toLowerCase()) continue;
        return MusicBrainzArtistMatch(
          mbid: mbid,
          name: artistName,
          score: score,
        );
      }
      return null;
    });
  }

  Future<List<MusicBrainzGenreEntry>> getArtistGenres(String mbid) async {
    if (mbid.trim().isEmpty) return const [];
    return _enqueue(() async {
      final uri = Uri.parse('$_baseUrl/artist/$mbid?inc=genres&fmt=json');
      final res = await _client.get(uri, headers: {'User-Agent': _userAgent});
      if (res.statusCode != 200) {
        AppLogger.log(
          'MusicBrainz getArtistGenres HTTP ${res.statusCode} for $mbid',
          name: 'MusicBrainzDataSource',
        );
        return <MusicBrainzGenreEntry>[];
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final raw = (body['genres'] as List?) ?? const [];
      final entries = <MusicBrainzGenreEntry>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final map = item as Map<String, dynamic>;
        final name = (map['name'] as String?)?.trim();
        if (name == null || name.isEmpty) continue;
        final count = (map['count'] as num?)?.toInt() ?? 0;
        entries.add(MusicBrainzGenreEntry(name: name, count: count));
      }
      return entries;
    });
  }

  void dispose() {
    _client.close();
  }
}
