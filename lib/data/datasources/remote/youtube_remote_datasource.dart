import 'dart:async';
import 'package:zyp_music/core/utils/app_logger.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart'
    hide Playlist, Video;
import 'package:dart_ytmusic_api/yt_music.dart' as ytm;
import 'package:dart_ytmusic_api/types.dart' as ytm_types;
import '../../../domain/entities/album.dart';
import '../../../domain/entities/artist.dart';
import '../../models/playlist_model.dart';
import '../../models/video_model.dart';
import '../../../service/auth_service.dart';
import 'authenticated_client.dart';
import 'youtube_audio_extractor.dart';

class YoutubeRemoteDataSource {
  static const _timeout = Duration(seconds: 30);

  final AuthService _authService;
  late YoutubeExplode _yt;
  late ytm.YTMusic _ytMusic;

  YoutubeRemoteDataSource({AuthService? authService})
      : _authService = authService ?? AuthService();

  Future<void> init() async {
    final cookies = await _authService.getCookies();
    final inner = AuthenticatedClient(cookies: cookies);
    final ytHttp = YoutubeHttpClient(inner);
    _yt = YoutubeExplode(httpClient: ytHttp);
    _ytMusic = ytm.YTMusic();
    try {
      await _ytMusic.initialize(cookies: cookies);
    } catch (e) {
      AppLogger.log('Failed to initialize YTMusic (possibly offline): $e', name: 'YoutubeRemoteDataSource');
    }
  }

  /// Rebuilds the YouTube + YTMusic clients against a fresh cookie read.
  ///
  /// Called by [ConnectivityService] when the device transitions from
  /// `offline -> online`, so the clients that were initialised against
  /// a dead radio at app start are replaced with a working pair before
  /// the next search / stream / metadata call lands.
  ///
  /// Safe to call repeatedly; the existing `_yt` client is closed before
  /// the new one is constructed. No audio playback is touched.
  Future<void> refreshNetworkClientHeaders() async {
    try {
      _yt.close();
    } catch (_) {
      // The previous client may already be closed (e.g. first launch
      // where `init` succeeded end-to-end). Swallow — we are about to
      // overwrite the reference anyway.
    }
    await init();
    AppLogger.log(
      'Network client headers refreshed after connectivity restoration',
      name: 'YoutubeRemoteDataSource',
    );
  }

  Future<PlaylistModel> getPlaylist(String playlistId) async {
    var attempt = 0;
    final stopwatch = Stopwatch()..start();

    while (true) {
      attempt++;
      try {
        try {
          // Try YT Music API first (fixes YouTube Music playlists)
          final p = await _ytMusic.getPlaylist(playlistId).timeout(_timeout);
          final videos = await _ytMusic.getPlaylistVideos(playlistId).timeout(_timeout);
          
          final tracks = <TrackModel>[];
          for (var i = 0; i < videos.length; i++) {
            final v = videos[i];
            tracks.add(TrackModel(
              id: v.videoId,
              title: v.name,
              author: v.artist.name,
              durationSeconds: v.duration ?? 0,
              thumbnailUrl: v.thumbnails.lastOrNull?.url,
              index: i,
            ));
          }
          
          return PlaylistModel(
            id: playlistId,
            title: p.name,
            author: p.artist.name,
            thumbnailUrl: p.thumbnails.lastOrNull?.url,
            videoCount: p.videoCount,
            tracks: tracks,
          );
        } catch (e) {
          AppLogger.log('YT Music playlist fetch failed for $playlistId: $e, falling back to YoutubeExplode', name: 'YoutubeRemoteDataSource');
          // Fallback to YoutubeExplode
          final ytPlaylist = await _yt.playlists
              .get(playlistId)
              .timeout(_timeout);

          final title = ytPlaylist.title;
          final author = ytPlaylist.author;

          final videos = await () async {
            try {
              return await _yt.playlists
                  .getVideos(playlistId)
                  .toList()
                  .timeout(_timeout);
            } catch (e) {
              AppLogger.log('Playlist videos fetch failed for $playlistId (attempt $attempt): $e',
                  name: 'YoutubeRemoteDataSource');
              return <dynamic>[];
            }
          }();

          if (videos.isEmpty) {
            throw Exception('No videos found for playlist/mix $playlistId');
          }

          final tracks = <TrackModel>[];
          for (var i = 0; i < videos.length; i++) {
            final video = videos[i];
            tracks.add(TrackModel(
              id: video.id.value,
              title: video.title,
              author: video.author,
              durationSeconds: video.duration?.inSeconds ?? 0,
              thumbnailUrl: video.thumbnails.mediumResUrl,
              index: i,
            ));
          }

          final thumbnailUrl = tracks.isNotEmpty ? tracks.first.thumbnailUrl : null;

          return PlaylistModel(
            id: playlistId,
            title: title,
            author: author,
            thumbnailUrl: thumbnailUrl,
            videoCount: tracks.length,
            tracks: tracks,
          );
        }
      } on TimeoutException {
        AppLogger.log('Attempt $attempt timed out for playlist $playlistId',
            name: 'YoutubeRemoteDataSource');
        if (attempt >= 3 || stopwatch.elapsed > const Duration(seconds: 45)) {
          rethrow;
        }
        await Future.delayed(Duration(seconds: 2 * attempt));
      } on Exception catch (e) {
        final msg = e.toString();
        AppLogger.log('Playlist fetch attempt $attempt failed for $playlistId: $msg',
            name: 'YoutubeRemoteDataSource');
        if (attempt >= 3 || stopwatch.elapsed > const Duration(seconds: 45)) {
          rethrow;
        }
        await Future.delayed(Duration(seconds: 2 * attempt));
      }
    }
  }

  Future<TrackModel> getVideo(String videoId) async {
    final video = await _yt.videos.get(videoId);
    return TrackModel(
      id: video.id.value,
      title: video.title,
      author: video.author,
      durationSeconds: video.duration?.inSeconds ?? 0,
      thumbnailUrl: video.thumbnails.mediumResUrl,
      index: 0,
    );
  }

  Future<String> getAudioUrl(String videoId, {String quality = 'medium'}) async {
    var attempt = 0;
    final stopwatch = Stopwatch()..start();
    while (true) {
      try {
        final url = await YoutubeAudioExtractor.instance.getAudioUrl(videoId);
        
        if (url != null && await _verifyUrl(url)) {
          return url;
        }

        throw Exception('No playable audio streams available for video $videoId');
      } on TimeoutException {
        attempt++;
        AppLogger.log('Attempt $attempt timed out for video $videoId',
            name: 'YoutubeRemoteDataSource');
        if (attempt >= 3 || stopwatch.elapsed > const Duration(seconds: 45)) {
          rethrow;
        }
        await Future.delayed(Duration(seconds: 2 * attempt));
      } on Exception catch (e) {
        attempt++;
        final msg = e.toString();
        if (attempt >= 3 || stopwatch.elapsed > const Duration(seconds: 45)) {
          AppLogger.log('All $attempt attempts failed for video $videoId: $msg',
              name: 'YoutubeRemoteDataSource');
          rethrow;
        }
        if (msg.contains('requestLimit') || msg.contains('429')) {
          AppLogger.log('Rate limited on attempt $attempt for video $videoId',
              name: 'YoutubeRemoteDataSource');
          await Future.delayed(Duration(seconds: 2 * attempt));
        } else if (msg.contains('ClientException') || msg.contains('Connection closed')) {
          AppLogger.log('Connection error on attempt $attempt for video $videoId',
              name: 'YoutubeRemoteDataSource');
          await Future.delayed(Duration(seconds: 2 * attempt));
        } else {
          AppLogger.log('Non-retryable error on attempt $attempt for video $videoId: $msg',
              name: 'YoutubeRemoteDataSource');
          rethrow;
        }
      }
    }
  }

  Future<bool> _verifyUrl(String url) async {
    try {
      final client = http.Client();
      final req = http.Request('GET', Uri.parse(url));
      req.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';
      req.headers['Range'] = 'bytes=0-1'; // Request minimal data
      
      final resp = await client.send(req);
      await resp.stream.drain();
      client.close();
      
      if (resp.statusCode >= 200 && resp.statusCode < 400) {
        return true;
      }
      AppLogger.log('URL verification failed with status: ${resp.statusCode}', name: 'YoutubeRemoteDataSource');
      return false;
    } catch (e) {
      AppLogger.log('URL verification threw: $e', name: 'YoutubeRemoteDataSource');
      return false;
    }
  }

  Future<List<TrackModel>> search(String query) async {
    // Append 'official audio' or 'music' to prioritize high-quality tracks if not already present
    var searchQuery = query;
    if (!searchQuery.toLowerCase().contains('official') && !searchQuery.toLowerCase().contains('music')) {
      searchQuery = '$searchQuery official audio';
    }
    
    final results = await _yt.search.search(searchQuery);
    final tracks = <TrackModel>[];
    for (var i = 0; i < results.length; i++) {
      final video = results[i];
      // Try to parse artist - topic channel format: "Artist - Topic"
      String author = video.author;
      String? album;
      if (author.endsWith(' - Topic')) {
        author = author.replaceAll(' - Topic', '');
      }
      
      tracks.add(TrackModel(
        id: video.id.value,
        title: video.title,
        author: author,
        album: album,
        durationSeconds: video.duration?.inSeconds ?? 0,
        thumbnailUrl: video.thumbnails.mediumResUrl,
        index: i,
      ));
    }
    return tracks;
  }

  Future<List<TrackModel>> searchTracks(String query) async {
    final results = await _ytMusic.searchSongs(query);
    final tracks = <TrackModel>[];
    
    for (var i = 0; i < results.length; i++) {
      final song = results[i];
      tracks.add(TrackModel(
        id: song.videoId,
        title: song.name,
        author: song.artist.name,
        album: song.album?.name,
        durationSeconds: song.duration ?? 0,
        thumbnailUrl: song.thumbnails.lastOrNull?.url,
        index: i,
      ));
    }
    return tracks;
  }

  Future<List<Album>> searchAlbums(String query) async {
    final results = await _ytMusic.searchAlbums(query);
    return results.map((a) => Album(
      id: a.albumId, // We use albumId to fetch album tracks later
      title: a.name,
      artistName: a.artist.name,
      year: a.year?.toString(),
      thumbnailUrl: a.thumbnails.lastOrNull?.url,
    )).toList();
  }

  Future<List<Artist>> searchArtists(String query) async {
    final results = await _ytMusic.searchArtists(query);
    return results.map((a) => Artist(
      id: a.artistId,
      name: a.name,
      thumbnailUrl: a.thumbnails.lastOrNull?.url,
    )).toList();
  }

  Future<List<PlaylistModel>> searchPlaylists(String query) async {
    final results = await _ytMusic.searchPlaylists(query);
    return results.map((p) => PlaylistModel(
      id: p.playlistId,
      title: p.name,
      author: p.artist.name,
      thumbnailUrl: p.thumbnails.lastOrNull?.url,
      videoCount: 0,
    )).toList();
  }

  Future<ytm_types.AlbumFull> getAlbum(String albumId) async {
    return await _ytMusic.getAlbum(albumId);
  }

  Future<ytm_types.ArtistFull> getArtist(String artistId) async {
    return await _ytMusic.getArtist(artistId);
  }

  Future<ytm_types.PlaylistFull> getPlaylistFull(String playlistId) async {
    return await _ytMusic.getPlaylist(playlistId);
  }

  Future<List<ytm_types.UpNextsDetails>> getUpNexts(String videoId) async {
    return await _ytMusic.getUpNexts(videoId);
  }

  void dispose() {
    _yt.close();
  }
}
