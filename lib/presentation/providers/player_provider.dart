import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:audio_service/audio_service.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/audio/gapless_queue_mixer.dart';
import '../../core/audio/dsp_crossfade_engine.dart';
import '../../core/constants/audio_quality.dart';
import '../../core/constants/repeat_mode.dart' as repeat;
  import '../../core/services/auto_dj_routing_service.dart';
  import '../../core/services/dj_history_ledger.dart';
  import '../../core/services/genre_enrichment_service.dart';
import '../../core/services/hybrid_cache_service.dart';
import '../../core/services/queue_manager.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/constants/network_state.dart';
import '../../data/repositories/charts_repository_impl.dart';
import '../../core/utils/app_logger.dart';
import '../../domain/entities/auto_dj_mode.dart';
import '../../domain/entities/video.dart';
import '../../domain/repositories/audio_repository.dart';
import '../../domain/repositories/playlist_repository.dart';
import '../../service/audio_handler.dart';
import '../../services/playback_session.dart';
import 'settings_provider.dart';

/// Phase 5: outcome of the cold-start path inside
/// `setAutoDJMode`. The mode-picker UI reads this to pick
/// the right snackbar text — "<mode> armed" vs "no library
/// found" vs the success case where a track is already
/// playing.
enum ColdStartResult {
  /// Cold-start path was suppressed (same-mode guard, off
  /// mode, or not cold-idle). The picker should show the
  /// default "armed" snackbar.
  skipped,

  /// A track was resolved and `play()` was called. The
  /// snackbar should mention the actual track title.
  startedWithTrack,

  /// The user is online but neither the local library nor
  /// the charts endpoint returned a track. The picker should
  /// show a "couldn't find a track" message.
  noLibraryOnline,

  /// The user is offline and the local library is empty.
  /// Per the user's "no library found" rule, the picker
  /// shows the offline-specific error.
  noLibraryOffline,
}

class PlayerProvider extends ChangeNotifier with WidgetsBindingObserver {
  final AudioRepository _audioRepository;
  final SettingsProvider _settingsProvider;
  final HybridCacheService _hybridCache;
  final QueueManager? _queueManager;
  DJHistoryLedger? _historyLedger;
  GaplessQueueMixer? _mixer;
  DspCrossfadeEngine? _dspEngine;

  /// Phase 5: charts repository used as the cold-start
  /// fallback ("recommend songs section") when the local
  /// library is empty and the device is online. The router's
  /// crate miner returns null in that case; the cold-start
  /// then hits `getGlobalTopSongs()` to seed playback with a
  /// recommended track.
  ChartsRepositoryImpl? _chartsRepository;

  /// Phase 5: connectivity probe used by the cold-start path
  /// to decide between charts (online) and a "no library
  /// found" snackbar (offline). The [QueueManager] already
  /// holds its own probe; this reference is the provider's
  /// view of the same signal so the cold-start can branch
  /// without touching the queue manager.
  ConnectivityService? _connectivityService;

  /// Phase 6: background MusicBrainz enrichment so future
  /// Auto-DJ routing calls can short-circuit the
  /// dominant-genre interceptor on a cache hit. The wiring
  /// follows the existing late-binding pattern used by
  /// `setHistoryLedger` and `setMixer`; see `app.dart` for
  /// the chain. Nullable so unit tests that build a
  /// `PlayerProvider` directly can run without one.
  GenreEnrichmentService? _genreEnrichment;

  /// Smart-DJ bootstrap fusion: the routing service reference
  /// used to:
  ///   1. Push the Top 5 Liked Artists / Genres + initial
  ///      history count into the engine at boot.
  ///   2. Bump [_cachedHistoryCount] every time the
  ///      80%-checkpoint write succeeds.
  ///
  /// The wiring matches the existing late-binding pattern
  /// used by `setHistoryLedger` and `setMixer`; see `app.dart`
  /// for the chain. Nullable so unit tests that build a
  /// `PlayerProvider` directly can run without one.
  AutoDjRoutingService? _routingService;

  /// Smart-DJ bootstrap fusion: the playlist repository used
  /// to read the local `favorite_tracks` table at boot. The
  /// provider calls `getFavoriteTracks()` once and computes
  /// the Top 5 Most Liked Artists / Genres in-memory (the
  /// spec's "GROUP BY artist ORDER BY COUNT(*) DESC LIMIT 5"
  /// aggregate, expressed over the existing public API). The
  /// primitive `List<String>` results are then handed down to
  /// the routing service — no live database references
  /// cross the isolate boundary into the engine.
  PlaylistRepository? _playlistRepository;

  /// Tracks whether the bootstrap-fusion cache has been
  /// populated for the current session. Prevents redundant
  /// re-initialisation when the `setRoutingService` and
  /// `setPlaylistRepository` setters are called in either
  /// order.
  bool _smartDjFusionBootstrapped = false;

  /// Idempotent gate that resolves once
  /// [_maybeBootstrapSmartDjFusion] has finished pushing the
  /// Top-Artists / Top-Genres cache into the routing service.
  /// The [QueueManager] awaits [smartDjBootstrapInitialization]
  /// at the top of `generateNextAutoDJTrack` so the very first
  /// `resolveNext()` call can never land on an empty fusion
  /// cache — which previously produced zero-score roulette
  /// wheels in Same-Genre mode at app cold start. The
  /// completer is completed exactly once; subsequent reads
  /// resolve on the next microtask with no behaviour change.
  final Completer<void> _smartDjBootstrapCompleter = Completer<void>();
  Future<void> get smartDjBootstrapInitialization =>
      _smartDjBootstrapCompleter.future;

  /// Dedicated high-frequency notifiers for position / buffer /
  /// duration. The seekbar subscribes to these via [SeekbarConnector]
  /// so audio-frame ticks do not propagate through the main
  /// [ChangeNotifier] channel and rebuild every `Consumer` in the
  /// tree. The legacy fields [_position], [_bufferedPosition], and
  /// [_duration] are still kept in sync for any code path that reads
  /// the getters (the audio handler bridge, the `_saveActiveTrackState`
  /// persistence, the gapless mixer's lookahead, etc.).
  final ValueNotifier<Duration> positionNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> bufferedPositionNotifier = ValueNotifier(
    Duration.zero,
  );
  final ValueNotifier<Duration> durationNotifier = ValueNotifier(Duration.zero);

  /// Drag lock. While a user is dragging the seekbar, position ticks
  /// from the engine would otherwise overwrite the optimistic
  /// `_dragValue` the seekbar painted. The lock is flipped on at
  /// [startSeek] and cleared by [_startPolling] the first time a
  /// stream tick lands within 500 ms of the seek target. The
  /// [_seekTimeoutTimer] is a hard 2-second safety net: if the
  /// engine is slow (network stream, cold cache), the lock is
  /// force-cleared regardless of the delta check.
  bool _isSeeking = false;
  Duration _seekPosition = Duration.zero;
  Timer? _seekTimeoutTimer;

  /// Cold-launch / rapid-tap guard. The pending-resume path in
  /// [togglePlayPause] calls `playTrack(track, startAt: pending)`,
  /// which is a multi-step async load (URL resolve → mixer add →
  /// engine setSource → seek → play). Without the guard, a fast
  /// double-tap of the play button would race two cold-launch
  /// loads against the same engine instance and leave the
  /// provider with a stuck `_isLoading` flag.
  bool _isTransitioning = false;

  StreamSubscription<CrossfadeReadyEvent>? _crossfadeSub;
  late final FallbackEngine _fallbackEngine;

  PlayerProvider(
    this._audioRepository,
    this._settingsProvider,
    this._hybridCache, {
    QueueManager? queueManager,
  }) : _queueManager = queueManager {
    _fallbackEngine = FallbackEngine();
    WidgetsBinding.instance.addObserver(this);

    _settingsProvider.addListener(() {
      PlaybackSession().clear();
    });

    _skipNextSubscription = _audioRepository.onSkipNextRequested.listen((_) {
      next();
    });
    _skipPrevSubscription = _audioRepository.onSkipPreviousRequested.listen((
      _,
    ) {
      previous();
    });
    // Drive the Hive-driven preload loop off the existing track-changed hook.
    addTrackChangedListener(_onTrackChangedForPreload);
    // Auto DJ engine state must invalidate any UI bound to this provider.
    _queueManager?.addListener(notifyListeners);
    // Late-bind the reverse reference so QueueManager.toggleAutoDJ can route
    // arm/disarm calls back into the new PlayerProvider API (startAutoQueue /
    // disarmAutoQueue). Setter is null-safe in case no QueueManager is wired
    // (e.g. unit tests that construct PlayerProvider directly).
    _queueManager?.setPlayerProvider(this);
    // Allow the offline Auto DJ pool to look up recently-played metadata.
    _queueManager?.metadataResolver = () => {
      for (final t in _recentlyPlayed) t.id: t,
    };
    // Restore the persisted Auto Queue engagement flag and active track
    // metadata from disk so the engine and miniplayer resume their
    // previous state across cold launches.
    _loadAutoQueueState();
    _startPolling();
    _loadActiveTrackState().then((_) {
      // Load recently played tracks on startup
      loadRecentlyPlayed().then((_) {
        _queueManager?.metadataResolver = () => {
          for (final t in _recentlyPlayed) t.id: t,
        };
        if (_recentlyPlayed.isNotEmpty) {
          notifyListeners();
        }
      });
    });
  }

  Track? _currentTrack;
  List<Track> _queue = [];
  List<Track>? _originalQueue;
  int _currentIndex = 0;
  bool _isPlaying = false;
  ProcessingState _processingState = ProcessingState.idle;
  bool _isLoading = false;
  bool _shuffleMode = false;
  repeat.PlaybackRepeatMode _repeatMode = repeat.PlaybackRepeatMode.none;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;
  String? _currentPlaylistId;
  StreamSubscription? _completionSubscription;
  StreamSubscription? _skipNextSubscription;
  StreamSubscription? _skipPrevSubscription;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _bufferedPositionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<ProcessingState>? _processingStateSub;
  StreamSubscription? _mediaItemSub;

  Timer? _sleepTimer;
  Timer? _sleepTimerTick;
  Duration? _sleepTimerRemaining;

  String? _lyrics;
  bool _isLoadingLyrics = false;

  Color? _dominantColor;
  bool _autoScroll = true;
  bool _isKaraokeMode = false;

  /// Phase 0: tracks whether the new Auto Queue predictive engine is armed.
  /// Independent of the legacy [_queueManager] Auto DJ state so the
  /// visual / engine flags can be transitioned independently during the
  /// Phase 0→2 refactor. Phases 1+ will replace this with the real
  /// DJPredictiveEngine arm flag.
  bool _isAutoQueueActive = false;

  /// Armed Standby flag. When true, the user has selected a non-off
  /// Auto DJ mode while the player was idle (empty queue, no current
  /// track) but has not yet picked their first song. The engine sits
  /// passively — no lookups, no fetches, no fallback tokens — until
  /// the user manually taps a song tile, at which point `setQueue`
  /// clears this flag and re-anchors the seed profile to the chosen
  /// track, transitioning the engine to fully active.
  bool _isArmedStandby = false;
  bool get isArmedStandby => _isArmedStandby;

  /// Phase 0: the currently-selected [AutoDJMode] (off / shuffle library
  /// / similar songs / same genre / same artist / smart DJ). The mode
  /// picker (entry points: track + album context menu "Start Auto DJ"
  /// tile, miniplayer AUTODJ icon, fullscreen AUTODJ icon) writes to
  /// this field. The per-mode engine logic (how each mode picks the next
  /// track) is wired in Phase 1 — for now the picker just records the
  /// choice and flips the legacy [QueueManager] flag so the icon's
  /// visual state continues to work.
  AutoDJMode _autoDJMode = AutoDJMode.off;

  /// [UI-Sync] Last track id that was successfully pushed through the
  /// MediaItem transition bridge. Used as a dedup guard so a duration-
  /// update re-emission of the same MediaItem does not trigger a full
  /// UI refresh cycle, while a genuine gapless boundary transition
  /// (new track id) always forces a redraw even when the manual queue
  /// index has already been updated by [onTrackQueued].
  String? _lastSyncedMediaItemId;

  final List<VoidCallback> _trackChangedListeners = [];

  void addTrackChangedListener(VoidCallback cb) {
    _trackChangedListeners.add(cb);
  }

  void removeTrackChangedListener(VoidCallback cb) {
    _trackChangedListeners.remove(cb);
  }

  static const _recentlyPlayedKey = 'recently_played';
  static const _maxRecent = 20;
  // Persistent state keys for the Auto Queue engine. Written on every
  // toggle and on app termination (via WidgetsBindingObserver) so the
  // next launch can resume the previous engagement.
  static const _autoQueueActiveKey = 'auto_queue_active';

  /// Position to seek to on the first `togglePlayPause` after a cold launch.
  /// Populated by `_loadActiveTrackState` and cleared by `togglePlayPause` /
  /// `playTrack` once consumed. Distinct from `_position` because the in-memory
  /// position is also driven by the audio stream — this flag tracks the
  /// one-shot cold-launch resume.
  Duration? _pendingResumePosition;
  Duration? get pendingResumePosition => _pendingResumePosition;

  /// True iff the current track has already been logged to the
  /// `dj_listening_history` ledger this session. Reset to false
  /// on every track change in the position-stream listener so a
  /// re-play of the same track re-arms the trigger. This is the
  /// "fire once per session" guard called out in the spec.
  bool _historyLoggedForCurrentTrack = false;
  bool get historyLoggedForCurrentTrack => _historyLoggedForCurrentTrack;

  /// Late-binds the AI DJ history ledger. Called once during app
  /// boot (after the [PlaylistDatabase] singleton has been
  /// initialised) so the 80% position monitor has somewhere to
  /// write. Nullable so unit tests can construct [PlayerProvider]
  /// without spinning up the full database stack.
  void setHistoryLedger(DJHistoryLedger ledger) {
    _historyLedger = ledger;
  }

  /// Late-binds the Smart-DJ routing service. Called once
  /// during app boot (after the [AutoDjRoutingService] has been
  /// constructed in `main.dart`). The reference is used to:
  ///   * Push the Top 5 Liked Artists / Genres + initial
  ///     history count into the engine via
  ///     [AutoDjRoutingService.bootstrapLikedSongs].
  ///   * Bump the cache counter via
  ///     [AutoDjRoutingService.notifyHistoryRowCommitted]
  ///     every time a row lands in `dj_listening_history`.
  /// Nullable so unit tests that construct [PlayerProvider]
  /// without a router can still run.
  void setRoutingService(AutoDjRoutingService router) {
    _routingService = router;
    _maybeBootstrapSmartDjFusion();
  }

  /// Late-binds the playlist repository so the provider can
  /// read the local `favorite_tracks` table once at boot and
  /// compute the Top 5 Liked Artists / Genres for the
  /// Smart-DJ bootstrap fusion cache. The repository is the
  /// same one used by `PlaylistProvider` for the favourites
  /// UI; no schema or query changes are required. Nullable
  /// so unit tests that don't need fusion can run.
  void setPlaylistRepository(PlaylistRepository repo) {
    _playlistRepository = repo;
    _maybeBootstrapSmartDjFusion();
  }

  /// Fires once both [setRoutingService] and
  /// [setPlaylistRepository] have been called. Reads the
  /// favorites table, computes the Top 5 Artists / Genres
  /// in-memory (mirroring the spec's
  /// `GROUP BY author ORDER BY COUNT(*) DESC LIMIT 5`
  /// aggregate over the existing public API), and pushes
  /// the primitive `List<String>` results plus the ledger's
  /// `rowCount()` into the engine. Idempotent — once the
  /// cache is populated, subsequent calls are no-ops.
  Future<void> _maybeBootstrapSmartDjFusion() async {
    if (_smartDjFusionBootstrapped) return;
    final router = _routingService;
    final repo = _playlistRepository;
    if (router == null || repo == null) return;

    int historyCount = 0;
    try {
      historyCount = await _historyLedger?.rowCount() ?? 0;
    } catch (e) {
      AppLogger.log(
        '[SmartDJFusion] rowCount() failed during bootstrap: $e',
        name: 'PlayerProvider',
      );
    }

    final topArtists = <String>[];
    final topGenres = <String>[];
    try {
      final favs = await repo.getFavoriteTracks();
      // In-memory aggregation: count occurrences of each
      // author, then take the top 5. Mirrors the spec's
      // `GROUP BY author ORDER BY COUNT(*) DESC LIMIT 5`
      // shape but runs in Dart over the existing
      // `getFavoriteTracks()` result so we do not need
      // a new raw-SQL helper in the database layer.
      final artistCounts = <String, int>{};
      final genreCounts = <String, int>{};
      for (final t in favs) {
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
      topArtists.addAll(artistEntries.take(5).map((e) => e.key));
      final genreEntries = genreCounts.entries.toList()
        ..sort((a, b) {
          final byCount = b.value.compareTo(a.value);
          if (byCount != 0) return byCount;
          return a.key.compareTo(b.key);
        });
      topGenres.addAll(genreEntries.take(5).map((e) => e.key));
    } catch (e) {
      AppLogger.log(
        '[SmartDJFusion] getFavoriteTracks() failed during bootstrap: $e',
        name: 'PlayerProvider',
      );
    }

    router.bootstrapLikedSongs(
      initialHistoryCount: historyCount,
      topLikedArtists: topArtists,
      topLikedGenres: topGenres,
    );
    _smartDjFusionBootstrapped = true;
    if (!_smartDjBootstrapCompleter.isCompleted) {
      _smartDjBootstrapCompleter.complete();
      AppLogger.log(
        '[SmartDJ-Engine] Bootstrap completer fulfilled.',
        name: 'PlayerProvider',
      );
    }
  }

  /// Late-binds the Phase 3 gapless queue mixer. Called once
  /// during app boot (after the [AudioPlayer] has been created
  /// and the [AutoDjRoutingService] is wired). The provider
  /// drives the mixer's 15-second-lookahead trigger surface
  /// from its existing position-stream listener, so the mixer
  /// never needs to subscribe to the audio source directly.
  void setMixer(GaplessQueueMixer mixer) {
    _mixer = mixer;

    // Subscribe to track queued events from the mixer (dynamic lookahead preloads)
    _mixer?.onTrackQueued = (track) {
      if (!_queue.any((t) => t.id == track.id)) {
        _queue.add(track);
        _syncRestoredStateToAudioHandler();
        notifyListeners();
      }
    };

    // Unify next track resolution under the PlayerProvider context
    _mixer?.nextTrackResolver = (current) async {
      // 1. If we have a next song in the manual queue, return it
      if (_currentIndex + 1 < _queue.length) {
        final nextTrack = _queue[_currentIndex + 1];
        AppLogger.log(
          'nextTrackResolver: resolved from manual queue: ${nextTrack.id} ("${nextTrack.title}")',
          name: 'PlayerProvider',
        );
        return nextTrack;
      }
      // 2. If Auto DJ is enabled, resolve via QueueManager
      if (_autoDJMode != AutoDJMode.off) {
        final nextTrack = await _queueManager?.generateNextAutoDJTrack(current);
        if (nextTrack != null) {
          AppLogger.log(
            'nextTrackResolver: resolved via Auto DJ mode=${_autoDJMode.name}: ${nextTrack.id} ("${nextTrack.title}")',
            name: 'PlayerProvider',
          );
          return nextTrack;
        }
      }
      return null;
    };

    // Surface the mixer's crossfade-ready events as a
    // notifyListeners() event so any UI listening on the
    // provider sees the state change. Phase 4 will consume this
    // to start the actual crossfade; Phase 3 only surfaces the
    // flag.
    _crossfadeSub?.cancel();
    _crossfadeSub = mixer.crossfadeReadyStream.listen((event) {
      AppLogger.log(
        'Crossfade ready: ${event.trackId} @ ${event.positionMs}ms '
        '(threshold=${event.thresholdMs}ms, src=${event.source.name})',
        name: 'PlayerProvider',
      );
      notifyListeners();
    });
  }

  /// Phase 5: late-binding setter for the DSP crossfade
  /// engine. Called from `main.dart` after the engine is
  /// constructed and started. The provider does NOT start /
  /// stop the engine — it only flips the gate when the
  /// Auto DJ mode changes (Smart DJ is the only mode that
  /// unlocks the crossfade pipeline per the spec's "Hook Up
  /// crossfadeReady DSP Links" rule).
  void setDspEngine(DspCrossfadeEngine engine) {
    _dspEngine = engine;
    // Sync the gate to the current mode so a late binding
    // (e.g. restoring the engine after a background isolate
    // restart) honours whatever mode the user already has
    // armed.
    engine.setActive(_autoDJMode == AutoDJMode.smartDj);
  }

  /// Phase 5: late-binding setter for the charts
  /// repository. Used by the cold-start fallback when the
  /// local library is empty and the device is online.
  void setChartsRepository(ChartsRepositoryImpl repo) {
    _chartsRepository = repo;
  }

  /// Phase 5: late-binding setter for the connectivity
  /// service. Used by the cold-start path to decide
  /// between the charts fallback (online) and a "no
  /// library found" notification (offline).
  void setConnectivityService(ConnectivityService svc) {
    _connectivityService = svc;
  }

  /// Phase 6: late-binding setter for the genre
  /// enrichment service. Once bound, every successful
  /// track transition kicks the service so the artist's
  /// MusicBrainz tag list lands in the local cache
  /// before the next Auto-DJ routing call.
  void setGenreEnrichmentService(GenreEnrichmentService svc) {
    _genreEnrichment = svc;
  }

  Box? _mediaStateBox;
  Future<Box> _getMediaStateBox() async {
    if (_mediaStateBox != null && _mediaStateBox!.isOpen) {
      return _mediaStateBox!;
    }
    _mediaStateBox = await Hive.openBox('media_state_persistence');
    return _mediaStateBox!;
  }

  Map<String, dynamic> _serializeTrack(Track track) {
    return {
      'id': track.id,
      'title': track.title,
      'thumbnailUrl': track.thumbnailUrl,
        'durationSeconds': track.duration?.inSeconds,
      'author': track.author,
      'album': track.album,
      'albumArtist': track.albumArtist,
      'year': track.year,
      'index': track.index,
      'source': track.source.name,
    };
  }

  Track _deserializeTrack(Map<String, dynamic> map) {
    final sourceStr = map['source'] as String?;
    final source = TrackSource.values.firstWhere(
      (e) => e.name == sourceStr || e.toString().split('.').last == sourceStr,
      orElse: () => TrackSource.youtube,
    );
    return Track(
      id: map['id'] as String,
      title: map['title'] as String,
      thumbnailUrl: map['thumbnailUrl'] as String?,
      // C1: preserve null. The SQLite `downloaded_tracks`
      // and `favorite_tracks` columns are nullable; coercing
      // to `0` would render as `0:00` for tracks the YouTube
      // API never returned a duration for.
      duration: (map['durationSeconds'] as int?) == null
          ? null
          : Duration(seconds: map['durationSeconds'] as int),
      author: map['author'] as String?,
      album: map['album'] as String?,
      albumArtist: map['albumArtist'] as String?,
      year: map['year'] as int?,
      index: map['index'] as int? ?? 0,
      source: source,
    );
  }

  Future<void> _syncRestoredStateToAudioHandler() async {
    final handler = _audioHandler;
    if (handler == null || _queue.isEmpty) return;
    try {
      final mediaItems = _queue
          .map(
            (track) => MediaItem(
              id: track.id,
              title: track.title,
              artist: track.author ?? '',
              album: track.album,
              artUri: track.thumbnailUrl != null
                  ? Uri.tryParse(track.thumbnailUrl!)
                  : null,
              duration: track.duration,
              extras: {'year': track.year, 'source': 'youtube'},
            ),
          )
          .toList();
      await handler.setQueue(mediaItems, startIndex: _currentIndex);
      if (_currentTrack != null && _currentIndex < mediaItems.length) {
        final activeMediaItem = mediaItems[_currentIndex];
        handler.updateMediaItem(activeMediaItem);
      }
    } catch (e) {
      AppLogger.log(
        'Error syncing restored state to audio handler: $e',
        name: 'PlayerProvider',
      );
    }
  }

  /// Wall-clock timestamp of the last persisted position write. Throttles the
  /// position-tick persistence so we do not hammer SharedPreferences on every
  /// stream frame (which fires multiple times per second).
  DateTime _lastPositionWrite = DateTime.fromMillisecondsSinceEpoch(0);

  List<Track> _recentlyPlayed = [];

  List<Track> get recentlyPlayed => List.unmodifiable(_recentlyPlayed);

  Future<void> loadRecentlyPlayed() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_recentlyPlayedKey);
    if (json == null) return;
    try {
      final list = jsonDecode(json) as List<dynamic>;
      _recentlyPlayed = list.map((e) {
        final m = e as Map<String, dynamic>;
        return Track(
          id: m['id'] as String,
          title: m['title'] as String,
          author: m['author'] as String?,
          thumbnailUrl: m['thumbnailUrl'] as String?,
          // C1: preserve null. See sibling block above.
          duration: (m['durationSeconds'] as int?) == null
              ? null
              : Duration(seconds: m['durationSeconds'] as int),
        );
      }).toList();

      // If we have history and no current track, restore the last played track
      // so the miniplayer is persistent and visible on startup!
      if (_recentlyPlayed.isNotEmpty && _currentTrack == null) {
        _currentTrack = _recentlyPlayed.first;
        _queue = [_currentTrack!];
        _currentIndex = 0;
        _processingState = ProcessingState.idle;
      }
    } catch (_) {}
  }

  Future<void> _addToRecentlyPlayed(Track track) async {
    _recentlyPlayed.removeWhere((t) => t.id == track.id);
    _recentlyPlayed.insert(0, track);
    if (_recentlyPlayed.length > _maxRecent) {
      _recentlyPlayed = _recentlyPlayed.sublist(0, _maxRecent);
    }
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(
      _recentlyPlayed
          .map(
            (t) => {
              'id': t.id,
              'title': t.title,
              'author': t.author,
              'thumbnailUrl': t.thumbnailUrl,
              'durationSeconds': t.duration?.inSeconds,
            },
          )
          .toList(),
    );
    await prefs.setString(_recentlyPlayedKey, json);
  }

  /// Persists the current Auto Queue engagement flag. Called on every
  /// enable/disable flip and on app termination so the next cold launch
  /// resumes the previous state.
  Future<void> _saveAutoQueueState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoQueueActiveKey, _queueManager?.isActive ?? false);
  }

  /// Restores the Auto Queue engagement flag from disk. Invoked once
  /// during construction. A previously-enabled engine is re-armed so the
  /// completion handler can immediately hand the baton to the
  /// recommendation loop on the next track end.
  Future<void> _loadAutoQueueState() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_autoQueueActiveKey) ?? false) {
      _queueManager?.enableAutoDJ();
    }
  }

  /// Persists the active track metadata + playback position. Invoked on
  /// app termination, lifecycle pause, periodic position ticks, and any
  /// explicit save points so the miniplayer can resume from the exact
  /// spot on the next launch.
  Future<void> _saveActiveTrackState() async {
    try {
      final track = _currentTrack;
      final box = await _getMediaStateBox();
      if (track == null) {
        await box.clear();
        return;
      }
      await box.put('track_id', track.id);
      await box.put('position_ms', _position.inMilliseconds);
      await box.put('duration_ms', _duration.inMilliseconds);
      await box.put('current_index', _currentIndex);

      final queueIds = _queue.map((t) => t.id).toList();
      await box.put('queue_ids', queueIds);

      final queueTracks = _queue.map((t) => _serializeTrack(t)).toList();
      await box.put('queue_tracks', queueTracks);

      await box.put('current_track', _serializeTrack(track));

      _lastPositionWrite = DateTime.now();
    } catch (e, stack) {
      AppLogger.log(
        'Error saving active track state: $e\n$stack',
        name: 'PlayerProvider',
      );
    }
  }

  /// Restores the active track metadata from disk into the in-memory
  /// queue. Playback is NOT auto-resumed — the miniplayer just appears
  /// populated at the saved position, and the first `togglePlayPause`
  /// (play) will seek to the saved position before kicking off the
  /// audio handler. The previously-saved position lives on
  /// `_pendingResumePosition` so `togglePlayPause` can pick it up.
  Future<void> _loadActiveTrackState() async {
    try {
      final box = await _getMediaStateBox();
      final id = box.get('track_id') as String?;
      if (id == null || id.isEmpty) return;
      if (_currentTrack != null) return; // Already restored by recently-played.

      final durationMs = box.get('duration_ms') as int? ?? 0;
      final restoredIndex = box.get('current_index') as int? ?? 0;

      // Restore queue
      final queueTracksMaps = box.get('queue_tracks') as List<dynamic>?;
      if (queueTracksMaps != null && queueTracksMaps.isNotEmpty) {
        _queue = queueTracksMaps
            .map((m) => _deserializeTrack(Map<String, dynamic>.from(m)))
            .toList();
      }

      _currentIndex = restoredIndex.clamp(
        0,
        _queue.isEmpty ? 0 : _queue.length - 1,
      );

      // Restore current track
      final currentTrackMap =
          box.get('current_track') as Map<dynamic, dynamic>?;
      if (currentTrackMap != null) {
        _currentTrack = _deserializeTrack(
          Map<String, dynamic>.from(currentTrackMap),
        );
      } else if (_queue.isNotEmpty) {
        _currentTrack = _queue[_currentIndex];
      }

      if (_currentTrack == null) return;

      // Cold-start position reset: always begin at the absolute
      // start of the track (00:00). Any saved midway seek pointer
      // is overridden so the player sits in a stable Paused state
      // at the song's beginning — eliminating audio processing
      // friction or hangs from mid-track cold restoration.
      _position = Duration.zero;
      _duration = Duration(milliseconds: durationMs);
      positionNotifier.value = Duration.zero;
      durationNotifier.value = Duration(milliseconds: durationMs);
      bufferedPositionNotifier.value = Duration.zero;
      _isPlaying = false;
      _processingState = ProcessingState.idle;
      _pendingResumePosition = Duration.zero;

      AppLogger.log(
        'Restored active track: ${_currentTrack!.id} at 0ms (forced) in Paused state (queue size ${_queue.length})',
        name: 'PlayerProvider',
      );

      await _syncRestoredStateToAudioHandler();

      notifyListeners();
    } catch (e, stack) {
      AppLogger.log(
        'Error loading active track state: $e\n$stack',
        name: 'PlayerProvider',
      );
    }
  }

  /// WidgetsBindingObserver hook. Persists the Auto Queue state and the
  /// active track metadata on app backgrounding (`paused`) and full
  /// termination (`detached`) so the next cold launch can resume from
  /// the last known position. `paused` covers the common Android case
  /// where the OS kills the process after sending it to the background
  /// without ever firing `detached`.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      _saveAutoQueueState();
      _saveActiveTrackState();
    }
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    final bool wasPlayingCurrent = (index == _currentIndex && _isPlaying);

    if (index == _currentIndex) {
      if (_queue.length > 1) {
        final newIdx = index < _queue.length - 1 ? index : index - 1;
        _queue.removeAt(index);
        _currentIndex = newIdx.clamp(0, _queue.length - 1);
        if (wasPlayingCurrent) {
          playFromQueue(_currentIndex);
        } else {
          _currentTrack = _queue[_currentIndex];
          _position = Duration.zero;
          _bufferedPosition = Duration.zero;
          notifyListeners();
        }
      } else {
        _queue.removeAt(index);
        stop();
      }
    } else {
      _queue.removeAt(index);
      if (index < _currentIndex) _currentIndex--;
      notifyListeners();
    }
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex >= _queue.length) return;
    final track = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, track);
    if (oldIndex == _currentIndex) {
      _currentIndex = newIndex;
    } else {
      if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
        _currentIndex--;
      } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
        _currentIndex++;
      }
    }
    notifyListeners();
  }

  Track? get currentTrack => _currentTrack;
  List<Track> get queue => _queue;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  bool get isBuffering =>
      _processingState == ProcessingState.loading ||
      _processingState == ProcessingState.buffering;
  bool get isActuallyPlaying => _isPlaying && !isBuffering;
  bool get isLoading => _isLoading;
  bool get shuffleMode => _shuffleMode;
  repeat.PlaybackRepeatMode get repeatMode => _repeatMode;
  Duration get position => _position;
  Duration get bufferedPosition => _bufferedPosition;
  Duration get duration => _duration;
  String? get error => _error;
  String? get currentPlaylistId => _currentPlaylistId;
  bool get isSleepTimerActive => _sleepTimer != null;
  Duration? get sleepTimerRemaining => _sleepTimerRemaining;
  String? get lyrics => _lyrics;
  bool get isLoadingLyrics => _isLoadingLyrics;
  Color? get dominantColor => _dominantColor;

  bool get autoScroll => _autoScroll;
  bool get isKaraokeMode => _isKaraokeMode;

  void setAutoScroll(bool value) {
    _autoScroll = value;
    notifyListeners();
  }

  void setKaraokeMode(bool value) {
    _isKaraokeMode = value;
    notifyListeners();
  }

  Future<void> _fetchLyricsForCurrentTrack() async {
    final track = _currentTrack;
    if (track == null) {
      _lyrics = null;
      _isLoadingLyrics = false;
      notifyListeners();
      return;
    }

    _isLoadingLyrics = true;
    _lyrics = null;
    notifyListeners();

    final result = await _audioRepository.getLyrics(track);

    // Only update if the track hasn't changed while we were fetching
    if (_currentTrack?.id == track.id) {
      _lyrics = result;
      _isLoadingLyrics = false;
      notifyListeners();
    }
  }

  Future<void> refreshLyrics() async {
    final track = _currentTrack;
    if (track == null) return;

    _isLoadingLyrics = true;
    _lyrics = null;
    notifyListeners();

    final result = await _audioRepository.refreshLyrics(track);

    if (_currentTrack?.id == track.id) {
      _lyrics = result;
      _isLoadingLyrics = false;
      notifyListeners();
    }
  }

  Future<void> _extractDominantColor(String? url) async {
    _dominantColor = null;
    notifyListeners();
    if (url == null || url.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('dynamicAccentColor') == false) return;

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(url),
        maximumColorCount: 5,
      );
      if (_currentTrack?.thumbnailUrl == url) {
        _dominantColor =
            palette.dominantColor?.color ?? palette.vibrantColor?.color;
        notifyListeners();
      }
    } catch (_) {}
  }

  void setQueue(List<Track> tracks, {int startIndex = 0, String? playlistId}) {
    _queue = tracks;
    _currentIndex = startIndex;
    _currentPlaylistId = playlistId;
    _originalQueue = null;
    _shuffleMode = false;
    _error = null;
    // Bugfix (Manual Interruption Preservation): a direct setQueue is a
    // user-initiated track load (tile tap, search selection, context
    // menu, playlist open, ...). Per the Auto DJ preservation rule, we
    // MUST NOT disarm the engine just because the user picked a new
    // seed. Instead the active seed parameters are re-anchored to the
    // newly-loaded track so the next 15-second lookahead tick uses the
    // fresh artist / genre keys as the basis for `resolveNext`. The
    // engine flag (`_isAutoDJEnabled`) is left untouched so the
    // miniplayer / fullscreen AUTODJ icon stays lit and the
    // continuation loop keeps running.
    final manager = _queueManager;
    final isEngaged = manager != null && manager.isActive;
    if (isEngaged &&
        tracks.isNotEmpty &&
        startIndex >= 0 &&
        startIndex < tracks.length) {
      final seed = tracks[startIndex];
      // Deactivate Armed Standby on first manual track selection.
      // The user has picked their first song, promoting it to the
      // official Active Master Seed and activating the lookahead
      // engine for subsequent 15-second ticks.
      if (_isArmedStandby) {
        _isArmedStandby = false;
        AppLogger.log(
          '[AutoDJEngine] Exiting Armed Standby — user selected '
          '"${seed.title}" by ${seed.author ?? 'Unknown'}. '
          'Promoting to Active Master Seed and activating lookahead.',
          name: 'PlayerProvider',
        );
      } else {
        AppLogger.log(
          '[AutoDJAnchor] Manual setQueue with Auto DJ armed - preserving '
          'engine state and shifting active seed parameters to new target '
          'track: "${seed.title}" by ${seed.author ?? 'Unknown'}',
          name: 'PlayerProvider',
        );
      }
      manager.updateActiveSeedProfile(seed);
    }
    notifyListeners();
  }

  /// Cleared: the Auto DJ functional block has been migrated to
  /// [startAutoQueue] per the Auto Queue spec. Kept as a no-op so any
  /// external callers (tests, legacy widgets) continue to compile and
  /// run without side-effects.
  void startAutoDJ(
    List<Track> tracks, {
    int startIndex = 0,
    String? playlistId,
  }) {
    // No-op: Auto DJ functional block has been migrated to Auto Queue.
  }

  /// Engages the Auto Queue engine.
  ///
  /// Phase 0 stub: flips the [_isAutoQueueActive] flag and notifies. The
  /// real predictive engine (DJPredictiveEngine) is wired in here during
  /// Phase 2 — until then, the engine is "armed" only in the sense that
  /// [_isAutoQueueActive] is true. Queue appending and the Markov-driven
  /// next-track picker are not yet active.
  Future<void> startAutoQueue(Track seedTrack) async {
    _isAutoQueueActive = true;
    debugPrint('startAutoQueue: ${seedTrack.title}');
    // TODO Phase 2: wire DJPredictiveEngine here
    notifyListeners();
  }

  /// Cold-starts the Auto Queue engine from [seedTrack]: fires [playTrack]
  /// so the audio loads and playback begins immediately, then flips the
  /// [_isAutoQueueActive] flag.
  ///
  /// Phase 0 stub: plays the seed track and arms the flag. The real
  /// predictive cold-start (full Markov chain build + seed-track write to
  /// `dj_listening_history`) is wired in here during Phases 1 + 2. Until
  /// then, the queue is NOT reset to a single-seed; only the playback
  /// engine is engaged.
  Future<void> coldStartAutoQueue(Track seedTrack) async {
    _isAutoQueueActive = true;
    debugPrint('coldStartAutoQueue: ${seedTrack.title}');
    // TODO Phase 2: wire DJPredictiveEngine cold-start here
    // TODO Phase 1: ensure seedTrack is logged to dj_listening_history
    await playTrack(seedTrack);
    notifyListeners();
  }

  /// Disarms the Auto Queue engine. Does NOT clear the active queue, does
  /// NOT stop playback — only flips the [_isAutoQueueActive] flag off so
  /// the predictive engine stops appending recommendations.
  void disarmAutoQueue() {
    _isAutoQueueActive = false;
    debugPrint('disarmAutoQueue');
    notifyListeners();
  }

  /// True iff the Auto Queue predictive engine is currently armed. Surface
  /// for the context-menu snackbar messaging and the post-Phase-2 miniplayer
  /// affordances. Independent of the legacy [isAutoDJEnabled] visual flag
  /// (which is driven by [QueueManager]) so the two states can be
  /// transitioned independently during the refactor.
  bool get isAutoQueueActive => _isAutoQueueActive;

  /// The currently-selected [AutoDJMode] (default [AutoDJMode.off]).
  /// Drives the per-mode engine (Phase 1) and the icon visual state
  /// (any non-off mode flips the legacy [QueueManager] flag so the
  /// miniplayer / fullscreen icon lights up exactly as it did before
  /// the refactor).
  AutoDJMode get autoDJMode => _autoDJMode;

  /// Sets the [AutoDJMode] for the engine. Phase 0 contract:
  ///
  /// * Updates [_autoDJMode] and notifies listeners.
  /// * Mirrors the change into the legacy [QueueManager] flag so the
  ///   miniplayer + fullscreen AUTODJ icon lights up for any non-off
  ///   mode. This preserves the pre-refactor visual behaviour with
  ///   zero risk of the icon staying dark when the engine is armed.
  /// * Does NOT touch the manual queue, the current playback, or the
  ///   position. Toggling modes is a no-op for playback continuity.
  /// * The per-mode engine logic — what each mode actually appends to
  ///   the queue — is wired in Phase 1. Until then, tapping a mode
  ///   simply records the choice and lights up the icon.
  ///
  /// **Phase 5 cold-start rule (the spec's "Idle Cold-Start
  /// Playback Rule"):** when the player is in an empty / idle
  /// state — no current track and no queued items — selecting any
  /// non-off mode triggers an instant cold-start: the engine
  /// resolves a track for the chosen mode, fills the queue, and
  /// calls `play()` so the user hears audio immediately. This
  /// eliminates the "I tapped a mode and nothing happened" dead
  /// air the pre-Phase-5 flow suffered from when the user armed
  /// the engine from the cold-idle miniplayer / fullscreen icon.
  ///
  /// Returns a [ColdStartResult] so the picker UI can show the
  /// right snackbar text ("<mode> armed" vs "no library found").
  /// The result is always populated, even on the no-op paths
  /// (the same-mode guard, the off-mode path, and the
  /// not-cold-idle path all return
  /// [ColdStartResult.skipped]).
  Future<ColdStartResult> setAutoDJMode(AutoDJMode mode) async {
    if (_autoDJMode == mode) return ColdStartResult.skipped;
    _autoDJMode = mode;
    debugPrint('setAutoDJMode: ${mode.label}');
    // Mirror the change into the legacy visual flag so the icons
    // light up. The QueueManager owns the actual `_isAutoDJEnabled`
    // backing field; calling enable/disable is the supported way to
    // mutate it from outside the class.
    if (mode.isActive) {
      _queueManager?.enableAutoDJ();
      _repeatMode = repeat.PlaybackRepeatMode.none;
    } else {
      _queueManager?.disableAutoDJ();
    }
    // Phase 2: tell the QueueManager which mode was selected BEFORE the
    // warm-up fires. This is critical: _warmUpNewMode calls
    // generateNextAutoDJTrack which reads _currentMode from the manager.
    // Setting it after would mean the warm-up always resolves via the
    // previous mode's strategy, defeating the purpose of the mode switch.
    _queueManager?.setCurrentMode(mode);
    // Phase 5: flip the DSP engine gate. Smart DJ is the
    // ONLY mode that unlocks the multi-decoder crossfade
    // pipeline; the other four active modes (Shuffle
    // Library, Similar Songs, Same Genre, Same Artist) use
    // the mixer's plain gapless handoff with no second
    // decoder.
    _dspEngine?.setActive(mode == AutoDJMode.smartDj);
    notifyListeners();
    // Armed Standby: when the player is idle (no current track,
    // no queued items) and the user selects a non-off mode, the
    // engine enters a passive standby state instead of executing
    // lookups against a dummy seed. No online fetches, no database
    // sweeps, no fallback tokens are generated. The mode tile
    // remains visually highlighted. The engine activates on the
    // first manual song selection via [setQueue].
    if (mode != AutoDJMode.off && _isColdIdle) {
      _isArmedStandby = true;
      AppLogger.log(
        '[AutoDJEngine] Entering Armed Standby for mode=${mode.label}. '
        'Waiting for explicit user track choice before activating lookahead.',
        name: 'PlayerProvider',
      );
      return ColdStartResult.skipped;
    }
    // Clear standby when the user explicitly switches to off mode
    // while in the idle state.
    if (mode == AutoDJMode.off && _isArmedStandby) {
      _isArmedStandby = false;
    }
    // Bugfix (atomic queue switching): when the user changes
    // mode mid-track we do NOT flush the preloaded timeline.
    // The existing items remain as an emergency buffer; a
    // background warm-up pre-resolves a candidate via the
    // newly-selected algorithm and verifies its URI token
    // before the next 15s-lookahead trigger trusts the new
    // mode's output.
    if (mode != AutoDJMode.off && _currentTrack != null) {
      unawaited(_warmUpNewMode(mode, currentTrack: _currentTrack!));
    }
    return ColdStartResult.skipped;
  }

  /// Bugfix: proactively resolves a candidate via the newly
  /// selected mode and verifies its URI token. The existing
  /// preloaded timeline (queued tracks behind the current
  /// one) is **not** touched — it stays as an emergency
  /// buffer so a user mid-track never hears dead air while
  /// the new algorithm warms up. Once the warm-up resolves
  /// a verified pick, the mixer's lookahead flag for the
  /// current track is cleared so the next position tick
  /// re-arms the T-15s resolver under the new mode's
  /// strategy and appends the candidate to the concatenation.
  ///
  /// Fire-and-forget: failures are logged and the existing
  /// preloaded items remain as the queue tail.
  Future<void> _warmUpNewMode(
    AutoDJMode mode, {
    required Track currentTrack,
  }) async {
    final manager = _queueManager;
    if (manager == null) return;
    try {
      final candidate = await manager.generateNextAutoDJTrack(currentTrack);
      if (candidate == null) {
        AppLogger.log(
          'setAutoDJMode warm-up: new mode=${mode.label} returned '
          'no candidate; existing preloaded timeline remains as buffer.',
          name: 'PlayerProvider',
        );
        return;
      }
      final uri = await _audioRepository.getAudioUrl(candidate);
      if (uri.isEmpty) {
        AppLogger.log(
          'setAutoDJMode warm-up: new mode=${mode.label} candidate '
          '${candidate.id} ("${candidate.title}") has empty URI; '
          'existing preloaded timeline remains as buffer.',
          name: 'PlayerProvider',
        );
        return;
      }
      AppLogger.log(
        'setAutoDJMode warm-up: verified next-track URI token for '
        'new mode=${mode.label}: '
        '${candidate.id} ("${candidate.title}"). '
        'Re-arming mixer lookahead so next T-15s tick appends '
        'the new-mode candidate to the concatenation.',
        name: 'PlayerProvider',
      );
      // [ModeSwitchFix] Clear the per-track lookahead fired flag so the
      // next position tick re-triggers the resolver under the new mode.
      // Without this, if the mode switch happens within the last 15s of
      // a track, the warm-up verifies a candidate but the mixer never
      // appends it because the flag was already set by the previous mode.
      _mixer?.clearLookaheadFor(_currentTrack?.id);
    } catch (e) {
      AppLogger.log(
        'setAutoDJMode warm-up: new mode=${mode.label} failed to '
        'resolve a verified URI token: $e. Existing preloaded '
        'timeline remains as buffer.',
        name: 'PlayerProvider',
      );
    }
  }

  /// True iff the player has nothing loaded and nothing queued.
  /// The spec's "idle cold start" trigger condition.
  bool get _isColdIdle =>
      _currentTrack == null &&
      _queue.isEmpty &&
      _processingState == ProcessingState.idle;

  /// Phase 5: instant cold-start when a non-off mode is armed
  /// from an empty state. Resolves a track for [mode] via the
  /// queue manager (which routes through the per-mode
  /// strategy), and falls back to the charts repository (the
  /// "recommend songs section") when the local library is
  /// empty and the device is online. Returns a
  /// [ColdStartResult] the picker uses to pick the right
  /// snackbar text.
  ///
  /// Cold-start resolve chain:
  ///   1. Router (per-mode strategy) — local crate + history
  ///      ledger. Returns null when the user has no library.
  ///   2. **Online?** Charts repository's `getGlobalTopSongs()`
  ///      ("recommend songs section"). Starts a session with
  ///      the top of the global charts list.
  ///   3. **Offline + no library?** Return
  ///      [ColdStartResult.noLibraryOffline] so the UI can
  ///      surface a "no library found" snackbar.
  Future<ColdStartResult> _coldStartForMode(AutoDJMode mode) async {
    final manager = _queueManager;
    if (manager == null) return ColdStartResult.skipped;
    // Use a minimal placeholder seed so the router has
    // something to score against. The seed carries the mode's
    // typical fingerprint; cold-starting a Smart DJ mode
    // without history is handled by the router's
    // attribute-intersection fallback.
    final seed = const Track(
      id: '__cold_start_seed__',
      title: 'Cold-start seed',
      genre: 'Unknown',
    );
    Track? next;
    String? resolvedVia;
    try {
      next = await manager.generateNextAutoDJTrack(seed);
      if (next != null) resolvedVia = 'router';
    } catch (e) {
      AppLogger.log(
        'Cold-start router failed for mode=${mode.label}: $e',
        name: 'PlayerProvider',
      );
    }
    // Fallback: charts repository when the router found
    // nothing AND the device is online. The "recommend
    // songs section" is the global Billboard top songs
    // list — the user gets a real track instead of
    // dead air, and the session kicks off cleanly.
    if (next == null) {
      final isOnline = _connectivityService?.state == NetworkState.online;
      if (isOnline) {
        final charts = _chartsRepository;
        if (charts != null) {
          try {
            final recommended = await charts.getGlobalTopSongs(
              forceRefresh: false,
            );
            if (recommended.isNotEmpty) {
              next = recommended.first;
              resolvedVia = 'charts';
            }
          } catch (e) {
            AppLogger.log(
              'Cold-start charts fallback failed: $e',
              name: 'PlayerProvider',
            );
          }
        }
      }
    }
    if (next == null) {
      // Both the router and the charts fallback returned
      // nothing. If we're online this means the charts
      // endpoint is also down (or returned an empty list);
      // if we're offline it means the user has no library
      // and no cached charts. The caller surfaces a "no
      // library found" snackbar so the user knows why
      // nothing played.
      final isOnline = _connectivityService?.state == NetworkState.online;
      AppLogger.log(
        'Cold-start: no track resolved (online=$isOnline, '
        'mode=${mode.label}); no library found',
        name: 'PlayerProvider',
      );
      return isOnline
          ? ColdStartResult.noLibraryOnline
          : ColdStartResult.noLibraryOffline;
    }
    _queue.add(next);
    _currentIndex = 0;
    _currentTrack = next;
    try {
      await playFromQueue(0);
    } catch (e) {
      AppLogger.log('Cold-start play() failed: $e', name: 'PlayerProvider');
    }
    AppLogger.log(
      'Cold-start instant play for mode=${mode.label} via=$resolvedVia: '
      '${next.title}',
      name: 'PlayerProvider',
    );
    return ColdStartResult.startedWithTrack;
  }

  /// Appends [tracks] to the end of the active queue without interrupting
  /// the currently playing track. **Never** engages Auto DJ — once the
  /// manual queue finishes, playback stops.
  void appendToQueue(List<Track> tracks) {
    if (tracks.isEmpty) return;
    _queue.addAll(tracks);
    notifyListeners();
  }

  void toggleShuffle() {
    if (_shuffleMode) {
      if (_originalQueue != null) {
        final currentId = _currentTrack?.id;
        _queue = List.from(_originalQueue!);
        _currentIndex = _queue.indexWhere((t) => t.id == currentId);
        if (_currentIndex < 0) _currentIndex = 0;
      }
      _originalQueue = null;
      _shuffleMode = false;
    } else {
      _originalQueue = List.from(_queue);
      final currentId = _currentTrack?.id;
      final currentIdx = _queue.indexWhere((t) => t.id == currentId);
      if (currentIdx >= 0) {
        final current = _queue.removeAt(currentIdx);
        _queue.shuffle(Random());
        _queue.insert(0, current);
        _currentIndex = 0;
      } else {
        _queue.shuffle(Random());
        _currentIndex = 0;
      }
      _shuffleMode = true;
    }
    notifyListeners();
  }

  void cycleRepeatMode() {
    _repeatMode =
        repeat.PlaybackRepeatMode.values[(_repeatMode.index + 1) %
            repeat.PlaybackRepeatMode.values.length];
    if (_autoDJMode.isActive) {
      _autoDJMode = AutoDJMode.off;
      _queueManager?.disableAutoDJ();
      _queueManager?.setCurrentMode(AutoDJMode.off);
      _dspEngine?.setActive(false);
    }
    notifyListeners();
  }

  void startSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _sleepTimerTick?.cancel();
    _sleepTimerRemaining = duration;
    _sleepTimer = Timer(duration, () {
      _sleepTimerRemaining = Duration.zero;
      _sleepTimer = null;
      _sleepTimerTick?.cancel();
      _sleepTimerTick = null;
      stop();
    });
    _sleepTimerTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_sleepTimerRemaining != null && _sleepTimerRemaining!.inSeconds > 0) {
        _sleepTimerRemaining =
            _sleepTimerRemaining! - const Duration(seconds: 1);
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimerTick?.cancel();
    _sleepTimer = null;
    _sleepTimerTick = null;
    _sleepTimerRemaining = null;
    notifyListeners();
  }

  Future<void> playTrack(
    Track track, {
    AudioQuality quality = AudioQuality.adaptive,
    Duration? startAt,
  }) async {
    _isLoading = true;
    _error = null;
    _stopPolling();
    _completionSubscription?.cancel();

    // Flush stale restored queue state from the audio handler when
    // the user manually selects a different track after cold-boot
    // restoration. Without this, the audio handler's queue may hold
    // the restored track's MediaItem while the player switches to
    // the user's selection, causing a window of stale metadata and
    // potential hanging during the handoff.
    _audioHandler?.clearQueue();

    notifyListeners();

    // Cold-launch resume: the pending position was captured by
    // `_loadActiveTrackState` so the first play after restart picks up
    // at the exact second the user left off instead of rewinding to
    // 0. We honour whichever value is supplied (explicit `startAt`
    // wins, falling back to the cold-launch flag).
    final effectiveStartAt = startAt ?? _pendingResumePosition;
    _pendingResumePosition = null;

    try {
      _currentTrack = track;
      _position = effectiveStartAt ?? Duration.zero;
      _bufferedPosition = Duration.zero;
      _addToRecentlyPlayed(track);

      // Kick off lyrics & color extraction concurrently — do NOT await either
      // here. Both are non-blocking background tasks: lyrics may take several
      // seconds over a slow network and blocking on them was causing the
      // provider to time them out (1500 ms) before the APIs had a chance to
      // respond, resulting in "No lyrics available" for most tracks.
      _fetchLyricsForCurrentTrack();
      _extractDominantColor(track.thumbnailUrl);

      final sourceRef = await PlaybackSession().resolve(track, _fallbackEngine);
      final qualityStr = sourceRef?.quality ?? 'adaptive';

      if (sourceRef != null) {
        _currentTrack = track.copyWith(activeSource: sourceRef);
      }

      if (_mixer != null) {
        await _mixer!.playTrack(_currentTrack!, startAt: effectiveStartAt);
      } else {
        final audioUrl = await _audioRepository.getAudioUrl(
          _currentTrack!,
          quality: qualityStr,
        );
        await _audioRepository.playTrack(_currentTrack!, audioUrl);
        if (effectiveStartAt != null && effectiveStartAt > Duration.zero) {
          try {
            await _audioRepository.seek(effectiveStartAt);
          } catch (e) {
            AppLogger.log(
              'playTrack seek to $effectiveStartAt failed: $e',
              name: 'PlayerProvider',
            );
          }
        }
      }
      _isPlaying = true;
      _startPolling();
      _listenForCompletion();
      for (final cb in _trackChangedListeners) {
        cb();
      }

      // Phase 6: kick background MusicBrainz enrichment for
      // the now-playing track so the next Auto-DJ call can
      // short-circuit on a cache hit. Fire-and-forget; never
      // block the user-facing track change on a remote
      // round-trip.
      _genreEnrichment?.enqueueForEnrichment([track]);

      _preloadNextTrack();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _preloadNextTrack() async {
    if (_currentIndex + 1 < _queue.length) {
      final nextTrack = _queue[_currentIndex + 1];
      // Do not block playback on preloading
      _audioRepository.preloadTrack(nextTrack);
    }
  }

  /// 80% playback interceptor. Called from the position-stream
  /// listener on every audio frame; cheap when no work is to be
  /// done (the dedupe flag short-circuits in O(1)). When the
  /// threshold is crossed for the first time this session the
  /// call schedules a fire-and-forget SQLite write through the
  /// [DJHistoryLedger] — the write itself runs off the UI thread
  /// (Dart's microtask queue + the sqflite background isolate)
  /// and never blocks the position stream.
  void _maybeLog80Percent() {
    if (_historyLoggedForCurrentTrack) return;
    if (!_isPlaying) return;
    final track = _currentTrack;
    final ledger = _historyLedger;
    if (track == null || ledger == null) return;
    final durMs = _duration.inMilliseconds;
    final posMs = _position.inMilliseconds;
    if (durMs <= 0) return;
    if (posMs < durMs * 0.80) return;
    if (ledger.hasBeenLoggedThisSession(track.id)) return;
    _historyLoggedForCurrentTrack = true;
    unawaited(_logCurrentTrackHistory(track));
  }

  /// Builds a [DJHistoryEntry] from the current track metadata and
  /// hands it to the ledger. The artist name is [Track.author]
  /// (the public-facing "artist" field on the YouTube Music /
  /// YouTube track model); genre / bpm / energy are not yet
  /// sourced from the local library (no metadata source exists
  /// in the current codebase), so they fall through to the
  /// schema defaults ('Unknown' / 0.0 / 0.5). The Markov engine
  /// can later enrich these from the AudioDB / MusicBrainz lookup
  /// service without changing the schema.
  Future<void> _logCurrentTrackHistory(Track track) async {
    final ledger = _historyLedger;
    if (ledger == null) return;
    try {
      await ledger.logTrack(
        DJHistoryEntry(
          trackId: track.id,
          artistName: track.author ?? 'Unknown',
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      // Smart-DJ bootstrap fusion: the row just committed
      // to `dj_listening_history` is the only event the
      // engine's `_cachedHistoryCount` cares about. Per the
      // spec, the increment lives inside the successful
      // completion closure of the existing database
      // operation — not on a 80%-threshold callback and
      // not on track end. The audit identified
      // `ledger.logTrack(...)` as the single production
      // write path; this is that path's success branch.
      _routingService?.notifyHistoryRowCommitted();
    } catch (e) {
      AppLogger.log(
        'Failed to log track history at 80%: $e',
        name: 'PlayerProvider',
      );
    }
  }

  /// Settings-slider-driven preload. On every track change we look ahead by
  /// `_settingsProvider.prebufferCount` (1..5) tracks, check the Hive box
  /// instantly, and fire background downloads for any missing ones.
  Future<void> _onTrackChangedForPreload() async {
    // New track → re-arm the 80% history-logger trigger. A
    // re-play of the same track from the user's perspective
    // (e.g. queue loop, manual previous) should also re-arm, so
    // we reset unconditionally on every track-change event.
    _historyLoggedForCurrentTrack = false;
    final lookAhead = _settingsProvider.prebufferCountClamped;
    for (var i = 1; i <= lookAhead; i++) {
      final idx = _currentIndex + i;
      if (idx < 0 || idx >= _queue.length) break;
      final track = _queue[idx];
      if (_hybridCache.isCached(track.id)) continue;
      if (_hybridCache.isActivelyCaching(track.id)) continue;
      _hybridCache.markCaching(track.id);
      // Fire-and-forget — never block the queue change on background writes.
      unawaited(
        _audioRepository.preloadTrack(track).catchError((_) {
          _hybridCache.markNotCaching(track.id);
        }),
      );
    }
  }

  Future<void> playFromQueue(
    int index, {
    AudioQuality quality = AudioQuality.adaptive,
  }) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    await playTrack(_queue[index], quality: quality);
  }

  Future<void> togglePlayPause() async {
    if (_isTransitioning) return;
    try {
      if (_isPlaying) {
        await _audioRepository.pause();
        _isPlaying = false;
        _autoScroll = false;
        // Persist immediately so a force-kill right after pause still
        // restores the paused-at position on the next launch.
        await _saveActiveTrackState();
      } else {
        // Cold-launch path: `_pendingResumePosition` was set by
        // `_loadActiveTrackState` if there is a saved position and
        // the audio handler has never been started. In that case a
        // plain `resume()` would be a no-op (the handler is idle), so
        // we route through `playTrack` with `startAt` so the audio
        // loads, seeks to the saved position, and starts playing in
        // one go.
        final pending = _pendingResumePosition;
        if (pending != null && _currentTrack != null) {
          // The cold-launch path is a multi-step async load
          // (URL resolve → mixer add → engine setSource → seek
          // → play). While it is in flight, subsequent taps of
          // the play/pause button must be ignored or two loads
          // will race against the same engine instance.
          _isTransitioning = true;
          try {
            await playTrack(_currentTrack!, startAt: pending);
          } finally {
            _isTransitioning = false;
          }
        } else {
          await _audioRepository.resume();
          _isPlaying = true;
        }
      }
      notifyListeners();
    } catch (e) {
      _isTransitioning = false;
      _error = 'Failed to toggle playback: ${e.toString()}';
      notifyListeners();
    }
  }

  Future<void> pause() async {
    try {
      await _audioRepository.pause();
      _isPlaying = false;
      _autoScroll = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to pause: ${e.toString()}';
      notifyListeners();
    }
  }

  Future<void> seekTo(Duration position) async {
    try {
      if (_pendingResumePosition != null) {
        _pendingResumePosition = position;
      }
      await _audioRepository.seek(position);
      _position = position;
      notifyListeners();
    } catch (e) {
      _position = position;
      notifyListeners();
      AppLogger.log(
        'Silent seek error (ignored on boot): $e',
        name: 'PlayerProvider',
      );
    }
  }

  /// Called by the seekbar at the start of a drag or tap. Flips
  /// the [_isSeeking] lock so the position stream listener
  /// suppresses updates until the engine catches up to the
  /// user-painted position. Idempotent: a second `startSeek` while
  /// already seeking cancels the prior timeout and reseats the
  /// lock with a fresh 2-second window once [endSeek] fires.
  void startSeek() {
    _isSeeking = true;
  }

  /// Called by the seekbar on every drag update and on tap.
  /// Updates the optimistic position so the seekbar paints
  /// against the user's finger instead of the last stream tick.
  /// Does NOT touch the audio engine — the actual seek is
  /// committed by [endSeek] on drag release.
  void updateSeek(Duration position) {
    _seekPosition = position;
    _position = position;
    positionNotifier.value = position;
  }

  /// Called by the seekbar on drag end (and on tap). Commits the
  /// final user-painted position to the audio engine, then keeps
  /// the [_isSeeking] lock armed for up to 2 seconds while the
  /// engine catches up. The lock auto-releases inside the
  /// position stream listener as soon as a tick lands within
  /// 500 ms of the seek target; the 2-second timer is a hard
  /// fallback for slow / unresponsive engines.
  void endSeek(Duration position) {
    _seekPosition = position;
    _position = position;
    positionNotifier.value = position;
    _audioRepository.seek(position);
    _seekTimeoutTimer?.cancel();
    _seekTimeoutTimer = Timer(const Duration(seconds: 2), () {
      if (_isSeeking) {
        _isSeeking = false;
        _seekTimeoutTimer = null;
      }
    });
  }

  Future<void> next() async {
    if (_currentIndex + 1 < _queue.length) {
      await playFromQueue(_currentIndex + 1);
      return;
    }
    if (_repeatMode == repeat.PlaybackRepeatMode.all && _queue.isNotEmpty) {
      await playFromQueue(0);
      return;
    }
    // End of the manual queue. The next-button is a no-op here — auto DJ
    // (if engaged) is only driven by the completion handler so a user who
    // taps "next" at the end of a manual queue does not unexpectedly flip
    // on the recommendation engine.
  }

  Future<void> previous() async {
    if (_position.inSeconds > 3) {
      seekTo(Duration.zero);
    } else if (_currentIndex > 0) {
      _currentIndex--;
      await playTrack(_queue[_currentIndex]);
    } else {
      seekTo(Duration.zero);
    }
  }

  void _startPolling() {
    _positionSub?.cancel();
    _bufferedPositionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _mediaItemSub?.cancel();
    _mediaItemSub = _audioHandler?.mediaItem.listen((item) {
      if (item == null) return;
      // [PlayerProviderSync] Bridge between the native gapless engine
      // and the Dart-side state. Every MediaItem change (gapless
      // auto-advance from the ConcatenatingAudioSource, manual user
      // skip, track expiration handoff) is intercepted here so the
      // miniplayer text views, album art imagery, dominant-color
      // scrim, and fullscreen player redraw against the new track —
      // even when nothing in the manual `_queue` knew about it yet.
      //
      // Dedup guard: use `_lastSyncedMediaItemId` instead of
      // `_currentTrack?.id` so that a gapless boundary transition
      // is NEVER suppressed even when `onTrackQueued` has already
      // mirrored the incoming track into `_queue` (which would make
      // the old `_currentTrack?.id == resolved.id` guard fire and
      // skip the redraw entirely, freezing the miniplayer art).
      //
      // Track resolution chain:
      //   1. The manual queue (the common case).
      //   2. The gapless mixer's preloaded timeline (Auto DJ /
      //      dynamic-lookahead picks that have not yet been mirrored
      //      into the manual queue by `onTrackQueued`).
      //   3. A minimal `Track` synthesized from the MediaItem's
      //      tag metadata as a last-resort fallback so the UI never
      //      desyncs from the live decoder.
      Track resolved;
      int? newIndex;
      final queueIndex = _queue.indexWhere((t) => t.id == item.id);
      if (queueIndex != -1) {
        resolved = _queue[queueIndex];
        newIndex = queueIndex;
      } else {
        Track? mixerTrack;
        final mixerQueue = _mixer?.queuedTracks;
        if (mixerQueue != null) {
          for (final t in mixerQueue) {
            if (t.id == item.id) {
              mixerTrack = t;
              break;
            }
          }
        }
        resolved =
            mixerTrack ??
            Track(
              id: item.id,
              title: item.title,
              author: item.artist,
              album: item.album,
              thumbnailUrl: item.artUri?.toString(),
              duration: item.duration ?? Duration.zero,
            );
      }
      // Skip the redraw ONLY when the exact same MediaItem id has
      // already been synced (e.g. a duration-update tick for the
      // same track). A genuine gapless boundary (new id) always
      // forces a full UI refresh regardless of queue state.
      if (_lastSyncedMediaItemId == resolved.id) return;
      _lastSyncedMediaItemId = resolved.id;
      AppLogger.log(
        '[PlayerProviderSync] Synchronizing UI to active MediaItem: '
        'track=${resolved.id} ("${resolved.title}"), '
        'queueIndex=$newIndex',
        name: 'PlayerProvider',
      );
      _currentTrack = resolved;
      if (newIndex != null) _currentIndex = newIndex;
      // [UI-Sync] Always refresh duration from the incoming MediaItem
      // on a gapless boundary. The duration stream may not update
      // until the decoder fully loads the new source, leaving the
      // miniplayer duration label frozen at the outgoing track's value.
      if (item.duration != null && item.duration != Duration.zero) {
        _duration = item.duration!;
      }
      _historyLoggedForCurrentTrack = false;
      _fetchLyricsForCurrentTrack();
      _extractDominantColor(_currentTrack?.thumbnailUrl);
      // Fire existing track-change hooks (preload loop, etc.) so
      // downstream side-effects (Hive-driven prebuffer) follow the
      // gapless transition too.
      for (final cb in _trackChangedListeners) {
        cb();
      }
      notifyListeners();
    });

    /// [UI-Sync] Public entry point for manual/native track synchronization.
    /// Used by the platform channel bridge (or Dart event listeners) to force
    /// a UI layout recalculation when a gapless boundary is crossed.
    void synchronizeActiveTrackState(String activeTrackId) {
      AppLogger.log(
        '[PlayerProviderSync] Force synchronizing active track state for: $activeTrackId',
        name: 'PlayerProvider',
      );
      // Find the track in the manual queue or mixer.
      Track? resolved;
      int? newIndex;
      final queueIndex = _queue.indexWhere((t) => t.id == activeTrackId);
      if (queueIndex != -1) {
        resolved = _queue[queueIndex];
        newIndex = queueIndex;
      } else {
        final mixerQueue = _mixer?.queuedTracks;
        if (mixerQueue != null) {
          for (final t in mixerQueue) {
            if (t.id == activeTrackId) {
              resolved = t;
              break;
            }
          }
        }
      }

      if (resolved != null) {
        _currentTrack = resolved;
        if (newIndex != null) _currentIndex = newIndex;
        _historyLoggedForCurrentTrack = false;
        _fetchLyricsForCurrentTrack();
        _extractDominantColor(_currentTrack?.thumbnailUrl);
        notifyListeners();
      }
    }

    _positionSub = _audioRepository.positionStream.listen((pos) {
      // Drag lock: while the user is dragging the seekbar, the
      // position they painted is the source of truth. The first
      // stream tick that lands within 500 ms of the seek target
      // is treated as the engine having caught up, and the lock
      // is released so subsequent ticks update the bar. The
      // 2-second [_seekTimeoutTimer] is a hard fallback — if the
      // engine never emits within that window (network stream,
      // cold cache), the lock is force-cleared regardless.
      if (_isSeeking) {
        final delta = (pos.inMilliseconds - _seekPosition.inMilliseconds).abs();
        if (delta < 500) {
          _isSeeking = false;
          _seekTimeoutTimer?.cancel();
          _seekTimeoutTimer = null;
        } else {
          // Engine has not caught up yet — keep the optimistic
          // value, do not run the side effects below (they would
          // act on stale data), do not touch the notifier.
          return;
        }
      }
      _position = pos;
      positionNotifier.value = pos;
      // Throttled persistence: Hive writes on every audio
      // frame (multiple per second) would thrash the disk. We coalesce
      // to one write per 2 seconds while a track is actively playing.
      if (_isPlaying) {
        final now = DateTime.now();
        if (now.difference(_lastPositionWrite).inMilliseconds >= 2000) {
          _lastPositionWrite = now;
          unawaited(_saveActiveTrackState());
        }
      }
      // 80% playback interceptor (Phase 1). The dedupe guard
      // (history-logged flag) ensures the SQLite write fires at
      // most once per (session, track) pair; the actual write is
      // fire-and-forget on the Dart event loop's microtask queue,
      // so it never blocks the position stream.
      _maybeLog80Percent();
      // Phase 3: 15-second-lookahead queue trigger + crossfade
      // trigger. Both are mixer methods that are themselves
      // idempotent (per-track dedupe set inside the mixer), so
      // calling them on every position tick is safe.
      final mixer = _mixer;
      final track = _currentTrack;
      if (mixer != null && track != null) {
        // Race-shield recovery: if a previous queueNextTrack
        // skipped its injection because the pipeline was
        // actively rebuilding, and the pipeline has since
        // settled, retry the deferred injection from the
        // position tick before issuing the normal lookahead
        // check. The mixer's dirty bit is cleared on a
        // successful add(), so this is a no-op once the
        // track lands in the native timeline.
        if (mixer.isLookaheadDirty && !mixer.isPipelineRebuilding) {
          unawaited(mixer.retryPendingInjection());
        }
        unawaited(
          mixer.maybeQueueNextAt(
            current: track,
            position: pos,
            duration: _duration,
          ),
        );
        unawaited(
          mixer.maybeFireCrossfadeAt(
            currentTrackId: track.id,
            position: pos,
            duration: _duration,
          ),
        );
      }
    });
    _bufferedPositionSub = _audioRepository.bufferedPositionStream.listen((
      pos,
    ) {
      _bufferedPosition = pos;
      bufferedPositionNotifier.value = pos;
    });
    _durationSub = _audioRepository.durationStream.listen((dur) {
      if (dur == _duration) return;
      _duration = dur;
      durationNotifier.value = dur;
      // Duration changes are rare (track change). The wider
      // `notifyListeners()` is OK here — a full consumer rebuild
      // on track load is the correct behaviour for time labels,
      // lyrics, and any other duration-dependent layout.
      notifyListeners();
    });
    _playingSub = _audioRepository.playingStream.listen((isPlaying) {
      if (_isPlaying != isPlaying) {
        _isPlaying = isPlaying;
        // Edge-triggered save: flipping playing→paused or paused→
        // playing is a meaningful state change worth persisting
        // immediately. togglePlayPause() also does this, but this
        // catches the case where the OS paused us (audio focus loss,
        // headphones unplugged, etc.) without going through the
        // provider.
        if (!isPlaying) {
          unawaited(_saveActiveTrackState());
        }
        notifyListeners();
      }
    });
    _processingStateSub?.cancel();
    _processingStateSub = _audioRepository.processingStateStream.listen((
      state,
    ) {
      if (_processingState != state) {
        _processingState = state;
        notifyListeners();
      }
    });
  }

  void _stopPolling() {
    _positionSub?.cancel();
    _positionSub = null;
    _bufferedPositionSub?.cancel();
    _bufferedPositionSub = null;
    _durationSub?.cancel();
    _durationSub = null;
    _playingSub?.cancel();
    _playingSub = null;
    _processingStateSub?.cancel();
    _processingStateSub = null;
    _mediaItemSub?.cancel();
    _mediaItemSub = null;
  }

  void _listenForCompletion() {
    _completionSubscription?.cancel();
    _completionSubscription = _audioRepository.processingStateStream.listen((
      state,
    ) {
      if (state == ProcessingState.completed && _queue.isNotEmpty) {
        if (_repeatMode == repeat.PlaybackRepeatMode.one) {
          seekTo(Duration.zero);
          _audioRepository.resume();
        } else if (_currentIndex + 1 < _queue.length) {
          next();
        } else if (_repeatMode == repeat.PlaybackRepeatMode.all) {
          playFromQueue(0);
        } else if (_queueManager?.isActive ?? false) {
          _generateAutoDJNext();
        } else {
          // End of the manual queue with Auto DJ disengaged. Strict finite
          // playback: stop without auto-rolling recommendations.
          _stopAfterQueue();
        }
      }
    });
  }

  /// Asks the [QueueManager] for the next Auto DJ track and plays it.
  /// Falls back to a graceful stop if the engine returns nothing.
  Future<void> _generateAutoDJNext() async {
    final manager = _queueManager;
    final current = _currentTrack;
    if (manager == null || current == null) {
      _stopAfterQueue();
      return;
    }
    final next = await manager.generateNextAutoDJTrack(current);
    if (next == null) {
      _stopAfterQueue();
      return;
    }
    _queue.add(next);
    await playFromQueue(_currentIndex + 1);
  }

  /// Stops playback at the end of the manual queue when Auto DJ is off.
  /// Mirrors the existing [stop] side-effects but leaves the queue and
  /// current track metadata intact so the miniplayer remains in its last
  /// resting state.
  void _stopAfterQueue() {
    _audioRepository.pause();
    _isPlaying = false;
    _autoScroll = false;
    _position = Duration.zero;
    _bufferedPosition = Duration.zero;
    _processingState = ProcessingState.idle;
    _queueManager?.disableAutoDJ();
    notifyListeners();
  }

  Future<void> stop() async {
    _stopPolling();
    _completionSubscription?.cancel();
    await _audioRepository.stop();
    _isPlaying = false;
    _position = Duration.zero;
    notifyListeners();
  }

  Future<void> clearQueue() async {
    _queue = [];
    _currentIndex = 0;
    _currentTrack = null;
    _currentPlaylistId = null;
    _originalQueue = null;
    _shuffleMode = false;
    _queueManager?.disableAutoDJ();
    _audioHandler?.clearQueue();
    await stop();
    unawaited(_saveActiveTrackState());
    notifyListeners();
  }

  /// Toggles the Auto DJ engine without changing the active queue. Used by
  /// the dedicated Auto DJ icon in the miniplayer and the full-screen
  /// player. Returns the new state.
  bool toggleAutoDJ() {
    final manager = _queueManager;
    if (manager == null) return false;
    return manager.toggleAutoDJ();
  }

  bool get isAutoDJEnabled => _queueManager?.isActive ?? false;

  void clearError() {
    _error = null;
    notifyListeners();
  }

  MusicAudioHandler? _audioHandler;

  void setAudioHandler(MusicAudioHandler handler) {
    _audioHandler = handler;
    _syncRestoredStateToAudioHandler();
    _startPolling();
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _sleepTimerTick?.cancel();
    _seekTimeoutTimer?.cancel();
    _stopPolling();
    _completionSubscription?.cancel();
    _skipNextSubscription?.cancel();
    _skipPrevSubscription?.cancel();
    _positionSub?.cancel();
    _bufferedPositionSub?.cancel();
    _durationSub?.cancel();
    _crossfadeSub?.cancel();
    // Final flush: capture the last position before the provider is
    // torn down. We do not await — the OS gives us a few hundred ms at
    // most and a fire-and-forget SharedPreferences write is fine.
    unawaited(_saveActiveTrackState());
    unawaited(_saveAutoQueueState());
    _queueManager?.removeListener(notifyListeners);
    WidgetsBinding.instance.removeObserver(this);
    positionNotifier.dispose();
    bufferedPositionNotifier.dispose();
    durationNotifier.dispose();
    super.dispose();
  }
}
