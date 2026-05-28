import '../../domain/entities/playlist.dart';
import '../../domain/entities/video.dart';
import '../../domain/repositories/playlist_repository.dart';
import '../datasources/local/playlist_database.dart';
import '../datasources/remote/youtube_remote_datasource.dart';
import '../models/playlist_model.dart';
import '../models/video_model.dart';

class PlaylistRepositoryImpl implements PlaylistRepository {
  final YoutubeRemoteDataSource remoteDataSource;
  final PlaylistDatabase localDatabase;

  PlaylistRepositoryImpl({
    required this.remoteDataSource,
    required this.localDatabase,
  });

  @override
  Future<Playlist> getPlaylist(String playlistId) async {
    final playlistModel = await remoteDataSource.getPlaylist(playlistId);
    await localDatabase.insertPlaylist(playlistModel);
    final trackModels = playlistModel.tracks;
    await localDatabase.insertTracks(playlistId, trackModels);
    return playlistModel.toEntity();
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
        durationSeconds: t.duration.inSeconds,
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
  Future<void> saveTrack(String playlistId, Track track) async {
    await localDatabase.insertTrack(playlistId, TrackModel(
      id: track.id,
      title: track.title,
      thumbnailUrl: track.thumbnailUrl,
      durationSeconds: track.duration.inSeconds,
      author: track.author,
      index: track.index,
    ));
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
