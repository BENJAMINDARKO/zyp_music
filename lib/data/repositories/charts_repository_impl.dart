import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/video_model.dart';
import '../../../domain/entities/album.dart';
import '../../../domain/entities/video.dart';
import '../datasources/remote/charts_remote_datasource.dart';
import '../../../core/utils/app_logger.dart';

class ChartsRepositoryImpl {
  final ChartsRemoteDataSource remoteDataSource;
  
  static const _ghanaKey = 'charts_ghana_songs_v3';
  static const _ghanaTimeKey = 'charts_ghana_time_v3';
  
  static const _globalKey = 'charts_global_songs_v3';
  static const _globalTimeKey = 'charts_global_time_v3';
  
  static const _billboardKey = 'charts_billboard_albums_v2';
  static const _billboardTimeKey = 'charts_billboard_time_v2';

  ChartsRepositoryImpl({required this.remoteDataSource});

  Future<String?> searchArtistId(String artistName) async {
    final results = await remoteDataSource.youtubeDataSource.searchArtists(artistName);
    if (results.isNotEmpty) {
      return results.first.id;
    }
    return null;
  }

  Future<List<Track>> getGhanaTopSongs({bool forceRefresh = false}) async {
    return _getWithCache(
      dataKey: _ghanaKey,
      timeKey: _ghanaTimeKey,
      duration: const Duration(hours: 24),
      forceRefresh: forceRefresh,
      fetcher: () async => (await remoteDataSource.getGhanaTopSongs()).map((e) => e.toEntity()).toList(),
      fromJson: (json) => TrackModel.fromMap(json).toEntity(),
      toJson: (track) => {
        'id': track.id,
        'title': track.title,
        'thumbnailUrl': track.thumbnailUrl,
        'durationSeconds': track.duration?.inSeconds,
        'author': track.author,
        'album': track.album,
        'albumArtist': track.albumArtist,
        'year': track.year,
        'index': track.index,
        'source': 'youtube',
      },
    );
  }

  Future<List<Track>> getGlobalTopSongs({bool forceRefresh = false}) async {
    return _getWithCache(
      dataKey: _globalKey,
      timeKey: _globalTimeKey,
      duration: const Duration(days: 3),
      forceRefresh: forceRefresh,
      fetcher: () async => (await remoteDataSource.getGlobalTopSongs()).map((e) => e.toEntity()).toList(),
      fromJson: (json) => TrackModel.fromMap(json).toEntity(),
      toJson: (track) => {
        'id': track.id,
        'title': track.title,
        'thumbnailUrl': track.thumbnailUrl,
        'durationSeconds': track.duration?.inSeconds,
        'author': track.author,
        'album': track.album,
        'albumArtist': track.albumArtist,
        'year': track.year,
        'index': track.index,
        'source': 'youtube',
      },
    );
  }

  Future<List<Album>> getFeaturedAlbums({bool forceRefresh = false}) async {
    return _getWithCache(
      dataKey: _billboardKey,
      timeKey: _billboardTimeKey,
      duration: const Duration(days: 7),
      forceRefresh: forceRefresh,
      fetcher: () => remoteDataSource.getBillboard200(),
      fromJson: (json) {
        // Need custom fromJson mapping for Album depending on how it's defined
        return Album(
          id: json['id'] ?? '',
          title: json['title'] ?? '',
          artistName: json['author'] ?? '',
          thumbnailUrl: json['thumbnailUrl'],
        );
      },
      toJson: (album) => {
        'id': album.id,
        'title': album.title,
        'author': album.artistName,
        'thumbnailUrl': album.thumbnailUrl,
      },
    );
  }

  Future<List<T>> _getWithCache<T>({
    required String dataKey,
    required String timeKey,
    required Duration duration,
    required bool forceRefresh,
    required Future<List<T>> Function() fetcher,
    required T Function(Map<String, dynamic>) fromJson,
    required Map<String, dynamic> Function(T) toJson,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    
    // Check cache
    if (!forceRefresh) {
      final lastFetchMillis = prefs.getInt(timeKey);
      if (lastFetchMillis != null) {
        final lastFetch = DateTime.fromMillisecondsSinceEpoch(lastFetchMillis);
        if (now.difference(lastFetch) < duration) {
          // Cache is valid
          final cachedData = prefs.getString(dataKey);
          if (cachedData != null) {
            try {
              final List<dynamic> decoded = jsonDecode(cachedData);
              return decoded.map((e) => fromJson(e as Map<String, dynamic>)).toList();
            } catch (e) {
              AppLogger.log('Cache decoding failed for $dataKey: $e', name: 'ChartsRepository');
            }
          }
        }
      }
    }

    // Fetch fresh data
    try {
      final freshData = await fetcher();
      if (freshData.isNotEmpty) {
        // Save to cache
        final encoded = jsonEncode(freshData.map((e) => toJson(e)).toList());
        await prefs.setString(dataKey, encoded);
        await prefs.setInt(timeKey, now.millisecondsSinceEpoch);
        return freshData;
      }
    } catch (e) {
      AppLogger.log('Network fetch failed for $dataKey: $e', name: 'ChartsRepository');
    }

    // Fallback to cache if network fails, regardless of expiry
    final cachedData = prefs.getString(dataKey);
    if (cachedData != null) {
      try {
        final List<dynamic> decoded = jsonDecode(cachedData);
        return decoded.map((e) => fromJson(e as Map<String, dynamic>)).toList();
      } catch (e) {
        AppLogger.log('Fallback cache decoding failed for $dataKey: $e', name: 'ChartsRepository');
      }
    }

    return [];
  }
}
