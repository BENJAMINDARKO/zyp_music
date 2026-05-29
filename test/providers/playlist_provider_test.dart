import 'package:flutter_test/flutter_test.dart';
import 'package:ytmusix/domain/entities/playlist.dart';
import 'package:ytmusix/domain/entities/video.dart';
import 'package:ytmusix/domain/repositories/playlist_repository.dart';
import 'package:ytmusix/presentation/providers/playlist_provider.dart';

class MockPlaylistRepository implements PlaylistRepository {
  final Map<String, Playlist> _store = {};
  final List<Playlist> _playlists = [];

  @override
  Future<Playlist> getPlaylist(String playlistId) async {
    return _store[playlistId]!;
  }

  @override
  Future<List<Playlist>> getSavedPlaylists() async {
    return List.from(_playlists);
  }

  @override
  Future<void> savePlaylist(Playlist playlist) async {
    _store[playlist.id] = playlist;
    _playlists.add(playlist);
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    _store.remove(playlistId);
    _playlists.removeWhere((p) => p.id == playlistId);
  }

  @override
  Future<void> saveTrack(String playlistId, Track track) async {}

  @override
  Future<List<Track>> getCachedTracks(String playlistId) async {
    return _store[playlistId]?.tracks ?? [];
  }

  @override
  Future<Playlist?> getCachedPlaylist(String playlistId) async {
    final p = _store[playlistId];
    if (p == null) return null;
    return p;
  }

  @override
  Future<Playlist> getFromUrl(String input) async {
    final trimmed = input.trim();
    final playlist = _store.values.firstWhere(
      (p) => p.id == trimmed || p.title == trimmed,
      orElse: () => Playlist(id: trimmed, title: trimmed),
    );
    return playlist;
  }
}

void main() {
  group('PlaylistProvider', () {
    late MockPlaylistRepository repository;
    late PlaylistProvider provider;

    setUp(() {
      repository = MockPlaylistRepository();
      provider = PlaylistProvider(repository);
    });

    test('initial state is empty', () {
      expect(provider.playlists, isEmpty);
      expect(provider.currentPlaylist, isNull);
      expect(provider.isLoading, false);
      expect(provider.error, isNull);
    });

    test('deletePlaylist removes playlist from state', () async {
      final playlist = Playlist(id: 'P1', title: 'Test');
      await repository.savePlaylist(playlist);
      await provider.loadSavedPlaylists();

      expect(provider.playlists.length, 1);

      await provider.deletePlaylist('P1');

      expect(provider.playlists, isEmpty);
    });

    test('loadSavedPlaylists populates playlists', () async {
      await repository.savePlaylist(Playlist(id: 'P1', title: 'A'));
      await repository.savePlaylist(Playlist(id: 'P2', title: 'B'));

      await provider.loadSavedPlaylists();

      expect(provider.playlists.length, 2);
    });

    test('clearError resets error state', () {
      provider.clearError();
      expect(provider.error, isNull);
    });
  });
}
