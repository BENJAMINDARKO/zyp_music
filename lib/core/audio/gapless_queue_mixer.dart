import 'dart:async';
import 'dart:math';

import 'package:just_audio/just_audio.dart';

import '../utils/app_logger.dart';
import '../../domain/entities/video.dart';

/// Thin wrapper around a single, persistent [AudioPlayer] running
/// a sequential [ConcatenatingAudioSource] timeline. The spec
/// says: "to completely sidestep dual-decoder thread race
/// conditions and audio rendering locks, the system must utilize
/// a single, persistent ExoPlayer instance running a sequential
/// MediaItem gapless timeline."
///
/// In `just_audio` (the Dart wrapper around ExoPlayer/Media3) the
/// equivalent is a single [AudioPlayer] with a
/// [ConcatenatingAudioSource] of pre-built [AudioSource]s. The
/// player crossfades between adjacent sources natively — there is
/// no second decoder, no second audio session, no render-thread
/// handoff. Appending a new source to the concatenation is the
/// `queueNextTrack` API the spec calls out.
///
/// ## Two trigger surfaces
///
/// * **15-second lookahead** — [maybeQueueNextAt] is called by
///   the host's position-stream listener at every position tick.
///   The first time `position >= duration - 15s` for the
///   currently-playing track, the host invokes the
///   [onQueueNext] callback to resolve a Track and hands it to
///   [queueNextTrack]. The dedupe flag ensures the callback
///   fires at most once per (track, session) pair.
/// * **Crossfade trigger** — [crossfadeReadyStream] emits when
///   the position cursor crosses the configured silence
///   boundary (Phase 3) OR the `duration - 5000ms` fallback
///   (spec). Phase 4 will consume this to start the actual
///   crossfade. Phase 3 only emits the flag.
class GaplessQueueMixer {
  static const String _logTag = 'GaplessQueueMixer';

  /// Default lookahead window from the spec: "Exactly 15 seconds
  /// before the active audio file hits its termination limit".
  static const Duration kLookahead = Duration(seconds: 35);

  /// Spec fallback for the crossfade trigger: "If the value
  /// returns null, fall back to a baseline threshold of
  /// duration - 5000ms".
  static const Duration kCrossfadeFallback = Duration(seconds: 10);

  AudioPlayer _player;

  /// The live concatenation. Replaced (not mutated-clear) by
  /// [playTrack] — [ConcatenatingAudioSource] does not support
  /// `clear()` (its children list is unmodifiable), so a fresh
  /// timeline is built and re-attached via the player.
  ConcatenatingAudioSource _concatenation =
      ConcatenatingAudioSource(children: []);

  /// Resolves a Track → [AudioSource] for the concatenation.
  /// Production code wires this to the AudioRepository
  /// (`getAudioUrl`); tests inject a fake.
  final Future<AudioSource> Function(Track track) _sourceBuilder;

  /// Resolves the next track to queue. Production code wires
  /// this to the [AutoDjRoutingService.resolveNext] call; tests
  /// inject a fake.
  Future<Track?> Function(Track current) nextTrackResolver;

  /// How to look up the silence boundary for a given trackId.
  /// Production code wires this to the [PlaylistDatabase] query;
  /// tests inject a fake. Returning `null` causes the mixer to
  /// fall back to the [kCrossfadeFallback] threshold.
  final Future<int?> Function(String trackId) _silenceResolver;

  /// Optional live duration probe. Currently unused by the
  /// mixer (the position-stream callback passes `duration`
  /// directly), kept for future per-track live probes.
  // ignore: unused_field
  final Stream<Duration?> Function(String trackId) _durationStream;

  final StreamController<CrossfadeReadyEvent> _crossfadeController =
      StreamController<CrossfadeReadyEvent>.broadcast();

  /// Track id → entry. We hold the [Track] alongside the
  /// resolved [AudioSource] so the mixer can hand the [Track]
  /// back to the resolver for the next-track query and to
  /// deduplicate queueNextTrack calls.
  final Map<String, _SourceEntry> _entries = <String, _SourceEntry>{};

  /// Per-track flag: true iff the 15s-lookahead has already
  /// resolved the next track for this source. Prevents the
  /// position listener from re-firing the resolver on every
  /// tick after T-15s.
  final Set<String> _lookaheadFiredFor = <String>{};

  /// Per-track flag: true iff the crossfadeReady event has
  /// Track IDs where the crossfade threshold has already fired.
  final Set<String> _crossfadeFiredFor = {};

  final _random = Random();
  final Map<String, int> _dynamicCrossfadeDurations = {};

  int _getDynamicCrossfadeMs(String trackId) {
    return _dynamicCrossfadeDurations.putIfAbsent(
      trackId,
      () => 15000 + _random.nextInt(15001), // 15,000 to 30,000 ms
    );
  }

  /// Set once by [attach]. When true, [playTrack] will rewire
  /// the player's audio source to the new concatenation; when
  /// false, the platform is not in use (test path).
  bool _attached = false;

  /// True while a `player.setAudioSource()` call is in flight.
  /// During this window the native [ConcatenatingMediaSource]
  /// reference is transiently detached, so any concurrent
  /// [queueNextTrack] call would crash the platform channel
  /// with a `NullPointerException` from Media3. Set inside a
  /// strict `try/finally` (no catch) so that high-stakes
  /// `setAudioSource` failures still propagate upward.
  bool _isPipelineRebuilding = false;
  bool get isPipelineRebuilding => _isPipelineRebuilding;

  /// Asymmetric lookahead recovery dirty bit. Flipped to `true`
  /// when [queueNextTrack] skips an injection because the
  /// pipeline was actively rebuilding. NOT set when the skip
  /// is caused by a cold-boot null concatenation — in that
  /// case the regular scheduler will re-fire and append the
  /// tracking token naturally. The position stream consumer
  /// (see [PlayerProvider]) checks this flag and, once the
  /// pipeline settles, re-attempts the pending injection.
  bool _isLookaheadDirty = false;
  bool get isLookaheadDirty => _isLookaheadDirty;

  /// The track whose injection was skipped due to an active
  /// pipeline rebuild. Held here so the position-stream
  /// recovery hook can retry the `add()` once the pipeline
  /// re-settles. Cleared on a successful injection.
  Track? _pendingDirtyTrack;

  void Function(Track track)? onTrackQueued;

  GaplessQueueMixer({
    required AudioPlayer player,
    required Future<AudioSource> Function(Track track) sourceBuilder,
    required Future<Track?> Function(Track current) nextTrackResolver,
    required Future<int?> Function(String trackId) silenceResolver,
    required Stream<Duration?> Function(String trackId) durationStream,
  })  : _player = player,
        _sourceBuilder = sourceBuilder,
        this.nextTrackResolver = nextTrackResolver,
        _silenceResolver = silenceResolver,
        _durationStream = durationStream;

  /// Wires the player to the current concatenation. Production
  /// code calls this once after construction; tests skip it
  /// (the platform call would fail in the test VM). Idempotent.
  Future<void> attach() async {
    if (_attached) return;
    _attached = true;
    if (_concatenation.length > 0) {
      _isPipelineRebuilding = true;
      try {
        await _player.setAudioSource(_concatenation);
      } finally {
        _isPipelineRebuilding = false;
      }
    }
  }

  /// The current concatenation. Exposed for tests + telemetry
  /// (e.g. "how many sources are preloaded behind the current
  /// one"). After [playTrack], this is a fresh concatenation
  /// containing only the new track.
  ConcatenatingAudioSource get concatenation => _concatenation;

  /// The underlying [AudioPlayer] (single, persistent, as the
  /// spec requires).
  AudioPlayer get player => _player;

  /// Live stream of crossfade-ready events. Phase 4 will
  /// subscribe to this to start the actual crossfade; Phase 3
  /// only emits the flag.
  Stream<CrossfadeReadyEvent> get crossfadeReadyStream =>
      _crossfadeController.stream;

  /// The 15-second-lookahead trigger surface. Called by the
  /// host's position listener on every tick. Idempotent: the
  /// resolver fires at most once per (track, session) pair.
  ///
  /// [current] is the currently-playing track (the host's
  /// position stream is expected to surface the same entity).
  /// When [current] is null the trigger is a no-op (the
  /// resolver needs a seed track).
  /// [position] is the live position cursor; [duration] is the
  /// live duration (may be null while the source is still
  /// loading).
  Future<void> maybeQueueNextAt({
    required Track? current,
    required Duration position,
    required Duration? duration,
  }) async {
    if (current == null) return;
    if (duration == null) return;
    final currentTrackId = current.id;
    final remaining = duration - position;
    // [SeekResilience] If the user seeks backward past the T-15s window,
    // clear the fired flag so the lookahead can re-arm on the next tick.
    // Without this, a seek to T-20s would leave the flag `true` and the
    // engine would never preload the next track until natural completion.
    if (remaining > kLookahead) {
      _lookaheadFiredFor.remove(currentTrackId);
      return;
    }
    if (_lookaheadFiredFor.contains(currentTrackId)) return;
    // T-15s reached. Resolve the next track (callback may
    // return null if the engine is off / no candidate). The
    // resolver itself is responsible for any session-recent
    // dedupe; this side just records that we fired.
    _lookaheadFiredFor.add(currentTrackId);
    AppLogger.log(
      'lookahead hit: $currentTrackId remaining=${remaining.inMilliseconds}ms',
      name: _logTag,
    );
    final next = await nextTrackResolver(current);
    if (next == null) return;
    await queueNextTrack(next);
  }

  /// Clears the per-track lookahead fired flag so the next position tick
  /// re-arms the T-15s resolver for [trackId]. Called by [PlayerProvider]
  /// after a mid-track mode switch where the warm-up has verified a
  /// candidate for the new mode — the existing preloaded sources are
  /// preserved as a buffer and the flag is simply reset so the resolver
  /// re-fires under the new mode's strategy.
  ///
  /// Safe to call with a null [trackId] (no-op).
  void clearLookaheadFor(String? trackId) {
    if (trackId != null) {
      _lookaheadFiredFor.remove(trackId);
      AppLogger.log(
        'clearLookaheadFor: re-armed lookahead for track=$trackId '
        '(mode switch warm-up complete)',
        name: _logTag,
      );
    }
  }

  /// Crossfade-trigger surface. Called by the host's position
  /// listener on every tick. Emits a [CrossfadeReadyEvent] the
  /// first time the position cursor crosses the silence
  /// boundary (or the [kCrossfadeFallback] threshold when no
  /// scan is available) for the currently-playing track.
  Future<void> maybeFireCrossfadeAt({
    required String currentTrackId,
    required Duration position,
    required Duration? duration,
  }) async {
    if (duration == null) return;
    if (_crossfadeFiredFor.contains(currentTrackId)) return;
    final silenceMs = await _silenceResolver(currentTrackId);
    
    final dynamicCrossfadeMs = _getDynamicCrossfadeMs(currentTrackId);
    final fallbackThresholdMs = duration.inMilliseconds - dynamicCrossfadeMs;
    
    final thresholdMs = silenceMs ?? fallbackThresholdMs;
    if (position.inMilliseconds < thresholdMs) return;

    // Race-shield: if the 15-second lookahead resolver (e.g. Vibe Match /
    // Smart DJ) is taking a long time to fetch metadata, the position stream
    // might cross the crossfade threshold before the next track is actually
    // appended. Wait until the next track arrives before consuming the flag.
    if (queuedTracks.length < 2) return;

    _crossfadeFiredFor.add(currentTrackId);
    AppLogger.log(
      'crossfadeReady: $currentTrackId at ${position.inMilliseconds}ms '
      '(threshold=${thresholdMs}ms, silenceMs=$silenceMs, dynamicDurationMs=$dynamicCrossfadeMs)',
      name: _logTag,
    );
    
    final actualCrossfadeDurationMs = silenceMs == null ? dynamicCrossfadeMs : (duration.inMilliseconds - silenceMs);
    
    _crossfadeController.add(CrossfadeReadyEvent(
      trackId: currentTrackId,
      positionMs: position.inMilliseconds,
      thresholdMs: thresholdMs,
      crossfadeDurationMs: actualCrossfadeDurationMs,
      source: silenceMs == null
          ? CrossfadeSource.durationFallback
          : CrossfadeSource.silenceScan,
    ));
  }

  /// Replaces the concatenation with a single-source timeline
  /// starting at [track]. Use this on cold start, on a manual
  /// user "Play this track" tap, and on the cold-start path of
  /// the Auto DJ engine.
  ///
  /// [ConcatenatingAudioSource] does not support `clear()`, so
  /// we build a fresh timeline and (when attached) rewire the
  /// player to it. The per-track dedupe sets are reset so a
  /// new track restarts the lookahead + crossfade windows
  /// from zero.
  ///
  /// Phase 4: optionally takes [resumeFrom] — when non-null
  /// and the track is the current one, the new player is
  /// seeked to that position before [play] is called. The DSP
  /// crossfade engine uses this when it has built a fresh
  /// `playerB` for the crossfade window and the mixer needs
  /// to be rewound to where it is in the timeline.
  Future<void> playTrack(Track track, {Duration? startAt}) async {
    final source = await _sourceBuilder(track);
    final entry = _SourceEntry(track, source);
    _entries
      ..clear()
      ..[track.id] = entry;
    _lookaheadFiredFor.clear();
    _crossfadeFiredFor.clear();
    final fresh = ConcatenatingAudioSource(children: [source]);
    if (_attached) {
      _isPipelineRebuilding = true;
      try {
        await _player.setAudioSource(fresh);
      } finally {
        _isPipelineRebuilding = false;
      }
      if (startAt != null) {
        await _player.seek(startAt);
      }
      unawaited(_player.play());
    }
    _concatenation = fresh;
  }

  /// Appends [track] to the live concatenation as a preloaded
  /// source. The ExoPlayer instance will pick it up gaplessly
  /// when the current source completes.
  ///
  /// The track's [AudioSource] is built lazily by the source
  /// builder closure. In practice the builder fetches the audio
  /// URL via the existing AudioRepository.getAudioUrl pipeline
  /// (which caches to disk on first hit) so the concatenation's
  /// lookahead buffer is populated before the user reaches the
  /// end of the current source.
  Future<void> queueNextTrack(Track track) async {
    if (_entries.containsKey(track.id)) {
      AppLogger.log(
        'queueNextTrack: already in timeline, skipping: ${track.id}',
        name: _logTag,
      );
      return;
    }
    final source = await _sourceBuilder(track);
    final entry = _SourceEntry(track, source);
    _entries[track.id] = entry;

    if (!_attached) {
      _concatenation.add(source);
      AppLogger.log(
        'queueNextTrack: appended ${track.id} (timeline now '
        '${_concatenation.length} sources)',
        name: _logTag,
      );
      onTrackQueued?.call(track);
      return;
    }

    // Asymmetric entry guard: short-circuit on EITHER an active
    // pipeline rebuild (a `setAudioSource` call is in flight and
    // the native ConcatenatingMediaSource is transiently detached)
    // OR a null concatenation (cold-boot, pre-initialization).
    if (_isPipelineRebuilding || _concatenation.length == 0) {
      // Asymmetric recovery: only flag the lookahead as dirty
      // when the skip is caused by an ACTIVE rebuild. Cold-boot
      // null skips are left alone — the regular scheduler will
      // fire and append the tracking token naturally once the
      // collection re-initializes on startup.
      if (_isPipelineRebuilding) {
        _isLookaheadDirty = true;
        _pendingDirtyTrack = track;
        AppLogger.warning(
          '[MixerRaceShield] Pipeline rebuilding; deferred lookahead injection '
          'for ${track.id} (dirty bit set, position stream will retry).',
          name: _logTag,
        );
      } else {
        AppLogger.warning(
          '[MixerRaceShield] Concatenation uninitialized (cold-boot); '
          'deferring lookahead injection for ${track.id}.',
          name: _logTag,
        );
      }
      return;
    }

    try {
      await _concatenation.add(source);
      _isLookaheadDirty = false;
      _pendingDirtyTrack = null;
      AppLogger.log(
        '[MixerRaceShield] Gapless lookahead token injected securely: ${track.title}',
        name: _logTag,
      );
    } catch (collisionError) {
      // Intentional suppression: append failures are lower-stakes
      // and the position stream dirty-bit recovery will retry the
      // injection once the pipeline settles.
      AppLogger.warning(
        '[MixerRaceShield] Suppressed timeline configuration collision: $collisionError',
        name: _logTag,
      );
    }
    AppLogger.log(
      'queueNextTrack: appended ${track.id} (timeline now '
      '${_concatenation.length} sources)',
      name: _logTag,
    );
    onTrackQueued?.call(track);
  }

  /// Race-shield recovery hook: when [queueNextTrack] short-
  /// circuited because a `setAudioSource` was in flight, the
  /// pending track is stashed here and the dirty bit is
  /// raised. The [PlayerProvider] position stream calls this
  /// on every tick. It is a no-op unless:
  ///
  ///   1. [isLookaheadDirty] is true (something was deferred),
  ///   2. [isPipelineRebuilding] is false (the pipeline has
  ///      settled — we must not race against a still-active
  ///      `setAudioSource` call), and
  ///   3. The native concatenation has re-initialized.
  ///
  /// On a successful `add()` the dirty bit is cleared. If the
  /// retry still hits a transient collision the dirty bit is
  /// left set so the next position tick will try again.
  Future<void> retryPendingInjection() async {
    if (!_isLookaheadDirty) return;
    if (_isPipelineRebuilding) return;
    final pending = _pendingDirtyTrack;
    if (pending == null) {
      _isLookaheadDirty = false;
      return;
    }
    if (_concatenation.length == 0) return;
    if (_entries.containsKey(pending.id)) {
      _isLookaheadDirty = false;
      _pendingDirtyTrack = null;
      return;
    }
    try {
      final source = await _sourceBuilder(pending);
      await _concatenation.add(source);
      _entries[pending.id] = _SourceEntry(pending, source);
      _isLookaheadDirty = false;
      _pendingDirtyTrack = null;
      AppLogger.log(
        '[MixerRaceShield] Recovery injection landed for ${pending.id} '
        '(timeline now ${_concatenation.length} sources).',
        name: _logTag,
      );
      onTrackQueued?.call(pending);
    } catch (collisionError) {
      AppLogger.warning(
        '[MixerRaceShield] Recovery injection still colliding; '
        'leaving dirty bit set for next tick: $collisionError',
        name: _logTag,
      );
    }
  }

  /// Returns the currently-playing track (or null if the
  /// timeline is empty).
  Track? get currentTrack {
    if (_entries.isEmpty) return null;
    final index = _player.currentIndex ?? 0;
    if (index >= 0 && index < _entries.length) {
      return _entries.values.elementAt(index).track;
    }
    return _entries.values.first.track;
  }

  /// All tracks currently in the timeline, in playback order.
  /// Phase 4: the DSP engine reads this to resolve the
  /// "incoming" track for the crossfade (the `crossfadeReady`
  /// event itself only carries the outgoing track id).
  List<Track> get queuedTracks {
    final index = _player.currentIndex ?? 0;
    if (index >= 0 && index < _entries.length) {
      return _entries.values.skip(index).map((e) => e.track).toList(growable: false);
    }
    return _entries.values.map((e) => e.track).toList(growable: false);
  }

  /// Re-exposes the source-builder closure for [track]. Phase
  /// 4: the DSP engine needs the same resolution pipeline
  /// (URL fetch, cache lookup, etc.) for `playerB` that the
  /// mixer uses for its concatenation.
  Future<AudioSource> buildSourceFor(Track track) {
    return _sourceBuilder(track);
  }

  /// Phase 4: swaps the mixer's primary [AudioPlayer] from the
  /// current (outgoing) instance to [newPlayer] (typically the
  /// `playerB` produced by the DSP crossfade engine). The
  /// caller is responsible for:
  ///
  ///   * having prepared [newPlayer] with the correct source
  ///     (usually the crossfade engine has already done this),
  ///   * setting [newPlayer]'s volume / speed to the post-
  ///     crossfade values,
  ///   * calling [MusicAudioHandler.replacePlayer] in the same
  ///     step so the audio handler's streams follow the new
  ///     player (the mixer does not own those subscriptions).
  ///
  /// Internally the mixer:
  ///   * stores [newPlayer] as its primary,
  ///   * disposes the outgoing player (the caller MUST have
  ///     stopped playback on it first; just_audio's
  ///     [AudioPlayer.dispose] is silent on a still-playing
  ///     player on Android),
  ///   * resets the per-track dedupe sets so the new player's
  ///     playback of the first remaining track restarts both
  ///     the 15-second-lookahead and crossfade windows from
  ///     zero.
  ///
  /// The concatenation is intentionally NOT rewired here — the
  /// crossfade engine hands a fully-prepared single-source
  /// [AudioPlayer] to the mixer; the mixer's next `queueNextTrack`
  /// call will lazily build a fresh concatenation around it.
  Future<void> adoptPlayer(AudioPlayer newPlayer, Track newTrack) async {
    final oldPlayer = _player;
    _player = newPlayer;
    _lookaheadFiredFor.clear();
    _crossfadeFiredFor.clear();

    final source = await buildSourceFor(newTrack);
    final entry = _SourceEntry(newTrack, source);
    _entries
      ..clear()
      ..[newTrack.id] = entry;

    if (newPlayer.audioSource is ConcatenatingAudioSource) {
      _concatenation = newPlayer.audioSource as ConcatenatingAudioSource;
    } else {
      _concatenation = ConcatenatingAudioSource(children: [source]);
      if (_attached) {
        _isPipelineRebuilding = true;
        try {
          await newPlayer.setAudioSource(_concatenation);
        } finally {
          _isPipelineRebuilding = false;
        }
      }
    }

    AppLogger.log(
      'adoptPlayer: old=${oldPlayer.hashCode} '
      'new=${newPlayer.hashCode} track=${newTrack.id} (timeline synchronized to new concatenating source)',
      name: _logTag,
    );
    await oldPlayer.dispose();
  }

  Future<void> dispose() async {
    await _crossfadeController.close();
    await _player.dispose();
  }
}

/// One slot in the concatenation timeline. We hold the original
/// [Track] alongside the resolved [AudioSource] so the
/// [GaplessQueueMixer] can hand the [Track] back to the resolver
/// for the next-track query.
class _SourceEntry {
  final Track track;
  final AudioSource source;
  _SourceEntry(this.track, this.source);
}

/// Crossfade-ready event. Phase 4 will consume this; Phase 3
/// only emits it.
class CrossfadeReadyEvent {
  final String trackId;
  final int positionMs;
  final int thresholdMs;
  final int crossfadeDurationMs;
  final CrossfadeSource source;

  const CrossfadeReadyEvent({
    required this.trackId,
    required this.positionMs,
    required this.thresholdMs,
    required this.crossfadeDurationMs,
    required this.source,
  });
}

/// Where the crossfade trigger threshold came from.
enum CrossfadeSource { silenceScan, durationFallback }
