import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/hybrid_cache_service.dart';
import '../../domain/entities/video.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../../presentation/providers/download_provider.dart';
import 'playlist_picker_dialog.dart';

class TrackContextMenu {
  static void show(BuildContext context, Track track) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    if (track.thumbnailUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          track.thumbnailUrl!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.music_note, color: Colors.white54, size: 48),
                        ),
                      )
                    else
                      const Icon(Icons.music_note, color: Colors.white54, size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (track.author != null)
                            Text(
                              track.author!,
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
              // "Auto Queue" item below. Tapping shows a placeholder
              // toast so the section ordering is preserved.
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
              // Auto Queue — the migrated functional block. If a track
              // is already playing or paused in memory, the existing
              // recommendation engine is engaged and the predicted next
              // track is appended after the current one. If the queue is
              // empty, Auto Queue cold-starts from the seed track (full
              // audio load + lyrics read + play) to eliminate dead-air.
              ListTile(
                leading: const Icon(Icons.auto_mode, color: Colors.white),
                title: const Text('Auto Queue', style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  'Automatically queues and appends matching tracks seamlessly to the end of your active queue.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () {
                  final player = sheetContext.read<PlayerProvider>();
                  player.startAutoQueue(track);
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
              // Add to Queue — appends to the existing queue without
              // engaging Auto Queue. The manual queue is finite; once it
              // ends the player stops.
              ListTile(
                leading: const Icon(Icons.playlist_play, color: Colors.white),
                title: const Text('Add to Queue', style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  'Append to the current playback list',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () {
                  final player = sheetContext.read<PlayerProvider>();
                  player.appendToQueue([track]);
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    const SnackBar(content: Text('Added to queue')),
                  );
                },
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.playlist_add, color: Colors.white),
                title: const Text('Add to Playlist', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showDialog(
                    context: sheetContext,
                    builder: (_) => PlaylistPickerDialog(track: track),
                  );
                },
              ),
              Consumer<PlaylistProvider>(
                builder: (context, provider, _) {
                  final isFav = provider.isFavorite(track.id);
                  return ListTile(
                    leading: Icon(
                      isFav ? Icons.favorite : Icons.favorite_border,
                      color: isFav ? Colors.red : Colors.white,
                    ),
                    title: const Text('Favorite', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      provider.toggleFavorite(track);
                      Navigator.pop(sheetContext);
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        SnackBar(content: Text(isFav ? 'Removed from Favorites' : 'Added to Favorites')),
                      );
                    },
                  );
                },
              ),
              Consumer<DownloadProvider>(
                builder: (context, provider, _) {
                  final isDownloaded = provider.downloadedTrackIds.contains(track.id);
                  return ListTile(
                    leading: Icon(
                      isDownloaded ? Icons.download_done : Icons.download,
                      color: isDownloaded ? Colors.green : Colors.white,
                    ),
                    title: const Text('Download', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      if (!isDownloaded) {
                        provider.downloadTrack(track, 'downloads');
                        Navigator.pop(sheetContext);
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(content: Text('Download started')),
                        );
                      } else {
                        Navigator.pop(sheetContext);
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(content: Text('Already downloaded')),
                        );
                      }
                    },
                  );
                },
              ),
              // Remove from Cache — only rendered when the track is
              // actually held in either the Hive transient tracker or
              // the SQLite library table. Dual-source check matches
              // the spec used by the download icon (see
              // `TrackDownloadIcon._isAlreadyDownloaded` and
              // `HybridCacheService.isCached` / `isDownloadedInSqlite`).
              Consumer2<DownloadProvider, HybridCacheService>(
                builder: (context, downloadProvider, hybridCache, _) {
                  final isCached = hybridCache.isCached(track.id) ||
                      hybridCache.isDownloadedInSqlite(track.id) ||
                      downloadProvider.downloadedTrackIds.contains(track.id);
                  if (!isCached) return const SizedBox.shrink();
                  return ListTile(
                    leading: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                    title: const Text(
                      'Remove from Cache',
                      style: TextStyle(color: Color(0xFFEF4444)),
                    ),
                    subtitle: const Text(
                      'Frees local storage; track will re-download next time',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      // Optimistic UI: show the snackbar first so the
                      // user gets immediate feedback even if the file
                      // delete takes a moment.
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        SnackBar(content: Text('Removing "${track.title}" from cache…')),
                      );
                      await downloadProvider.removeTrackFromCache(track);
                      if (sheetContext.mounted) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          SnackBar(content: Text('Removed "${track.title}" from cache')),
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
