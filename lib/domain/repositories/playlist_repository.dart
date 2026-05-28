import '../entities/playlist.dart';
import '../entities/video.dart';

abstract class PlaylistRepository {
  Future<Playlist> getPlaylist(String playlistId);
  Future<List<Playlist>> getSavedPlaylists();
  Future<void> savePlaylist(Playlist playlist);
  Future<void> deletePlaylist(String playlistId);
  Future<void> saveTrack(String playlistId, Track track);
  Future<List<Track>> getCachedTracks(String playlistId);
}
