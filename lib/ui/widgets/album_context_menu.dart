import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/album.dart';
import '../../domain/entities/video.dart';
import '../../presentation/providers/player_provider.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/download_provider.dart';
import 'auto_dj_mode_picker.dart';

/// Long-press context menu for an Album card.
///
/// Distinct routing options per the hybrid Auto DJ spec:
/// * **Start Auto DJ** — replaces the active queue with the album tracks
///   and engages the Auto DJ engine so playback continues past the last
///   track on the album.
/// * **Add to Queue** — appends every album track to the active queue
///   without disturbing the currently playing track and without engaging
///   Auto DJ.
class AlbumContextMenu {
  static void show(BuildContext context, Album album) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final tracks = album.tracks.isNotEmpty
            ? album.tracks
            : <Track>[
                Track(
                  id: album.id,
                  title: album.title,
                  author: album.artistName,
                  thumbnailUrl: album.thumbnailUrl,
                  duration: Duration.zero,
                  source: TrackSource.youtube,
                ),
              ];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    if (album.thumbnailUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          album.thumbnailUrl!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.album, color: Colors.white54, size: 48),
                        ),
                      )
                    else
                      const Icon(Icons.album, color: Colors.white54, size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            album.title,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (album.artistName != null)
                            Text(
                              album.artistName!,
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white24),
              // Start Auto DJ — phase 0 binding: opens the Auto DJ mode
              // picker (Off / Shuffle Library / Similar Songs / Same
              // Genre / Same Artist / Smart DJ). The album context menu
              // does not pre-seed the engine with a track — the user
              // picks the mode and the engine arms against whatever
              // track is currently loaded (or has just been queued via
              // the "Add to Queue" tile below). The actual per-mode
              // engine behaviour lands in Phase 1; for now the picker
              // records the choice and lights up the miniplayer /
              // fullscreen AUTODJ icon.
              ListTile(
                leading: const Icon(Icons.auto_awesome, color: Color(0xFFEAB308)),
                title: const Text('Start Auto DJ', style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  'Pick a mode — Off, Shuffle Library, Similar Songs, Same Genre, Same Artist, Smart DJ',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () {
                  debugPrint('AlbumContextMenu: Start Auto DJ tapped for album "${album.title}"');
                  AutoDJModePicker.show(sheetContext);
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_play, color: Colors.white),
                title: const Text('Add to Queue', style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  'Append every track to the current playback list',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () {
                  final player = sheetContext.read<PlayerProvider>();
                  player.appendToQueue(tracks);
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    SnackBar(content: Text('Added ${tracks.length} track(s) to queue')),
                  );
                },
              ),
              const Divider(color: Colors.white24),
              Consumer<PlaylistProvider>(
                builder: (context, provider, _) {
                  final isFav = provider.isAlbumFavorite(album.id);
                  return ListTile(
                    leading: Icon(
                      isFav ? Icons.favorite : Icons.favorite_border,
                      color: isFav ? Colors.red : Colors.white,
                    ),
                    title: const Text('Favorite Album', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      provider.toggleFavoriteAlbum(album);
                      Navigator.pop(sheetContext);
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        SnackBar(
                          content: Text(isFav ? 'Removed ${album.title} from favorites' : 'Added ${album.title} to favorites'),
                        ),
                      );
                    },
                  );
                },
              ),
              // Remove from Cache — iterates over the album's tracks
              // and calls `removeTrackCompletely` for each. Only
              // rendered when the album has at least one track in the
              // Hive tracker, the SQLite library, or the in-memory
              // download mirror.
              Consumer<DownloadProvider>(
                builder: (context, downloadProvider, _) {
                  if (!downloadProvider.isAlbumCached(album)) {
                    return const SizedBox.shrink();
                  }
                  return ListTile(
                    leading: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                    title: const Text(
                      'Remove from Cache',
                      style: TextStyle(color: Color(0xFFEF4444)),
                    ),
                    subtitle: const Text(
                      'Frees local storage for every cached track in this album',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        SnackBar(content: Text('Clearing cache for "${album.title}"…')),
                      );
                      final removed = await downloadProvider.removeAlbumFromCache(album);
                      if (sheetContext.mounted) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          SnackBar(
                            content: Text(
                              removed == 0
                                  ? 'No cached tracks to remove'
                                  : 'Removed $removed track(s) from cache',
                            ),
                          ),
                        );
                      }
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
