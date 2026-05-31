import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:ytmusix/presentation/providers/player_provider.dart';
import 'package:ytmusix/presentation/widgets/player_bar.dart';
import 'package:ytmusix/domain/entities/video.dart';
import 'package:ytmusix/domain/repositories/audio_repository.dart';

class MockAudioRepo implements AudioRepository {
  @override Future<String> getAudioUrl(Track track) async => '';
  @override Future<void> playTrack(Track track, String audioUrl) async {}
  @override Future<void> play(String url) async {}
  @override Future<void> pause() async {}
  @override Future<void> resume() async {}
  @override Future<void> stop() async {}
  @override Future<void> seek(Duration position) async {}
  @override Future<Duration> getPosition() async => Duration.zero;
  @override Future<Duration> getDuration() async => Duration.zero;
  @override Future<bool> isPlaying() async => false;

  @override
  Stream<ProcessingState> get processingStateStream => const Stream.empty();

  @override
  bool get currentTrackCompleted => false;

  @override
  Stream<void> get onSkipNextRequested => const Stream.empty();

  @override
  Stream<void> get onSkipPreviousRequested => const Stream.empty();

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Stream<Duration> get durationStream => const Stream.empty();
}

void main() {
  testWidgets('PlayerBar is hidden when no track is playing', (tester) async {
    final repo = MockAudioRepo();
    final provider = PlayerProvider(repo);

    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider<PlayerProvider>.value(
        value: provider,
        child: const Scaffold(body: PlayerBar()),
      ),
    ));

    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
