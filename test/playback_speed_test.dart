import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:zyp_music/presentation/providers/player_provider.dart';
import 'package:zyp_music/presentation/providers/settings_provider.dart';
import 'package:zyp_music/core/services/hybrid_cache_service.dart';
import 'package:zyp_music/domain/repositories/audio_repository.dart';
import 'package:zyp_music/domain/entities/video.dart';
import 'package:zyp_music/ui/widgets/playback_speed_selector.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive/hive.dart';
import 'dart:async';

class _MockAudioRepository implements AudioRepository {
  final _skipNextCtrl = StreamController<void>.broadcast();
  final _skipPrevCtrl = StreamController<void>.broadcast();
  @override Stream<void> get onSkipNextRequested => _skipNextCtrl.stream;
  @override Stream<void> get onSkipPreviousRequested => _skipPrevCtrl.stream;
  double lastSetSpeed = 1.0;

  @override Future<({String url, bool fromCache})> getAudioUrl(Track track, {String quality = 'adaptive'}) async => (url: '', fromCache: false);
  @override Future<void> playTrack(Track track, String audioUrl, {bool fromCache = true}) async {}
  @override Future<void> play(String url) async {}
  @override Future<void> pause() async {}
  @override Future<void> resume() async {}
  @override Future<void> stop() async {}
  @override Future<void> seek(Duration position) async {}
  @override Future<void> setPlaybackSpeed(double speed) async {
    lastSetSpeed = speed;
  }
  @override Future<Duration> getPosition() async => Duration.zero;
  @override Future<Duration> getDuration() async => Duration.zero;
  @override Future<bool> isPlaying() async => false;
  @override Stream<bool> get playingStream => const Stream.empty();
  @override Stream<ProcessingState> get processingStateStream => const Stream.empty();
  @override Stream<Duration> get positionStream => const Stream.empty();
  @override Stream<Duration> get bufferedPositionStream => const Stream.empty();
  @override Stream<Duration> get durationStream => const Stream.empty();
  @override bool get currentTrackCompleted => false;
  @override Future<String?> getLyrics(Track track) async => null;
  @override Future<String?> getLyricsOffline(Track track) async => null;
  @override Future<String?> refreshLyrics(Track track) async => null;
  @override Future<List<Track>> getUpNexts(Track track) async => [];
  @override Future<void> preloadTrack(Track track) async {}
  @override Future<void> preloadTrackLyrics(Track track) async {}
  @override Future<AudioSource> buildAudioSource(Track track) => throw UnimplementedError();

  void dispose() {
    _skipNextCtrl.close();
    _skipPrevCtrl.close();
  }
}

void main() {
  setUp(() {
    Hive.init('/tmp/zyp_test_hive');
    SharedPreferences.setMockInitialValues({});
    FlutterError.onError = (details) {
      if (details.exception.toString().contains('RenderFlex') ||
          details.exception.toString().contains('overflow')) return;
      FlutterError.presentError(details);
    };
  });

  tearDown(() {
    FlutterError.onError = FlutterError.presentError;
  });

  group('PlayerProvider playback speed', () {
    test('starts at 1.0', () {
      final repo = _MockAudioRepository();
      final provider = PlayerProvider(repo, SettingsProvider(), HybridCacheService());
      expect(provider.playbackSpeed, 1.0);
    });

    test('cycles 1.0 -> 1.5 -> 2.0 -> 0.5', () async {
      final repo = _MockAudioRepository();
      final provider = PlayerProvider(repo, SettingsProvider(), HybridCacheService());

      await provider.setPlaybackSpeed(1.5);
      expect(provider.playbackSpeed, 1.5);
      expect(repo.lastSetSpeed, 1.5);

      await provider.setPlaybackSpeed(2.0);
      expect(provider.playbackSpeed, 2.0);
      expect(repo.lastSetSpeed, 2.0);

      await provider.setPlaybackSpeed(0.5);
      expect(provider.playbackSpeed, 0.5);
      expect(repo.lastSetSpeed, 0.5);
    });

    test('resets to 1.0 and propagates to repo on track change', () async {
      final repo = _MockAudioRepository();
      final provider = PlayerProvider(repo, SettingsProvider(), HybridCacheService());

      // Set a custom speed
      await provider.setPlaybackSpeed(2.0);
      expect(provider.playbackSpeed, 2.0);
      expect(repo.lastSetSpeed, 2.0);

      // Simulate a track change (calls the reset listener)
      // The reset is triggered via _trackChangedListeners which fires
      // when playTrack or the media item sync sets a new track.
      // We can trigger it by setting a queue and playing.
      final track = Track(id: 't1', title: 'Test', author: 'Artist');
      provider.setQueue([track], startIndex: 0);
      await provider.playFromQueue(0);
      await pumpEventQueue();

      // Speed should have reset to 1.0
      expect(provider.playbackSpeed, 1.0);
      expect(repo.lastSetSpeed, 1.0);
    });
  });

  group('PlaybackSpeedSelector widget', () {
    testWidgets('tapping plus and minus increments and decrements by 0.01', (tester) async {
      final repo = _MockAudioRepository();
      final provider = PlayerProvider(repo, SettingsProvider(), HybridCacheService());

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: provider),
              ChangeNotifierProvider.value(value: SettingsProvider()),
            ],
            child: const Scaffold(
              body: Center(child: PlaybackSpeedSelector()),
            ),
          ),
        ),
      );

      // Initially 1.00x
      expect(find.text('1.00x'), findsOneWidget);

      // Tap the plus button to increment to 1.01x
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('1.01x'), findsOneWidget);

      // Tap the minus button to decrement back to 1.00x
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();
      expect(find.text('1.00x'), findsOneWidget);

      // Tap plus button twice (1.02x) then double tap the text to reset to 1.00x
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('1.02x'), findsOneWidget);

      // Double tap to reset
      await tester.tap(find.text('1.02x'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('1.02x'));
      await tester.pumpAndSettle();
      expect(find.text('1.00x'), findsOneWidget);
    });
  });
}
