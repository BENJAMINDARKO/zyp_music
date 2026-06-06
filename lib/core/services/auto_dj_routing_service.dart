import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../domain/entities/auto_dj_mode.dart';
import '../../domain/entities/video.dart';
import '../utils/app_logger.dart';
import 'dj_history_ledger.dart';
import 'genre_proximity_graph.dart';
import 'local_crate_miner.dart';

/// Network-connectivity signal used by the routing service. The
/// QueueManager's existing `NetworkState` enum (online / offline /
/// unknown) maps to this via a one-line adapter.
enum NetworkAvailability { online, offline, unknown }

/// Function signature for the optional online Similar-Songs fetcher.
/// Production code injects a closure that delegates to
/// `AudioRepository.getUpNexts`; tests inject a fake that returns a
/// fixed list (or `null` to simulate the endpoint being down).
typedef OnlineSimilarFetcher = Future<List<Track>?> Function(Track current);

/// Function signature for the connectivity probe. Mirrors the
/// QueueManager's `connectivity.state` getter.
typedef ConnectivityProbe = NetworkAvailability Function();

/// Serializable payload for the Smart-DJ scoring isolate.
///
/// The `compute()` boundary forbids live object references, so
/// the routing service serialises the entire scoring context
/// into this primitive-only structure before crossing into the
/// background isolate. Reconstruction of the lightweight
/// `Map<String, dynamic>` shapes happens inside
/// [_smartDjIsolateScore], and the engine's core
/// [AutoDjRoutingService] (which holds the database references)
/// is never reachable from the isolate thread.
class _SmartDjScoreInput {
  final List<Map<String, dynamic>> candidates;
  final List<Map<String, dynamic>> stateEntries;
  final List<Map<String, dynamic>> fullHistory;
  final List<String> topLikedArtists;
  final List<String> topLikedGenres;
  final double beta;

  const _SmartDjScoreInput({
    required this.candidates,
    required this.stateEntries,
    required this.fullHistory,
    required this.topLikedArtists,
    required this.topLikedGenres,
    required this.beta,
  });
}

/// Top-level entry point for the Smart-DJ scoring
/// `compute()` isolate. Reconstructs the lightweight scoring
/// context from the serialised payload, runs the Markov +
/// Liked-Song fusion per candidate, and returns a flat
/// `List<Map<String, dynamic>>` of `{trackId, score}` so the
/// caller can pair it back with the in-memory candidate pool
/// without exposing any model objects across the boundary.
List<Map<String, dynamic>> _smartDjIsolateScore(
    _SmartDjScoreInput input) {
  final topLikedArtistsLower =
      input.topLikedArtists.map((a) => a.toLowerCase()).toSet();
  final topLikedGenresLower = input.topLikedGenres.toSet();

  // Reconstruct the state + fullHistory as `Map<String, dynamic>`
  // lookups compatible with the existing `_markovScore` shape
  // (the engine reads `state[i].trackId`, `state[i].artistName`,
  // `state[i].primaryGenre`).
  final state = input.stateEntries;
  final fullHistory = input.fullHistory;

  final results = <Map<String, dynamic>>[];
  for (final c in input.candidates) {
    // Re-implement `_markovScore` here because the static
    // boundary cannot reach the engine's instance method.
    // The arithmetic mirrors the instance helper 1:1.
    final a = state.isEmpty ? null : state.first;
    final candidateArtistLower = (c['author'] as String?)?.toLowerCase();
    final artistMatch = a != null &&
        candidateArtistLower != null &&
        (a['artistName'] as String).toLowerCase() == candidateArtistLower;
    final genreMatch = a != null &&
        (a['primaryGenre'] as String) != 'Unknown' &&
        (a['primaryGenre'] as String) == c['genre'];

    int matchingContext = 0;
    int transitionsToCandidate = 0;
    if (fullHistory.length > state.length) {
      for (var i = 0; i + state.length < fullHistory.length; i++) {
        final window = fullHistory.sublist(i, i + state.length);
        bool ok = true;
        for (var j = 0; j < state.length; j++) {
          if (window[j]['trackId'] != state[j]['trackId']) {
            ok = false;
            break;
          }
        }
        if (!ok) continue;
        matchingContext++;
        final next = fullHistory[i + state.length];
        if (next['trackId'] == c['id'] ||
            (candidateArtistLower != null &&
                (next['artistName'] as String).toLowerCase() ==
                    candidateArtistLower &&
                next['primaryGenre'] == c['genre'])) {
          transitionsToCandidate++;
        }
      }
    }
    final temporal = matchingContext == 0
        ? 0.0
        : transitionsToCandidate / matchingContext;

    final markov = (artistMatch ? 0.5 : 0.0) +
        (genreMatch ? 0.3 : 0.0) +
        0.2 * temporal;

    // Liked-Song affinity with the null-genre reallocation
    // guard. The static helper is exposed as a top-level
    // function so the isolate can call it without holding
    // a back-pointer to the engine.
    final affinity = AutoDjRoutingService.likedAffinityFor(
      c,
      topLikedArtistsLower,
      topLikedGenresLower,
    );

    final blended = (1.0 - input.beta) * markov + input.beta * affinity;
    results.add(<String, dynamic>{
      'trackId': c['id'],
      'score': blended,
    });
  }
  return results;
}

/// The 5-mode AI DJ routing engine. Receives the current track and
/// the user-selected [AutoDJMode], returns the next track to queue,
/// or `null` if no candidate is available.
///
/// All five active modes (Shuffle Library, Similar Songs, Same
/// Genre, Same Artist, Smart DJ) share three infrastructure
/// components:
///
/// * A [LocalCrateMiner] that supplies the on-disk-verified
///   candidate pool (the spec's "Dual-Database Local Crate Miner").
/// * A [GenreProximityGraph] that drives the Same-Genre and
///   Same-Artist fallback traversal.
/// * A [DJHistoryLedger] that supplies the Smart-DJ Markov corpus.
///
/// The [OnlineSimilarFetcher] and [ConnectivityProbe] are injected
/// function references so the unit tests can drive the
/// online/offline branching without spinning up the rest of the
/// app.
class AutoDjRoutingService {
  static const String _logTag = 'AutoDjRoutingService';

  /// Number of consecutive history rows the Smart-DJ Markov state
  /// spans. The spec is explicit: "Evaluate the last 3 tracks
  /// committed to your history rows" — so the state is a 3-token
  /// window and the engine emits a 2-step transition context.
  static const int _markovWindow = 3;

  /// Optional RNG injected for stochastic selection paths (the
  /// Same-Genre roulette wheel and the random-zero-sum fallback).
  /// Tests inject a seeded [Random] (e.g. `Random(42)`) for
  /// deterministic assertions.
  final Random _random;

  final LocalCrateMiner _crateMiner;
  final GenreProximityGraph _graph;
  final DJHistoryLedger? _historyLedger;
  final OnlineSimilarFetcher? _onlineFetcher;
  final ConnectivityProbe _connectivityProbe;

  /// Smart DJ bootstrap-fusion cache: the number of rows in
  /// `dj_listening_history` at last invalidation. Read directly
  /// by [likedAffinityWeight] (the linear-decay matrix) so
  /// every [resolveNext] call avoids a synchronous database
  /// round-trip. Populated once at boot via
  /// [bootstrapLikedSongs] and bumped by
  /// [notifyHistoryRowCommitted] every time the application
  /// commits a new row to the ledger.
  int _cachedHistoryCount = 0;

  /// Smart DJ bootstrap-fusion cache: the user's Top 5 Most
  /// Liked Artists, computed once at boot by
  /// [bootstrapLikedSongs] from the local `favorite_tracks`
  /// table. The affinity scorer ([_likedAffinityFor]) consults
  /// this list to award the 0.6 artist component of
  /// $L_{affinity}$.
  List<String> _topLikedArtists = const <String>[];

  /// Smart DJ bootstrap-fusion cache: the user's Top 5 Most
  /// Liked Genres, computed once at boot by
  /// [bootstrapLikedSongs] from the local `favorite_tracks`
  /// (joined against `track_metadata`). The affinity scorer
  /// consults this list to award the 0.4 genre component of
  /// $L_{affinity}$ — except when the candidate's genre is
  /// null / empty / `"Unknown"`, in which case the genre
  /// weight is reallocated to the artist component per the
  /// spec's null-defensiveness rule.
  List<String> _topLikedGenres = const <String>[];

  /// Maximum history row count at which the linear-decay
  /// Liked-Song bias reaches zero. The spec defines β as
  /// `max(0.0, 0.6 * (1.0 - H/150))`; at H=150 β collapses
  /// to 0 and the engine runs in pure-Markov mode. Surfaced
  /// as a constant so the formula's behaviour is grep-able
  /// from any caller.
  static const int _likedBiasWindow = 150;

  /// The peak β at cold start. The spec defines the 60%
  /// Liked / 40% Live ratio at H=0; this is the upper bound
  /// of the linear decay.
  static const double _likedBiasPeak = 0.6;

  AutoDjRoutingService({
    required LocalCrateMiner crateMiner,
    GenreProximityGraph? graph,
    DJHistoryLedger? historyLedger,
    OnlineSimilarFetcher? onlineFetcher,
    ConnectivityProbe? connectivityProbe,
    Random? random,
    int initialHistoryCount = 0,
    List<String> topLikedArtists = const <String>[],
    List<String> topLikedGenres = const <String>[],
  })  : _crateMiner = crateMiner,
        _graph = graph ?? const GenreProximityGraph(),
        _historyLedger = historyLedger,
        _onlineFetcher = onlineFetcher,
        _connectivityProbe = connectivityProbe ?? (() => NetworkAvailability.unknown),
        _random = random ?? Random(),
        _cachedHistoryCount = initialHistoryCount,
        _topLikedArtists = List<String>.unmodifiable(topLikedArtists),
        _topLikedGenres = List<String>.unmodifiable(topLikedGenres);

  /// Late-binds the bootstrap-fusion cache. Called by
  /// [PlayerProvider] when the local `favorite_tracks` table
  /// has been read once. The provider computes the Top 5
  /// Artists / Genres via the existing
  /// `PlaylistRepository.getFavoriteTracks()` and hands the
  /// primitive [String] lists down to the engine, satisfying
  /// the spec's "no live database references cross the
  /// isolate boundary" rule. The [_cachedHistoryCount] is
  /// re-seeded here so the linear-decay weight is correct on
  /// the very first [resolveNext] call.
  void bootstrapLikedSongs({
    required int initialHistoryCount,
    required List<String> topLikedArtists,
    required List<String> topLikedGenres,
  }) {
    _cachedHistoryCount = initialHistoryCount;
    _topLikedArtists = List<String>.unmodifiable(topLikedArtists);
    _topLikedGenres = List<String>.unmodifiable(topLikedGenres);
    AppLogger.log(
      '[SmartDJFusion] Bootstrapped liked-songs cache: '
      'historyCount=$initialHistoryCount '
      'topArtists=$topLikedArtists '
      'topGenres=$topLikedGenres',
      name: _logTag,
    );
  }

  /// Increments [_cachedHistoryCount] by one. Called by
  /// [PlayerProvider] immediately after
  /// `DJHistoryLedger.logTrack(...)` resolves successfully —
  /// i.e. inside the successful completion closure of the
  /// only production write path to `dj_listening_history`.
  /// Kept as a tiny method (one-liner plus log) so the
  /// call site reads as a single intent statement.
  void notifyHistoryRowCommitted() {
    _cachedHistoryCount += 1;
    AppLogger.log(
      '[SmartDJFusion] History row committed; '
      '_cachedHistoryCount=$_cachedHistoryCount',
      name: _logTag,
    );
  }

  /// The current Liked-Song bias weight β, computed via the
  /// spec's linear decay:
  ///
  ///   β = max(0.0, 0.6 * (1.0 - H / 150))
  ///
  /// At H = 0 the engine runs at 60% Liked / 40% Live. At
  /// H ≥ 150 the bias collapses to 0 and the engine runs
  /// in pure-Markov mode.
  double get likedAffinityWeight {
    final h = _cachedHistoryCount;
    if (h >= _likedBiasWindow) return 0.0;
    final raw = _likedBiasPeak * (1.0 - h / _likedBiasWindow);
    return raw < 0.0 ? 0.0 : raw;
  }

  /// Exposed for tests / telemetry.
  int get cachedHistoryCount => _cachedHistoryCount;
  List<String> get topLikedArtists => _topLikedArtists;
  List<String> get topLikedGenres => _topLikedGenres;

  /// The most-recently re-anchored seed track. Surfaced for telemetry
  /// and the routing post-mortem log; the per-mode strategies still
  /// receive the seed via the `current` parameter on every
  /// [resolveNext] call (the seed is implicit in the playback flow),
  /// so this field is observational only.
  Track? _currentSeed;
  Track? get currentSeed => _currentSeed;

  /// Convenience getter mirroring the spec's
  /// `autoDjService.currentSeedArtist` field. Returns the seed's
  /// `author` (the YouTube Music / YouTube "artist" field on
  /// [Track]) so callers don't have to peel the seed open.
  String? get currentSeedArtist => _currentSeed?.author;

  /// Re-anchors the active seed parameters to [newTrack]. Called by
  /// [QueueManager.updateActiveSeedProfile] when the user manually
  /// loads a new track via a tile tap, context menu, search
  /// selection, or playlist open while Auto DJ is armed.
  ///
  /// The re-anchor is intentionally lightweight:
  ///
  ///   * Records [newTrack] as the new seed for telemetry.
  ///   * Logs the artist / genre fingerprint of the new seed so the
  ///     routing post-mortem makes it clear which manual swap
  ///     triggered the next batch of recommendations.
  ///
  /// The per-mode dedupe state (the Shuffle Library rolling window,
  /// the recent-session id set held on [QueueManager]) is left
  /// untouched on purpose — the user's intent is "keep the same DJ
  /// session running but pivot the seed", not "start a fresh
  /// session". The next 15-second-lookahead trigger will pass the
  /// new seed into [resolveNext] via the `current` parameter, at
  /// which point every active strategy parses the fresh artist /
  /// genre keys (e.g. *Kwesi Arthur* parameters for Same Artist)
  /// and continues uninterrupted music generation.
  void updateActiveSeedProfile(Track newTrack) {
    _currentSeed = newTrack;
    AppLogger.log(
      '[AutoDJAnchor] Re-anchored seed profile: track="${newTrack.title}" '
      'artist=${newTrack.author ?? 'Unknown'} '
      'genre=${newTrack.genre ?? 'Unknown'}',
      name: _logTag,
    );
  }

  /// Public entry point. Routes the request through the per-mode
  /// strategy and returns the chosen track (or null).
  ///
  /// [recentIds] is the spec's "runtime session memory array
  /// tracking recently played song IDs" — every mode is required
  /// to consult it and never return a track whose id is in the
  /// set. Pass the union of the currently-playing track id and any
  /// session-recently-played ids.
  ///
  /// [history] is the same-genre artist's "3-track extended memory
  /// artist-penalization matrix" feed: the most-recently-played
  /// [Track] objects in chronological order (index 0 is the
  /// immediate last track). Modes other than Same-Genre ignore
  /// the parameter. Callers MUST pass an immutable list (the
  /// routing service does not mutate it).
  Future<Track?> resolveNext({
    required AutoDJMode mode,
    required Track current,
    required Set<String> recentIds,
    List<Track> history = const <Track>[],
  }) async {
    final exclude = <String>{...recentIds, current.id};
    AppLogger.log(
      'resolveNext mode=${mode.name} current=${current.id} '
      'exclude.size=${exclude.length} history.size=${history.length}',
      name: _logTag,
    );

    // Bugfix: Guard against cold-boot dummy tracking requests.
    // When the engine is in Armed Standby (mode selected on empty
    // queue), the caller passes a placeholder seed. Return null so
    // no lookup, fetch, or fallback tokens are generated until the
    // user explicitly picks their first track.
    if (current.id == '__cold_start_seed__') {
      AppLogger.log(
        '[AutoDJEngine] Empty or dummy seed detected. Entering '
        'Armed Standby. Waiting for explicit user track choice.',
        name: _logTag,
      );
      return null;
    }

    switch (mode) {
      case AutoDJMode.off:
        return null;

      case AutoDJMode.shuffleLibrary:
        return _shuffleLibrary(current, exclude);

      case AutoDJMode.similarSongs:
        return _similarSongs(current, exclude);

      case AutoDJMode.sameGenre:
        return _sameGenre(current, exclude, history);

      case AutoDJMode.sameArtist:
        return _sameArtist(current, exclude);

      case AutoDJMode.smartDj:
        return _smartDj(current, exclude);
    }
  }

  // ---------------------------------------------------------------------------
  // Per-mode strategies
  // ---------------------------------------------------------------------------

  /// Shuffle Library: forced offline (the spec says "Regardless of
  /// whether the system reports a valid network handshake, this
  /// mode must entirely bypass web discovery engines"). Pulls the
  /// crate, applies the **20-song rolling window dedup** so a
  /// track is never repeated until at least 20 *unique* library
  /// tracks have been processed, and returns the first surviving
  /// candidate.
  ///
  /// The rolling window is held in the service instance so it
  /// survives across the Auto DJ completion loop. Per the spec:
  ///
  ///   * If the local library has < 20 songs, the dedup window
  ///     is sized to the total library count.
  ///   * If the window is exhausted (every candidate has been
  ///     picked), the window is cleared and a fresh set is
  ///     drawn.
  ///   * The window slides: every new pick evicts the oldest
  ///     entry to keep the dedup horizon rolling.
  final List<String> _previousBlockTrackIds = <String>[];
  final List<String> _currentBlockTrackIds = <String>[];

  void _generateNextBlock(List<String> allIds) {
    final totalLibraryCount = allIds.length;
    final targetSize = totalLibraryCount < 20 ? totalLibraryCount : 20;

    final rawCandidates = List<String>.from(allIds);
    rawCandidates.removeWhere((id) => _previousBlockTrackIds.contains(id));

    if (rawCandidates.isEmpty && allIds.isNotEmpty) {
      _previousBlockTrackIds.clear();
      rawCandidates.addAll(allIds);
    }

    rawCandidates.shuffle(_random);

    _previousBlockTrackIds.clear();
    _previousBlockTrackIds.addAll(_currentBlockTrackIds);

    _currentBlockTrackIds.clear();
    _currentBlockTrackIds.addAll(rawCandidates.take(targetSize));
  }

  bool _artistMatches(String? candidateArtist, String seedArtist) {
    if (candidateArtist == null) return false;
    final candidateLower = candidateArtist.toLowerCase();
    final seedLower = seedArtist.toLowerCase();
    if (candidateLower == seedLower) return true;

    final separators = RegExp(r'\b(feat\.?|ft\.?|&|,|and|with)\b', caseSensitive: false);
    final parts = candidateLower.split(separators);
    for (var part in parts) {
      if (part.trim() == seedLower) return true;
    }
    return false;
  }

  Future<Track?> _shuffleLibrary(Track current, Set<String> exclude) async {
    final crate = await _crateMiner.mine();
    if (crate.isEmpty) {
      AppLogger.log('Shuffle Library: crate is empty.', name: _logTag);
      return null;
    }
    final allIds = crate.map((t) => t.id).toList();

    if (_currentBlockTrackIds.isEmpty) {
      _generateNextBlock(allIds);
      AppLogger.log('Shuffle Library: Generated new block: ${_currentBlockTrackIds.length} tracks', name: _logTag);
    }

    String? pickedId;
    for (final id in _currentBlockTrackIds) {
      if (!exclude.contains(id) && allIds.contains(id)) {
        pickedId = id;
        break;
      }
    }

    if (pickedId == null) {
      _generateNextBlock(allIds);
      AppLogger.log('Shuffle Library: Current block exhausted or excluded, regenerated next block: ${_currentBlockTrackIds.length} tracks', name: _logTag);
      for (final id in _currentBlockTrackIds) {
        if (!exclude.contains(id) && allIds.contains(id)) {
          pickedId = id;
          break;
        }
      }
    }

    if (pickedId == null) {
      final fallback = crate.where((t) => !exclude.contains(t.id)).toList();
      if (fallback.isEmpty) {
        AppLogger.log('Shuffle Library: No fallback tracks available.', name: _logTag);
        return null;
      }
      fallback.shuffle(_random);
      final track = fallback.first;
      AppLogger.log('Shuffle Library: Block selection failed, fell back to random track: ${track.title} (${track.id})', name: _logTag);
      return track;
    }

    _currentBlockTrackIds.remove(pickedId);
    final track = crate.firstWhere((t) => t.id == pickedId);
    AppLogger.log('Shuffle Library: Picked track: ${track.title} (${track.id}), remaining in block: ${_currentBlockTrackIds.length}', name: _logTag);
    return track;
  }

  Future<Track?> _similarSongs(Track current, Set<String> exclude) async {
    final fetcher = _onlineFetcher;
    final isOnline = fetcher != null && _connectivityProbe() == NetworkAvailability.online;
    AppLogger.log('Similar Songs: isOnline=$isOnline, seed=${current.title} (${current.id}), genre=${current.genre}', name: _logTag);

    if (current.genre == null) {
      AppLogger.warning(
        '[Similar Songs] Seed track ${current.id} has no genre metadata; '
        'bypassing similarity path and engaging Shuffle Library safety '
        'fallback tracker.',
        name: _logTag,
      );
      return _shuffleLibrary(current, exclude);
    }

    if (isOnline) {
      try {
        final online = await fetcher(current);
        if (online == null || online.isEmpty) {
          AppLogger.warning(
            '[Similar Songs] Match query returned 0 nodes for trackId: '
            '${current.id}. Engaging safety fallback tracker.',
            name: _logTag,
          );
          return _shuffleLibrary(current, exclude);
        }
        final candidates = online.where((t) => !exclude.contains(t.id)).toList();
        AppLogger.log('Similar Songs: Fetched ${online.length} online recommendations, ${candidates.length} unique candidates', name: _logTag);
        if (candidates.isNotEmpty) {
          final exactGenreMatch = candidates.firstWhere(
            (t) => t.genre != null && t.genre == current.genre,
            orElse: () => const _SentinelTrack(),
          );
          if (exactGenreMatch is! _SentinelTrack) {
            AppLogger.log('Similar Songs: Exact genre match found online: ${exactGenreMatch.title} (${exactGenreMatch.id})', name: _logTag);
            return exactGenreMatch;
          }

          final neighbors = _graph.neighborsOf(current.genre);
          final neighborMatch = candidates.firstWhere(
            (t) => t.genre != null && neighbors.containsKey(t.genre),
            orElse: () => const _SentinelTrack(),
          );
          if (neighborMatch is! _SentinelTrack) {
            AppLogger.log('Similar Songs: Neighboring genre match found online: ${neighborMatch.title} (${neighborMatch.id})', name: _logTag);
            return neighborMatch;
          }

          final track = candidates.first;
          AppLogger.log('Similar Songs: No genre/neighbor match online, selecting first candidate: ${track.title} (${track.id})', name: _logTag);
          return track;
        }
      } catch (e) {
        AppLogger.warning(
          '[Similar Songs] SimilarAutoNext network fetch failed: $e. '
          'Engaging safety fallback tracker.',
          name: _logTag,
        );
        return _shuffleLibrary(current, exclude);
      }
    }
    AppLogger.log('Similar Songs: Falling back to local attribute intersection.', name: _logTag);
    final track = await _attributeIntersection(current, exclude);
    if (track != null) {
      AppLogger.log('Similar Songs: Picked local match: ${track.title} (${track.id}), genre=${track.genre}', name: _logTag);
      return track;
    }
    AppLogger.warning(
      '[Similar Songs] No local attribute-intersection match for '
      'trackId: ${current.id}. Engaging safety fallback tracker.',
      name: _logTag,
    );
    return _shuffleLibrary(current, exclude);
  }

  Future<Track?> _sameGenre(
    Track current,
    Set<String> exclude,
    List<Track> history,
  ) async {
    final candidates = <Track>[];

    final offline = await _crateMiner.mine(excludeIds: exclude);
    candidates.addAll(offline);
    AppLogger.log('Same Genre: mined ${offline.length} offline candidates.', name: _logTag);

    final fetcher = _onlineFetcher;
    final isOnline = fetcher != null && _connectivityProbe() == NetworkAvailability.online;
    if (isOnline) {
      try {
        final online = await fetcher(current);
        if (online != null && online.isNotEmpty) {
          final uniqueOnline = online.where((t) => !exclude.contains(t.id));
          candidates.addAll(uniqueOnline);
          AppLogger.log('Same Genre: Fetched ${online.length} online tracks, added ${uniqueOnline.length} unique candidates.', name: _logTag);
        }
      } catch (e) {
        AppLogger.log('Online same-genre fetch failed: $e', name: _logTag);
      }
    }

    if (candidates.isEmpty) {
      AppLogger.log('Same Genre: Candidate pool is empty.', name: _logTag);
      return null;
    }

    final seenIds = <String>{};
    final uniqueCandidates = <Track>[];
    for (final t in candidates) {
      if (seenIds.add(t.id)) {
        uniqueCandidates.add(t);
      }
    }

    // Full BFS sweep up to depth 3 — gather every candidate that
    // matches any reachable genre. The previous "first-hit"
    // termination was deterministic and caused the engine to
    // lock onto a small set of tracks at the head of the crate
    // (the same `Rock` row was returned over and over). Walking
    // the full neighbourhood lets the roulette wheel below
    // exercise the artist-penalty matrix on a much richer pool.
    final rawCandidates = _harvestBfsCandidates(
      seedGenre: current.genre,
      candidates: uniqueCandidates,
    );
    if (rawCandidates.isEmpty) {
      AppLogger.log('Same Genre: BFS sweep yielded no candidates.', name: _logTag);
      return null;
    }
    AppLogger.log(
      'Same Genre: BFS sweep harvested ${rawCandidates.length} candidates '
      'from seed=${current.genre} (history.size=${history.length}).',
      name: _logTag,
    );

    // Score every harvested candidate with the
    // 3-track extended memory artist-penalization matrix.
    // S_final = W_path * A_penalty where:
    //   * W_path comes from the genre graph (1-hop lookup with
    //     a 0.55 floor for multi-hop genres).
    //   * A_penalty is 0.15 / 0.40 / 0.65 / 1.0 depending on
    //     whether the candidate's artist matches history[0],
    //     history[1], history[2], or none of them.
    // The list is walked in BFS priority order so the
    // cumulative-sum anchor stays deterministic; the roulette
    // pointer is the only stochastic component.
    final scoredPool = <MapEntry<Track, double>>[];
    double cumulativeScoreSum = 0.0;
    for (final track in rawCandidates) {
      final wPath = _pathProximity(current.genre, track.genre);
      final aPenalty = _artistDecayPenalty(track, history);
      final finalScore = wPath * aPenalty;
      if (finalScore > 0.0) {
        cumulativeScoreSum += finalScore;
        scoredPool.add(MapEntry<Track, double>(track, cumulativeScoreSum));
      }
    }

    // Random-zero-sum fallback: when every candidate shares an
    // artist with the 3-track history (the common case after
    // several manual skips in a row), the cumulative sum can
    // collapse to 0.0. The pre-refactor `rawCandidates.first`
    // path was deterministic and alphabetised the picks, so
    // the engine visibly looped on a single track. We use the
    // injected RNG to pick a random index from the FULL
    // harvested set, preserving unpredictable variance.
    if (cumulativeScoreSum == 0.0) {
      final fallbackIndex = _random.nextInt(rawCandidates.length);
      final fallbackTrack = rawCandidates[fallbackIndex];
      AppLogger.log(
        'Same Genre: Cumulative score collapsed to 0; random '
        'fallback selected index $fallbackIndex -> '
        '${fallbackTrack.title} (${fallbackTrack.id})',
        name: _logTag,
      );
      return fallbackTrack;
    }

    // Proportional fitness wheel: generate a uniform double in
    // [0, ΣS) and walk the cumulative array until the running
    // sum crosses the pointer. The first candidate to do so
    // wins. Because `_random` is injected with a seeded
    // instance in tests, the selection is fully reproducible.
    final rouletteTarget = _random.nextDouble() * cumulativeScoreSum;
    for (final entry in scoredPool) {
      if (entry.value >= rouletteTarget) {
        final picked = entry.key;
        AppLogger.log(
          'Same Genre: Roulette wheel landed on '
          '${picked.title} (${picked.id}) at pointer=$rouletteTarget '
          '(cumulative=${entry.value}).',
          name: _logTag,
        );
        return picked;
      }
    }
    // Defensive tail-return: floating-point rounding can leave
    // the last cumulative entry just below the pointer; the
    // trailing candidate is the highest-scoring one and is the
    // safest pick in that edge case.
    return scoredPool.last.key;
  }

  /// Walks the genre proximity graph in BFS order (already capped
  /// at depth 3 by the underlying graph implementation) and
  /// returns **every** candidate whose `genre` matches any
  /// reachable node, in priority order. The previous BFS
  /// implementation terminated on the first hit; this one
  /// completes a full sweep so the roulette wheel has a rich
  /// pool to draw from.
  List<Track> _harvestBfsCandidates({
    required String? seedGenre,
    required List<Track> candidates,
  }) {
    final harvested = <Track>[];
    final harvestedIds = <String>{};
    for (final g in _graph.searchBreadth(seedGenre)) {
      for (final t in candidates) {
        if (harvestedIds.contains(t.id)) continue;
        if ((t.genre ?? 'Unknown') == g) {
          harvested.add(t);
          harvestedIds.add(t.id);
        }
      }
    }
    return harvested;
  }

  /// W_path lookup. The graph exposes 1-hop weights via
  /// [GenreProximityGraph.neighborsOf] (preserves the const
  /// adjacency map). For the seed itself, weight is 1.0 (exact
  /// match). For multi-hop genres that the BFS has walked
  /// through, we use the graph's documented floor weight of
  /// 0.55 (the lower bound of the `[0.55, 0.95]` band) so the
  /// matrix has a non-zero contribution even for distant
  /// neighbours.
  double _pathProximity(String? seedGenre, String? trackGenre) {
    if (seedGenre == null || trackGenre == null) return 0.55;
    if (seedGenre == trackGenre) return 1.0;
    final neighbors = _graph.neighborsOf(seedGenre);
    final w = neighbors[trackGenre];
    if (w != null) return w;
    return 0.55;
  }

  /// 3-track extended memory artist-penalization matrix. The
  /// spec is:
  ///   * history[0] (immediate last track) — 0.15
  ///   * history[1] (two tracks ago)       — 0.40
  ///   * history[2] (three tracks ago)     — 0.65
  ///   * no match                          — 1.0
  /// The most-recent track gets the heaviest penalty so the
  /// engine immediately breaks the "two-track loop" pattern.
  /// Older history entries decay toward neutral so the matrix
  /// doesn't suppress a track the user heard several songs ago.
  double _artistDecayPenalty(Track track, List<Track> history) {
    if (history.isEmpty) return 1.0;
    if (_artistEquals(track.author, history[0].author)) return 0.15;
    if (history.length > 1 &&
        _artistEquals(track.author, history[1].author)) {
      return 0.40;
    }
    if (history.length > 2 &&
        _artistEquals(track.author, history[2].author)) {
      return 0.65;
    }
    return 1.0;
  }

  bool _artistEquals(String? a, String? b) {
    if (a == null || b == null) return false;
    return a.toLowerCase() == b.toLowerCase();
  }

  /// Same Artist: strict artist match (the spec's "Every single
  /// appended song must belong to the said artist"). The genre
  /// graph is consulted only to expand the **search breadth** of
  /// the candidate pool — the artist filter is still applied to
  /// every candidate, so a candidate from a neighbouring genre is
  /// only accepted if its `author` string equals the current
  /// track's `author`.
  Future<Track?> _sameArtist(Track current, Set<String> exclude) async {
    final artist = current.author;
    if (artist == null || artist.isEmpty) {
      AppLogger.log('Same Artist: Seed artist is null or empty.', name: _logTag);
      return null;
    }
    final seedGenre = current.genre;
    final fetcher = _onlineFetcher;
    final isOnline = fetcher != null && _connectivityProbe() == NetworkAvailability.online;

    AppLogger.log('Same Artist: artist=$artist, seedGenre=$seedGenre, isOnline=$isOnline', name: _logTag);

    if (isOnline) {
      try {
        final online = await fetcher(current);
        if (online != null && online.isNotEmpty) {
          final onlineCandidates = online.where((t) => !exclude.contains(t.id)).toList();
          AppLogger.log('Same Artist: online track pool: ${onlineCandidates.length} tracks', name: _logTag);
          
          for (final g in _graph.searchBreadth(seedGenre)) {
            final match = onlineCandidates.firstWhere(
              (t) => _artistMatches(t.author, artist) && (t.genre ?? 'Unknown') == g,
              orElse: () => const _SentinelTrack(),
            );
            if (match is! _SentinelTrack) {
              AppLogger.log('Same Artist: Online match found in neighboring genre "$g": ${match.title} (${match.id})', name: _logTag);
              return match;
            }
          }
          
          final matchAny = onlineCandidates.firstWhere(
            (t) => _artistMatches(t.author, artist),
            orElse: () => const _SentinelTrack(),
          );
          if (matchAny is! _SentinelTrack) {
            AppLogger.log('Same Artist: Online match found in any genre: ${matchAny.title} (${matchAny.id})', name: _logTag);
            return matchAny;
          }
        }
      } catch (e) {
        AppLogger.log('Online same-artist fetch failed: $e', name: _logTag);
      }
    }

    final crate = await _crateMiner.mine(excludeIds: exclude);
    AppLogger.log('Same Artist: local crate pool: ${crate.length} tracks', name: _logTag);
    if (crate.isEmpty) return null;

    for (final g in _graph.searchBreadth(seedGenre)) {
      final match = crate.firstWhere(
        (t) => _artistMatches(t.author, artist) && (t.genre ?? 'Unknown') == g,
        orElse: () => const _SentinelTrack(),
      );
      if (match is! _SentinelTrack) {
        AppLogger.log('Same Artist: Local match found in neighboring genre "$g": ${match.title} (${match.id})', name: _logTag);
        return match;
      }
    }

    final matchAny = crate.firstWhere(
      (t) => _artistMatches(t.author, artist),
      orElse: () => const _SentinelTrack(),
    );
    if (matchAny is! _SentinelTrack) {
      AppLogger.log('Same Artist: Local match found in any genre: ${matchAny.title} (${matchAny.id})', name: _logTag);
      return matchAny;
    }

    AppLogger.log('Same Artist: No matching track found for artist "$artist".', name: _logTag);
    return null;
  }

  Future<Track?> _smartDj(Track current, Set<String> exclude) async {
    final ledger = _historyLedger;
    if (ledger == null) {
      AppLogger.log(
        'Smart DJ: no history ledger bound; falling back to attribute intersection',
        name: _logTag,
      );
      return _attributeIntersection(current, exclude);
    }
    final history = await ledger.getRecent(limit: 50);
    if (history.isEmpty) {
      AppLogger.log('Smart DJ: History is empty; falling back to attribute intersection', name: _logTag);
      return _attributeIntersection(current, exclude);
    }
    final state = _extractMarkovState(history);
    AppLogger.log('Smart DJ: Extracted Markov state containing ${state.length} entries. Seed: ${current.title} (${current.id})', name: _logTag);

    List<Track> candidates = [];
    final fetcher = _onlineFetcher;
    final isOnline = fetcher != null && _connectivityProbe() == NetworkAvailability.online;
    if (isOnline) {
      try {
        final online = await fetcher(current);
        if (online != null && online.isNotEmpty) {
          candidates = online.where((t) => !exclude.contains(t.id)).toList();
          AppLogger.log('Smart DJ: Fetched ${online.length} online tracks, ${candidates.length} unique candidates', name: _logTag);
        }
      } catch (e) {
        AppLogger.log('Online Smart DJ fetch failed: $e', name: _logTag);
      }
    }

    if (candidates.isEmpty) {
      candidates = await _crateMiner.mine(excludeIds: exclude);
      AppLogger.log('Smart DJ: Local crate mined: ${candidates.length} candidates', name: _logTag);
    }

    if (candidates.isEmpty) {
      AppLogger.log('Smart DJ: Candidate pool is empty.', name: _logTag);
      return null;
    }

    final currentArtist = current.author?.toLowerCase();
    final currentGenre = current.genre;
    final neighbors = _graph.neighborsOf(currentGenre);

    var filtered = candidates.where((t) {
      final differentArtist = currentArtist == null || t.author?.toLowerCase() != currentArtist;
      final relatedGenre = currentGenre == null || neighbors.containsKey(t.genre);
      return differentArtist && relatedGenre;
    }).toList();
    AppLogger.log('Smart DJ: Unpredictability check (different artist + related genre) reduced pool from ${candidates.length} to ${filtered.length}', name: _logTag);

    if (filtered.isEmpty) {
      filtered = candidates.where((t) {
        return currentArtist == null || t.author?.toLowerCase() != currentArtist;
      }).toList();
      AppLogger.log('Smart DJ: Related sub-genre empty, falling back to different artist only: ${filtered.length} candidates', name: _logTag);
    }
    if (filtered.isEmpty) {
      filtered = candidates;
      AppLogger.log('Smart DJ: Different artist empty, falling back to all candidates: ${filtered.length} candidates', name: _logTag);
    }

    final scored = <_ScoredTrack>[];
    // Smart-DJ bootstrap fusion: the Liked-Song affinity
    // component is blended with the live Markov score via
    //   score = (1 - β) * markov + β * L_affinity
    // where β decays linearly from 0.6 at H=0 to 0.0 at
    // H≥150. The blend is computed inside a `compute()`
    // background isolate so the heavy row-similarity
    // scan, the affinity match, and the linear-decay
    // multiplication never block the position stream. The
    // input payload is strictly primitive (`List<String>`
    // for the top-5 caches, `List<Map<String, dynamic>>`
    // for the candidate pool and history entries), and
    // the return value is a flat list of
    // `{trackId, score}` so no live object references
    // cross the isolate boundary.
    final beta = likedAffinityWeight;
    final serializedCandidates = <Map<String, dynamic>>[
      for (final c in filtered)
        <String, dynamic>{
          'id': c.id,
          'title': c.title,
          'author': c.author,
          'genre': c.genre,
        },
    ];
    // Use camelCase keys in the isolate payload so the
    // boundary code (which mirrors the existing
    // `_markovScore` instance helper) reads them
    // naturally. `toMap()` writes snake_case for the
    // SQLite schema, so we project the two fields the
    // scorer actually consumes.
    final serializedState = <Map<String, dynamic>>[
      for (final e in state)
        <String, dynamic>{
          'trackId': e.trackId,
          'artistName': e.artistName,
          'primaryGenre': e.primaryGenre,
        },
    ];
    final serializedFullHistory = <Map<String, dynamic>>[
      for (final e in history)
        <String, dynamic>{
          'trackId': e.trackId,
          'artistName': e.artistName,
          'primaryGenre': e.primaryGenre,
        },
    ];
    final input = _SmartDjScoreInput(
      candidates: serializedCandidates,
      stateEntries: serializedState,
      fullHistory: serializedFullHistory,
      topLikedArtists: _topLikedArtists,
      topLikedGenres: _topLikedGenres,
      beta: beta,
    );
    List<Map<String, dynamic>> scoredResults;
    try {
      scoredResults = await compute(_smartDjIsolateScore, input);
    } catch (e) {
      AppLogger.warning(
        '[SmartDJFusion] compute() isolate failed; falling back to '
        'in-process scoring: $e',
        name: _logTag,
      );
      // Fallback path: in-process scoring (preserves the
      // pre-fusion behaviour for any platform that refuses
      // the isolate spawn — typically the test runner).
      scoredResults = <Map<String, dynamic>>[];
      for (final candidate in filtered) {
        final markov = _markovScore(
          state: state,
          current: current,
          candidate: candidate,
          fullHistory: history,
        );
        final affinity = _likedAffinityFor(candidate);
        scoredResults.add(<String, dynamic>{
          'trackId': candidate.id,
          'score': (1.0 - beta) * markov + beta * affinity,
        });
      }
    }

    // Pair the isolate scores back with the in-memory
    // candidate pool by track id and pick the top.
    final byId = <String, _ScoredTrack>{
      for (final entry in scoredResults)
        (entry['trackId'] as String): _ScoredTrack(
          filtered.firstWhere(
            (t) => t.id == entry['trackId'],
            orElse: () => filtered.first,
          ),
          (entry['score'] as num).toDouble(),
        ),
    };
    scored.addAll(byId.values);
    scored.sort((a, b) => b.score.compareTo(a.score));
    if (scored.isEmpty) {
      AppLogger.log('Smart DJ: Scored candidates list is empty.', name: _logTag);
      return null;
    }

    var pick = scored.first.track;
    final topScore = scored.first.score;
    AppLogger.log(
      'Smart DJ: Top scored track: ${pick.title} (${pick.id}) '
      'with score $topScore (β=$beta)',
      name: _logTag,
    );

    if (topScore <= 0) {
      AppLogger.log('Smart DJ: Top score is 0. Falling back to local attribute intersection.', name: _logTag);
      final fallbackScore = await _attributeIntersection(current, exclude);
      if (fallbackScore != null) {
        pick = fallbackScore;
        AppLogger.log('Smart DJ: Attribute intersection fallback selected: ${pick.title} (${pick.id})', name: _logTag);
      }
    }
    return pick;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<Track?> _attributeIntersection(
      Track current, Set<String> exclude) async {
    final crate = await _crateMiner.mine(excludeIds: exclude);
    if (crate.isEmpty) return null;
    final currentArtist = current.author?.toLowerCase();
    final currentGenre = current.genre;
    Track? best;
    double bestScore = 0;
    for (final t in crate) {
      final artistMatch = currentArtist != null &&
              t.author?.toLowerCase() == currentArtist;
      final genreMatch = currentGenre != null && t.genre == currentGenre;
      final s = (artistMatch ? 0.6 : 0.0) + (genreMatch ? 0.4 : 0.0);
      if (s > bestScore) {
        best = t;
        bestScore = s;
      }
    }
    return best;
  }

  /// Computes the Liked-Song affinity score $L_{affinity}$
  /// for a candidate track. Implements the spec's
  /// "deterministic metadata affinity scoring" with the
  /// null-genre reallocation guard.
  ///
  /// Normal intersection matrix (valid metadata present):
  ///   * Artist match (weight 0.6) — candidate's author is in
  ///     the top-5 liked artists cache.
  ///   * Genre match  (weight 0.4) — candidate's genre is in
  ///     the top-5 liked genres cache.
  ///   * $L_{affinity}$ = artistScore + genreScore (range 0..1).
  ///
  /// Null-genre defensive guard: if the candidate's genre is
  /// `null`, empty, or the literal string `"Unknown"`, the
  /// engine MUST NOT evaluate a static 0.0 genre match.
  /// Instead the missing 0.4 genre weight is reallocated to
  /// the artist component — a matching artist therefore
  /// scores a perfect 1.0, a non-matching artist scores 0.0.
  /// Tracks with partial metadata are never mathematically
  /// penalised.
  static double likedAffinityFor(
    Map<String, dynamic> candidate,
    Set<String> topLikedArtists,
    Set<String> topLikedGenres,
  ) {
    final author = (candidate['author'] as String?)?.toLowerCase();
    final genre = candidate['genre'] as String?;
    final artistInTop = author != null && topLikedArtists.contains(author);
    final genreMissing =
        genre == null || genre.isEmpty || genre == 'Unknown';
    if (genreMissing) {
      // Spec: reallocate the missing genre weight (0.4) onto
      // the artist component. A matching artist therefore
      // scores 1.0; a non-matching artist scores 0.0.
      return artistInTop ? 1.0 : 0.0;
    }
    final genreInTop = topLikedGenres.contains(genre);
    return (artistInTop ? 0.6 : 0.0) + (genreInTop ? 0.4 : 0.0);
  }

  /// Instance-form wrapper for [_likedAffinityFor] that reads
  /// the cache fields. Useful for tests and any in-process
  /// caller; the [_smartDj] isolate path uses the static
  /// helper above with a serialised payload.
  double _likedAffinityFor(Track candidate) {
    return likedAffinityFor(
      <String, dynamic>{
        'id': candidate.id,
        'author': candidate.author,
        'genre': candidate.genre,
      },
      _topLikedArtists.map((a) => a.toLowerCase()).toSet(),
      _topLikedGenres.toSet(),
    );
  }

  /// Pulls the most-recent N history rows (where N = [_markovWindow])
  /// and returns them as the Markov state vector. If fewer than N
  /// rows are available, returns whatever is available (the
  /// [_markovScore] helper handles shorter states by padding with
  /// the sentinel "no transition observed").
  List<DJHistoryEntry> _extractMarkovState(List<DJHistoryEntry> history) {
    if (history.length <= _markovWindow) return history;
    return history.sublist(0, _markovWindow);
  }

  /// Computes P(A → B) per the spec formula.
  ///
  /// * **A** is the most recent history entry (the "current state"
  ///   from the user's perspective).
  /// * **B** is the candidate track under evaluation.
  /// * **state** is the last [_markovWindow] history rows.
  /// * **fullHistory** is the full sliding window used to compute
  ///   the empirical transition frequency.
  ///
  /// We compare candidate metadata to **A** (not to the entire
  /// state) for the artist / genre match components because the
  /// spec defines those as binary weights between the two tracks
  /// being evaluated; only the temporal_cluster_weight is
  /// state-dependent.
  double _markovScore({
    required List<DJHistoryEntry> state,
    required Track current,
    required Track candidate,
    required List<DJHistoryEntry> fullHistory,
  }) {
    final a = state.isEmpty ? null : state.first;
    final artistMatch = a != null &&
        candidate.author != null &&
        a.artistName.toLowerCase() == candidate.author!.toLowerCase();
    final genreMatch = a != null &&
        a.primaryGenre != 'Unknown' &&
        a.primaryGenre == candidate.genre;

    // Temporal weight: scan the history for transitions A → B
    // using the most recent 3-row state as the context. We look
    // for consecutive 3-windows whose first 3 entries match the
    // current state and count how many of them transition into B
    // (i.e. the row that immediately follows the 3-window is B).
    final stateIds =
        state.map((e) => e.trackId).toList(growable: false);
    final candidateArtistLower = candidate.author?.toLowerCase();
    int matchingContext = 0;
    int transitionsToCandidate = 0;
    if (fullHistory.length > stateIds.length) {
      for (var i = 0; i + stateIds.length < fullHistory.length; i++) {
        final window = fullHistory.sublist(i, i + stateIds.length);
        bool ok = true;
        for (var j = 0; j < stateIds.length; j++) {
          if (window[j].trackId != stateIds[j]) {
            ok = false;
            break;
          }
        }
        if (!ok) continue;
        matchingContext++;
        final next = fullHistory[i + stateIds.length];
        if (next.trackId == candidate.id ||
            (candidateArtistLower != null &&
                next.artistName.toLowerCase() == candidateArtistLower &&
                next.primaryGenre == candidate.genre)) {
          transitionsToCandidate++;
        }
      }
    }
    final temporal = matchingContext == 0
        ? 0.0
        : transitionsToCandidate / matchingContext;

    return (artistMatch ? 0.5 : 0.0) +
        (genreMatch ? 0.3 : 0.0) +
        0.2 * temporal;
  }
}

class _ScoredTrack {
  final Track track;
  final double score;
  const _ScoredTrack(this.track, this.score);
}

/// Sentinel value for `firstWhere`'s `orElse` so we can return
/// `null` from a typed lookup without an `O(n)`-and-`is`-check
/// pattern at every call site.
class _SentinelTrack extends Track {
  const _SentinelTrack()
      : super(id: '__sentinel__', title: '__sentinel__');
}
