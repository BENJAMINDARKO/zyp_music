import 'package:flutter/foundation.dart';
import '../../core/services/jump_back_in_service.dart';
import '../../data/datasources/local/playlist_database.dart';
import '../../domain/entities/video.dart';
import '../providers/player_provider.dart';
import '../providers/playlist_provider.dart';

class JumpBackInProvider extends ChangeNotifier {
  final PlaylistDatabase _database;
  final PlayerProvider _playerProvider;
  final PlaylistProvider _playlistProvider;

  List<JumpBackInRecommendation> _recommendations = [];
  bool _isLoading = false;

  List<JumpBackInRecommendation> get recommendations => _recommendations;
  List<JumpBackInRecommendation> get compactItems =>
      _recommendations.take(4).toList();
  bool get isLoading => _isLoading;
  bool get hasData => _recommendations.isNotEmpty;

  JumpBackInProvider({
    required PlaylistDatabase database,
    required PlayerProvider playerProvider,
    required PlaylistProvider playlistProvider,
  })  : _database = database,
        _playerProvider = playerProvider,
        _playlistProvider = playlistProvider;

  Future<void> load({String? currentGenre}) async {
    _isLoading = true;
    notifyListeners();

    try {
      final candidates = <String, JumpBackInCandidate>{};
      final historyRows = await _database.rawQuery(
        'SELECT track_id, artist_name, primary_genre, '
        'title, thumbnail_url, COUNT(*) as plays, '
        'MAX(timestamp) as last_played '
        'FROM dj_listening_history GROUP BY track_id '
        'ORDER BY plays DESC LIMIT 50',
      );

      final favourites = _playlistProvider.favoriteTracks;
      final favouriteIds = favourites.map((t) => t.id).toSet();
      final recentlyPlayed = _playerProvider.recentlyPlayed;

      for (final row in historyRows) {
        final trackId = row['track_id'] as String? ?? '';
        if (trackId.isEmpty || candidates.containsKey(trackId)) continue;
        final title = row['title'] as String? ?? 'Unknown';
        final artist = row['artist_name'] as String?;
        final genre = row['primary_genre'] as String?;
        final thumbnailUrl = row['thumbnail_url'] as String?;
        final plays = (row['plays'] as int?) ?? 0;
        final lastPlayedMs = row['last_played'] as int?;
        final isFav = favouriteIds.contains(trackId);

        candidates[trackId] = JumpBackInCandidate(
          id: trackId,
          type: JumpBackInType.track,
          title: title,
          subtitle: artist ?? 'Unknown artist',
          genre: genre,
          artist: artist,
          thumbnailUrl: thumbnailUrl,
          playCount: plays,
          isFavorite: isFav,
          lastPlayed: lastPlayedMs != null
              ? DateTime.fromMillisecondsSinceEpoch(lastPlayedMs)
              : null,
        );
      }

      for (final track in recentlyPlayed) {
        if (candidates.containsKey(track.id)) continue;
        candidates[track.id] = JumpBackInCandidate(
          id: track.id,
          type: JumpBackInType.track,
          title: track.title,
          subtitle: track.author ?? 'Unknown artist',
          thumbnailUrl: track.thumbnailUrl,
          playCount: 1,
          isFavorite: favouriteIds.contains(track.id),
          lastPlayed: DateTime.now(),
        );
      }

      for (final track in favourites) {
        if (candidates.containsKey(track.id)) continue;
        candidates[track.id] = JumpBackInCandidate(
          id: track.id,
          type: JumpBackInType.track,
          title: track.title,
          subtitle: track.author ?? 'Unknown artist',
          thumbnailUrl: track.thumbnailUrl,
          isFavorite: true,
        );
      }

      if (candidates.isEmpty) {
        _recommendations = [];
        _isLoading = false;
        notifyListeners();
        return;
      }

      _recommendations = JumpBackInEngine.score(
        candidates: candidates.values.toList(),
        currentGenre: currentGenre,
      );
    } catch (_) {
      _recommendations = [];
    }

    _isLoading = false;
    notifyListeners();
  }
}

extension on PlaylistDatabase {
  Future<List<Map<String, dynamic>>> rawQuery(String sql) async {
    final db = await database;
    return db.rawQuery(sql);
  }
}
