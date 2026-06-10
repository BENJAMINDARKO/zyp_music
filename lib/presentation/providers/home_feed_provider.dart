import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/datasources/local/playlist_database.dart';
import '../../domain/entities/video.dart';

class HomeFeedProvider extends ChangeNotifier {
  final PlaylistDatabase _database;

  List<TopGenreTrack>? _topSongsPerTopGenre;
  List<PopularItem>? _popularAlbumsAndSingles;
  ListeningStats? _listeningStats;
  List<HistoryArtistEntry>? _topArtistsFromHistory;
  List<Track>? _allDownloadedTracks;

  bool _loadingTopSongsPerTopGenre = false;
  bool _loadingPopularAlbumsAndSingles = false;
  bool _loadingListeningStats = false;
  bool _loadingTopArtistsFromHistory = false;
  bool _loadingAllDownloadedTracks = false;

  HomeFeedProvider({required PlaylistDatabase database})
      : _database = database;

  List<TopGenreTrack>? get topSongsPerTopGenre => _topSongsPerTopGenre;
  List<PopularItem>? get popularAlbumsAndSingles => _popularAlbumsAndSingles;
  ListeningStats? get listeningStats => _listeningStats;
  List<HistoryArtistEntry>? get topArtistsFromHistory => _topArtistsFromHistory;
  List<Track>? get allDownloadedTracks => _allDownloadedTracks;

  bool get isLoadingTopSongsPerTopGenre => _loadingTopSongsPerTopGenre;
  bool get isLoadingPopularAlbumsAndSingles => _loadingPopularAlbumsAndSingles;
  bool get isLoadingListeningStats => _loadingListeningStats;
  bool get isLoadingTopArtistsFromHistory => _loadingTopArtistsFromHistory;
  bool get isLoadingAllDownloadedTracks => _loadingAllDownloadedTracks;

  Future<void> loadTopSongsPerTopGenre({int genreLimit = 6}) async {
    if (_loadingTopSongsPerTopGenre) return;
    _loadingTopSongsPerTopGenre = true;
    notifyListeners();

    try {
      _topSongsPerTopGenre = await _database.getTopSongsPerTopGenre(
        genreLimit: genreLimit,
      );
    } catch (e) {
      _topSongsPerTopGenre = const [];
      debugPrint('[HomeFeed] loadTopSongsPerTopGenre failed: $e');
    } finally {
      _loadingTopSongsPerTopGenre = false;
      notifyListeners();
    }
  }

  Future<void> loadPopularAlbumsAndSingles({int limit = 10}) async {
    if (_loadingPopularAlbumsAndSingles) return;
    _loadingPopularAlbumsAndSingles = true;
    notifyListeners();

    try {
      _popularAlbumsAndSingles =
          await _database.getMostPlayedAlbumsAndSingles(limit: limit);
    } catch (e) {
      _popularAlbumsAndSingles = const [];
      debugPrint('[HomeFeed] loadPopularAlbumsAndSingles failed: $e');
    } finally {
      _loadingPopularAlbumsAndSingles = false;
      notifyListeners();
    }
  }

  Future<void> loadListeningStats() async {
    if (_loadingListeningStats) return;
    _loadingListeningStats = true;
    notifyListeners();

    try {
      _listeningStats = await _database.getListeningStats();
    } catch (e) {
      _listeningStats = ListeningStats.empty;
      debugPrint('[HomeFeed] loadListeningStats failed: $e');
    } finally {
      _loadingListeningStats = false;
      notifyListeners();
    }
  }

  Future<void> loadTopArtistsFromHistory({int limit = 10}) async {
    if (_loadingTopArtistsFromHistory) return;
    _loadingTopArtistsFromHistory = true;
    notifyListeners();

    try {
      _topArtistsFromHistory = await _database.getTopArtistsFromHistory(
        limit: limit,
      );
    } catch (e) {
      _topArtistsFromHistory = const [];
      debugPrint('[HomeFeed] loadTopArtistsFromHistory failed: $e');
    } finally {
      _loadingTopArtistsFromHistory = false;
      notifyListeners();
    }
  }

  Future<void> loadAllDownloadedTracks() async {
    if (_loadingAllDownloadedTracks) return;
    _loadingAllDownloadedTracks = true;
    notifyListeners();

    try {
      final rows = await _database.getAllDownloadedTracks();
      _allDownloadedTracks = rows.map((row) => Track(
        id: row['id'] as String,
        title: row['title'] as String? ?? 'Unknown',
        author: row['author'] as String?,
        album: row['album'] as String?,
        albumId: row['albumId'] as String?,
        year: row['year'] as int?,
        thumbnailUrl: row['thumbnailUrl'] as String?,
        duration: (row['durationSeconds'] as int?) != null
            ? Duration(seconds: row['durationSeconds'] as int)
            : null,
      )).toList();
    } catch (e) {
      _allDownloadedTracks = const [];
      debugPrint('[HomeFeed] loadAllDownloadedTracks failed: $e');
    } finally {
      _loadingAllDownloadedTracks = false;
      notifyListeners();
    }
  }

  Future<void> loadAll() async {
    await Future.wait([
      loadTopSongsPerTopGenre(),
      loadPopularAlbumsAndSingles(),
      loadListeningStats(),
      loadTopArtistsFromHistory(),
      loadAllDownloadedTracks(),
    ]);
  }

  void invalidate() {
    _topSongsPerTopGenre = null;
    _popularAlbumsAndSingles = null;
    _listeningStats = null;
    _topArtistsFromHistory = null;
    _allDownloadedTracks = null;
    notifyListeners();
  }
}
