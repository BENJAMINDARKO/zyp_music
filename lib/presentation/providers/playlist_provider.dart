import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:zyp_music/core/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants/playlist_sort_mode.dart';
import '../../core/services/auto_dj_routing_service.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/video.dart';
import '../../domain/entities/album.dart';
import '../../domain/entities/artist.dart';
import '../../domain/repositories/playlist_repository.dart';
import 'download_provider.dart';

class PlaylistProvider extends ChangeNotifier {
  final PlaylistRepository _repository;

  /// Spec 2G Fix #6: late-bound routing service reference
  /// for refreshing the Smart-DJ Liked-Songs cache after
  /// a user favorites or unfavorites a track. Set via
  /// [setRoutingService] from `app.dart`. Idempotent.
  AutoDjRoutingService? _routingService;

  /// Spec 2G Fix #6: debounce timer for the liked-cache
  /// refresh. 500ms after the last favorite action
  /// collapses a bulk-favorite operation (e.g., favoriting
  /// an entire album) into a single refresh.
  Timer? _likedCacheRefreshTimer;
  static const Duration _likedCacheRefreshDebounce =
      Duration(milliseconds: 500);

  PlaylistProvider(this._repository) {
    loadSavedPlaylists();
    loadFavorites();
  }

  /// Spec 2G Fix #6: late-binding setter for the routing
  /// service. Called from `app.dart` so the debounced
  /// refresh triggered by favorite actions can reach the
  /// engine's [AutoDjRoutingService.refreshLikedSongsCache].
  void setRoutingService(AutoDjRoutingService routingService) {
    _routingService = routingService;
  }

  /// Spec 2G Fix #6: schedules a debounced refresh of the
  /// Smart-DJ Liked-Songs cache. Called at the end of every
  /// favorite / unfavorite / bulk-favorite method. The 500ms
  /// debounce collapses a bulk-favorite operation into a
  /// single refresh — favoriting an album with 12 tracks
  /// fires [_refreshLikedSongsCache] once at the end, not
  /// 12 times during the loop.
  void _scheduleLikedCacheRefresh() {
    _likedCacheRefreshTimer?.cancel();
    _likedCacheRefreshTimer =
        Timer(_likedCacheRefreshDebounce, () {
      _refreshLikedSongsCache();
    });
  }

  /// Spec 2G Fix #6: re-reads the favorites table, recomputes
  /// the Top 5 Liked Artists and Genres, and pushes the new
  /// values into [AutoDjRoutingService.refreshLikedSongsCache].
  /// Failures are logged and swallowed — a stale cache is
  /// preferable to a hot-path crash on a favorite action.
  Future<void> _refreshLikedSongsCache() async {
    final routingService = _routingService;
    if (routingService == null) return;
    try {
      final favs = await _repository.getFavoriteTracks();
      final computed =
          AutoDjRoutingService.computeTopLikedArtistsAndGenres(favs);
      routingService.refreshLikedSongsCache(
        topLikedArtists: computed.artists,
        topLikedGenres: computed.genres,
      );
    } catch (e) {
      AppLogger.log(
        '[FavoritesRefresh] Failed to refresh liked cache: $e',
        name: 'PlaylistProvider',
      );
    }
  }

  List<Playlist> _playlists = [];
  Playlist? _currentPlaylist;
  bool _isLoading = false;
  String? _error;
  PlaylistSortMode _sortMode = PlaylistSortMode.dateAdded;
  Set<String> _favoriteIds = {};
  List<Track> _favoriteTracks = [];
  Set<String> _favoriteAlbumIds = {};
  List<Album> _favoriteAlbums = [];
  Set<String> _favoriteArtistIds = {};
  List<Artist> _favoriteArtists = [];
  String? _lastAddedPlaylistId;

  PlaylistSortMode get sortMode => _sortMode;
  List<Track> get favoriteTracks => _favoriteTracks;
  List<Album> get favoriteAlbums => _favoriteAlbums;
  List<Artist> get favoriteArtists => _favoriteArtists;
  String? get lastAddedPlaylistId => _lastAddedPlaylistId;

  List<Playlist> get playlists {
    final sorted = List<Playlist>.from(_playlists);
    switch (_sortMode) {
      case PlaylistSortMode.title:
        sorted.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case PlaylistSortMode.trackCount:
        sorted.sort((a, b) => b.videoCount.compareTo(a.videoCount));
        break;
      case PlaylistSortMode.dateAdded:
        break;
    }
    return sorted;
  }

  void setSortMode(PlaylistSortMode mode) {
    _sortMode = mode;
    notifyListeners();
  }

  Playlist? get currentPlaylist => _currentPlaylist;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<Playlist?> fetchPlaylist(String input) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final cleanId = _extractPlaylistId(input);
      if (cleanId.isEmpty) {
        _error = 'Could not extract a playlist ID from that URL';
        return null;
      }
      _currentPlaylist = await _repository.getPlaylist(cleanId);
      await _reloadSilently();
      return _currentPlaylist;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Playlist?> fetchFromUrl(String input) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _currentPlaylist = await _repository.getFromUrl(input);
      await _reloadSilently();
      return _currentPlaylist;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _reloadSilently() async {
    try {
      _playlists = await _repository.getSavedPlaylists();
    } catch (e) {
      AppLogger.log('Failed to reload playlists silently: $e', name: 'PlaylistProvider');
    }
  }

  Future<void> loadSavedPlaylists() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _playlists = await _repository.getSavedPlaylists();
      try {
        final prefs = await SharedPreferences.getInstance();
        _lastAddedPlaylistId = prefs.getString('lastAddedPlaylistId');
      } catch (_) {}
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadPlaylistLocally(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _currentPlaylist = await _repository.getCachedPlaylist(id);
    } catch (e) {
      _error = e.toString();
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
    } catch (e) {
      AppLogger.log('Failed to load cached playlist $playlistId: $e',
          name: 'PlaylistProvider');
    }
  }

  Set<String> get favoriteIds => _favoriteIds;

  bool isFavorite(String trackId) => _favoriteIds.contains(trackId);

  Future<void> loadFavorites() async {
    try {
      _favoriteIds = await _repository.getFavoriteIds();
      _favoriteTracks = await _repository.getFavoriteTracks();

      _favoriteAlbums = await _repository.getFavoriteAlbums();
      _favoriteAlbumIds = _favoriteAlbums.map((e) => e.id).toSet();

      _favoriteArtists = await _repository.getFavoriteArtists();
      _favoriteArtistIds = _favoriteArtists.map((e) => e.id).toSet();

      notifyListeners();
    } catch (e) {
      AppLogger.log('Failed to load favorites: $e', name: 'PlaylistProvider');
    }
  }

  Future<void> toggleFavorite(Track track, {DownloadProvider? downloadProvider}) async {
    final wasFavorite = _favoriteIds.contains(track.id);
    if (wasFavorite) {
      _favoriteIds.remove(track.id);
      _favoriteTracks.removeWhere((t) => t.id == track.id);
      if (downloadProvider != null) {
        try {
          await downloadProvider.deleteDownloadedTrack(track.id);
        } catch (_) {}
      }
    } else {
      _favoriteIds.add(track.id);
      _favoriteTracks.insert(0, track);
      if (downloadProvider != null) {
        try {
          await downloadProvider.downloadTrack(track, 'favorite');
        } catch (_) {}
      }
    }
    notifyListeners();
    try {
      await _repository.toggleFavorite(track);
    } catch (e) {
      if (wasFavorite) {
        _favoriteIds.add(track.id);
        _favoriteTracks.insert(0, track);
        if (downloadProvider != null) {
          try {
            await downloadProvider.downloadTrack(track, 'favorite');
          } catch (_) {}
        }
      } else {
        _favoriteIds.remove(track.id);
        _favoriteTracks.removeWhere((t) => t.id == track.id);
        if (downloadProvider != null) {
          try {
            await downloadProvider.deleteDownloadedTrack(track.id);
          } catch (_) {}
        }
      }
      notifyListeners();
    }
    // Spec 2G Fix #6: debounced refresh of the Smart-DJ
    // Liked-Songs cache so a fresh favorite is reflected
    // in Smart DJ's affinity bias within ~500ms.
    _scheduleLikedCacheRefresh();
  }

  bool isAlbumFavorite(String albumId) => _favoriteAlbumIds.contains(albumId);

  Future<void> toggleFavoriteAlbum(Album album, {DownloadProvider? downloadProvider}) async {
    final wasFavorite = _favoriteAlbumIds.contains(album.id);
    if (wasFavorite) {
      _favoriteAlbumIds.remove(album.id);
      _favoriteAlbums.removeWhere((a) => a.id == album.id);
      if (downloadProvider != null) {
        try {
          for (final track in album.tracks) {
            await downloadProvider.deleteDownloadedTrack(track.id);
          }
        } catch (_) {}
      }
    } else {
      _favoriteAlbumIds.add(album.id);
      _favoriteAlbums.insert(0, album);
      if (downloadProvider != null) {
        try {
          await downloadProvider.downloadAlbum(album, this);
        } catch (_) {}
      }
    }
    notifyListeners();
    try {
      await _repository.toggleFavoriteAlbum(album);
    } catch (e) {
      if (wasFavorite) {
        _favoriteAlbumIds.add(album.id);
        _favoriteAlbums.insert(0, album);
        if (downloadProvider != null) {
          try {
            await downloadProvider.downloadAlbum(album, this);
          } catch (_) {}
        }
      } else {
        _favoriteAlbumIds.remove(album.id);
        _favoriteAlbums.removeWhere((a) => a.id == album.id);
        if (downloadProvider != null) {
          try {
            for (final track in album.tracks) {
              await downloadProvider.deleteDownloadedTrack(track.id);
            }
          } catch (_) {}
        }
      }
      notifyListeners();
    }
    // Spec 2G Fix #6: debounced refresh (see toggleFavorite
    // for the same call).
    _scheduleLikedCacheRefresh();
  }

  bool isArtistFavorite(String artistId) => _favoriteArtistIds.contains(artistId);

  Future<void> toggleFavoriteArtist(Artist artist) async {
    final wasFavorite = _favoriteArtistIds.contains(artist.id);
    if (wasFavorite) {
      _favoriteArtistIds.remove(artist.id);
      _favoriteArtists.removeWhere((a) => a.id == artist.id);
    } else {
      _favoriteArtistIds.add(artist.id);
      _favoriteArtists.insert(0, artist);
    }
    notifyListeners();
    try {
      await _repository.toggleFavoriteArtist(artist);
    } catch (e) {
      if (wasFavorite) {
        _favoriteArtistIds.add(artist.id);
        _favoriteArtists.insert(0, artist);
      } else {
        _favoriteArtistIds.remove(artist.id);
        _favoriteArtists.removeWhere((a) => a.id == artist.id);
      }
      notifyListeners();
    }
    // Spec 2G Fix #6: debounced refresh (see toggleFavorite).
    _scheduleLikedCacheRefresh();
  }

  Future<Playlist?> getFavoritesPlaylist() async {
    try {
      final tracks = await _repository.getFavoriteTracks();
      if (tracks.isEmpty) return null;
      return Playlist(
        id: '__favorites__',
        title: 'Favorites',
        thumbnailUrl: tracks.first.thumbnailUrl,
        videoCount: tracks.length,
        tracks: tracks,
      );
    } catch (e) {
      AppLogger.log('Failed to get favorites playlist: $e', name: 'PlaylistProvider');
      return null;
    }
  }

  Future<List<Track>> getEditorsPicks() async {
    try {
      return await _repository.getEditorsPicks();
    } catch (e) {
      AppLogger.log('Failed to get editors picks: $e', name: 'PlaylistProvider');
      return [];
    }
  }

  Future<List<Track>?> getCachedTracks(String playlistId) async {
    try {
      return _repository.getCachedTracks(playlistId);
    } catch (e) {
      AppLogger.log('Failed to get cached tracks for $playlistId: $e',
          name: 'PlaylistProvider');
      return null;
    }
  }

  Future<void> saveSingleTrack(Track track) async {
    final playlist = Playlist(
      id: track.id,
      title: track.title,
      author: track.author,
      thumbnailUrl: track.thumbnailUrl,
      videoCount: 1,
      tracks: [track],
    );
    await _repository.savePlaylist(playlist);
    await _reloadSilently();
    notifyListeners();
  }

  Future<Playlist> createPlaylist(String title) async {
    final id = 'local_\${DateTime.now().millisecondsSinceEpoch}';
    final playlist = Playlist(
      id: id,
      title: title,
      author: 'Local Playlist',
      videoCount: 0,
      tracks: [],
    );
    await _repository.savePlaylist(playlist);
    await _reloadSilently();
    notifyListeners();
    return playlist;
  }

  Future<void> renamePlaylist(String id, String newTitle) async {
    final index = _playlists.indexWhere((p) => p.id == id);
    if (index == -1) return;
    try {
      await _repository.updatePlaylistTitle(id, newTitle);
      _playlists[index] = Playlist(
        id: _playlists[index].id,
        title: newTitle,
        description: _playlists[index].description,
        thumbnailUrl: _playlists[index].thumbnailUrl,
        author: _playlists[index].author,
        videoCount: _playlists[index].videoCount,
        tracks: _playlists[index].tracks,
      );
      if (_currentPlaylist?.id == id) {
        _currentPlaylist = Playlist(
          id: _currentPlaylist!.id,
          title: newTitle,
          description: _currentPlaylist!.description,
          thumbnailUrl: _currentPlaylist!.thumbnailUrl,
          author: _currentPlaylist!.author,
          videoCount: _currentPlaylist!.videoCount,
          tracks: _currentPlaylist!.tracks,
        );
      }
      notifyListeners();
    } catch (e) {
      AppLogger.log('Failed to rename playlist $id: $e', name: 'PlaylistProvider');
    }
  }

  Future<void> addTrackToPlaylist(String playlistId, Track track) async {
    try {
      await _repository.saveTrack(playlistId, track);
      _lastAddedPlaylistId = playlistId;
      
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('lastAddedPlaylistId', playlistId);
      } catch (e) {
        AppLogger.log('Failed to save lastAddedPlaylistId: $e', name: 'PlaylistProvider');
      }
      
      // Update in-memory if it's the current playlist
      if (_currentPlaylist?.id == playlistId) {
        _currentPlaylist = Playlist(
          id: _currentPlaylist!.id,
          title: _currentPlaylist!.title,
          description: _currentPlaylist!.description,
          thumbnailUrl: _currentPlaylist!.thumbnailUrl,
          author: _currentPlaylist!.author,
          videoCount: _currentPlaylist!.videoCount + 1,
          tracks: [..._currentPlaylist!.tracks, track],
        );
      }
      
      // Update the playlist list
      final index = _playlists.indexWhere((p) => p.id == playlistId);
      if (index != -1) {
        _playlists[index] = Playlist(
          id: _playlists[index].id,
          title: _playlists[index].title,
          description: _playlists[index].description,
          thumbnailUrl: _playlists[index].thumbnailUrl ?? track.thumbnailUrl,
          author: _playlists[index].author,
          videoCount: _playlists[index].videoCount + 1,
          tracks: _playlists[index].tracks, // We don't cache all tracks here
        );
      }
      notifyListeners();
    } catch (e) {
      AppLogger.log('Failed to add track ${track.id} to $playlistId: $e',
          name: 'PlaylistProvider');
    }
  }

  Future<void> removeTrackFromPlaylist(
      String playlistId, String trackId) async {
    if (_currentPlaylist?.id == playlistId) {
      _currentPlaylist = Playlist(
        id: _currentPlaylist!.id,
        title: _currentPlaylist!.title,
        description: _currentPlaylist!.description,
        thumbnailUrl: _currentPlaylist!.thumbnailUrl,
        author: _currentPlaylist!.author,
        videoCount: _currentPlaylist!.videoCount - 1,
        tracks:
            _currentPlaylist!.tracks.where((t) => t.id != trackId).toList(),
      );
      notifyListeners();
    }
    try {
      await _repository.removeTrack(playlistId, trackId);
    } catch (e) {
      AppLogger.log('Failed to remove track $trackId from $playlistId: $e',
          name: 'PlaylistProvider');
    }
  }

  Future<void> reorderTracks(
      String playlistId, List<String> trackIdsInOrder) async {
    try {
      await _repository.reorderTracks(playlistId, trackIdsInOrder);
    } catch (e) {
      AppLogger.log('Failed to reorder tracks in $playlistId: $e',
          name: 'PlaylistProvider');
    }
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

  Future<String> exportPlaylists(String format) async {
    final playlists = await _repository.getSavedPlaylists();
    final data = <Map<String, dynamic>>[];
    for (final p in playlists) {
      final tracks = await _repository.getCachedTracks(p.id);
      data.add({
        'id': p.id,
        'title': p.title,
        'author': p.author,
        'thumbnailUrl': p.thumbnailUrl,
        'videoCount': p.videoCount,
        'tracks': tracks.map((t) => {
          'id': t.id,
          'title': t.title,
          'author': t.author,
          'durationSeconds': t.duration?.inSeconds,
          'thumbnailUrl': t.thumbnailUrl,
        }).toList(),
      });
    }
    final export = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'playlists': data,
    };

    String content;
    String ext;
    switch (format) {
      case 'xml':
        ext = 'xml';
        content = _toXml(export);
        break;
      case 'md':
        ext = 'md';
        content = _toMarkdown(playlists);
        break;
      default:
        ext = 'json';
        content = const JsonEncoder.withIndent('  ').convert(export);
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/ytmusix_export.$ext');
    await file.writeAsString(content);
    return file.path;
  }

  Future<int> importPlaylists(String filePath) async {
    final file = File(filePath);
    final content = await file.readAsString();
    final trimmed = content.trim();
    int count = 0;

    if (trimmed.startsWith('{')) {
      final json = jsonDecode(trimmed) as Map<String, dynamic>;
      final playlists = json['playlists'] as List<dynamic>;
      for (final p in playlists) {
        final id = p['id'] as String;
        final url = 'https://www.youtube.com/playlist?list=$id';
        try {
          await fetchFromUrl(url);
          count++;
        } catch (e) {
          AppLogger.log('Import failed for $id: $e', name: 'PlaylistProvider');
        }
      }
    } else if (trimmed.startsWith('<')) {
      final idRegex = RegExp(r'<id>([^<]+)</id>');
      for (final match in idRegex.allMatches(trimmed)) {
        final id = match.group(1)!;
        try {
          await fetchFromUrl('https://www.youtube.com/playlist?list=$id');
          count++;
        } catch (e) {
          AppLogger.log('Import failed for $id: $e', name: 'PlaylistProvider');
        }
      }
    } else {
      final urlRegex = RegExp(r'https?://[^\s\)\]]+');
      for (final match in urlRegex.allMatches(trimmed)) {
        try {
          await fetchFromUrl(match.group(0)!);
          count++;
        } catch (e) {
          AppLogger.log('Import failed: $e', name: 'PlaylistProvider');
        }
      }
    }
    return count;
  }

  String _toXml(Map<String, dynamic> data) {
    final buf = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n');
    buf.writeln('<ytmusix version="${data['version']}" exportedAt="${data['exportedAt']}">');
    for (final p in data['playlists'] as List<dynamic>) {
      buf.writeln('  <playlist>');
      buf.writeln('    <id>${p['id']}</id>');
      buf.writeln('    <title>${_xmlEscape(p['title'])}</title>');
      buf.writeln('    <author>${_xmlEscape(p['author'] ?? '')}</author>');
      buf.writeln('    <videoCount>${p['videoCount']}</videoCount>');
      final tracks = p['tracks'] as List<dynamic>?;
      if (tracks != null && tracks.isNotEmpty) {
        buf.writeln('    <tracks>');
        for (final t in tracks) {
          buf.writeln('      <track>');
          buf.writeln('        <id>${t['id']}</id>');
          buf.writeln('        <title>${_xmlEscape(t['title'])}</title>');
          buf.writeln('      </track>');
        }
        buf.writeln('    </tracks>');
      }
      buf.writeln('  </playlist>');
    }
    buf.writeln('</ytmusix>');
    return buf.toString();
  }

  String _xmlEscape(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

  String _toMarkdown(List<Playlist> playlists) {
    final buf = StringBuffer('# YTMusix Export\n\n');
    buf.writeln('Exported on ${DateTime.now().toLocal()}\n');
    for (final p in playlists) {
      buf.writeln('- [${p.title}](${"https://www.youtube.com/playlist?list=${p.id}"})');
    }
    return buf.toString();
  }

  Future<List<Track>> search(String query) async {
    try {
      return await _repository.search(query);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return [];
    }
  }

  Future<List<Track>> searchTracks(String query) async {
    try {
      return await _repository.searchTracks(query);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return [];
    }
  }

  Future<List<Album>> searchAlbums(String query) async {
    try {
      return await _repository.searchAlbums(query);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return [];
    }
  }

  Future<List<Artist>> searchArtists(String query) async {
    try {
      return await _repository.searchArtists(query);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return [];
    }
  }

  Future<List<Playlist>> searchPlaylists(String query) async {
    try {
      return await _repository.searchPlaylists(query);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return [];
    }
  }

  Future<Album> getAlbum(String albumId) async {
    return await _repository.getAlbum(albumId);
  }

  Future<Artist> getArtist(String artistId) async {
    return await _repository.getArtist(artistId);
  }

  Future<Playlist> getPlaylistFull(String playlistId) async {
    return await _repository.getPlaylist(playlistId);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<Artist?> findCorrectArtist(String artistName, String? albumName) async {
    try {
      final query = albumName != null ? "$artistName $albumName" : artistName;
      final results = await _repository.searchArtists(query);
      if (results.isEmpty) {
        final fallbackResults = await _repository.searchArtists(artistName);
        if (fallbackResults.isEmpty) return null;
        return await getArtist(fallbackResults.first.id);
      }

      final topResults = results.take(3).toList();
      for (final result in topResults) {
        final artist = await getArtist(result.id);
        if (albumName != null) {
          final hasAlbum = artist.albums.any((a) => a.title.toLowerCase() == albumName.toLowerCase() || a.title.toLowerCase().contains(albumName.toLowerCase()));
          if (hasAlbum) return artist;
        }
      }
      return await getArtist(results.first.id);
    } catch (e) {
      // Return null on failure so caller can handle it gracefully
      return null;
    }
  }

  /// Spec 2G Fix #6: cancel any pending debounced refresh
  /// before the provider is torn down. Without this, the
  /// timer could fire after dispose, calling
  /// [AutoDjRoutingService.refreshLikedSongsCache] on a
  /// service whose owner has been released.
  @override
  void dispose() {
    _likedCacheRefreshTimer?.cancel();
    super.dispose();
  }
}
