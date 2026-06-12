import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/album.dart';
import '../../domain/entities/video.dart';
import '../../presentation/providers/player_provider.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/download_provider.dart';
import 'auto_dj_mode_picker.dart';
import 'apple_music_sheet.dart';
import "../../core/utils/thumbnail_url.dart";

class AlbumContextMenu {
  static void show(BuildContext context, Album album) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black54,
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
        return AppleMusicSheet(
          child: SafeArea(
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
                            rewriteThumbnailSize(album.thumbnailUrl),
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(PhosphorIconsRegular.discoBall, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), size: 48),
                          ),
                        )
                      else
                        Icon(PhosphorIconsRegular.discoBall, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), size: 48),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              album.title,
                              style: TextStyle(fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (album.artistName != null)
                              Text(
                                album.artistName!,
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
                  title: Text('Start Auto DJ'),
                  subtitle: Text(
                    'Pick a mode — Off, Shuffle Library, Similar Songs, Same Genre, Same Artist, Smart DJ',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), fontSize: 12),
                  ),
                  onTap: () {
                    debugPrint('AlbumContextMenu: Start Auto DJ tapped for album "${album.title}"');
                    AutoDJModePicker.show(sheetContext);
                  },
                ),
                ListTile(
                  leading: Icon(PhosphorIconsRegular.playlist, color: Theme.of(context).colorScheme.onSurface),
                  title: Text('Add to Queue'),
                  subtitle: Text(
                    'Append every track to the current playback list',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), fontSize: 12),
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
                Divider(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.24)),
                Consumer<PlaylistProvider>(
                  builder: (context, provider, _) {
                    final isFav = provider.isAlbumFavorite(album.id);
                    return ListTile(
                      leading: Icon(
                        isFav ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                        color: isFav ? Colors.red : Theme.of(context).colorScheme.onSurface,
                      ),
                      title: Text('Favorite Album'),
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
                Consumer<DownloadProvider>(
                  builder: (context, downloadProvider, _) {
                    final isExported = downloadProvider.isAlbumExported(album);
                    final isExporting = downloadProvider.isAlbumExporting(album);

                    Widget iconWidget;
                    if (isExported) {
                      iconWidget = const Icon(PhosphorIconsFill.thumbsUp, color: Colors.green);
                    } else if (isExporting) {
                      iconWidget = const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.green)),
                      );
                    } else {
                      iconWidget = Icon(PhosphorIconsRegular.thumbsUp, color: Theme.of(context).colorScheme.onSurface);
                    }

                    return ListTile(
                      leading: iconWidget,
                      title: const Text('Export Album to Folder'),
                      subtitle: Text(
                        'Save all tracks as .m4a with album art to external folder',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), fontSize: 12),
                      ),
                      onTap: () {
                        if (!isExported && !isExporting) {
                          downloadProvider.exportAlbum(album);
                          Navigator.pop(sheetContext);
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            SnackBar(content: Text('Exporting album to folder...')),
                          );
                        } else {
                          Navigator.pop(sheetContext);
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(content: Text('Already exported or exporting')),
                          );
                        }
                      },
                    );
                  },
                ),
                Consumer<DownloadProvider>(
                  builder: (context, downloadProvider, _) {
                    if (!downloadProvider.isAlbumCached(album)) {
                      return const SizedBox.shrink();
                    }
                    return ListTile(
                      leading: const Icon(PhosphorIconsRegular.trash, color: Color(0xFFEF4444)),
                      title: const Text(
                        'Remove from Cache',
                        style: TextStyle(color: Color(0xFFEF4444)),
                      ),
                      subtitle: Text(
                        'Frees local storage for every cached track in this album',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), fontSize: 12),
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
          ),
        );
      },
    );
  }
}
