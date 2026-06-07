import 'dart:async';
import 'dart:collection';

import '../../data/datasources/local/playlist_database.dart';
import '../../data/datasources/remote/musicbrainz_datasource.dart';
import '../../domain/entities/video.dart';
import '../utils/app_logger.dart';
import '../utils/normalise.dart';
import 'genre_normalization_service.dart';

class GenreEnrichmentService {
  final MusicBrainzDataSource _mb;
  final PlaylistDatabase _db;
  final GenreNormalizationService _normalization;

  final Map<String, Future<void>> _inFlight = HashMap();
  final Queue<String> _fifo = Queue<String>();
  final Set<String> _queued = <String>{};
  Future<void> _worker = Future<void>.value();

  GenreEnrichmentService({
    required MusicBrainzDataSource mb,
    required PlaylistDatabase db,
    required GenreNormalizationService normalization,
  })  : _mb = mb,
        _db = db,
        _normalization = normalization;

  /// Synchronous path used by the Auto DJ routing layer when the
  /// seed track has no genre tag on the wire. Returns the cached
  /// genre list for the track's artist if the database already
  /// has one; otherwise returns an empty list so the caller can
  /// fall through to the existing dominant-genre interceptor.
  /// Never blocks on a network round-trip — that's
  /// [enqueueForEnrichment]'s job.
  Future<List<String>> readCached(Track track) async {
    final key = _keyFor(track);
    if (key == null) return const <String>[];
    final cached = await _db.getCachedArtistGenres(key);
    if (cached == null) return const <String>[];
    return cached.rawGenres;
  }

  /// Synchronous read of the already-normalized matrix keys for
  /// [track]'s artist. Returns an empty list on cache miss or when
  /// the cache row predates Spec 2A (no `normalized_genres_json`
  /// column populated). Used by the AI DJ scoring engine on the
  /// hot path — it does NOT want to block on a dictionary lookup
  /// or a re-normalization pass. Spec 2A §3B.
  Future<List<String>> readNormalized(Track track) async {
    final key = _keyFor(track);
    if (key == null) return const <String>[];
    final cached = await _db.getCachedArtistGenres(key);
    if (cached == null) return const <String>[];
    return cached.normalizedGenres;
  }

  /// Enriches [track] in place if a cached entry exists. Used by
  /// the Auto DJ routing layer immediately before it consults the
  /// dominant-genre interceptor so a previously-enriched artist
  /// can short-circuit the heuristic.
  Future<List<String>> enrichSync(Track track) async {
    return readCached(track);
  }

  /// Fire-and-forget background enrichment. Coalesces concurrent
  /// requests for the same artist and walks the MusicBrainz gate
  /// serially via [MusicBrainzDataSource._enqueue]. Persists the
  /// result in the `artist_genres` table so the next call hits the
  /// cache. Returns immediately; the caller MUST NOT await this
  /// for routing decisions.
  void enqueueForEnrichment(Iterable<Track> tracks) {
    for (final t in tracks) {
      final key = _keyFor(t);
      if (key == null) continue;
      if (_inFlight.containsKey(key)) continue;
      if (_queued.contains(key)) continue;
      _queued.add(key);
      _fifo.add(key);
    }
    if (_fifo.isEmpty) return;
    _worker = _worker.then((_) => _drain());
  }

  /// Awaitable barrier: resolves when the FIFO worker has drained
  /// every enqueued artist. Useful for tests that want to assert
  /// on the post-enrichment cache state without sleeping for the
  /// MusicBrainz 1-req/sec throttle. Safe to call when no work is
  /// in flight — returns immediately.
  Future<void> drain() {
    return _worker;
  }

  Future<void> _drain() async {
    while (_fifo.isNotEmpty) {
      final key = _fifo.removeFirst();
      _queued.remove(key);
      if (_inFlight.containsKey(key)) continue;
      final future = _enrichOne(key);
      _inFlight[key] = future;
      try {
        await future;
      } catch (e) {
        AppLogger.log(
          'Genre enrichment failed for $key: $e',
          name: 'GenreEnrichmentService',
        );
      } finally {
        _inFlight.remove(key);
      }
    }
  }

  Future<void> _enrichOne(String normalizedKey) async {
    final cached = await _db.getCachedArtistGenres(normalizedKey);
    if (cached != null && cached.rawGenres.isNotEmpty) return;
    final display = _displayForKey(normalizedKey);
    if (display == null) return;
    final match = await _mb.searchArtist(display);
    if (match == null) return;
    final entries = await _mb.getArtistGenres(match.mbid);
    if (entries.isEmpty) {
      final confidence = match.score;
      await _db.cacheArtistGenres(
        normalizedArtist: normalizedKey,
        displayName: match.name,
        mbid: match.mbid,
        genres: const [],
        normalizedGenres: const [],
        confidence: confidence,
        countryCode: match.country,
      );
      return;
    }
    entries.sort((a, b) => b.count.compareTo(a.count));
    final names = entries.map((e) => e.name).toList(growable: false);
    final normalizedGenres = _normalization.normalizeAll(names);
    final confidence = match.score;
    await _db.cacheArtistGenres(
      normalizedArtist: normalizedKey,
      displayName: match.name,
      mbid: match.mbid,
      genres: names,
      normalizedGenres: normalizedGenres,
      confidence: confidence,
      countryCode: match.country,
    );
  }

  String? _keyFor(Track t) {
    final author = t.author?.trim();
    if (author == null || author.isEmpty) return null;
    return normalise(author);
  }

  String? _displayForKey(String key) {
    return key;
  }
}
