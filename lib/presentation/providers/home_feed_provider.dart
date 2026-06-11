import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/datasources/local/playlist_database.dart';
import 'package:audiotags/audiotags.dart';

import '../../domain/entities/video.dart';
import '../../core/services/hybrid_cache_service.dart';

class HomeFeedProvider extends ChangeNotifier {
  final PlaylistDatabase _database;
  final HybridCacheService? _cacheService;

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

  HomeFeedProvider({
    required PlaylistDatabase database,
    HybridCacheService? cacheService,
  })  : _database = database,
        _cacheService = cacheService;

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
      final tracks = await _database.getTopSongsPerTopGenre(
        genreLimit: genreLimit,
      );
      
      if (_cacheService != null) {
        _topSongsPerTopGenre = tracks.map((track) {
          if (track.title == null || track.title == 'Unknown Track') {
            final entry = _cacheService!.getTrackerEntry(track.trackId);
            if (entry != null) {
              return track.copyWith(
                title: entry.title,
                artistName: entry.author,
                thumbnailUrl: entry.thumbnailUrl,
              );
            }
          }
          return track;
        }).toList();
      } else {
        _topSongsPerTopGenre = tracks;
      }
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
      final items = await _database.getMostPlayedAlbumsAndSingles(limit: limit);
      
      if (_cacheService != null) {
        _popularAlbumsAndSingles = items.map((item) {
          if (item.title == null || item.title == 'Unknown') {
            final entry = _cacheService!.getTrackerEntry(item.id);
            if (entry != null) {
              return item.copyWith(
                title: entry.title,
                artistName: entry.author,
                thumbnailUrl: entry.thumbnailUrl,
              );
            }
          }
          return item;
        }).toList();
      } else {
        _popularAlbumsAndSingles = items;
      }
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
      final artists = await _database.getTopArtistsFromHistory(
        limit: limit,
      );

      if (_cacheService != null) {
        _topArtistsFromHistory = artists.map((artist) {
          if (artist.thumbnailUrl == null && artist.sampleTrackId != null) {
            final entry = _cacheService!.getTrackerEntry(artist.sampleTrackId!);
            if (entry != null && entry.thumbnailUrl != null) {
              return artist.copyWith(thumbnailUrl: entry.thumbnailUrl);
            }
          }
          return artist;
        }).toList();
      } else {
        _topArtistsFromHistory = artists;
      }
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
      
      final List<Track> tracks = [];
      
      for (final row in rows) {
        final id = row['id'] as String;
        if (id.startsWith('local_') || id.startsWith('importstub_')) continue;

        String title = row['title'] as String? ?? '';
        String? author = row['author'] as String?;
        
        if (title.isEmpty || title == 'Unknown') {
          try {
            final filePath = row['filePath'] as String?;
            if (filePath != null) {
              final tag = await AudioTags.read(filePath);
              if (tag != null && tag.title != null && tag.title!.isNotEmpty) {
                title = tag.title!;
                author = tag.trackArtist ?? author;
              }
            }
          } catch (_) {}
          if (title.isEmpty) title = 'Unknown';
        }
        
        tracks.add(Track(
          id: row['id'] as String,
          title: title,
          author: author,
          album: row['album'] as String?,
          albumId: row['albumId'] as String?,
          year: row['year'] as int?,
          thumbnailUrl: row['thumbnailUrl'] as String?,
          duration: (row['durationSeconds'] as int?) != null
              ? Duration(seconds: row['durationSeconds'] as int)
              : null,
        ));
      }

      if (_cacheService != null) {
        final hiveIds = _cacheService!.getCachedTrackIds();
        final sqliteIds = tracks.map((t) => t.id).toSet();

        for (final id in hiveIds) {
          if (id.startsWith('local_') || id.startsWith('importstub_')) continue;

          if (!sqliteIds.contains(id)) {
            final entry = _cacheService!.getTrackerEntry(id);
            if (entry != null) {
              tracks.add(Track(
                id: entry.trackId,
                title: entry.title ?? 'Unknown',
                author: entry.author,
                thumbnailUrl: entry.thumbnailUrl,
              ));
            }
          }
        }
      }

      _allDownloadedTracks = tracks;
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
