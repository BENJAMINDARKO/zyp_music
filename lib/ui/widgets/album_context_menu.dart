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
      useRootNavigator: true,
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
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Album Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: Row(
                      children: [
                        if (album.thumbnailUrl != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              rewriteThumbnailSize(album.thumbnailUrl),
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(PhosphorIconsRegular.discoBall, color: Colors.white54, size: 56),
                            ),
                          )
                        else
                          Icon(PhosphorIconsRegular.discoBall, color: Colors.white54, size: 56),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                album.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              if (album.artistName != null)
                                Text(
                                  album.artistName!,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Section 1: Playback Actions
                  AppleMusicSheet.buildSection(context, [
                    AppleMusicSheet.buildMenuItem(
                      context,
                      'Start Auto DJ',
                      PhosphorIconsRegular.sparkle,
                      () => AutoDJModePicker.show(sheetContext),
                      subtitle: 'Pick a mode — Off, Shuffle Library, Similar Songs...',
                    ),
                    AppleMusicSheet.buildMenuItem(
                      context,
                      'Add to Queue',
                      PhosphorIconsRegular.playlist,
                      () {
                        final player = sheetContext.read<PlayerProvider>();
                        player.appendToQueue(tracks);
                        Navigator.pop(sheetContext);
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          SnackBar(content: Text('Added ${tracks.length} track(s) to queue')),
                        );
                      },
                      subtitle: 'Append every track to current queue',
                    ),
                  ]),

                  // Section 2: Favourites and Downloads
                  Consumer2<PlaylistProvider, DownloadProvider>(
                    builder: (context, playlistProvider, downloadProvider, _) {
                      final isFav = playlistProvider.isAlbumFavorite(album.id);
                      final isExported = downloadProvider.isAlbumExported(album);
                      final isExporting = downloadProvider.isAlbumExporting(album);

                      final list = <Widget>[];

                      // Favorite Album
                      list.add(AppleMusicSheet.buildMenuItem(
                        context,
                        'Favorite Album',
                        isFav ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                        () {
                          playlistProvider.toggleFavoriteAlbum(album);
                          Navigator.pop(sheetContext);
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            SnackBar(
                              content: Text(isFav ? 'Removed ${album.title} from favorites' : 'Added ${album.title} to favorites'),
                            ),
                          );
                        },
                        iconColor: isFav ? Colors.red : Colors.white,
                      ));

                      // Export Album
                      Widget trailingIcon;
                      if (isExported) {
                        trailingIcon = const Icon(PhosphorIconsFill.thumbsUp, color: Colors.green);
                      } else if (isExporting) {
                        trailingIcon = const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.green)),
                        );
                      } else {
                        trailingIcon = Icon(PhosphorIconsRegular.thumbsUp, color: Colors.white.withOpacity(0.7));
                      }

                      list.add(ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        title: const Text(
                          'Export Album to Folder',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: Colors.white),
                        ),
                        subtitle: Text(
                          'Save all tracks as .m4a with album art to external folder',
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                        ),
                        trailing: trailingIcon,
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
                      ));

                      return AppleMusicSheet.buildSection(context, list);
                    },
                  ),

                  // Section 3: Cache Management
                  Consumer<DownloadProvider>(
                    builder: (context, downloadProvider, _) {
                      if (!downloadProvider.isAlbumCached(album)) {
                        return const SizedBox.shrink();
                      }
                      return AppleMusicSheet.buildSection(context, [
                        AppleMusicSheet.buildMenuItem(
                          context,
                          'Remove from Cache',
                          PhosphorIconsRegular.trash,
                          () async {
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
                          destructive: true,
                          subtitle: 'Frees local storage for every cached track in this album',
                        ),
                      ]);
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
