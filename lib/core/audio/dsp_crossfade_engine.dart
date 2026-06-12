import 'dart:async';
import 'dart:math' as math;

import 'package:just_audio/just_audio.dart';

import '../utils/app_logger.dart';
import '../../domain/entities/video.dart';
import '../../data/datasources/local/playlist_database.dart';
import '../../service/audio_handler.dart';
import 'gapless_queue_mixer.dart';

/// Phase 4 — Smart DJ DSP engine.
///
/// When the gapless mixer's `crossfadeReadyStream` fires (Phase
/// 3), the engine takes over playback for the overlap window
/// using **two simultaneous** [AudioPlayer] instances — the
/// existing `playerA` (the current track) and a freshly-built
/// `playerB` (the next track). The engine:
///   1. **Tempo-matches** the two tracks via pitch-corrected
///      `setSpeed` (just_audio delegates to ExoPlayer's
///      `SonicAudioProcessor` on Android, which is the
///      spec's "built-in pitch-preserving" path).
///   2. **Aligns the downbeat** of `playerB` to the next 4-beat
///      bar boundary of `playerA` (bar-quantized delay).
///   3. **Crossfades** over a 10-second window with an
///      equal-power `cos/sin` gain curve at a 16ms tick.
///   4. **Releases** `playerA` and promotes `playerB` to the
///      primary listener source via [MusicAudioHandler.replacePlayer]
///      and [GaplessQueueMixer.adoptPlayer].
///   5. **Normalizes** `playerB`'s speed back to 1.0x over a
///      4-second linear ramp so the user-facing speed indicator
///      returns to baseline (the spec's validation gate).
///
/// All control flow runs on the main isolate but yields
/// between ticks via [Future.delayed]; the actual audio
/// mixing is on the platform's render thread (managed by
/// ExoPlayer, two independent decoder instances). The spec's
/// "Dispatchers.IO for low-level audio tracking" maps in Dart
/// to: BPM lookups go through the async sqflite API (off the
/// main thread), the silence-scanner runs in a Dart `Isolate`
/// (Phase 3), and the DSP math itself is microsecond-scale
/// so it does not block the UI loop.
class DspCrossfadeEngine {
  static const String _logTag = 'DspCrossfadeEngine';

  // -- Spec constants -------------------------------------------------------

  /// Spec §4.1: "strictly within an 8% variance window".
  static const double kRateMin = 0.92;
  static const double kRateMax = 1.08;

  /// Spec §4.2: 10-second crossfade window.
  static const Duration kCrossfadeDuration = Duration(seconds: 10);

  /// Spec §4.2: 16ms tick (≈60Hz).
  static const Duration kCrossfadeTick = Duration(milliseconds: 16);

  /// Spec §4.4: 4-second normalization ramp.
  static const Duration kNormalizeRamp = Duration(seconds: 4);

  // -- Dependencies ---------------------------------------------------------

  final GaplessQueueMixer _mixer;
  final MusicAudioHandler _audioHandler;
  final PlaylistDatabase _db;

  StreamSubscription<CrossfadeReadyEvent>? _sub;

  /// Token that gates the in-flight crossfade. Set on every
  /// new `crossfadeReady` event; the previous tick loops check
  /// this and bail out early if it has changed (i.e. a new
  /// crossfade has superseded the current one — user manual
  /// skip, etc.).
  int _runId = 0;

  /// Phase 5: the engine is gated to the Smart DJ mode only.
  /// The other four active modes (Shuffle Library, Similar
  /// Songs, Same Genre, Same Artist) use the mixer's plain
  /// gapless handoff — no second decoder, no pitch correction,
  /// no crossfade. Smart DJ is the only pathway that unlocks
  /// the multi-decoder audio engine per the spec's "Hook Up
  /// crossfadeReady DSP Links" rule.
  ///
  /// `_active` mirrors the gate state. Default false so a
  /// construction without `setActive(true)` is a no-op (the
  /// subscription is wired in `start()` but the handler bails
  /// before running the crossfade pipeline).
  bool _active = false;

  DspCrossfadeEngine({
    required GaplessQueueMixer mixer,
    required MusicAudioHandler audioHandler,
    required PlaylistDatabase db,
  })  : _mixer = mixer,
        _audioHandler = audioHandler,
        _db = db;

  /// Subscribes to the mixer's `crossfadeReadyStream`. Each
  /// event kicks off a new crossfade — *only when the engine
  /// is active* (i.e. Smart DJ mode is currently selected).
  /// Idempotent: calling twice replaces the prior subscription.
  void start() {
    _sub?.cancel();
    _sub = _mixer.crossfadeReadyStream.listen(_onCrossfadeReady);
    AppLogger.log(
      'started, subscribed to mixer.crossfadeReadyStream '
      '(active=$_active)',
      name: _logTag,
    );
  }

  /// Phase 5: gates the engine on or off. Called by the host
  /// (PlayerProvider) when the Auto DJ mode changes:
  ///
  ///   * `setActive(true)` when the user picks Smart DJ.
  ///   * `setActive(false)` when the user picks any other mode
  ///     (or Off).
  ///
  /// Safe to call from any thread; the field is read by the
  /// event handler on the main isolate, so the worst-case race
  /// is "the very next crossfadeReady after a mode switch
  /// honours the new gate state".
  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    AppLogger.log(
      'gate flipped: active=$active',
      name: _logTag,
    );
  }

  /// True iff the engine is currently gating the crossfade
  /// pipeline. Useful for tests and for the host to verify
  /// the state after a mode switch.
  bool get isActive => _active;

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  // -------------------------------------------------------------------------
  // Trigger
  // -------------------------------------------------------------------------

  Future<void> _onCrossfadeReady(CrossfadeReadyEvent event) async {
    // Phase 5: Smart DJ gate. The other four active modes
    // (Shuffle Library, Similar Songs, Same Genre, Same
    // Artist) use the mixer's plain gapless handoff; the
    // crossfade DSP pipeline is Smart DJ exclusive.
    if (!_active) {
      return;
    }
    final myRunId = ++_runId;
    AppLogger.log(
      'crossfadeReady received: trackId=${event.trackId} '
      'pos=${event.positionMs}ms threshold=${event.thresholdMs}ms '
      'source=${event.source.name}',
      name: _logTag,
    );
    final outgoing = _mixer.currentTrack;
    if (outgoing == null) {
      AppLogger.log('no current track on mixer; abort', name: _logTag);
      return;
    }
    // The next track is whatever the mixer has queued behind
    // the current one. We pick the first entry whose track id
    // is not the outgoing one.
    final queued = _mixer.queuedTracks;
    final incoming = queued.length >= 2 ? queued[1] : null;
    if (incoming == null) {
      AppLogger.log('no queued track on mixer; abort', name: _logTag);
      return;
    }
    try {
      await _runCrossfade(
        runId: myRunId,
        outgoing: outgoing,
        incoming: incoming,
        startPositionMs: event.positionMs,
        crossfadeDurationMs: event.crossfadeDurationMs,
      );
    } catch (e, st) {
      AppLogger.log('crossfade failed: $e\n$st', name: _logTag);
    }
  }

  // -------------------------------------------------------------------------
  // Main crossfade pipeline
  // -------------------------------------------------------------------------

  Future<void> _runCrossfade({
    required int runId,
    required Track outgoing,
    required Track incoming,
    required int startPositionMs,
    required int crossfadeDurationMs,
  }) async {
    // 4.1.1 Look up the two BPMs.
    final bpmA = await _db.getTrackBpm(outgoing.id);
    final bpmB = await _db.getTrackBpm(incoming.id);

    // 4.1.2 Clamp the raw tempo ratio to ±8%.
    final rate = _computeClampedRateRatio(bpmA: bpmA, bpmB: bpmB);
    AppLogger.log(
      'BPMs: A=${bpmA?.toStringAsFixed(2) ?? "?"} '
      'B=${bpmB?.toStringAsFixed(2) ?? "?"} '
      'rawRatio=${(bpmA != null && bpmB != null && bpmB > 0) ? (bpmA / bpmB).toStringAsFixed(3) : "n/a"} '
      'clampedRate=${rate.toStringAsFixed(3)}',
      name: _logTag,
    );

    // 4.1.3 Build playerB. The DSP engine does NOT touch the
    // mixer's concatenation; it constructs an independent
    // AudioPlayer for the overlap window. After the crossfade
    // finishes, the engine hands playerB back to the audio
    // handler / mixer as the new primary.
    final playerB = AudioPlayer();
    try {
      final source = await _mixer.buildSourceFor(incoming);
      final concatenationB = ConcatenatingAudioSource(children: [source]);
      await playerB.setAudioSource(concatenationB);
      await playerB.setSpeed(rate);
      await playerB.setVolume(0.0);

      // 4.3 Bar-quantized beat alignment. We must respect the
      // runId token so a user-driven manual skip during the
      // bar-wait window cancels the crossfade cleanly.
      final delayMs = _computeBarDelayMs(
        currentBpm: bpmA,
        currentPositionMs: startPositionMs,
      );
      AppLogger.log('bar-quantized delay: ${delayMs}ms', name: _logTag);
      if (delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: delayMs));
        if (runId != _runId) {
          AppLogger.log('superseded during bar-wait; abort', name: _logTag);
          return;
        }
      }

      // 4.2 Begin the crossfade. Start playerB at volume 0,
      // then drive both volumes through the equal-power
      // gain curve.
      playerB.play(); // DO NOT await this; just_audio's play() completes when the song ends!
      if (runId != _runId) return;
      final playerA = _mixer.player;

      var elapsedMs = 0;
      final stopwatch = Stopwatch()..start();
      while (elapsedMs < crossfadeDurationMs) {
        if (runId != _runId) {
          AppLogger.log('superseded mid-crossfade; abort', name: _logTag);
          return;
        }
        final t = elapsedMs / crossfadeDurationMs;
        final gainA = _equalPowerFadeOut(t);
        final gainB = _equalPowerFadeIn(t);
        
        // Unawaited volume updates. Awaiting platform channel calls inside
        // a 16ms loop adds massive overhead, stretching the 10s loop to 16s+.
        unawaited(playerA.setVolume(gainA));
        unawaited(playerB.setVolume(gainB));
        
        await Future.delayed(kCrossfadeTick);
        elapsedMs = stopwatch.elapsedMilliseconds;
      }

      // 4.2 End-of-crossfade: stop + dispose playerA, swap
      // the audio handler + mixer to playerB.
      AppLogger.log(
        'crossfade window complete; swapping primary to playerB',
        name: _logTag,
      );
      // Snap the gains to their terminal values so the
      // listener doesn't notice any quantisation drift.
      await playerA.setVolume(0.0);
      await playerB.setVolume(1.0);
      // Stop playerA and flush its codec buffers so all native
      // MediaCodec event-loop handlers close down cleanly before
      // the player is handed to replacePlayer / adoptPlayer for
      // disposal. This prevents background "Handler sending
      // message to a Handler on a dead thread" warnings.
      await playerA.stop();
      await playerA.setAudioSource(
        ConcatenatingAudioSource(children: []),
      );
      await _audioHandler.replacePlayer(playerB);
      await _mixer.adoptPlayer(playerB, incoming);

      // 4.4 Linear tempo normalization. Ramp the rate from
      // `rate` back to 1.0 over 4 seconds, then snap to
      // exactly 1.0 to drop floating-point drift.
      var rampElapsedMs = 0;
      while (rampElapsedMs < kNormalizeRamp.inMilliseconds) {
        if (runId != _runId) return;
        final t = rampElapsedMs / kNormalizeRamp.inMilliseconds;
        final interpolated = rate + (t * (1.0 - rate));
        await playerB.setSpeed(interpolated);
        await Future<void>.delayed(kCrossfadeTick);
        rampElapsedMs += kCrossfadeTick.inMilliseconds;
      }
      await playerB.setSpeed(1.0);
      AppLogger.log('normalization ramp complete; speed snapped to 1.0x',
          name: _logTag);
    } catch (e, st) {
      AppLogger.log('crossfade pipeline error: $e\n$st', name: _logTag);
      // Clean up playerB before disposal to prevent codec
      // event-loop leaks on the error path.
      await playerB.stop();
      await playerB.setAudioSource(
        ConcatenatingAudioSource(children: []),
      );
      await playerB.dispose();
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // DSP math (pure, testable)
  // -------------------------------------------------------------------------

  /// Spec §4.1: "rawTempoRatio = currentTrackBpm / incomingTrackBpm",
  /// clamped to [kRateMin, kRateMax]. Returns 1.0 when either BPM
  /// is unknown — the engine still runs the equal-power
  /// crossfade, just without tempo matching.
  static double _computeClampedRateRatio({
    required double? bpmA,
    required double? bpmB,
  }) {
    if (bpmA == null || bpmB == null || bpmA <= 0 || bpmB <= 0) {
      return 1.0;
    }
    final raw = bpmA / bpmB;
    return raw.clamp(kRateMin, kRateMax);
  }

  /// Spec §4.2:
  ///   Gain_A(t) = cos(t * π/2)   (fading out)
  ///   Gain_B(t) = sin(t * π/2)   (fading in)
  ///
  /// At t=0: A=cos(0)=1, B=sin(0)=0 (full A, silent B).
  /// At t=1: A=cos(π/2)=0, B=sin(π/2)=1 (silent A, full B).
  /// At t=0.5: A=B=1/√2 ≈ 0.7071 (the equal-power midpoint —
  /// the key property the spec calls out: A² + B² = 1 at every
  /// t, so the perceived acoustic energy is preserved).
  static double _equalPowerFadeOut(double t) {
    return math.cos(t * math.pi / 2.0);
  }

  static double _equalPowerFadeIn(double t) {
    return math.sin(t * math.pi / 2.0);
  }

  /// Spec §4.3: bar-quantized delay.
  ///   barDurationMs = (60000.0 / currentBpm) * 4
  ///   timeUntilNextBar = barDurationMs - (currentPos % barDurationMs)
  ///
  /// When the outgoing track's BPM is unknown the engine
  /// returns 0 (start the crossfade immediately). When the
  /// current position is already on a bar boundary the
  /// remainder is 0 → next bar is "now".
  static int _computeBarDelayMs({
    required double? currentBpm,
    required int currentPositionMs,
  }) {
    if (currentBpm == null || currentBpm <= 0) return 0;
    final barMs = (60000.0 / currentBpm) * 4.0;
    if (barMs <= 0) return 0;
    final positionInBar = currentPositionMs % barMs.toInt();
    final delta = barMs.toInt() - positionInBar;
    return delta < 0 ? 0 : delta;
  }
}

// ---------------------------------------------------------------------------
// (No extension needed — GaplessQueueMixer exposes `queuedTracks` and
// `buildSourceFor` directly for the DSP engine to consume.)
// ---------------------------------------------------------------------------
