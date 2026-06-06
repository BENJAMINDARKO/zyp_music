// Phase 3 — Gapless Queue Mixer.
// Validation gate coverage: the spec's 15-second-lookahead
// trigger surface fires once per (track, session) pair, the
// queueNextTrack API deduplicates, and the crossfade trigger
// surface honours the silence-scan threshold with the spec's
// duration-5s fallback.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'package:zyp_music/core/audio/gapless_queue_mixer.dart';
import 'package:zyp_music/domain/entities/video.dart';

void main() {
  // just_audio's AudioPlayer constructor talks to audio_session
  // (a method-channel client) during construction. In the unit
  // test VM that requires the test binding to be up so the
  // platform channel has a real messenger behind it.
  TestWidgetsFlutterBinding.ensureInitialized();

  // We pass a real AudioPlayer to the mixer but never call
  // attach() (which would try to talk to the platform). The
  // tests exercise the mixer's pure logic — the 15s trigger,
  // the crossfade trigger, the queueNext dedupe — without
  // touching the platform audio path.
  late AudioPlayer player;
  late _CapturingRouter router;
  late _CapturingSilence silence;
  late GaplessQueueMixer mixer;

  setUp(() {
    player = AudioPlayer();
    router = _CapturingRouter();
    silence = _CapturingSilence();
    mixer = GaplessQueueMixer(
      player: player,
      sourceBuilder: (t) async => _FakeAudioSource(t.id),
      nextTrackResolver: router.resolve,
      silenceResolver: silence.getMs,
      durationStream: (_) => const Stream<Duration?>.empty(),
    );
  });

  tearDown(() async {
    await mixer.dispose();
  });

  group('GaplessQueueMixer.15s lookahead', () {
    test('does not fire when remaining > 15s', () async {
      await mixer.maybeQueueNextAt(
        current: const Track(id: 'a', title: 'A'),
        position: const Duration(seconds: 10),
        duration: const Duration(seconds: 30),
      );
      expect(router.calls, 0);
    });

    test('fires exactly once when remaining ≤ 15s', () async {
      router.next = const Track(id: 'b', title: 'B');
      await mixer.maybeQueueNextAt(
        current: const Track(id: 'a', title: 'A'),
        position: const Duration(seconds: 16),
        duration: const Duration(seconds: 30),
      );
      expect(router.calls, 1);
      // Second call with the same track must not re-fire.
      await mixer.maybeQueueNextAt(
        current: const Track(id: 'a', title: 'A'),
        position: const Duration(seconds: 18),
        duration: const Duration(seconds: 30),
      );
      expect(router.calls, 1);
    });

    test('resets the dedupe flag when a new track starts (playTrack)',
        () async {
      // Seed the timeline with track A and trigger lookahead.
      await mixer.playTrack(const Track(id: 'a', title: 'A'));
      router.next = const Track(id: 'b', title: 'B');
      await mixer.maybeQueueNextAt(
        current: const Track(id: 'a', title: 'A'),
        position: const Duration(seconds: 16),
        duration: const Duration(seconds: 30),
      );
      expect(router.calls, 1);
      // Now play a new track. The dedupe flag should reset.
      await mixer.playTrack(const Track(id: 'c', title: 'C'));
      router.next = const Track(id: 'd', title: 'D');
      await mixer.maybeQueueNextAt(
        current: const Track(id: 'c', title: 'C'),
        position: const Duration(seconds: 16),
        duration: const Duration(seconds: 30),
      );
      expect(router.calls, 2);
    });

    test('does not throw when duration is null', () async {
      await mixer.maybeQueueNextAt(
        current: const Track(id: 'a', title: 'A'),
        position: const Duration(seconds: 20),
        duration: null,
      );
      expect(router.calls, 0);
    });

    test('does not throw when current is null', () async {
      await mixer.maybeQueueNextAt(
        current: null,
        position: const Duration(seconds: 20),
        duration: const Duration(seconds: 30),
      );
      expect(router.calls, 0);
    });

    test('does not fire when the router returns null', () async {
      router.next = null;
      await mixer.maybeQueueNextAt(
        current: const Track(id: 'a', title: 'A'),
        position: const Duration(seconds: 16),
        duration: const Duration(seconds: 30),
      );
      // The resolver was invoked (which is the contract — the
      // mixer is allowed to ask once per track), but the
      // timeline must not have grown.
      expect(router.calls, 1);
      expect(mixer.concatenation.length, 0);
    });
  });

  group('GaplessQueueMixer.queueNextTrack', () {
    test('appends a new source to the concatenation', () async {
      await mixer.playTrack(const Track(id: 'a', title: 'A'));
      expect(mixer.concatenation.length, 1);
      await mixer.queueNextTrack(const Track(id: 'b', title: 'B'));
      expect(mixer.concatenation.length, 2);
    });

    test('deduplicates: queueing the same track twice is a no-op',
        () async {
      await mixer.playTrack(const Track(id: 'a', title: 'A'));
      await mixer.queueNextTrack(const Track(id: 'b', title: 'B'));
      await mixer.queueNextTrack(const Track(id: 'b', title: 'B'));
      expect(mixer.concatenation.length, 2);
    });
  });

  group('GaplessQueueMixer.crossfade trigger', () {
    test('uses the silence boundary when available', () async {
      silence.ms = 25000; // 25s boundary
      final fired = <CrossfadeReadyEvent>[];
      final sub = mixer.crossfadeReadyStream.listen(fired.add);
      await mixer.maybeFireCrossfadeAt(
        currentTrackId: 'a',
        position: const Duration(milliseconds: 24000),
        duration: const Duration(seconds: 30),
      );
      await _flush();
      // Below threshold → no event yet.
      expect(fired, isEmpty);
      await mixer.maybeFireCrossfadeAt(
        currentTrackId: 'a',
        position: const Duration(milliseconds: 26000),
        duration: const Duration(seconds: 30),
      );
      await _flush();
      expect(fired, hasLength(1));
      expect(fired.first.thresholdMs, 25000);
      expect(fired.first.source, CrossfadeSource.silenceScan);
      await sub.cancel();
    });

    test('falls back to duration - 5s when no silence scan is available',
        () async {
      silence.ms = null; // no scan yet
      final fired = <CrossfadeReadyEvent>[];
      final sub = mixer.crossfadeReadyStream.listen(fired.add);
      // Duration = 30s, fallback threshold = 30_000 - 5_000 = 25_000.
      await mixer.maybeFireCrossfadeAt(
        currentTrackId: 'a',
        position: const Duration(milliseconds: 24999),
        duration: const Duration(seconds: 30),
      );
      await _flush();
      expect(fired, isEmpty);
      await mixer.maybeFireCrossfadeAt(
        currentTrackId: 'a',
        position: const Duration(milliseconds: 25000),
        duration: const Duration(seconds: 30),
      );
      await _flush();
      expect(fired, hasLength(1));
      expect(fired.first.thresholdMs, 25000);
      expect(fired.first.source, CrossfadeSource.durationFallback);
      await sub.cancel();
    });

    test('fires exactly once per (track, session) pair', () async {
      silence.ms = 25000;
      final fired = <CrossfadeReadyEvent>[];
      final sub = mixer.crossfadeReadyStream.listen(fired.add);
      // Cross the threshold several times.
      for (var pos = 24000; pos <= 28000; pos += 1000) {
        await mixer.maybeFireCrossfadeAt(
          currentTrackId: 'a',
          position: Duration(milliseconds: pos),
          duration: const Duration(seconds: 30),
        );
      }
      await _flush();
      expect(fired, hasLength(1));
      await sub.cancel();
    });
  });

  group('GaplessQueueMixer.currentTrack/queuedTracks indexing and callbacks', () {
    test('currentTrack and queuedTracks return the correct tracks based on playTrack and queueNextTrack', () async {
      final queued = <Track>[];
      mixer.onTrackQueued = queued.add;

      await mixer.playTrack(const Track(id: 'a', title: 'A'));
      await mixer.queueNextTrack(const Track(id: 'b', title: 'B'));
      await mixer.queueNextTrack(const Track(id: 'c', title: 'C'));

      expect(mixer.currentTrack?.id, 'a');
      expect(mixer.queuedTracks.map((t) => t.id), ['a', 'b', 'c']);
      expect(queued.map((t) => t.id), ['b', 'c']);
    });

    test('adoptPlayer clears history, sets new player, and configures timeline', () async {
      final playerB = AudioPlayer();
      await mixer.adoptPlayer(playerB, const Track(id: 'incoming', title: 'Incoming'));

      expect(mixer.currentTrack?.id, 'incoming');
      expect(mixer.queuedTracks.map((t) => t.id), ['incoming']);
      expect(mixer.player, playerB);
    });
  });
}

/// Drains the microtask queue so any events a [StreamController]
/// has queued are delivered to their listeners. The
/// [GaplessQueueMixer] emits via a broadcast controller whose
/// listeners run on the microtask queue; without this flush the
/// test's `expect(... fired, hasLength(1))` runs before the
/// listener has fired.
Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
}

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class _FakeAudioSource extends StreamAudioSource {
  final String tag;
  _FakeAudioSource(this.tag);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    return StreamAudioResponse(
      sourceLength: 1024,
      contentLength: 1024,
      offset: 0,
      stream: const Stream<List<int>>.empty(),
      contentType: 'audio/mp4',
    );
  }
}

class _CapturingRouter {
  Track? next;
  int calls = 0;
  Future<Track?> resolve(Track current) async {
    calls++;
    return next;
  }
}

class _CapturingSilence {
  int? ms;
  Future<int?> getMs(String trackId) async => ms;
}
