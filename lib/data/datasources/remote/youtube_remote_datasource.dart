import '../../../core/utils/normalise.dart';

import 'dart:async';
import 'package:zyp_music/core/utils/app_logger.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart'
    hide Playlist, Video;
import 'package:dart_ytmusic_api/yt_music.dart' as ytm;
import 'package:dart_ytmusic_api/types.dart' as ytm_types;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../domain/entities/album.dart';
import '../../../domain/entities/artist.dart';
import '../../models/playlist_model.dart';
import '../../models/video_model.dart';
import '../../../service/auth_service.dart';
import '../../../core/utils/thumbnail_url.dart';
import 'authenticated_client.dart';
import 'youtube_audio_extractor.dart';

class YoutubeRemoteDataSource {
  static const _timeout = Duration(seconds: 30);

  static YoutubeRemoteDataSource? _instance;
  static YoutubeRemoteDataSource? get instance => _instance;

  final AuthService _authService;
  late YoutubeExplode _yt;
  late ytm.YTMusic _ytMusic;

  /// Public read-only handle on the underlying [ytm.YTMusic]
  /// instance. Exposed so adjacent services (currently the
  /// lyrics chain, future: sponsor-block pre-roller, etc.) can
  /// call into the same authenticated client without having
  /// to instantiate their own — and without forcing the
  /// remote data source to know about lyrics at all.
  ytm.YTMusic get ytMusic => _ytMusic;

  YoutubeRemoteDataSource({AuthService? authService})
      : _authService = authService ?? AuthService() {
    _instance = this;
  }

  Future<void> init() async {
    final cookieHeader = await _authService.getCookieHeader();
    if (cookieHeader != null && cookieHeader.isNotEmpty) {
      final inner = AuthenticatedClient(cookieHeader: cookieHeader);
      final ytHttp = YoutubeHttpClient(inner);
      _yt = YoutubeExplode(httpClient: ytHttp);
      _ytMusic = ytm.YTMusic();
      try {
        await _ytMusic.initialize(cookies: cookieHeader);
      } catch (e) {
        AppLogger.log('Failed to initialize YTMusic (possibly offline): $e', name: 'YoutubeRemoteDataSource');
      }
    } else {
      final inner = http.Client();
      final ytHttp = YoutubeHttpClient(inner);
      _yt = YoutubeExplode(httpClient: ytHttp);
      _ytMusic = ytm.YTMusic();
      try {
        await _ytMusic.initialize();
      } catch (e) {
        AppLogger.log('Failed to initialize YTMusic (possibly offline): $e', name: 'YoutubeRemoteDataSource');
      }
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
              author: cleanArtistName(v.artist.name),
              durationSeconds: v.duration,
              thumbnailUrl: v.thumbnails.lastOrNull?.url,
              index: i,
            ));
          }
          
          return PlaylistModel(
            id: playlistId,
            title: p.name,
            author: cleanArtistName(p.artist.name),
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
            if (playlistId.startsWith('OLAK')) {
              throw Exception('This album format is no longer supported by YouTube due to recent changes. Please delete it from your library/history and search for the album again.');
            }
            throw Exception('No videos found for playlist/mix $playlistId');
          }

          final tracks = <TrackModel>[];
          for (var i = 0; i < videos.length; i++) {
            final video = videos[i];
            tracks.add(TrackModel(
              id: video.id.value,
              title: video.title,
              author: cleanArtistName(video.author),
              durationSeconds: video.duration?.inSeconds,
              thumbnailUrl: video.thumbnails.mediumResUrl,
              index: i,
            ));
          }

          final thumbnailUrl = tracks.isNotEmpty ? tracks.first.thumbnailUrl : null;

          return PlaylistModel(
            id: playlistId,
            title: title,
            author: cleanArtistName(author),
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
      author: cleanArtistName(video.author),
      durationSeconds: video.duration?.inSeconds,
      thumbnailUrl: video.thumbnails.mediumResUrl,
      index: 0,
    );
  }

  Future<String> getAudioUrl(String videoId, {String quality = 'medium'}) async {
    var attempt = 0;
    final stopwatch = Stopwatch()..start();
    while (true) {
      try {
        String? url = await YoutubeAudioExtractor.instance.getAudioUrl(videoId);
        
        if (url == null) {
          try {
            AppLogger.log('Falling back to ytMusic.getSong for $videoId', name: 'YoutubeRemoteDataSource');
            final song = await _ytMusic.getSong(videoId);
            final adaptive = song.adaptiveFormats ?? [];
            for (var f in adaptive) {
              if (f['mimeType']?.toString().contains('audio/') == true) {
                final audioUrl = f['url']?.toString();
                if (audioUrl != null && audioUrl.isNotEmpty) {
                  url = audioUrl;
                  AppLogger.log('Successfully extracted URL from ytMusic fallback', name: 'YoutubeRemoteDataSource');
                  break;
                }
              }
            }
          } catch (e) {
            AppLogger.log('ytMusic fallback failed: $e', name: 'YoutubeRemoteDataSource');
          }
        }

        if (url != null) {
          unawaited(_verifyUrl(url).then((verified) {
            if (!verified) {
              AppLogger.log('Background verification failed for $videoId', name: 'YoutubeRemoteDataSource');
            }
          }));
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
    
    final prefs = await SharedPreferences.getInstance();
    final explicitFilter = prefs.getString('explicitFilter') ?? 'both';
    if (explicitFilter == 'clean') {
      searchQuery = '$searchQuery clean';
    } else if (explicitFilter == 'explicit') {
      searchQuery = '$searchQuery explicit';
    }
    
    final results = await _yt.search.search(searchQuery);
    final tracks = <TrackModel>[];
    
    void addVideos(Iterable videos) {
      for (final video in videos) {
        String author = video.author;
        String? album;
        if (author.endsWith(' - Topic')) {
          author = author.replaceAll(' - Topic', '');
        }
        
        tracks.add(TrackModel(
          id: video.id.value,
          title: video.title,
          author: cleanArtistName(author),
          album: album,
          durationSeconds: video.duration?.inSeconds,
          thumbnailUrl: video.thumbnails.mediumResUrl,
          index: tracks.length,
        ));
      }
    }

    addVideos(results);

    // Fetch up to 2 additional pages to ensure >20 results
    try {
      var currentPage = results;
      for (int i = 0; i < 2; i++) {
        final nextPage = await currentPage.nextPage();
        if (nextPage != null && nextPage.isNotEmpty) {
          addVideos(nextPage);
          currentPage = nextPage;
        } else {
          break;
        }
      }
    } catch (_) {}

    return tracks;
  }

  Future<List<TrackModel>> searchTracks(String query) async {
    // Pagination: `dart_ytmusic_api` 1.3.6's `searchSongs`
    // signature is `(String query)` only — there is no
    // `limit`/`offset` parameter and no continuation-token
    // accessor. The upstream response is capped at the
    // library's default page size; the UI's
    // infinite-scroll handler therefore re-invokes this
    // method with a refined query rather than paging the
    // same query. If a future version exposes pagination,
    // thread the `limit`/`page` arguments through here.
    
    var searchQuery = query;
    final prefs = await SharedPreferences.getInstance();
    final explicitFilter = prefs.getString('explicitFilter') ?? 'both';
    if (explicitFilter == 'clean') {
      searchQuery = '$searchQuery clean';
    } else if (explicitFilter == 'explicit') {
      searchQuery = '$searchQuery explicit';
    }

    final results = await _ytMusic.searchSongs(searchQuery);
    final tracks = <TrackModel>[];

    for (var i = 0; i < results.length; i++) {
      final song = results[i];
      tracks.add(TrackModel(
        id: song.videoId,
        title: song.name,
        author: cleanArtistName(song.artist.name),
        album: song.album?.name,
        durationSeconds: song.duration,
        thumbnailUrl: rewriteThumbnailSize(song.thumbnails.lastOrNull?.url),
        index: i,
      ));
    }

    // Removed YoutubeExplode generic search fallback to keep tracks pure YT Music.

    return tracks;
  }

  Future<List<Album>> searchAlbums(String query) async {
    // Pagination: `dart_ytmusic_api` 1.3.6's `searchAlbums`
    // signature is `(String query)` only — no
    // `limit`/`offset` and no continuation-token
    // accessor. Same constraint as `searchTracks` above.
    final results = await _ytMusic.searchAlbums(query);
    return results.map((a) => Album(
      id: a.albumId, // We use albumId to fetch album tracks later
      title: a.name,
      artistName: a.artist.name,
      year: a.year?.toString(),
      thumbnailUrl: rewriteThumbnailSize(a.thumbnails.lastOrNull?.url),
    )).toList();
  }

  Future<List<Artist>> searchArtists(String query) async {
    // Pagination: `dart_ytmusic_api` 1.3.6's `searchArtists`
    // signature is `(String query)` only — no
    // `limit`/`offset` and no continuation-token
    // accessor. Same constraint as `searchTracks` above.
    final results = await _ytMusic.searchArtists(query);
    return results.map((a) => Artist(
      id: a.artistId,
      name: a.name,
      thumbnailUrl: rewriteThumbnailSize(a.thumbnails.lastOrNull?.url),
    )).toList();
  }

  Future<List<PlaylistModel>> searchPlaylists(String query) async {
    // Pagination: `dart_ytmusic_api` 1.3.6's `searchPlaylists`
    // signature is `(String query)` only — no
    // `limit`/`offset` and no continuation-token
    // accessor. Same constraint as `searchTracks` above.
    final results = await _ytMusic.searchPlaylists(query);
    return results.map((p) => PlaylistModel(
      id: p.playlistId,
      title: p.name,
      author: cleanArtistName(p.artist.name),
      thumbnailUrl: rewriteThumbnailSize(p.thumbnails.lastOrNull?.url),
      videoCount: 0,
    )).toList();
  }

  Future<ytm_types.AlbumFull> getAlbum(String albumId) async {
    return await _ytMusic.getAlbum(albumId);
  }

  Future<ytm_types.ArtistFull> getArtist(String artistId) async {
    return await _ytMusic.getArtist(artistId);
  }

  Future<List<ytm_types.SongDetailed>> getArtistSongs(String artistId) async {
    return await _ytMusic.getArtistSongs(artistId);
  }

  Future<ytm_types.PlaylistFull> getPlaylistFull(String playlistId) async {
    return await _ytMusic.getPlaylist(playlistId);
  }

  Future<List<ytm_types.UpNextsDetails>> getUpNexts(String videoId) async {
    return await _ytMusic.getUpNexts(videoId);
  }

  Future<List<ytm_types.HomeSection>> getHomeSections() async {
    return await _ytMusic.getHomeSections();
  }

  void setGl(String code) {
    _ytMusic.config['GL'] = code;
    AppLogger.log('GL set to $code on live YTMusic instance', name: 'YoutubeRemoteDataSource');
  }

  void dispose() {
    _yt.close();
  }
}
