import 'dart:async';
import 'dart:collection';

import '../../data/datasources/local/playlist_database.dart';
import '../../data/datasources/remote/musicbrainz_datasource.dart';
import '../../domain/entities/video.dart';
import '../utils/app_logger.dart';
import '../utils/normalise.dart';

class GenreEnrichmentService {
  final MusicBrainzDataSource _mb;
  final PlaylistDatabase _db;

  final Map<String, Future<void>> _inFlight = HashMap();
  final Queue<String> _fifo = Queue<String>();
  final Set<String> _queued = <String>{};
  Future<void> _worker = Future<void>.value();

  GenreEnrichmentService({
    required MusicBrainzDataSource mb,
    required PlaylistDatabase db,
  })  : _mb = mb,
        _db = db;

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
    return cached ?? const <String>[];
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
    if (cached != null && cached.isNotEmpty) return;
    final display = _displayForKey(normalizedKey);
    if (display == null) return;
    final match = await _mb.searchArtist(display);
    if (match == null) return;
    final entries = await _mb.getArtistGenres(match.mbid);
    if (entries.isEmpty) {
      await _db.cacheArtistGenres(
        normalizedArtist: normalizedKey,
        displayName: match.name,
        mbid: match.mbid,
        genres: const [],
      );
      return;
    }
    entries.sort((a, b) => b.count.compareTo(a.count));
    final names = entries.map((e) => e.name).toList(growable: false);
    await _db.cacheArtistGenres(
      normalizedArtist: normalizedKey,
      displayName: match.name,
      mbid: match.mbid,
      genres: names,
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
