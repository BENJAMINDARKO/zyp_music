import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../domain/entities/auto_dj_mode.dart';
import '../../domain/entities/video.dart';
import '../utils/app_logger.dart';
import 'country_bonus_service.dart';
import 'dj_history_ledger.dart';
import 'genre_enrichment_service.dart';
import 'genre_normalization_service.dart';
import 'genre_proximity_graph.dart';
import 'genre_similarity_engine.dart';
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
/// [smartDjIsolateScore], and the engine's core
/// [AutoDjRoutingService] (which holds the database references)
/// is never reachable from the isolate thread.
@visibleForTesting
class SmartDjScoreInput {
  final List<Map<String, dynamic>> candidates;
  final List<Map<String, dynamic>> stateEntries;
  final List<Map<String, dynamic>> fullHistory;
  final List<String> topLikedArtists;
  final List<String> topLikedGenres;
  final double beta;

  /// Spec 2C: precomputed per-candidate genre similarity, looked
  /// up on the main isolate where the [GenreSimilarityEngine]
  /// lives (the matrix cannot cross the `compute()` boundary).
  /// Keyed by `candidate['id']`. Missing keys fall through to
  /// 0.0 — same as the `_similarityEngine` null-degradation path.
  final Map<String, double> precomputedGenreSimilarity;

  /// Spec 2C: lowercased artist names from the QueueManager
  /// session history (the `history` parameter of [resolveNext]).
  /// Used by the new `artist_diversity` term — a candidate whose
  /// artist appears in this set gets 0.3 (recent), the seed
  /// artist gets 0.0, and anything else gets 1.0.
  final List<String> recentArtists;

  /// Spec 2C: cold-start indicator. When the ledger has < 3
  /// rows of history, the temporal term is dropped entirely and
  /// the formula degrades to `0.5·diversity + 0.5·genre_similarity`.
  final bool useColdStart;

  const SmartDjScoreInput({
    required this.candidates,
    required this.stateEntries,
    required this.fullHistory,
    required this.topLikedArtists,
    required this.topLikedGenres,
    required this.beta,
    required this.precomputedGenreSimilarity,
    required this.recentArtists,
    required this.useColdStart,
  });
}

/// Top-level entry point for the Smart-DJ scoring
/// `compute()` isolate. Reconstructs the lightweight scoring
/// context from the serialised payload, runs the corrected
/// three-term formula per candidate, and returns a flat
/// `List<Map<String, dynamic>>` of `{trackId, score}` so the
/// caller can pair it back with the in-memory candidate pool
/// without exposing any model objects across the boundary.
///
/// Spec 2C formula:
///
///   score = 0.40·artist_diversity
///         + 0.40·genre_similarity (precomputed on main isolate)
///         + 0.20·temporal_pattern   (Laplace-smoothed transition
///                                    frequency over the seed artist)
///
/// Cold-start (history < 3 rows): drops the temporal term,
///   score = 0.50·diversity + 0.50·genre_similarity
///
/// All artist comparisons are lowercased on both sides to
/// prevent the "Black Sherif" vs "black sherif" case-sensitivity
/// trap flagged in the spec's "what could still go wrong" notes.
@visibleForTesting
List<Map<String, dynamic>> smartDjIsolateScore(
    SmartDjScoreInput input) {
  final topLikedArtistsLower =
      input.topLikedArtists.map((a) => a.toLowerCase()).toSet();
  final topLikedGenresLower = input.topLikedGenres.toSet();

  // Reconstruct the state + fullHistory as `Map<String, dynamic>`
  // lookups compatible with the seed/temporal logic (the engine
  // reads `state[i].trackId`, `state[i].artistName`).
  final state = input.stateEntries;
  final fullHistory = input.fullHistory;
  final recentArtistSet = input.recentArtists.toSet();

  // Seed = most recent history row. Lowercased once for
  // case-insensitive comparison with the candidate artist
  // (which is also lowercased in `_smartDj` before serialisation).
  final seedArtistLower = state.isNotEmpty
      ? (state.first['artistName'] as String?)?.toLowerCase()
      : null;

  // Precompute temporal denominator once across all candidates.
  // The formula counts how often in `fullHistory` the seed artist
  // was followed by some other artist, then Laplace-smoothed by
  // the number of distinct successor artists. This is an
  // empirical transition frequency, not a state-context lookup —
  // i.e. "across the last 50 rows, how often has the seed
  // artist's slot transitioned into artist X?"
  final Map<String, int> transitionFreq = <String, int>{};
  int totalTransitionsFromSeed = 0;
  if (!input.useColdStart && seedArtistLower != null) {
    for (int i = 0; i < fullHistory.length - 1; i++) {
      final current =
          (fullHistory[i]['artistName'] as String?)?.toLowerCase();
      final next =
          (fullHistory[i + 1]['artistName'] as String?)?.toLowerCase();
      if (current == seedArtistLower && next != null && next != seedArtistLower) {
        transitionFreq[next] = (transitionFreq[next] ?? 0) + 1;
        totalTransitionsFromSeed++;
      }
    }
  }
  // Laplace smoothing: denominator = (count + distinct_successors)
  // so an unseen artist gets 1 / (N + |S|), not 0. Falls back to
  // 1 if there are zero observed transitions.
  final distinctSuccessors = transitionFreq.length;
  final temporalDenominator = totalTransitionsFromSeed +
      (distinctSuccessors > 0 ? distinctSuccessors : 1);

  final results = <Map<String, dynamic>>[];
  for (final c in input.candidates) {
    final candidateId = c['id'] as String;
    final candidateArtistLower = (c['author'] as String?)?.toLowerCase();

    // Term 1: artist diversity
    //   0.0 if candidate == seed artist (avoid immediate repeats)
    //   0.3 if candidate is in the recent session history
    //   1.0 otherwise
    //   0.5 for unknown/empty artist — neutral, neither
    //   penalised nor rewarded.
    double diversity;
    if (candidateArtistLower == null || candidateArtistLower.isEmpty) {
      diversity = 0.5;
    } else if (seedArtistLower != null &&
        candidateArtistLower == seedArtistLower) {
      diversity = 0.0;
    } else if (recentArtistSet.contains(candidateArtistLower)) {
      diversity = 0.3;
    } else {
      diversity = 1.0;
    }

    // Term 2: genre similarity (precomputed on the main isolate).
    // Missing key = 0.0 (graceful degradation when
    // `_similarityEngine` is null).
    final genreSim = input.precomputedGenreSimilarity[candidateId] ?? 0.0;

    // Term 3: temporal pattern (skipped in cold-start).
    double temporal = 0.0;
    if (!input.useColdStart && candidateArtistLower != null) {
      final freq = transitionFreq[candidateArtistLower] ?? 0;
      temporal = (freq + 1) / temporalDenominator;
    }

    // Apply the formula weights.
    final markov = input.useColdStart
        ? (diversity * 0.50) + (genreSim * 0.50)
        : (diversity * 0.40) +
            (genreSim * 0.40) +
            (temporal * 0.20);

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
      'trackId': candidateId,
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

  /// Phase 6: MusicBrainz enrichment. Late-bound (and
  /// optional) so legacy call sites that build the engine
  /// without going through `main.dart` keep working. When
  /// null the routing layer runs in pure-Markov mode with
  /// the dominant-genre interceptor as the only genre
  /// fallback.
  final GenreEnrichmentService? _genreEnrichment;

  /// Spec 2B / 2C: the proximity-matrix-backed similarity
  /// engine. The new Smart-DJ scoring formula precomputes
  /// per-candidate genre similarity on the main isolate (where
  /// the matrix lives) and passes a scalar `Map<id, score>` to
  /// the scoring isolate — the matrix itself never crosses the
  /// `compute()` boundary. Optional so test rigs that don't need
  /// it can omit it; when null, every candidate's
  /// `genre_similarity` term collapses to 0.0 (the 0.40 weight
  /// is unused, equivalent to running the old pure-Markov
  /// engine). Graceful degradation, not a crash.
  final GenreSimilarityEngine? _similarityEngine;

  /// Spec 2D: optional normalization service used by the
  /// Shuffle Library genre filter. When a filter is active,
  /// every crate track's raw `genre` is passed through
  /// [GenreNormalizationService.normalize] so the comparison
  /// is matrix-key-to-matrix-key (not raw-MB-tag-to-matrix
  /// key). Optional so legacy call sites that build the
  /// engine without a normalization service can omit it;
  /// when null AND a filter is set, the engine logs and
  /// silently falls back to the unfiltered pool (same as
  /// the `<5 matches` fallback). Graceful degradation, not
  /// a crash.
  final GenreNormalizationService? _genreNormalization;

  /// Spec 2E: country-aware Same-Genre bonus. Reads the
  /// seed and candidate `Track.country` values (populated by
  /// the crate miner from `artist_genres.country_code`) and
  /// multiplies the final candidate score by
  /// `CountryBonusService.scoreFor(...)`. Optional so legacy
  /// rigs that don't need it can omit it; when null, the
  /// bonus is bypassed entirely (treated as 1.0). The
  /// service is purely additive — the rest of the scoring
  /// shape is preserved. Smart DJ deliberately ignores this
  /// bonus to keep the genre-similarity signal unweighted by
  /// geography.
  final CountryBonusService? _countryBonusService;

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

  /// Spec 2D: minimum size of the genre-filtered pool before
  /// the Shuffle Library engine silently falls back to the
  /// unfiltered crate. Below this threshold, the user has
  /// filtered so aggressively that any further restriction
  /// would degrade to a single-track re-pick loop, which
  /// defeats the purpose of a "shuffle". Tunable: bump to
  /// 10+ for users with large libraries who want stricter
  /// matching; lower to 3 for users with small libraries
  /// who still want genre-based narrowing.
  static const int _minFilteredPoolSize = 5;

  /// Spec 2D: active filter for Shuffle Library mode. When
  /// non-null, the engine restricts the crate to tracks
  /// whose normalized genre (matrix key) matches this value.
  /// Set via [setShuffleLibraryGenreFilter]; cleared via
  /// passing null. Thread-local state (no isolate hop
  /// required) — the filter is applied on the main isolate
  /// before the rolling-window block is generated.
  String? _shuffleLibraryGenreFilter;

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
    GenreEnrichmentService? genreEnrichment,
    GenreSimilarityEngine? similarityEngine,
    GenreNormalizationService? genreNormalization,
    CountryBonusService? countryBonusService,
    Random? random,
    int initialHistoryCount = 0,
    List<String> topLikedArtists = const <String>[],
    List<String> topLikedGenres = const <String>[],
  })  : _crateMiner = crateMiner,
        _graph = graph ?? const GenreProximityGraph(),
        _historyLedger = historyLedger,
        _onlineFetcher = onlineFetcher,
        _connectivityProbe = connectivityProbe ?? (() => NetworkAvailability.unknown),
        _genreEnrichment = genreEnrichment,
        _similarityEngine = similarityEngine,
        _genreNormalization = genreNormalization,
        _countryBonusService = countryBonusService,
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

  /// Spec 2G Fix #6: refreshes the Top 5 Liked Artists /
  /// Genres cache. Called by the favorites layer (e.g.,
  /// `PlaylistProvider`) after the user favorites or
  /// unfavorites a track. Upstream debounce (500ms) handles
  /// bulk-favoriting an album efficiently — this method
  /// runs once per debounced batch, not per action.
  ///
  /// The pushed values replace the existing caches
  /// immediately. The caller is responsible for
  /// recomputing the top-N lists from the current
  /// `favorite_tracks` table state; this method does not
  /// query the database.
  void refreshLikedSongsCache({
    required List<String> topLikedArtists,
    required List<String> topLikedGenres,
  }) {
    _topLikedArtists = List<String>.unmodifiable(topLikedArtists);
    _topLikedGenres = List<String>.unmodifiable(topLikedGenres);
    AppLogger.log(
      '[SmartDJFusion] Refreshed liked-songs cache: '
      'topArtists=${_topLikedArtists.length} '
      'topGenres=${_topLikedGenres.length}',
      name: _logTag,
    );
  }

  /// Spec 2D: get the active Shuffle Library genre filter
  /// (a matrix key, e.g. `"Afrobeats"` or `"Hip-Hop"`), or
  /// null if no filter is active. Surfaced as a getter so
  /// the UI can display the current filter in the bottom
  /// sheet.
  String? get shuffleLibraryGenreFilter => _shuffleLibraryGenreFilter;

  /// Spec 2D: set the active Shuffle Library genre filter
  /// (a matrix key) or clear it by passing null. The change
  /// takes effect on the next [resolveNext] call. Calling
  /// this method does NOT re-shuffle the current block —
  /// the rolling-window block continues to consume from
  /// the OLD pool until exhaustion, then regenerates from
  /// the new pool. This matches the spec's "silent
  /// fallback" intent: a mid-block filter change should
  /// never produce a jarring cut to a different artist.
  void setShuffleLibraryGenreFilter(String? matrixKey) {
    _shuffleLibraryGenreFilter = matrixKey;
    AppLogger.log(
      '[ShuffleLibraryFilter] Filter set to: $matrixKey',
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
        return _sameArtist(current, exclude, history);

      case AutoDJMode.smartDj:
        return _smartDj(current, exclude, history);
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

    // Spec 2D: apply the active genre filter (if any) to
    // produce a `pool` that drives the rolling-window block.
    // The unfiltered `crate` stays available as the
    // fallback target when the filter is too narrow. The
    // filter is a matrix key (e.g. "Afrobeats"), not a raw
    // MB tag — we run every candidate's raw `genre` through
    // [GenreNormalizationService.normalize] to get a
    // matrix-key-to-matrix-key comparison.
    final pool = _applyShuffleLibraryGenreFilter(crate);
    final isFiltered =
        _shuffleLibraryGenreFilter != null && pool != crate;
    final List<Track> blockSource;
    if (isFiltered) {
      // Inside the filtered branch, both the filter key
      // and the filtered pool are non-null by construction
      // (see `isFiltered = filter != null && pool != crate`
      // above), so we can read them without further guards.
      final filterKey = _shuffleLibraryGenreFilter;
      final filteredPool = pool;
      AppLogger.log(
        'Shuffle Library: filter "$filterKey" matched '
        '${filteredPool.length}/${crate.length} tracks',
        name: _logTag,
      );
      blockSource = filteredPool;
    } else {
      blockSource = crate;
    }
    final allIds = blockSource.map((t) => t.id).toList();

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
      final fallbackSource =
          isFiltered ? crate : blockSource;
      final fallback = fallbackSource.where((t) => !exclude.contains(t.id)).toList();
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

  /// Spec 2D: applies [_shuffleLibraryGenreFilter] (if set)
  /// to [crate], normalising each track's raw `genre`
  /// through [GenreNormalizationService.normalize] and
  /// keeping only tracks whose normalised genre matches the
  /// filter matrix key. Returns the original [crate]
  /// unchanged when:
  ///   * no filter is set (the common case),
  ///   * the filter is set but [GenreNormalizationService]
  ///     was not injected (graceful degradation),
  ///   * the filtered pool would have fewer than
  ///     [_minFilteredPoolSize] matches (silent fallback to
  ///     avoid degenerate single-track shuffle loops).
  ///
  /// The returned reference is either `crate` (no
  /// filtering happened) or a new `List<Track>` (filter
  /// applied). The caller checks reference identity to
  /// detect the filtered case for logging.
  List<Track> _applyShuffleLibraryGenreFilter(List<Track> crate) {
    final filter = _shuffleLibraryGenreFilter;
    if (filter == null) return crate;
    final normalizer = _genreNormalization;
    if (normalizer == null) {
      AppLogger.warning(
        '[ShuffleLibraryFilter] Filter "$filter" requested but no '
        'GenreNormalizationService injected; falling back to '
        'unfiltered pool.',
        name: _logTag,
      );
      return crate;
    }
    final filtered = <Track>[];
    for (final track in crate) {
      final raw = track.genre;
      if (raw == null || raw.isEmpty) continue;
      final canonical = normalizer.normalize(raw);
      if (canonical == filter) {
        filtered.add(track);
      }
    }
    if (filtered.length < _minFilteredPoolSize) {
      AppLogger.warning(
        '[ShuffleLibraryFilter] Filter "$filter" matched '
        '${filtered.length} tracks (< $_minFilteredPoolSize); '
        'silent fallback to unfiltered pool.',
        name: _logTag,
      );
      return crate;
    }
    return filtered;
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

    // Phase 6: seed enrichment. If the track's `genre` came
    // over the wire as null/empty/"Unknown", consult the
    // MusicBrainz cache (read-only, never blocks on a remote
    // round-trip) before the dominant-genre interceptor gets
    // a chance. This short-circuits the interceptor on the
    // common case where the user already played the same
    // artist in a previous session.
    final enricher = _genreEnrichment;
    Track seed = current;
    if (enricher != null && _isUnknownGenre(current.genre)) {
      final enriched = await enricher.enrichSync(current);
      if (enriched.isNotEmpty) {
        seed = current.copyWith(genre: enriched.first);
        AppLogger.log(
          'Same Genre: seed enriched from cache → "${enriched.first}".',
          name: _logTag,
        );
      }
    }

    // Phase 6: fire-and-forget background enrichment for the
    // full candidate pool. Pool enrichment is best-effort; the
    // seed enrichment above is the only path the routing
    // decision depends on.
    if (enricher != null) {
      enricher.enqueueForEnrichment(uniqueCandidates);
    }

    // Full BFS sweep up to depth 3 — gather every candidate that
    // matches any reachable genre. The previous "first-hit"
    // termination was deterministic and caused the engine to
    // lock onto a small set of tracks at the head of the crate
    // (the same `Rock` row was returned over and over). Walking
    // the full neighbourhood lets the roulette wheel below
    // exercise the artist-penalty matrix on a much richer pool.
    final rawCandidates = _harvestBfsCandidates(
      seedGenre: seed.genre,
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
    // S_final = W_path * A_penalty * C_bonus where:
    //   * W_path comes from the genre graph (1-hop lookup with
    //     a 0.55 floor for multi-hop genres).
    //   * A_penalty is 0.15 / 0.40 / 0.65 / 1.0 depending on
    //     whether the candidate's artist matches history[0],
    //     history[1], history[2], or none of them.
    //   * C_bonus is 1.0 / 0.85 / 0.7 / 1.0 (same country /
    //     same region / different region / either side
    //     unknown) — Spec 2E. Multiplicative, applied last so
    //     it can't mask a strong artist-already-played penalty
    //     and can't revive a zero-score path.
    // The list is walked in BFS priority order so the
    // cumulative-sum anchor stays deterministic; the roulette
    // pointer is the only stochastic component.
    final scoredPool = <MapEntry<Track, double>>[];
    double cumulativeScoreSum = 0.0;
    final countryBonus = _countryBonusService;
    for (final track in rawCandidates) {
      final wPath = _pathProximity(current.genre, track.genre);
      final aPenalty = _artistDecayPenalty(track, history);
      final cBonus = countryBonus == null
          ? 1.0
          : countryBonus.scoreFor(current.country, track.country);
      final finalScore = wPath * aPenalty * cBonus;
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
  ///
  /// Defensive: when [seedGenre] is null, empty, or the literal
  /// "Unknown" placeholder, the seed carries no usable signal
  /// and a BFS anchored on it would walk unrelated genres (or
  /// yield nothing at all if the graph has no entry for the
  /// placeholder). In that case we substitute the most-frequent
  /// valid genre in [candidates] as the BFS origin via
  /// [_extractDominantPoolGenre]. If the pool itself has no
  /// valid genres, graph traversal is meaningless and we return
  /// the raw pool verbatim so the caller's random-fallback can
  /// still pick from it.
  List<Track> _harvestBfsCandidates({
    required String? seedGenre,
    required List<Track> candidates,
  }) {
    final hasUsableSeed = seedGenre != null &&
        seedGenre.isNotEmpty &&
        seedGenre != 'Unknown';
    if (!hasUsableSeed) {
      final dominant = _extractDominantPoolGenre(candidates);
      if (dominant == null) {
        AppLogger.log(
          'Same Genre: seed genre unusable (${seedGenre ?? "null"}) and '
          'candidate pool has no valid genres; skipping BFS, returning '
          'raw pool of ${candidates.length} candidates.',
          name: _logTag,
        );
        return List<Track>.from(candidates);
      }
      AppLogger.log(
        'Same Genre: seed genre unusable (${seedGenre ?? "null"}); '
        'substituting dominant pool genre "$dominant" as BFS origin.',
        name: _logTag,
      );
      seedGenre = dominant;
    }
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

  /// Frequency-maps [pool]'s `genre` field and returns the genre
  /// string with the highest occurrence count. Null, empty, and
  /// the literal "Unknown" placeholder are strictly excluded and
  /// contribute nothing to the count. Ties are broken by the
  /// alphabetically-first genre, giving the result a stable
  /// ordering across runs. Returns `null` when no candidate in
  /// the pool carries a valid genre — the caller should treat
  /// that as a signal to skip graph traversal entirely.
  /// Null/empty/"Unknown" defence used by the Phase 6 seed
  /// enrichment path. Mirrors the predicate inside
  /// [_extractDominantPoolGenre] so the routing layer's
  /// decision to consult the MusicBrainz cache is consistent
  /// with the dominant-genre interceptor's view of an
  /// "unknowable" genre.
  bool _isUnknownGenre(String? g) {
    if (g == null) return true;
    final trimmed = g.trim();
    if (trimmed.isEmpty) return true;
    if (trimmed == 'Unknown') return true;
    return false;
  }

  String? _extractDominantPoolGenre(List<Track> pool) {
    final counts = <String, int>{};
    for (final t in pool) {
      final g = t.genre?.trim();
      if (g == null || g.isEmpty || g == 'Unknown') continue;
      counts.update(g, (v) => v + 1, ifAbsent: () => 1);
    }
    if (counts.isEmpty) return null;
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });
    return entries.first.key;
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

  /// Spec 2F: same-artist year-distance bonus. Multiplicative
  /// soft scoring — a candidate that is far in years from
  /// [anchorYear] is still selectable, just with a lower
  /// roulette weight. This rewards album-adjacent playback
  /// (e.g. track 1 of 2019 album followed by track 2 of the
  /// same album) without hard-excluding deluxe reissues or
  /// later-period B-sides.
  ///
  /// Mapping (linear interpolation between the spec's four
  /// anchor points):
  ///   distance 0  → 1.0   (same year / deluxe edition)
  ///   distance 1  → 0.7   (closely related — e.g. deluxe vs
  ///                        standard of the same album cycle)
  ///   distance 2  → 0.55  (interpolated)
  ///   distance 3  → 0.4   (moderate — next album)
  ///   distance 4  → 0.3   (interpolated)
  ///   distance 5+ → 0.2   (floor — far catalogue entry)
  ///
  /// Either year null returns 1.0 (neutral — the bonus is
  /// "unknown", not "zero"). The Track.year column is nullable
  /// in the schema; bands and pre-1980 catalogue entries
  /// frequently lack a release year, so we never penalise
  /// missing data.
  double _yearDistanceBonus(int? anchorYear, int? trackYear) {
    if (anchorYear == null || trackYear == null) return 1.0;
    final distance = (trackYear - anchorYear).abs();
    if (distance == 0) return 1.0;
    if (distance == 1) return 0.7;
    if (distance == 2) return 0.55;
    if (distance == 3) return 0.4;
    if (distance == 4) return 0.3;
    return 0.2;
  }

  /// Same Artist: strict artist match (the spec's "Every single
  /// appended song must belong to the said artist"). Spec 2F
  /// adds a soft year-distance bonus — the pool is every
  /// same-artist candidate (online + local crate), and the
  /// roulette wheel is biased toward tracks closer in
  /// [Track.year] to the most recent same-artist play in
  /// [history] (falling back to the seed's year). The genre
  /// BFS sweep from the pre-2F implementation is dropped: with
  /// year-distance scoring, "any same-artist track" is the
  /// right shape for the pool — genre adjacency is no longer
  /// the priority signal.
  Future<Track?> _sameArtist(
    Track current,
    Set<String> exclude,
    List<Track> history,
  ) async {
    final artist = current.author;
    if (artist == null || artist.isEmpty) {
      AppLogger.log('Same Artist: Seed artist is null or empty.', name: _logTag);
      return null;
    }

    // Spec 2F: find the anchor year. If the user just played
    // another track by the same artist (history[0] is a
    // same-artist hit), use that track's year so the
    // year-distance is measured from the "current album
    // session" the user is in, not from the track that just
    // ended. If no recent same-artist play exists, fall
    // back to the seed's own year.
    int? anchorYear = current.year;
    for (final h in history) {
      if (_artistMatches(h.author, artist)) {
        anchorYear = h.year ?? anchorYear;
        break;
      }
    }

    // Collect every candidate (online + local crate). Dedupe
    // by track id so an online-favoured track isn't
    // double-counted if the miner also surfaces it.
    final seenIds = <String>{};
    final uniqueCandidates = <Track>[];
    final fetcher = _onlineFetcher;
    final isOnline =
        fetcher != null && _connectivityProbe() == NetworkAvailability.online;
    if (isOnline) {
      try {
        final online = await fetcher(current);
        if (online != null && online.isNotEmpty) {
          for (final t in online) {
            if (exclude.contains(t.id)) continue;
            if (seenIds.add(t.id)) uniqueCandidates.add(t);
          }
          AppLogger.log(
            'Same Artist: online track pool: ${uniqueCandidates.length} tracks',
            name: _logTag,
          );
        }
      } catch (e) {
        AppLogger.log('Online same-artist fetch failed: $e', name: _logTag);
      }
    }

    final crate = await _crateMiner.mine(excludeIds: exclude);
    AppLogger.log(
      'Same Artist: local crate pool: ${crate.length} tracks',
      name: _logTag,
    );
    for (final t in crate) {
      if (seenIds.add(t.id)) uniqueCandidates.add(t);
    }
    if (uniqueCandidates.isEmpty) {
      AppLogger.log('Same Artist: candidate pool is empty.', name: _logTag);
      return null;
    }

    // Filter to same-artist only — the spec is strict: "Every
    // single appended song must belong to the said artist".
    final sameArtist = uniqueCandidates
        .where((t) => _artistMatches(t.author, artist))
        .toList(growable: false);
    if (sameArtist.isEmpty) {
      AppLogger.log(
        'Same Artist: No matching track found for artist "$artist".',
        name: _logTag,
      );
      return null;
    }

    // Score by year distance from the anchor. Pool order
    // is the dedupe order (online first, then crate), so
    // the cumulative-sum anchor is deterministic. Only
    // candidates with a strictly positive bonus enter the
    // wheel — and since the bonus floor is 0.2, every
    // same-artist candidate qualifies (assuming both
    // years are known).
    final scoredPool = <MapEntry<Track, double>>[];
    double cumulativeScoreSum = 0.0;
    for (final track in sameArtist) {
      final yBonus = _yearDistanceBonus(anchorYear, track.year);
      cumulativeScoreSum += yBonus;
      scoredPool.add(MapEntry<Track, double>(track, cumulativeScoreSum));
    }

    // Random-zero-sum fallback: if the bonus collapsed to
    // 0.0 (impossible with the current 0.2 floor, but
    // future-proofed), pick a random same-artist candidate
    // via the injected RNG to preserve unpredictable
    // variance — never deterministically alphabetise.
    if (cumulativeScoreSum == 0.0) {
      final fallbackIndex = _random.nextInt(sameArtist.length);
      final fallbackTrack = sameArtist[fallbackIndex];
      AppLogger.log(
        'Same Artist: Cumulative score collapsed to 0; random fallback '
        'selected index $fallbackIndex -> ${fallbackTrack.title} (${fallbackTrack.id})',
        name: _logTag,
      );
      return fallbackTrack;
    }

    // Proportional fitness wheel: generate a uniform double
    // in [0, ΣS) and walk the cumulative array until the
    // running sum crosses the pointer. The first
    // same-artist candidate to do so wins. Because `_random`
    // is injected with a seeded instance in tests, the
    // selection is fully reproducible.
    final rouletteTarget = _random.nextDouble() * cumulativeScoreSum;
    for (final entry in scoredPool) {
      if (entry.value >= rouletteTarget) {
        final picked = entry.key;
        AppLogger.log(
          'Same Artist: Roulette wheel landed on '
          '${picked.title} (${picked.id}) at pointer=$rouletteTarget '
          '(cumulative=${entry.value}, anchorYear=${anchorYear ?? "null"}, '
          'trackYear=${picked.year ?? "null"}, yBonus='
          '${_yearDistanceBonus(anchorYear, picked.year).toStringAsFixed(2)}).',
          name: _logTag,
        );
        return picked;
      }
    }
    // Defensive tail-return: floating-point rounding can
    // leave the last cumulative entry just below the
    // pointer; the trailing candidate is the
    // lowest-priority same-artist match and is the safest
    // pick in that edge case.
    return scoredPool.last.key;
  }

  Future<Track?> _smartDj(
    Track current,
    Set<String> exclude,
    List<Track> history,
  ) async {
    final ledger = _historyLedger;
    if (ledger == null) {
      AppLogger.log(
        'Smart DJ: no history ledger bound; falling back to attribute intersection',
        name: _logTag,
      );
      return _attributeIntersection(current, exclude);
    }
    final fullHistory = await ledger.getRecent(limit: 50);
    // Spec 2G Fix #1: the previous early-return to
    // `_attributeIntersection` on empty history produced
    // same-artist runs for Track 2 of fresh sessions (the
    // attribute-intersection path has no artist-diversity
    // logic). The Spec 2C cold-start formula already handles
    // empty state correctly: `useColdStart = _cachedHistoryCount
    // < 3` switches to 50/50 diversity + genre_similarity
    // weights, dropping the temporal term. Let execution
    // continue into the candidate harvest + scoring loop
    // below — the cold-start path runs the new formula.
    if (fullHistory.isEmpty) {
      AppLogger.log(
        'Smart DJ: History is empty; entering cold-start formula '
        '(50/50 diversity + genre_similarity, no temporal term).',
        name: _logTag,
      );
      // No return — flow continues into candidate harvest and
      // scoring below. The cold-start branch is detected
      // later via `useColdStart = _cachedHistoryCount < 3`
      // (or, when the ledger is fresh and the bootstrap
      // count is also 0, the very same comparison).
    }
    final state = _extractMarkovState(fullHistory);
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

    // Spec 2C Section B.4: loosened pre-filter from AND to OR.
    // The new diversity scoring inside the isolate does the
    // fine-grained filtering — the pre-filter only needs to
    // exclude clearly out-of-context candidates (same artist
    // AND unrelated genre). Diverse-artist exact-genre matches
    // are explicitly admitted so the new formula has a chance
    // to rank them.
    var filtered = candidates.where((t) {
      final differentArtist = currentArtist == null ||
          t.author?.toLowerCase() != currentArtist;
      final relatedGenre = currentGenre == null ||
          neighbors.containsKey(t.genre);
      return differentArtist || relatedGenre;
    }).toList();
    AppLogger.log(
      'Smart DJ: Loosened pre-filter (different artist OR related genre) '
      'reduced pool from ${candidates.length} to ${filtered.length}',
      name: _logTag,
    );

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

    // Spec 2C Section B.4 Step 3: extract recent artist names
    // from the QueueManager session history (the `history`
    // parameter of [resolveNext]). These feed the
    // `artist_diversity` term — a candidate whose artist is
    // in this set scores 0.3 (recent) instead of 1.0.
    final recentArtists = <String>[];
    for (final track in history) {
      final artist = track.author?.toLowerCase();
      if (artist != null && artist.isNotEmpty) {
        recentArtists.add(artist);
      }
    }

    // Spec 2C Section B.4 Step 4: cold-start indicator. The
    // ledger cache counter can undercount on upgrade installs
    // (audit §9.3) — pre-existing bug, accepted degradation.
    final useColdStart = _cachedHistoryCount < 3;

    // Spec 2C Section B.4 Step 2: precompute per-candidate
    // genre similarity on the main isolate, where the
    // [GenreSimilarityEngine] lives. Each `readNormalized`
    // call is a single SQLite primary-key lookup (~1ms on
    // device), so a 50-100 candidate pool is fine without
    // batching. If profiling later shows this is hot, batch
    // via a single `IN (?, ?, ...)` query.
    final precomputedGenreSimilarity = <String, double>{};
    final seedNormalizedGenres = _genreEnrichment != null
        ? await _genreEnrichment.readNormalized(current)
        : <String>[];
    for (final candidate in filtered) {
      final candidateGenres = _genreEnrichment != null
          ? await _genreEnrichment.readNormalized(candidate)
          : <String>[];
      precomputedGenreSimilarity[candidate.id] =
          _similarityEngine?.score(
                seedNormalizedGenres,
                candidateGenres,
              ) ??
              0.0;
    }
    AppLogger.log(
      'Smart DJ: Precomputed genre similarity for '
      '${precomputedGenreSimilarity.length} candidates. '
      'Seed genres: $seedNormalizedGenres',
      name: _logTag,
    );

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
    // boundary code reads them naturally. `toMap()` writes
    // snake_case for the SQLite schema, so we project the
    // fields the scorer actually consumes.
    final serializedState = <Map<String, dynamic>>[
      for (final e in state)
        <String, dynamic>{
          'trackId': e.trackId,
          'artistName': e.artistName,
          'primaryGenre': e.primaryGenre,
        },
    ];
    final serializedFullHistory = <Map<String, dynamic>>[
      for (final e in fullHistory)
        <String, dynamic>{
          'trackId': e.trackId,
          'artistName': e.artistName,
          'primaryGenre': e.primaryGenre,
        },
    ];
    final input = SmartDjScoreInput(
      candidates: serializedCandidates,
      stateEntries: serializedState,
      fullHistory: serializedFullHistory,
      topLikedArtists: _topLikedArtists,
      topLikedGenres: _topLikedGenres,
      beta: beta,
      precomputedGenreSimilarity: precomputedGenreSimilarity,
      recentArtists: recentArtists,
      useColdStart: useColdStart,
    );
    List<Map<String, dynamic>> scoredResults;
    try {
      scoredResults = await compute(smartDjIsolateScore, input);
    } catch (e) {
      AppLogger.warning(
        '[SmartDJFusion] compute() isolate failed; falling back to '
        'in-process scoring: $e',
        name: _logTag,
      );
      // In-process fallback path: same formula as
      // smartDjIsolateScore, inlined so the test runner
      // and any platform that refuses the isolate spawn
      // still get correct results. Reuses the precomputed
      // genre similarities from the main-isolate step.
      scoredResults = <Map<String, dynamic>>[];
      final recentArtistSet = recentArtists.toSet();
      final seedArtistLower =
          state.isNotEmpty ? state.first.artistName.toLowerCase() : null;

      // Compute temporal stats inline (same logic as the
      // isolate function).
      final Map<String, int> transitionFreq = <String, int>{};
      int totalTransitionsFromSeed = 0;
      if (!useColdStart && seedArtistLower != null) {
        for (int i = 0; i < fullHistory.length - 1; i++) {
          final cur = fullHistory[i].artistName.toLowerCase();
          final nxt = fullHistory[i + 1].artistName.toLowerCase();
          if (cur == seedArtistLower && nxt != seedArtistLower) {
            transitionFreq[nxt] = (transitionFreq[nxt] ?? 0) + 1;
            totalTransitionsFromSeed++;
          }
        }
      }
      final distinctSuccessors = transitionFreq.length;
      final temporalDenominator = totalTransitionsFromSeed +
          (distinctSuccessors > 0 ? distinctSuccessors : 1);

      for (final candidate in filtered) {
        final candidateArtistLower = candidate.author?.toLowerCase();

        // Term 1: artist diversity (same logic as isolate).
        double diversity;
        if (candidateArtistLower == null || candidateArtistLower.isEmpty) {
          diversity = 0.5;
        } else if (seedArtistLower != null &&
            candidateArtistLower == seedArtistLower) {
          diversity = 0.0;
        } else if (recentArtistSet.contains(candidateArtistLower)) {
          diversity = 0.3;
        } else {
          diversity = 1.0;
        }

        // Term 2: genre similarity (precomputed).
        final genreSim =
            precomputedGenreSimilarity[candidate.id] ?? 0.0;

        // Term 3: temporal pattern (skipped in cold-start).
        double temporal = 0.0;
        if (!useColdStart && candidateArtistLower != null) {
          final freq = transitionFreq[candidateArtistLower] ?? 0;
          temporal = (freq + 1) / temporalDenominator;
        }

        final markov = useColdStart
            ? (diversity * 0.50) + (genreSim * 0.50)
            : (diversity * 0.40) +
                (genreSim * 0.40) +
                (temporal * 0.20);

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

    // Spec 2C Section C.1: post-scoring hard cap. Any
    // candidate whose artist matches one of the last two
    // tracks in the QueueManager session is multiplied by
    // 0.3 to break the "Black Sherif x5 in a row" churn.
    // The cap applies only to the ranked list — not the
    // diversity term — so a same-artist candidate can
    // still win if every non-match candidate has been
    // exhausted.
    final lastTwoArtists = <String>{};
    for (final track in history.take(2)) {
      final artist = track.author?.toLowerCase();
      if (artist != null && artist.isNotEmpty) {
        lastTwoArtists.add(artist);
      }
    }
    if (lastTwoArtists.isNotEmpty) {
      final cappedIds = <String>[];
      final rescored = <_ScoredTrack>[];
      for (final entry in scored) {
        final entryArtist = entry.track.author?.toLowerCase();
        if (entryArtist != null && lastTwoArtists.contains(entryArtist)) {
          rescored.add(_ScoredTrack(entry.track, entry.score * 0.3));
          cappedIds.add(entry.track.id);
        } else {
          rescored.add(entry);
        }
      }
      if (cappedIds.isNotEmpty) {
        AppLogger.log(
          'Smart DJ: post-cap ×0.3 applied to recent-artist '
          'candidates: $cappedIds',
          name: _logTag,
        );
        rescored.sort((a, b) => b.score.compareTo(a.score));
        scored
          ..clear()
          ..addAll(rescored);
      }
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
  /// rows are available, returns whatever is available. The
  /// isolate function handles shorter states by treating the
  /// available rows as the seed context.
  List<DJHistoryEntry> _extractMarkovState(List<DJHistoryEntry> history) {
    if (history.length <= _markovWindow) return history;
    return history.sublist(0, _markovWindow);
  }

  /// Spec 2G Fix #6: shared helper that recomputes the
  /// Top-N Liked Artists and Genres from the user's
  /// `favorite_tracks` snapshot. Used by:
  ///   * `PlayerProvider._maybeBootstrapSmartDjFusion`
  ///     (the boot-time one-shot)
  ///   * `PlaylistProvider._refreshLikedSongsCache`
  ///     (the post-favorite debounced refresh)
  ///
  /// The aggregation is purely in-memory over the
  /// `getFavoriteTracks()` result so we don't need a new
  /// raw-SQL helper in the database layer. The shapes
  /// mirror the spec's `GROUP BY author ORDER BY COUNT(*)
  /// DESC LIMIT N`: descending by count, alphabetical
  /// tiebreak so the result is deterministic across
  /// refreshes.
  static ({List<String> artists, List<String> genres})
      computeTopLikedArtistsAndGenres(
    List<Track> favorites, {
    int limit = 5,
  }) {
    final artistCounts = <String, int>{};
    final genreCounts = <String, int>{};
    for (final t in favorites) {
      final a = t.author?.trim();
      if (a != null && a.isNotEmpty) {
        artistCounts.update(a, (v) => v + 1, ifAbsent: () => 1);
      }
      final g = t.genre?.trim();
      if (g != null && g.isNotEmpty && g != 'Unknown') {
        genreCounts.update(g, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    final artistEntries = artistCounts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });
    final genreEntries = genreCounts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });
    return (
      artists: artistEntries.take(limit).map((e) => e.key).toList(),
      genres: genreEntries.take(limit).map((e) => e.key).toList(),
    );
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
