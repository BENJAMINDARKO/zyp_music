import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/services/hybrid_cache_service.dart';
import '../../domain/entities/video.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../../presentation/providers/download_provider.dart';
import 'auto_dj_mode_picker.dart';
import 'playlist_picker_dialog.dart';
import 'apple_music_sheet.dart';
import "../../core/utils/thumbnail_url.dart";

class TrackContextMenu {
  static void show(BuildContext context, Track track) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (sheetContext) {
        return AppleMusicSheet(
          child: SafeArea(
            child: SingleChildScrollView(
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
                              rewriteThumbnailSize(track.thumbnailUrl),
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(PhosphorIconsRegular.musicNote, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), size: 48),
                            ),
                          )
                        else
                          Icon(PhosphorIconsRegular.musicNote, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), size: 48),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title,
                                style: TextStyle(fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (track.author != null)
                                Text(
                                  track.author!,
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.70), fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.24)),
                  ListTile(
                    leading: const Icon(PhosphorIconsRegular.sparkle, color: Color(0xFFEAB308)),
                    title: Text('Start Auto DJ', style: TextStyle(fontWeight: FontWeight.normal)),
                    subtitle: Text(
                      'Pick a mode — Off, Shuffle Library, Similar Songs, Same Genre, Same Artist, Smart DJ',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), fontSize: 12),
                    ),
                    onTap: () {
                      debugPrint('TrackContextMenu: Start Auto DJ tapped for ${track.title}');
                      AutoDJModePicker.show(sheetContext);
                    },
                  ),
                  ListTile(
                    leading: Icon(PhosphorIconsRegular.playlist, color: Theme.of(context).colorScheme.onSurface),
                    title: Text('Add to Queue'),
                    subtitle: Text(
                      'Append to the current playback list',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), fontSize: 12),
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
                  Divider(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.24)),
                  ListTile(
                    leading: Icon(PhosphorIconsRegular.playlist, color: Theme.of(context).colorScheme.onSurface),
                    title: Text('Add to Playlist'),
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
                          isFav ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                          color: isFav ? Colors.red : Theme.of(context).colorScheme.onSurface,
                        ),
                        title: Text('Favorite'),
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
                          isDownloaded ? PhosphorIconsFill.checkCircle : PhosphorIconsRegular.downloadSimple,
                          color: isDownloaded ? Colors.green : Theme.of(context).colorScheme.onSurface,
                        ),
                        title: Text('Download'),
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
                  Consumer2<DownloadProvider, HybridCacheService>(
                    builder: (context, downloadProvider, hybridCache, _) {
                      final isCached = hybridCache.isCached(track.id) ||
                          hybridCache.isDownloadedInSqlite(track.id) ||
                          downloadProvider.downloadedTrackIds.contains(track.id);
                      if (!isCached) return const SizedBox.shrink();
                      return ListTile(
                        leading: const Icon(PhosphorIconsRegular.trash, color: Color(0xFFEF4444)),
                        title: const Text(
                          'Remove from Cache',
                          style: TextStyle(color: Color(0xFFEF4444)),
                        ),
                        subtitle: Text(
                          'Frees local storage; track will re-download next time',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), fontSize: 12),
                        ),
                        onTap: () async {
                          Navigator.pop(sheetContext);
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
            ),
          ),
        );
      },
    );
  }
}
