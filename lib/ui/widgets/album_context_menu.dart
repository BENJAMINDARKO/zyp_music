import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/album.dart';
import '../../domain/entities/video.dart';
import '../../presentation/providers/player_provider.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/download_provider.dart';

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
              // Start Auto DJ — slot kept open per the Auto Queue
              // migration spec; functional block moved to the new
              // "Auto Queue" item below.
              ListTile(
                leading: const Icon(Icons.auto_awesome, color: Color(0xFFEAB308)),
                title: const Text('Start Auto DJ', style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  'Coming soon — slot reserved for future logic',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    const SnackBar(content: Text('Start Auto DJ — coming soon')),
                  );
                },
              ),
              // Auto Queue — migrated functional block. Seeds the
              // engine with the supplied album tracks. If the queue is
              // empty, cold-starts from the first album track; otherwise
              // appends the predicted next track after the current one.
              ListTile(
                leading: const Icon(Icons.auto_mode, color: Colors.white),
                title: const Text('Auto Queue', style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  'Automatically queues and appends matching tracks seamlessly to the end of your active queue.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () {
                  final player = sheetContext.read<PlayerProvider>();
                  final seed = tracks.first;
                  if (player.queue.isEmpty) {
                    player.coldStartAutoQueue(seed);
                  } else {
                    player.startAutoQueue(seed);
                  }
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    SnackBar(
                      content: Text(
                        player.isAutoQueueActive
                            ? 'Auto Queue engaged — queue extended'
                            : 'Auto Queue engaged — cold-starting',
                      ),
                    ),
                  );
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
