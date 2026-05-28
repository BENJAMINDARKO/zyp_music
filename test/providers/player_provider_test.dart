import 'package:flutter_test/flutter_test.dart';
import 'package:ytmusix/domain/entities/video.dart';
import 'package:ytmusix/domain/repositories/audio_repository.dart';
import 'package:ytmusix/presentation/providers/player_provider.dart';

class MockAudioRepository implements AudioRepository {
  bool _playing = false;
  Duration _position = Duration.zero;

  @override
  Future<String> getAudioUrl(Track track) async => 'https://example.com/audio.mp4';

  @override
  Future<void> playTrack(Track track, String audioUrl) async {
    _playing = true;
  }

  @override
  Future<void> play(String url) async {
    _playing = true;
  }

  @override
  Future<void> pause() async => _playing = false;

  @override
  Future<void> resume() async => _playing = true;

  @override
  Future<void> stop() async {
    _playing = false;
    _position = Duration.zero;
  }

  @override
  Future<void> seek(Duration position) async => _position = position;

  @override
  Future<Duration> getPosition() async => _position;

  @override
  Future<Duration> getDuration() async => const Duration(seconds: 200);

  @override
  Future<bool> isPlaying() async => _playing;
}

void main() {
  group('PlayerProvider', () {
    late MockAudioRepository repository;
    late PlayerProvider provider;

    setUp(() {
      repository = MockAudioRepository();
      provider = PlayerProvider(repository);
    });

    test('initial state is idle', () {
      expect(provider.currentTrack, isNull);
      expect(provider.queue, isEmpty);
      expect(provider.isPlaying, false);
      expect(provider.isLoading, false);
      expect(provider.error, isNull);
    });

    test('setQueue sets the track list', () {
      final tracks = [
        Track(id: 'v1', title: 'Track 1'),
        Track(id: 'v2', title: 'Track 2'),
      ];

      provider.setQueue(tracks);

      expect(provider.queue.length, 2);
      expect(provider.currentIndex, 0);
    });

    test('setQueue respects startIndex', () {
      final tracks = [
        Track(id: 'v1', title: 'Track 1'),
        Track(id: 'v2', title: 'Track 2'),
      ];

      provider.setQueue(tracks, startIndex: 1);

      expect(provider.currentIndex, 1);
    });

    test('playTrack updates currentTrack and isPlaying', () async {
      final track = Track(id: 'v1', title: 'Track 1');

      await provider.playTrack(track);

      expect(provider.currentTrack?.id, 'v1');
      expect(provider.isPlaying, true);
      expect(provider.isLoading, false);
      expect(provider.error, isNull);
    });

    test('stop resets player state', () async {
      final track = Track(id: 'v1', title: 'Track 1');
      await provider.playTrack(track);
      expect(provider.isPlaying, true);

      await provider.stop();

      expect(provider.isPlaying, false);
      expect(provider.position, Duration.zero);
    });

    test('togglePlayPause toggles playing state', () async {
      final track = Track(id: 'v1', title: 'Track 1');
      await provider.playTrack(track);
      expect(provider.isPlaying, true);

      await provider.togglePlayPause();
      expect(provider.isPlaying, false);

      await provider.togglePlayPause();
      expect(provider.isPlaying, true);
    });

    test('next does nothing if at end of queue', () async {
      final track = Track(id: 'v1', title: 'Track 1');
      provider.setQueue([track]);
      await provider.playTrack(track);

      await provider.next();
      expect(provider.currentTrack?.id, 'v1');
    });

    test('previous does nothing if at start of queue', () async {
      final track = Track(id: 'v1', title: 'Track 1');
      provider.setQueue([track]);
      await provider.playTrack(track);

      await provider.previous();
      expect(provider.currentTrack?.id, 'v1');
    });

    test('clearError resets error', () {
      provider.clearError();
      expect(provider.error, isNull);
    });
  });
}
