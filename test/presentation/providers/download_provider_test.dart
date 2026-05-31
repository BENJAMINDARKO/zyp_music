import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ytmusix/domain/entities/playlist.dart';
import 'package:ytmusix/domain/entities/video.dart';
import 'package:ytmusix/presentation/providers/download_provider.dart';
import 'package:ytmusix/service/download_service.dart';

class MockDownloadService extends DownloadService {
  MockDownloadService() : super.test();

  final _progressController = StreamController<DownloadProgress>.broadcast(sync: true);
  final _completedController = StreamController<String>.broadcast(sync: true);
  final _downloadedIds = <String>{};
  bool _cancelled = false;

  @override
  Stream<DownloadProgress> get progressStream => _progressController.stream;

  @override
  Stream<String> get completedStream => _completedController.stream;

  @override
  Future<Set<String>> getAllDownloadedIds() async => Set.from(_downloadedIds);

  @override
  Future<Set<String>> getFullyDownloadedPlaylistIds() async => {};

  @override
  Future<void> downloadPlaylist(Playlist playlist) async {
    for (final track in playlist.tracks) {
      if (_cancelled) break;
      _downloadedIds.add(track.id);
      _completedController.add(track.id);
    }
  }

  @override
  void cancelDownload() {
    _cancelled = true;
  }

  @override
  void dispose() {
    _progressController.close();
    _completedController.close();
  }
}

void main() {
  group('DownloadProvider', () {
    late MockDownloadService service;
    late DownloadProvider provider;

    setUp(() {
      service = MockDownloadService();
      provider = DownloadProvider(service);
    });

    test('initial state is empty', () async {
      await provider.init();
      expect(provider.downloadedTrackIds, isEmpty);
      expect(provider.downloadedPlaylists, isEmpty);
      expect(provider.activeDownloads, isEmpty);
      expect(provider.downloadingPlaylists, isEmpty);
    });

    test('downloadPlaylist marks playlist as downloading', () async {
      final playlist = Playlist(
        id: 'PL1',
        title: 'Test',
        tracks: [Track(id: 'v1', title: 'T1')],
      );

      final future = provider.downloadPlaylist(playlist);
      expect(provider.isDownloadingPlaylist('PL1'), true);
      await future;
      expect(provider.isDownloadingPlaylist('PL1'), false);
    });

    test('downloadPlaylist tracks downloaded tracks', () async {
      final playlist = Playlist(
        id: 'PL1',
        title: 'Test',
        tracks: [
          Track(id: 'v1', title: 'T1'),
          Track(id: 'v2', title: 'T2'),
        ],
      );

      await provider.downloadPlaylist(playlist);

      expect(provider.downloadedTrackIds, contains('v1'));
      expect(provider.downloadedTrackIds, contains('v2'));
      expect(provider.isPlaylistFullyDownloaded('PL1'), true);
    });

    test('cancelDownload clears state', () async {
      final playlist = Playlist(
        id: 'PL1',
        title: 'Test',
        tracks: [Track(id: 'v1', title: 'T1')],
      );

      provider.downloadPlaylist(playlist);
      provider.cancelDownload();

      expect(provider.isDownloadingPlaylist('PL1'), false);
      expect(provider.activeDownloads, isEmpty);
    });

    test('init loads downloaded track IDs', () async {
      final playlist = Playlist(
        id: 'PL1',
        title: 'Test',
        tracks: [Track(id: 'v1', title: 'T1')],
      );
      await provider.downloadPlaylist(playlist);

      final provider2 = DownloadProvider(service);
      await provider2.init();

      expect(provider2.downloadedTrackIds, contains('v1'));
    });

    test('dispose clears all state', () async {
      final playlist = Playlist(
        id: 'PL1',
        title: 'Test',
        tracks: [Track(id: 'v1', title: 'T1')],
      );
      await provider.downloadPlaylist(playlist);
      provider.dispose();

      expect(provider.downloadingPlaylists, isEmpty);
      expect(provider.activeDownloads, isEmpty);
      expect(provider.playlistDownloadProgress, isEmpty);
    });
  });
}
