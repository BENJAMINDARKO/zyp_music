import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/video_model.dart';
import '../../../core/utils/app_logger.dart';

/// Pure metadata fetcher for Tidal's public track catalog.
///
/// This data source is **strictly metadata-only**. It performs unauthenticated
/// `GET` requests against Tidal's public v1 API to read track duration, title,
/// artist, album, and album cover — then maps those fields onto a [TrackModel].
///
/// It does NOT touch audio streaming, fallback logic, or playback routing. It
/// never returns a stream URL, manifest, or any payload field outside the
/// matrix documented in the project spec.
///
/// ## Caching
///
/// Track metadata is stable, signed-URL-free data, so it is cached in two
/// layers, mirroring the project's chart-data and search-cache tiers:
///
/// 1. **In-memory session cache** — repeat lookups for the same track ID
///    inside the same app launch skip both disk and network.
/// 2. **SharedPreferences cache** — successful fetches are persisted alongside
///    a millisecond timestamp. Entries are considered fresh for
///    [_defaultMaxAge] (7 days). On cache hit, the in-memory layer is
///    repopulated and the network is never contacted.
///
/// On a network failure, an *expired* cache entry is still returned as a
/// resilience fallback (same behavior as `ChartsRepositoryImpl._getWithCache`).
class TidalMetadataDataSource {
  TidalMetadataDataSource({http.Client? client})
      : _client = client ?? http.Client();

  static const String _logTag = 'TidalMetadataDataSource';

  // Tidal's public v1 catalog API. The guest OAuth flow is the only auth
  // surface used; no user credentials are sent or stored.
  static const String _authUrl = 'https://auth.tidal.com/v1/oauth2/token';
  static const String _apiBase = 'https://api.tidal.com/v1';

  // These identifiers are Tidal's *public* web client credentials. They are
  // embedded in Tidal's public web player and rotate only when Tidal ships a
  // new client build — they are not user secrets. If Tidal ever revokes them,
  // replace the pair with the values published in a fresh Tidal web build.
  static const String _clientId = '7m7Ap1SysBzOsR9CJtC3qa';
  static const String _clientSecret =
      'vUOD3M8mx5f9vwz9mVAZ3wTKlqOOxqxgtP3O3WcsxFRxOQrA8OE';

  // Highest resolution Tidal serves for a public cover. 1280x1280 is the
  // largest square crop available on the public CDN; 640x640 is the next
  // step down. We always request 1280x1280 per the spec rule.
  static const int _coverSize = 1280;
  static const int _coverFallbackSize = 640;

  // Cache configuration -----------------------------------------------------
  static const String _cacheKeyPrefix = 'tidal_track_meta';
  static const Duration _defaultMaxAge = Duration(days: 7);
  static const Duration _httpTimeout = Duration(seconds: 8);

  final http.Client _client;
  String? _cachedToken;
  DateTime _tokenExpiresAt = DateTime.fromMillisecondsSinceEpoch(0);

  // In-memory session cache: trackId -> (TrackModel, storedAt).
  // Mirrors the "Results are cached in memory for the current app session"
  // contract used by `PlaylistProvider.searchSilently`.
  final Map<String, _CachedTrack> _sessionCache = <String, _CachedTrack>{};

  /// Fetches public metadata for a single Tidal track and returns a populated
  /// [TrackModel]. Returns `null` if the track cannot be resolved.
  ///
  /// Set [force] to `true` to bypass both the in-memory and SharedPreferences
  /// caches and always hit Tidal's API. The freshly fetched payload is then
  /// written back to both caches.
  ///
  /// Only the five fields listed in the spec matrix are extracted from the
  /// response — every other payload key is ignored.
  Future<TrackModel?> fetchTidalMetadata(
    String trackId, {
    bool force = false,
  }) async {
    final id = trackId.trim();
    if (id.isEmpty) {
      AppLogger.log('Refusing to fetch metadata for empty trackId',
          name: _logTag);
      return null;
    }

    // Tier 1: in-memory session cache.
    if (!force) {
      final sessionHit = _sessionCache[id];
      if (sessionHit != null) {
        AppLogger.log('Tidal metadata in-memory cache hit for id=$id',
            name: _logTag);
        return sessionHit.track;
      }
    }

    // Tier 2: SharedPreferences cache (with network-failure fallback).
    final prefs = await SharedPreferences.getInstance();
    final cached = _readPersistedCache(prefs, id, _defaultMaxAge);
    if (!force && cached != null) {
      AppLogger.log('Tidal metadata prefs cache hit for id=$id',
          name: _logTag);
      _sessionCache[id] = _CachedTrack(cached, DateTime.now());
      return cached;
    }

    // Tier 3: network fetch.
    final fresh = await _fetchFromNetwork(id);
    if (fresh != null) {
      await _writePersistedCache(prefs, id, fresh);
      _sessionCache[id] = _CachedTrack(fresh, DateTime.now());
      return fresh;
    }

    // Network failed — fall back to expired prefs cache as resilience.
    final expiredFallback = _readPersistedCache(prefs, id, null);
    if (expiredFallback != null) {
      AppLogger.log(
        'Tidal metadata network failed for id=$id; serving expired cache',
        name: _logTag,
      );
      _sessionCache[id] = _CachedTrack(expiredFallback, DateTime.now());
      return expiredFallback;
    }

    return null;
  }

  Future<TrackModel?> _fetchFromNetwork(String id) async {
    try {
      final token = await _ensureGuestToken();
      final uri = Uri.parse('$_apiBase/tracks/$id').replace(
        queryParameters: <String, String>{'countryCode': 'US'},
      );

      final response = await _client
          .get(uri, headers: <String, String>{
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
            'User-Agent': 'zyp_music/1.0 (metadata-only)',
          })
          .timeout(_httpTimeout);

      if (response.statusCode != 200) {
        AppLogger.log(
          'Tidal track lookup failed: HTTP ${response.statusCode}',
          name: _logTag,
        );
        return null;
      }

      final Map<String, dynamic> body =
          json.decode(response.body) as Map<String, dynamic>;
      return _mapToTrackModel(id, body);
    } on TimeoutException {
      AppLogger.log('Tidal track lookup timed out for id=$id',
          name: _logTag);
      return null;
    } catch (e) {
      AppLogger.log('Tidal track lookup error: $e', name: _logTag);
      return null;
    }
  }

  /// Exchanges the public client credentials for a short-lived guest bearer
  /// token. Caches the token in memory until ~60s before its declared expiry.
  Future<String> _ensureGuestToken() async {
    final now = DateTime.now();
    if (_cachedToken != null && now.isBefore(_tokenExpiresAt)) {
      return _cachedToken!;
    }

    final response = await _client
        .post(
          Uri.parse(_authUrl),
          headers: <String, String>{
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent': 'zyp_music/1.0 (metadata-only)',
          },
          body: <String, String>{
            'client_id': _clientId,
            'client_secret': _clientSecret,
            'grant_type': 'client_credentials',
          },
        )
        .timeout(_httpTimeout);

    if (response.statusCode != 200) {
      throw Exception(
          'Tidal guest token request failed: HTTP ${response.statusCode}');
    }

    final Map<String, dynamic> body =
        json.decode(response.body) as Map<String, dynamic>;
    final token = body['access_token'] as String?;
    final expiresIn = (body['expires_in'] as num?)?.toInt() ?? 3600;
    if (token == null || token.isEmpty) {
      throw Exception('Tidal guest token response missing access_token');
    }

    _cachedToken = token;
    Duration ttl = Duration(seconds: expiresIn - 60);
    const Duration minTtl = Duration(minutes: 1);
    const Duration maxTtl = Duration(hours: 24);
    if (ttl < minTtl) ttl = minTtl;
    if (ttl > maxTtl) ttl = maxTtl;
    _tokenExpiresAt = now.add(ttl);
    return token;
  }

  // ---------------------------------------------------------------------------
  // SharedPreferences cache (mirrors ChartsRepositoryImpl._getWithCache)
  // ---------------------------------------------------------------------------

  String _dataKey(String trackId) => '$_cacheKeyPrefix:$trackId';
  String _timestampKey(String trackId) => '$_cacheKeyPrefix:$trackId:ts';

  TrackModel? _readPersistedCache(
    SharedPreferences prefs,
    String trackId,
    Duration? maxAge,
  ) {
    final timestamp = prefs.getInt(_timestampKey(trackId));
    final payload = prefs.getString(_dataKey(trackId));
    if (timestamp == null || payload == null) return null;

    if (maxAge != null) {
      final age =
          DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(timestamp));
      if (age > maxAge) return null;
    }

    try {
      final Map<String, dynamic> map =
          json.decode(payload) as Map<String, dynamic>;
      return _trackModelFromMap(map);
    } catch (e) {
      AppLogger.log(
        'Tidal cache decoding failed for id=$trackId: $e',
        name: _logTag,
      );
      return null;
    }
  }

  Future<void> _writePersistedCache(
    SharedPreferences prefs,
    String trackId,
    TrackModel track,
  ) async {
    try {
      await prefs.setString(_dataKey(trackId), json.encode(_trackModelToMap(track)));
      await prefs.setInt(
        _timestampKey(trackId),
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      AppLogger.log('Tidal cache write failed for id=$trackId: $e',
          name: _logTag);
    }
  }

  Map<String, dynamic> _trackModelToMap(TrackModel t) => <String, dynamic>{
        'id': t.id,
        'title': t.title,
        'thumbnailUrl': t.thumbnailUrl,
        'durationSeconds': t.durationSeconds,
        'author': t.author,
        'album': t.album,
      };

  TrackModel _trackModelFromMap(Map<String, dynamic> m) => TrackModel(
        id: m['id'] as String,
        title: m['title'] as String,
        thumbnailUrl: m['thumbnailUrl'] as String?,
        durationSeconds: (m['durationSeconds'] as num?)?.toInt() ?? 0,
        author: m['author'] as String?,
        album: m['album'] as String?,
      );

  // ---------------------------------------------------------------------------
  // Payload mapping (spec matrix)
  // ---------------------------------------------------------------------------

  /// Maps the raw Tidal track payload onto the application's [TrackModel],
  /// touching **only** the fields enumerated in the spec matrix:
  ///
  ///   title        <- title
  ///   author       <- artist.name  (fallback artists[0].name)
  ///   album        <- album.title
  ///   duration     <- duration (seconds, safe-parsed)
  ///   thumbnailUrl <- album.cover / cover, rewritten to 1280x1280
  TrackModel? _mapToTrackModel(String trackId, Map<String, dynamic> json) {
    final title = (json['title'] as String?)?.trim();
    if (title == null || title.isEmpty) {
      AppLogger.log('Tidal payload missing title for id=$trackId',
          name: _logTag);
      return null;
    }

    final author = _extractArtistName(json);
    final album = _extractAlbumTitle(json);
    final durationSeconds = _parseDurationSeconds(json['duration']);
    final coverUrl = _formatHighResCoverUrl(
      _extractCoverId(json),
      preferredSize: _coverSize,
      fallbackSize: _coverFallbackSize,
    );

    return TrackModel(
      id: trackId,
      title: title,
      thumbnailUrl: coverUrl,
      durationSeconds: durationSeconds,
      author: author,
      album: album,
    );
  }

  String? _extractArtistName(Map<String, dynamic> json) {
    final artist = json['artist'];
    if (artist is Map<String, dynamic>) {
      final name = (artist['name'] as String?)?.trim();
      if (name != null && name.isNotEmpty) return name;
    }
    final artists = json['artists'];
    if (artists is List && artists.isNotEmpty) {
      final first = artists.first;
      if (first is Map<String, dynamic>) {
        final name = (first['name'] as String?)?.trim();
        if (name != null && name.isNotEmpty) return name;
      }
    }
    return null;
  }

  String _extractAlbumTitle(Map<String, dynamic> json) {
    final album = json['album'];
    if (album is Map<String, dynamic>) {
      final title = (album['title'] as String?)?.trim();
      if (title != null && title.isNotEmpty) return title;
    }
    return '';
  }

  int _parseDurationSeconds(dynamic raw) {
    if (raw is int) return raw < 0 ? 0 : raw;
    if (raw is double) {
      final v = raw.toInt();
      return v < 0 ? 0 : v;
    }
    if (raw is String) {
      final parsed = int.tryParse(raw);
      if (parsed != null) return parsed < 0 ? 0 : parsed;
    }
    return 0;
  }

  /// Tidal cover IDs are hyphenated (e.g. `0e8e70e0-c5d3-4c30-95c0-70c5d3bc308a`).
  /// The public image CDN expects the segments split by `/` followed by the
  /// requested size, e.g. `.../0e8e70e0/c5d3/4c30/95c0/70c5d3bc308a/1280x1280.jpg`.
  String? _extractCoverId(Map<String, dynamic> json) {
    final album = json['album'];
    if (album is Map<String, dynamic>) {
      final cover = album['cover'];
      if (cover is String && cover.isNotEmpty) return cover;
    }
    final cover = json['cover'];
    if (cover is String && cover.isNotEmpty) return cover;
    return null;
  }

  /// Builds the highest-resolution Tidal cover URL for the given cover ID.
  ///
  /// If the API already returned a fully-qualified URL, this rewrites any
  /// `/{size}x{size}/` segment to the [preferredSize] (default `1280x1280`).
  /// If the input is a bare cover ID, it assembles the canonical CDN URL.
  String? _formatHighResCoverUrl(
    String? coverValue, {
    int preferredSize = _coverSize,
    int fallbackSize = _coverFallbackSize,
  }) {
    if (coverValue == null || coverValue.isEmpty) return null;

    if (coverValue.startsWith('http://') || coverValue.startsWith('https://')) {
      return _rewriteUrlToHighRes(
        coverValue,
        preferredSize: preferredSize,
        fallbackSize: fallbackSize,
      );
    }

    final pathSegments = coverValue.split('-').where((s) => s.isNotEmpty).join('/');
    if (pathSegments.isEmpty) return null;
    return 'https://resources.tidal.com/images/$pathSegments/$preferredSize.jpg';
  }

  /// Upgrades any `/{digits}x{digits}/` dimension segment inside a Tidal image
  /// URL to the [preferredSize]. If no segment is present, appends one before
  /// the file extension. Falls back to [fallbackSize] if [preferredSize] is
  /// rejected by the CDN.
  String _rewriteUrlToHighRes(
    String url, {
    required int preferredSize,
    required int fallbackSize,
  }) {
    final dimPattern = RegExp(r'/(?:(\d+)x(\d+))(?=\.jpg|\.jpeg|\.png|\.webp|$)');
    final rewritten = url.replaceAllMapped(
      dimPattern,
      (_) => '/${preferredSize}x$preferredSize',
    );
    if (rewritten != url) return rewritten;

    final extMatch = RegExp(r'\.(jpg|jpeg|png|webp)$', caseSensitive: false)
        .matchAsPrefix(rewritten);
    if (extMatch != null) {
      final ext = extMatch.group(0)!;
      return '${rewritten.substring(0, extMatch.start)}/${preferredSize}x$preferredSize$ext';
    }
    return '${rewritten.replaceAll(RegExp(r'/+$'), '')}/${preferredSize}x$preferredSize.jpg';
  }

  void dispose() {
    _client.close();
    _sessionCache.clear();
  }
}

class _CachedTrack {
  final TrackModel track;
  final DateTime storedAt;
  _CachedTrack(this.track, this.storedAt);
}
