import 'package:flutter/foundation.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/repositories/playlist_repository.dart';

class PlaylistProvider extends ChangeNotifier {
  final PlaylistRepository _repository;

  PlaylistProvider(this._repository);

  List<Playlist> _playlists = [];
  Playlist? _currentPlaylist;
  bool _isLoading = false;
  String? _error;

  List<Playlist> get playlists => _playlists;
  Playlist? get currentPlaylist => _currentPlaylist;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchPlaylist(String playlistId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final cleanId = _extractPlaylistId(playlistId);
      _currentPlaylist = await _repository.getPlaylist(cleanId);
      await loadSavedPlaylists();
    } catch (e) {
      _error = 'Failed to load playlist: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadSavedPlaylists() async {
    _isLoading = true;
    notifyListeners();
    try {
      _playlists = await _repository.getSavedPlaylists();
    } catch (e) {
      _error = 'Failed to load saved playlists';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadCachedPlaylist(String playlistId) async {
    try {
      final cached = await _repository.getCachedPlaylist(playlistId);
      if (cached != null) {
        _currentPlaylist = cached;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _repository.deletePlaylist(playlistId);
    _playlists.removeWhere((p) => p.id == playlistId);
    if (_currentPlaylist?.id == playlistId) {
      _currentPlaylist = null;
    }
    notifyListeners();
  }

  String _extractPlaylistId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return trimmed;
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.queryParameters.containsKey('list')) {
      final id = uri.queryParameters['list'];
      if (id != null && id.isNotEmpty) return id;
    }
    return trimmed;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
