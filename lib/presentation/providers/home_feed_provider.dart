import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:dart_ytmusic_api/types.dart' as ytm_types;
import 'package:path_provider/path_provider.dart';
import '../../data/datasources/local/playlist_database.dart';
import '../../data/datasources/remote/youtube_remote_datasource.dart';
import 'package:audiotags/audiotags.dart';

import '../../domain/entities/album.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/video.dart';
import '../../core/services/hybrid_cache_service.dart';

class YTFeedSection {
  final String title;
  final List<YTFeedItem> items;
  YTFeedSection(this.title, this.items);
}

class YTFeedItem {
  final Track? track;
  final Album? album;
  final Playlist? playlist;
  YTFeedItem({this.track, this.album, this.playlist});
}

class HomeFeedProvider extends ChangeNotifier {
  final PlaylistDatabase _database;
  final HybridCacheService? _cacheService;
  final YoutubeRemoteDataSource _dataSource;

  List<TopGenreTrack>? _topSongsPerTopGenre;
  List<PopularItem>? _popularAlbumsAndSingles;
  ListeningStats? _listeningStats;
  List<HistoryArtistEntry>? _topArtistsFromHistory;
  List<Track>? _allDownloadedTracks;
  List<YTFeedSection>? _ytHomeSections;

  bool _loadingTopSongsPerTopGenre = false;
  bool _loadingPopularAlbumsAndSingles = false;
  bool _loadingListeningStats = false;
  bool _loadingTopArtistsFromHistory = false;
  bool _loadingAllDownloadedTracks = false;
  bool _loadingYTMusicHome = false;

  HomeFeedProvider({
    required PlaylistDatabase database,
    required YoutubeRemoteDataSource dataSource,
    HybridCacheService? cacheService,
  })  : _database = database,
        _dataSource = dataSource,
        _cacheService = cacheService;

  List<TopGenreTrack>? get topSongsPerTopGenre => _topSongsPerTopGenre;
  List<PopularItem>? get popularAlbumsAndSingles => _popularAlbumsAndSingles;
  ListeningStats? get listeningStats => _listeningStats;
  List<HistoryArtistEntry>? get topArtistsFromHistory => _topArtistsFromHistory;
  List<Track>? get allDownloadedTracks => _allDownloadedTracks;
  List<YTFeedSection>? get ytHomeSections => _ytHomeSections;

  bool get isLoadingTopSongsPerTopGenre => _loadingTopSongsPerTopGenre;
  bool get isLoadingPopularAlbumsAndSingles => _loadingPopularAlbumsAndSingles;
  bool get isLoadingListeningStats => _loadingListeningStats;
  bool get isLoadingTopArtistsFromHistory => _loadingTopArtistsFromHistory;
  bool get isLoadingAllDownloadedTracks => _loadingAllDownloadedTracks;
  bool get isLoadingYTMusicHome => _loadingYTMusicHome;

  Future<void> loadTopSongsPerTopGenre({int genreLimit = 6}) async {
    if (_loadingTopSongsPerTopGenre) return;
    _loadingTopSongsPerTopGenre = true;
    notifyListeners();

    try {
      final tracks = await _database.getTopSongsPerTopGenre(
        genreLimit: genreLimit,
      );

      _topSongsPerTopGenre = _enrichTracks(tracks);
    } catch (e) {
      _topSongsPerTopGenre = const [];
      debugPrint('[HomeFeed] loadTopSongsPerTopGenre failed: $e');
    } finally {
      _loadingTopSongsPerTopGenre = false;
      notifyListeners();
    }
  }

  List<TopGenreTrack> _enrichTracks(List<TopGenreTrack> tracks) {
    final cache = _cacheService;
    if (cache == null) return tracks;
    return tracks.map((track) {
      if (_hasMetadata(track.title)) return track;
      final entry = cache.getTrackerEntry(track.trackId);
      if (entry == null) return track;
      return track.copyWith(
        title: entry.title ?? track.title,
        artistName: entry.author ?? track.artistName,
        thumbnailUrl: entry.thumbnailUrl ?? track.thumbnailUrl,
      );
    }).toList();
  }

  bool _hasMetadata(String? title) =>
    title != null && title.isNotEmpty && title != 'Unknown' && title != 'Unknown Track';

  Future<void> loadPopularAlbumsAndSingles({int limit = 10}) async {
    if (_loadingPopularAlbumsAndSingles) return;
    _loadingPopularAlbumsAndSingles = true;
    notifyListeners();

    try {
      final items = await _database.getMostPlayedAlbumsAndSingles(limit: limit);

      final cache = _cacheService;
      if (cache != null) {
        _popularAlbumsAndSingles = items.map((item) {
          if (_hasMetadata(item.title)) return item;
          final entry = cache.getTrackerEntry(item.id);
          if (entry == null) return item;
          return item.copyWith(
            title: entry.title ?? item.title,
            artistName: entry.author ?? item.artistName,
            thumbnailUrl: entry.thumbnailUrl ?? item.thumbnailUrl,
          );
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

      final cache = _cacheService;
      if (cache != null) {
        _topArtistsFromHistory = artists.map((artist) {
          if (artist.thumbnailUrl != null) return artist;
          // Try sampleTrackId first, then scan Hive for any track by this artist
          if (artist.sampleTrackId != null) {
            final entry = cache.getTrackerEntry(artist.sampleTrackId!);
            if (entry?.thumbnailUrl != null) {
              return artist.copyWith(thumbnailUrl: entry!.thumbnailUrl);
            }
          }
          // Broader scan: look up any cached track matching the artist name
          final thumb = _findArtistThumbnail(artist.artistName);
          if (thumb != null) return artist.copyWith(thumbnailUrl: thumb);
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

  String? _findArtistThumbnail(String artistName) {
    final cache = _cacheService;
    if (cache == null || artistName.isEmpty) return null;
    final key = artistName.trim().toLowerCase();
    for (final id in cache.getCachedTrackIds()) {
      final entry = cache.getTrackerEntry(id);
      if (entry == null) continue;
      final entryAuthor = entry.author?.trim().toLowerCase() ?? '';
      if (entryAuthor == key && entry.thumbnailUrl != null) {
        return entry.thumbnailUrl;
      }
    }
    return null;
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
        String? thumbnailUrl = row['thumbnailUrl'] as String?;
        
        if (!_hasMetadata(title) || author == null || thumbnailUrl == null) {
          // Try Hive cache first
          final cache = _cacheService;
          if (cache != null) {
            final entry = cache.getTrackerEntry(id);
            if (entry != null) {
              if (!_hasMetadata(title)) title = entry.title ?? title;
              author ??= entry.author;
              thumbnailUrl ??= entry.thumbnailUrl;
            }
          }
          // Fall back to file metadata tags
          if (!_hasMetadata(title)) {
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
          }
          if (title.isEmpty) title = 'Unknown';
        }
        
        tracks.add(Track(
          id: id,
          title: title,
          author: author,
          album: row['album'] as String?,
          albumId: row['albumId'] as String?,
          year: row['year'] as int?,
          thumbnailUrl: thumbnailUrl,
          duration: (row['durationSeconds'] as int?) != null
              ? Duration(seconds: row['durationSeconds'] as int)
              : null,
        ));
      }

      final cache = _cacheService;
      if (cache != null) {
        final hiveIds = cache.getCachedTrackIds();
        final sqliteIds = tracks.map((t) => t.id).toSet();

        for (final id in hiveIds) {
          if (id.startsWith('local_') || id.startsWith('importstub_')) continue;

          if (!sqliteIds.contains(id)) {
            final entry = cache.getTrackerEntry(id);
            if (entry == null) continue;

            String title = entry.title ?? '';
            String? author = entry.author;
            String? thumbnailUrl = entry.thumbnailUrl;

            tracks.add(Track(
              id: entry.trackId,
              title: title.isNotEmpty ? title : 'Unknown',
              author: author,
              thumbnailUrl: thumbnailUrl,
            ));
          }
        }
      }

      _allDownloadedTracks = tracks;

      // Backfill Unknown tracks from YTMusic API in the background.
      // YouTube audio files have no embedded ID3 tags, so the only
      // way to get metadata is from the API.
      if (_cacheService != null) {
        _backfillUnknownTrackMetadata(tracks);
      }
    } catch (e) {
      _allDownloadedTracks = const [];
      debugPrint('[HomeFeed] loadAllDownloadedTracks failed: $e');
    } finally {
      _loadingAllDownloadedTracks = false;
      notifyListeners();
    }
  }

  /// Fetches metadata from YTMusic for tracks with Unknown titles and
  /// persists the result to Hive so future loads don't need the API.
  Future<void> _backfillUnknownTrackMetadata(List<Track> tracks) async {
    final cache = _cacheService;
    if (cache == null) return;

    final unknownIds = tracks
        .where((t) => t.title == 'Unknown' || t.title.isEmpty)
        .map((t) => t.id)
        .toList();

    if (unknownIds.isEmpty) return;

    bool updated = false;

    for (final id in unknownIds) {
      try {
        final video = await _dataSource.getVideo(id);
        if (video.title.isNotEmpty && video.title != 'Unknown') {
          await cache.backfillMetadata(id, video.title, author: video.author);
          // Also update the in-memory list
          final idx = tracks.indexWhere((t) => t.id == id);
          if (idx != -1) {
            tracks[idx] = Track(
              id: id,
              title: video.title,
              author: video.author,
              thumbnailUrl: video.thumbnailUrl,
              duration: video.durationSeconds != null
                  ? Duration(seconds: video.durationSeconds!)
                  : null,
            );
            updated = true;
          }
        }
      } catch (_) {}
    }

    if (updated) {
      _allDownloadedTracks = List<Track>.from(tracks);
      notifyListeners();
    }
  }

  void setGl(String code) {
    _dataSource.setGl(code);
  }

  /// Load YTMusic home sections — tries disk cache first, falls back
  /// to the API. Use [refreshYTMusicHome] to force a fresh API fetch.
  Future<void> loadYTMusicHome() async {
    if (_loadingYTMusicHome) return;
    _loadingYTMusicHome = true;
    notifyListeners();

    try {
      final cached = await _readCachedYTFeedSections();
      if (cached != null) {
        _ytHomeSections = cached;
        return;
      }
      final rawSections = await _dataSource.getHomeSections();
      _ytHomeSections = rawSections.map(_convertSection).toList();
      await _writeCachedYTFeedSections(_ytHomeSections!);
    } catch (e) {
      _ytHomeSections = const [];
      debugPrint('[HomeFeed] loadYTMusicHome failed: $e');
    } finally {
      _loadingYTMusicHome = false;
      notifyListeners();
    }
  }

  /// Force a fresh API fetch, bypassing the disk cache.
  Future<void> refreshYTMusicHome() async {
    if (_loadingYTMusicHome) return;
    _loadingYTMusicHome = true;
    notifyListeners();

    try {
      final rawSections = await _dataSource.getHomeSections();
      _ytHomeSections = rawSections.map(_convertSection).toList();
      await _writeCachedYTFeedSections(_ytHomeSections!);
    } catch (e) {
      debugPrint('[HomeFeed] refreshYTMusicHome failed: $e');
    } finally {
      _loadingYTMusicHome = false;
      notifyListeners();
    }
  }

  String? _cacheDir;

  Future<String> _ytHomeCachePath() async {
    if (_cacheDir == null) {
      final dir = await getTemporaryDirectory();
      _cacheDir = dir.path;
    }
    return '$_cacheDir/yt_home_sections.json';
  }

  Future<void> _writeCachedYTFeedSections(List<YTFeedSection> sections) async {
    try {
      final path = await _ytHomeCachePath();
      final json = sections.map(_sectionToJson).toList();
      await File(path).writeAsString(jsonEncode(json));
    } catch (_) {}
  }

  Future<List<YTFeedSection>?> _readCachedYTFeedSections() async {
    try {
      final path = await _ytHomeCachePath();
      final file = File(path);
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString()) as List;
      return json
          .map((e) => _sectionFromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _sectionToJson(YTFeedSection s) => {
        'title': s.title,
        'items': s.items.map(_itemToJson).toList(),
      };

  Map<String, dynamic> _itemToJson(YTFeedItem item) {
    if (item.track != null) {
      final t = item.track!;
      return {
        'type': 'track',
        'id': t.id,
        'title': t.title,
        'author': t.author,
        'thumbnailUrl': t.thumbnailUrl,
        'albumId': t.albumId,
        'album': t.album,
        'durationMs': t.duration?.inMilliseconds,
      };
    }
    if (item.album != null) {
      final a = item.album!;
      return {
        'type': 'album',
        'id': a.id,
        'title': a.title,
        'artistName': a.artistName,
        'thumbnailUrl': a.thumbnailUrl,
        'year': a.year,
      };
    }
    if (item.playlist != null) {
      final p = item.playlist!;
      return {
        'type': 'playlist',
        'id': p.id,
        'title': p.title,
        'author': p.author,
        'thumbnailUrl': p.thumbnailUrl,
        'trackCount': p.videoCount,
      };
    }
    return {'type': 'empty'};
  }

  YTFeedSection _sectionFromJson(Map<String, dynamic> json) => YTFeedSection(
        json['title'] as String,
        (json['items'] as List)
            .map((j) => _itemFromJson(j as Map<String, dynamic>))
            .toList(),
      );

  YTFeedItem _itemFromJson(Map<String, dynamic> json) {
    switch (json['type'] as String) {
      case 'track':
        return YTFeedItem(
          track: Track(
            id: json['id'] as String,
            title: json['title'] as String,
            author: json['author'] as String?,
            thumbnailUrl: json['thumbnailUrl'] as String?,
            albumId: json['albumId'] as String?,
            album: json['album'] as String?,
            duration: json['durationMs'] != null
                ? Duration(milliseconds: json['durationMs'] as int)
                : null,
          ),
        );
      case 'album':
        return YTFeedItem(
          album: Album(
            id: json['id'] as String,
            title: json['title'] as String,
            artistName: json['artistName'] as String?,
            thumbnailUrl: json['thumbnailUrl'] as String?,
            year: json['year'] as String?,
          ),
        );
      case 'playlist':
        return YTFeedItem(
          playlist: Playlist(
            id: json['id'] as String,
            title: json['title'] as String,
            author: json['author'] as String?,
            thumbnailUrl: json['thumbnailUrl'] as String?,
            videoCount: json['trackCount'] as int? ?? 0,
          ),
        );
      default:
        return YTFeedItem();
    }
  }

  YTFeedSection _convertSection(ytm_types.HomeSection section) {
    final items = section.contents.map<YTFeedItem>((item) {
      if (item is ytm_types.SongDetailed) {
        return YTFeedItem(track: _songToTrack(item));
      } else if (item is ytm_types.AlbumDetailed) {
        return YTFeedItem(album: _albumToAlbum(item));
      } else if (item is ytm_types.PlaylistDetailed) {
        return YTFeedItem(playlist: _playlistToPlaylist(item));
      }
      return YTFeedItem();
    }).toList();
    return YTFeedSection(section.title, items);
  }

  Track _songToTrack(ytm_types.SongDetailed s) => Track(
    id: s.videoId,
    title: s.name,
    author: s.artist.name,
    albumId: s.album?.albumId,
    album: s.album?.name,
    duration: s.duration != null ? Duration(seconds: s.duration!) : null,
    thumbnailUrl: s.thumbnails.lastOrNull?.url,
  );

  Album _albumToAlbum(ytm_types.AlbumDetailed a) => Album(
    id: a.albumId,
    title: a.name,
    artistName: a.artist.name,
    year: a.year?.toString(),
    thumbnailUrl: a.thumbnails.lastOrNull?.url,
  );

  Playlist _playlistToPlaylist(ytm_types.PlaylistDetailed p) => Playlist(
    id: p.playlistId,
    title: p.name,
    author: p.artist.name,
    thumbnailUrl: p.thumbnails.lastOrNull?.url,
  );

  Future<void> loadAll() async {
    await Future.wait([
      loadTopSongsPerTopGenre(),
      loadPopularAlbumsAndSingles(),
      loadListeningStats(),
      loadTopArtistsFromHistory(),
      loadAllDownloadedTracks(),
      loadYTMusicHome(),
    ]);
  }

  void invalidate() {
    _topSongsPerTopGenre = null;
    _popularAlbumsAndSingles = null;
    _listeningStats = null;
    _topArtistsFromHistory = null;
    _allDownloadedTracks = null;
    _ytHomeSections = null;
    notifyListeners();
  }
}
