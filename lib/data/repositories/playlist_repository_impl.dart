import 'dart:async';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/video.dart';
import '../../domain/entities/album.dart';
import '../../domain/entities/artist.dart';
import '../../domain/repositories/audio_repository.dart';
import '../../domain/repositories/playlist_repository.dart';
import '../datasources/local/playlist_database.dart';
import '../datasources/remote/youtube_remote_datasource.dart';
import '../models/playlist_model.dart';
import '../models/video_model.dart';
import '../../core/services/audio_cache_service.dart';
import '../../core/utils/normalise.dart';
import '../../core/utils/app_logger.dart';

class PlaylistRepositoryImpl implements PlaylistRepository {
  final YoutubeRemoteDataSource remoteDataSource;
  final PlaylistDatabase localDatabase;

  /// Optional reference to the audio repository, used to fire a
  /// background lyrics fetch + validation when a track is favorited.
  /// Spec §1: every track that gets cached (including via the favorite
  /// path) must run the structural lyrics validation pass.
  final AudioRepository? _audioRepository;

  /// Optional handle to the audio cache service. When supplied, the
  /// favorite path runs the Hive-to-SQLite cache migration hook so a
  /// track that is already sitting in the transient cache (because it
  /// was pre-buffered or favorited earlier) gets registered in the
  /// permanent library without forcing a duplicate re-download.
  final AudioCacheService? _audioCacheService;

  PlaylistRepositoryImpl({
    required this.remoteDataSource,
    required this.localDatabase,
    AudioRepository? audioRepository,
    AudioCacheService? audioCacheService,
  })  : _audioRepository = audioRepository,
        _audioCacheService = audioCacheService;

  @override
  Future<Playlist> getPlaylist(String playlistId) async {
    if (playlistId.startsWith('local_')) {
      final localPlaylist = await getCachedPlaylist(playlistId);
      if (localPlaylist != null) {
        return localPlaylist;
      }
      throw Exception('Local playlist not found');
    }

    // Prefer local cache if the playlist is already imported/saved
    final cached = await getCachedPlaylist(playlistId);
    if (cached != null && cached.tracks.isNotEmpty) {
      return cached;
    }

    try {
      final playlistModel = await remoteDataSource.getPlaylist(playlistId);
      await localDatabase.insertPlaylist(playlistModel);
      final trackModels = playlistModel.tracks;
      await localDatabase.insertTracks(playlistId, trackModels);
      return playlistModel.toEntity();
    } catch (e) {
      if (cached != null) {
        return cached;
      }
      rethrow;
    }
  }

  @override
  Future<Playlist> getFromUrl(String input) async {
    final trimmed = input.trim();

    final videoId = _parseVideoId(trimmed);
    final playlistId = _parsePlaylistId(trimmed);

    if (playlistId != null) {
      final playlist = await remoteDataSource.getPlaylist(playlistId);
      await localDatabase.insertPlaylist(playlist);
      await localDatabase.insertTracks(playlist.id, playlist.tracks);
      return playlist.toEntity();
    }

    if (videoId != null) {
      final track = await remoteDataSource.getVideo(videoId);
      final playlist = Playlist(
        id: videoId,
        title: track.title,
        author: track.author,
        thumbnailUrl: track.thumbnailUrl,
        videoCount: 1,
        tracks: [track.toEntity()],
      );
      await localDatabase.insertPlaylist(PlaylistModel(
        id: playlist.id,
        title: playlist.title,
        thumbnailUrl: playlist.thumbnailUrl,
        author: playlist.author,
        videoCount: 1,
      ));
      await localDatabase.insertTrack(playlist.id, TrackModel(
        id: track.id,
        title: track.title,
        thumbnailUrl: track.thumbnailUrl,
        durationSeconds: track.durationSeconds,
        author: track.author,
        index: 0,
      ));
      return playlist;
    }

    throw Exception('Could not parse YouTube URL or ID: $input');
  }

  String? _parseVideoId(String input) {
    final patterns = [
      RegExp(r'(?:youtube\.com/watch\?.*v=)([a-zA-Z0-9_-]{11})'),
      RegExp(r'(?:youtu\.be/)([a-zA-Z0-9_-]{11})'),
      RegExp(r'(?:youtube\.com/shorts/)([a-zA-Z0-9_-]{11})'),
      RegExp(r'(?:m\.youtube\.com/watch\?.*v=)([a-zA-Z0-9_-]{11})'),
      RegExp(r'^([a-zA-Z0-9_-]{11})$'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(input);
      if (match != null) return match.group(1);
    }
    return null;
  }

  String? _parsePlaylistId(String input) {
    final patterns = [
      RegExp(r'(?:list=)([a-zA-Z0-9_-]+)'),
      RegExp(r'^([a-zA-Z0-9_-]{13,})$'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(input);
      if (match != null) return match.group(1);
    }
    return null;
  }

  @override
  Future<List<Playlist>> getSavedPlaylists() async {
    final models = await localDatabase.getAllPlaylists();
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<void> savePlaylist(Playlist playlist) async {
    await localDatabase.insertPlaylist(PlaylistModel(
      id: playlist.id,
      title: playlist.title,
      description: playlist.description,
      thumbnailUrl: playlist.thumbnailUrl,
      author: playlist.author,
      videoCount: playlist.tracks.length,
    ));
    await localDatabase.insertTracks(
      playlist.id,
      playlist.tracks.map((t) => TrackModel(
        id: t.id,
        title: t.title,
        thumbnailUrl: t.thumbnailUrl,
        durationSeconds: t.duration?.inSeconds,
        author: t.author,
        index: t.index,
      )).toList(),
    );
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    await localDatabase.deletePlaylist(playlistId);
  }

  @override
  Future<void> renamePlaylist(String playlistId, String newTitle) async {
    await localDatabase.renamePlaylist(playlistId, newTitle);
  }

  @override
  @override
  Future<void> saveTrack(String playlistId, Track track) async {
    await localDatabase.insertTrack(playlistId, TrackModel(
      id: track.id,
      title: track.title,
      thumbnailUrl: track.thumbnailUrl,
      durationSeconds: track.duration?.inSeconds,
      author: track.author,
      index: track.index,
    ));
  }

  @override
  Future<void> saveLocalFileTrack(String playlistId, Track track, String filePath) async {
    final trackModel = TrackModel(
      id: track.id,
      title: track.title,
      thumbnailUrl: track.thumbnailUrl,
      durationSeconds: track.duration?.inSeconds,
      author: track.author,
      album: track.album,
      albumArtist: track.albumArtist,
      year: track.year,
      index: track.index,
      source: track.source,
    );
    await localDatabase.insertTrack(playlistId, trackModel);
    await localDatabase.markTrackDownloaded(
      track.id,
      playlistId,
      filePath,
      title: track.title,
      thumbnailUrl: track.thumbnailUrl,
      durationSeconds: track.duration?.inSeconds,
      author: track.author,
      album: track.album,
      albumId: track.albumId,
      year: track.year,
    );
  }

  @override
  Future<void> saveTracks(String playlistId, List<Track> tracks) async {
    final models = tracks.map((track) => TrackModel(
      id: track.id,
      title: track.title,
      thumbnailUrl: track.thumbnailUrl,
      durationSeconds: track.duration?.inSeconds,
      author: track.author,
      index: track.index,
    )).toList();
    await localDatabase.insertTracks(playlistId, models);
  }

  @override
  Future<void> updatePlaylistTitle(String id, String newTitle) async {
    await localDatabase.updatePlaylistTitle(id, newTitle);
  }

  @override
  Future<void> removeTrack(String playlistId, String trackId) async {
    await localDatabase.removeTrack(playlistId, trackId);
  }

  @override
  Future<void> updateTrackInPlaylist(String playlistId, String oldTrackId, Track newTrack) async {
    await localDatabase.updateTrackInPlaylist(
      playlistId,
      oldTrackId,
      TrackModel(
        id: newTrack.id,
        title: newTrack.title,
        thumbnailUrl: newTrack.thumbnailUrl,
        durationSeconds: newTrack.duration?.inSeconds,
        author: newTrack.author,
        index: newTrack.index,
      ),
    );
  }

  @override
  Future<void> reorderTracks(
      String playlistId, List<String> trackIdsInOrder) async {
    await localDatabase.reorderTracks(playlistId, trackIdsInOrder);
  }

  @override
  Future<void> toggleFavorite(Track track) async {
    final wasFavorite = await localDatabase.isTrackFavorite(track.id);
    await localDatabase.toggleFavoriteTrack(TrackModel(
      id: track.id,
      title: track.title,
      thumbnailUrl: track.thumbnailUrl,
      durationSeconds: track.duration?.inSeconds,
      author: track.author,
      index: track.index,
    ));
    // Spec §1: when a track is favorited the caching service must also
    // run the structural lyrics validation. Fire-and-forget — the
    // favorite toggle must not block on a network lyrics round-trip,
    // and a failed lyrics fetch must not roll back the favorite.
    final repo = _audioRepository;
    if (repo != null) {
      unawaited(repo.preloadTrackLyrics(track));
    }
    // Hive-to-SQLite cache migration hook. When the user is *adding*
    // the track as a favorite (not removing it), the migration has
    // two branches:
    //
    //   • If the Hive transient cache already has the audio file
    //     (the True branch in the cache migration spec), mirror the
    //     tracking record into the permanent SQLite library, then
    //     gently evict the Hive entry.
    //   • If the Hive box has no record (the False branch), fire the
    //     independent background downloader with the
    //     "writeToLibraryOnSuccess" flag set so the verified success
    //     token is committed to SQLite once the network fetch lands.
    final cache = _audioCacheService;
    if (!wasFavorite && cache != null) {
      unawaited(_handleFavoritedTrack(track, cache));
    }
  }

  /// Internal helper for [toggleFavorite] that runs the spec's
  /// two-branch cache migration: try the True branch first, and if it
  /// does not fire, fall through to the False branch.
  Future<void> _handleFavoritedTrack(Track track, AudioCacheService cache) async {
    final migrated = await cache.migrateToLibrary(track);
    if (migrated) return;
    // False branch: files are missing. Fire the decoupled
    // background downloader so the verified success token gets
    // written straight into SQLite once complete.
    await cache.downloadTrackIndependent(
      track,
      playlistId: 'favorites',
      writeToLibraryOnSuccess: true,
    );
  }

  @override
  Future<bool> isFavorite(String trackId) async {
    return localDatabase.isTrackFavorite(trackId);
  }

  @override
  Future<Set<String>> getFavoriteIds() async {
    return localDatabase.getFavoriteTrackIds();
  }

  @override
  Future<List<Track>> getFavoriteTracks() async {
    final models = await localDatabase.getFavoriteTracks();
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<void> toggleFavoriteAlbum(Album album) async {
    final wasFavorite = await localDatabase.isAlbumFavorite(album.id);
    await localDatabase.toggleFavoriteAlbum(
      album.id,
      album.title,
      album.thumbnailUrl,
      album.artistName,
      album.year,
    );
    // Spec §3 album array processing: when the user is *adding* the
    // album as a favorite, run the two-branch cache migration for
    // every track in the album. Tracks already in the Hive transient
    // cache are migrated to SQLite (True branch); tracks that are
    // missing are handed to the concurrent album downloader (False
    // branch) so each one is processed through the decoupled
    // background downloader simultaneously via Future.wait().
    final cache = _audioCacheService;
    if (!wasFavorite && cache != null) {
      unawaited(_handleFavoritedAlbum(album, cache));
    }
  }

  /// Internal helper for [toggleFavoriteAlbum] that runs the spec's
  /// two-branch album-level cache migration: migrate every track the
  /// Hive box has, then concurrently download the rest.
  Future<void> _handleFavoritedAlbum(Album album, AudioCacheService cache) async {
    final missing = await cache.migrateAlbumToLibrary(album);
    if (missing.isEmpty) return;
    // False branch for the surviving tracks: kick off the
    // Future.wait()-driven album downloader with
    // writeToLibraryOnSuccess so each completed download gets
    // written into SQLite.
    await cache.downloadEntireAlbum(
      Album(
        id: album.id,
        title: album.title,
        artistName: album.artistName,
        year: album.year,
        thumbnailUrl: album.thumbnailUrl,
        tracks: missing,
      ),
      writeToLibraryOnSuccess: true,
    );
  }

  @override
  Future<bool> isAlbumFavorite(String albumId) async {
    return localDatabase.isAlbumFavorite(albumId);
  }

  @override
  Future<List<Album>> getFavoriteAlbums() async {
    final maps = await localDatabase.getFavoriteAlbums();
    return maps.map((m) => Album(
      id: m['id'],
      title: m['title'],
      thumbnailUrl: m['thumbnailUrl'],
      artistName: m['artistName'],
      year: m['year'],
      tracks: const [],
    )).toList();
  }

  @override
  Future<void> toggleFavoriteArtist(Artist artist) async {
    await localDatabase.toggleFavoriteArtist(
      artist.id,
      artist.name,
      artist.thumbnailUrl,
    );
  }

  @override
  Future<bool> isArtistFavorite(String artistId) async {
    return localDatabase.isArtistFavorite(artistId);
  }

  @override
  Future<List<Artist>> getFavoriteArtists() async {
    final maps = await localDatabase.getFavoriteArtists();
    return maps.map((m) => Artist(
      id: m['id'],
      name: m['name'],
      thumbnailUrl: m['thumbnailUrl'],
    )).toList();
  }

  bool _isOfficialVideoOrSimilar(Track track) {
    final title = track.title.toLowerCase();
    return title.contains('official audio') ||
           title.contains('official video') ||
           title.contains('visualizer') ||
           title.contains('lyric video');
  }

  @override
  Future<List<Track>> search(String query) async {
    // "Other" tab shows standard YT search which includes official videos/visualizers
    try {
      final models = await remoteDataSource.search(query);
      final tracks = models.map((m) => m.toEntity().copyWith(source: TrackSource.youtube)).toList();
      return _deduplicateTracks(tracks);
    } catch (_) {
      return <Track>[];
    }
  }

  @override
  Future<List<Track>> searchTracks(String query) async {
    try {
      final models = await remoteDataSource.searchTracks(query);
      return models
          .map((m) => m.toEntity().copyWith(source: TrackSource.youtube_music))
          .where((t) => !_isOfficialVideoOrSimilar(t))
          .toList();
    } catch (e) {
      AppLogger.log('YouTube searchTracks failed for "$query": $e', name: 'PlaylistRepository');
      return <Track>[];
    }
  }

  List<Track> _deduplicateTracks(List<Track> tracks) {
    final Map<String, Track> unified = {};
    for (final track in tracks) {
      final normTitle = normalise(track.title);
      final normArtist = normalise(track.author ?? '');

      var foundMatch = false;
      for (final key in unified.keys) {
        final existing = unified[key]!;
        final existingNormTitle = normalise(existing.title);
        final existingNormArtist = normalise(existing.author ?? '');

        if (existingNormTitle == normTitle && existingNormArtist == normArtist) {
          // C1: `null` duration means "unknown" (live streams, unlisted
          // videos, etc.) — treat the same as the original code's `0`
          // sentinel for "trust the title/artist match without
          // cross-checking duration".
          final existingDur = existing.duration?.inSeconds;
          final trackDur = track.duration?.inSeconds;
          final diff = (existingDur == null || trackDur == null)
              ? 0
              : (existingDur - trackDur).abs();
          if (diff <= 5 ||
              existingDur == null ||
              existingDur == 0 ||
              trackDur == null ||
              trackDur == 0) {
            // Merge source
            final newSourceRef = SourceRef(
              provider: track.source,
              streamId: track.id,
              quality: 'adaptive',
            );
            existing.sources.add(newSourceRef);
            foundMatch = true;
            break;
          }
        }
      }

      if (!foundMatch) {
        final newSources = <SourceRef>[
          SourceRef(
            provider: track.source,
            streamId: track.id,
            quality: 'adaptive',
          )
        ];
        unified[track.id] = track.copyWith(
          id: 'unified_${track.id}',
          sources: newSources,
        );
      }
    }

    return unified.values.toList();
  }

  @override
  Future<List<Album>> searchAlbums(String query) async {
    return await remoteDataSource.searchAlbums(query);
  }

  @override
  Future<List<Artist>> searchArtists(String query) async {
    return await remoteDataSource.searchArtists(query);
  }

  @override
  Future<List<Playlist>> searchPlaylists(String query) async {
    final models = await remoteDataSource.searchPlaylists(query);
    return models.map((m) => Playlist(
      id: m.id,
      title: m.title,
      author: m.author,
      thumbnailUrl: m.thumbnailUrl,
      videoCount: 0,
      tracks: const [],
    )).toList();
  }

  @override
  Future<Album> getAlbum(String albumId) async {
    try {
      final a = await remoteDataSource.getAlbum(albumId);
      return Album(
        id: a.playlistId,
        title: a.name,
        artistName: a.artist.name,
        year: a.year?.toString(),
        thumbnailUrl: a.thumbnails.lastOrNull?.url,
        tracks: a.songs.map((s) => Track(
          id: s.videoId,
          title: s.name,
          thumbnailUrl: s.thumbnails.lastOrNull?.url,
          // C1: preserve null. `s.duration` is nullable from
          // the YouTube Music API (live streams, unlisted).
          // Coercing to `0` would render as `0:00` in the UI.
          duration: s.duration == null
              ? null
              : Duration(seconds: s.duration!),
          author: s.artist.name,
          albumId: s.album?.albumId,
          index: 0,
        )).toList(),
      );
    } catch (e) {
      // If the ID is actually a playlist ID, fetching it as an album throws.
      // This frequently occurs when tapping singles or auto-generated albums.
      // We gracefully fallback to fetching it as a playlist.
      final p = await remoteDataSource.getPlaylist(albumId);
      return Album(
        id: p.id,
        title: p.title,
        artistName: p.author,
        year: '',
        thumbnailUrl: p.thumbnailUrl,
        tracks: p.tracks.map((t) => t.toEntity()).toList(),
      );
    }
  }

  @override
  Future<Artist> getArtist(String artistId) async {
    final a = await remoteDataSource.getArtist(artistId);
    return Artist(
      id: a.artistId,
      name: a.name,
      thumbnailUrl: a.thumbnails.lastOrNull?.url,
      albums: a.topAlbums.map((al) => Album(
        id: al.playlistId,
        title: al.name,
        artistName: a.name,
        year: al.year?.toString(),
        thumbnailUrl: al.thumbnails.lastOrNull?.url,
      )).toList(),
      topTracks: a.topSongs.map((s) => Track(
        id: s.videoId,
        title: s.name,
        thumbnailUrl: s.thumbnails.lastOrNull?.url,
        // C1: preserve null. See sibling block above.
        duration: s.duration == null
            ? null
            : Duration(seconds: s.duration!),
        author: a.name,
        albumId: s.album?.albumId,
        index: 0,
      )).toList(),
    );
  }

  @override
  Future<List<Track>> getEditorsPicks() async {
    final models = await remoteDataSource.search("Top Hits");
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<List<Track>> getCachedTracks(String playlistId) async {
    final models = await localDatabase.getTracks(playlistId);
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<Playlist?> getCachedPlaylist(String playlistId) async {
    final playlists = await localDatabase.getAllPlaylists();
    final match = playlists.where((p) => p.id == playlistId).firstOrNull;
    if (match == null) return null;
    final tracks = await getCachedTracks(playlistId);
    return Playlist(
      id: match.id,
      title: match.title,
      description: match.description,
      thumbnailUrl: match.thumbnailUrl,
      author: match.author,
      videoCount: match.videoCount,
      tracks: tracks,
    );
  }
}
