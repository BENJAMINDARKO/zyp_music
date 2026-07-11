import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/services/hybrid_cache_service.dart';
import '../../domain/entities/video.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../../presentation/providers/download_provider.dart';
import '../screens/album_screen.dart';
import '../screens/artist_screen.dart';
import 'auto_dj_mode_picker.dart';
import 'add_to_playlist_modal.dart';
import 'apple_music_sheet.dart';
import "../../core/utils/thumbnail_url.dart";

class TrackContextMenu {
  static Widget _buildQuickAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    Color? iconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 10.0),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: iconColor ?? Colors.white,
              size: 22,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
                  // Track Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: Row(
                      children: [
                        if (track.thumbnailUrl != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              rewriteThumbnailSize(track.thumbnailUrl),
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(PhosphorIconsRegular.musicNote, color: Colors.white54, size: 56),
                            ),
                          )
                        else
                          Icon(PhosphorIconsRegular.musicNote, color: Colors.white54, size: 56),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                track.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              if (track.author != null)
                                Text(
                                  track.author!,
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

                  // Quick Actions Row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Quick Add: + Add
                        _buildQuickAction(
                          context,
                          icon: PhosphorIconsRegular.plus,
                          label: 'Add',
                          onTap: () {
                            final player = sheetContext.read<PlayerProvider>();
                            player.appendToQueue([track]);
                            Navigator.pop(sheetContext);
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(content: Text('Added to queue')),
                            );
                          },
                        ),
                        // Quick Favourite
                        Consumer<PlaylistProvider>(
                          builder: (context, provider, _) {
                            final isFav = provider.isFavorite(track.id);
                            return _buildQuickAction(
                              context,
                              icon: isFav ? PhosphorIconsFill.star : PhosphorIconsRegular.star,
                              label: 'Favourite',
                              iconColor: isFav ? Colors.amber : null,
                              onTap: () {
                                provider.toggleFavorite(
                                  track,
                                  downloadProvider: sheetContext.read<DownloadProvider>(),
                                );
                                Navigator.pop(sheetContext);
                                ScaffoldMessenger.of(sheetContext).showSnackBar(
                                  SnackBar(content: Text(isFav ? 'Removed from Favorites' : 'Added to Favorites')),
                                );
                              },
                            );
                          },
                        ),
                        // Quick Share
                        _buildQuickAction(
                          context,
                          icon: PhosphorIconsRegular.share,
                          label: 'Share',
                          onTap: () {
                            Navigator.pop(sheetContext);
                            Share.share('Check out ${track.title} by ${track.author ?? "Unknown Artist"} on ZYPMusic!\nhttps://youtube.com/watch?v=${track.id}');
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Section 1: Playlist & Queue
                  AppleMusicSheet.buildSection(context, [
                    AppleMusicSheet.buildMenuItem(
                      context,
                      title: 'Add to Playlist',
                      icon: PhosphorIconsRegular.playlist,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        AddToPlaylistModal.show(context, track);
                      },
                    ),
                    AppleMusicSheet.buildMenuItem(
                      context,
                      title: 'Create Station',
                      icon: PhosphorIconsRegular.broadcast,
                      subtitle: 'Start Auto DJ recommended station',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        AutoDJModePicker.show(context);
                      },
                    ),
                    AppleMusicSheet.buildMenuItem(
                      context,
                      title: 'Add to Queue',
                      icon: PhosphorIconsRegular.listPlus,
                      onTap: () {
                        final player = sheetContext.read<PlayerProvider>();
                        player.appendToQueue([track]);
                        Navigator.pop(sheetContext);
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(content: Text('Added to queue')),
                        );
                      },
                    ),
                  ]),

                  // Section 2: Navigation & Metadata
                  AppleMusicSheet.buildSection(context, [
                    AppleMusicSheet.buildMenuItem(
                      context,
                      title: 'Go to Album',
                      icon: PhosphorIconsRegular.disc,
                      subtitle: (track.album != null && track.album!.isNotEmpty) ? track.album : 'Search Album',
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        final provider = context.read<PlaylistProvider>();
                        final query = (track.album != null && track.album!.isNotEmpty)
                            ? track.album!
                            : "${track.title} ${track.author ?? ''}".trim();
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Searching for album...'),
                            duration: Duration(seconds: 2),
                          ),
                        );

                        final res = await provider.searchAlbums(query);
                        if (res.isNotEmpty && context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AlbumScreen(albumId: res.first.id),
                            ),
                          );
                        } else if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Album details not found')),
                          );
                        }
                      },
                    ),
                    if (track.author != null && track.author!.isNotEmpty)
                      AppleMusicSheet.buildMenuItem(
                        context,
                        title: 'Go to Artist',
                        icon: PhosphorIconsRegular.microphone,
                        subtitle: track.author,
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          final provider = context.read<PlaylistProvider>();
                          final artist = await provider.findCorrectArtist(
                            track.author!,
                            track.album,
                          );
                          if (artist != null && context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ArtistScreen(artistId: artist.id),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Artist details not found')),
                            );
                          }
                        },
                      ),
                    AppleMusicSheet.buildMenuItem(
                      context,
                      title: 'View Credits',
                      icon: PhosphorIconsRegular.info,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: const Color(0xFF1E1E1E),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            title: Text(track.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Artist: ${track.author ?? 'Unknown'}', style: const TextStyle(color: Colors.white70)),
                                const SizedBox(height: 6),
                                if (track.album != null) ...[
                                  Text('Album: ${track.album}', style: const TextStyle(color: Colors.white70)),
                                  const SizedBox(height: 6),
                                ],
                                if (track.year != null) ...[
                                  Text('Year: ${track.year}', style: const TextStyle(color: Colors.white70)),
                                  const SizedBox(height: 6),
                                ],
                                Text('Source: ${track.source.name.toUpperCase()}', style: const TextStyle(color: Colors.white70)),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close', style: TextStyle(color: Color(0xFFEAB308))),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    AppleMusicSheet.buildMenuItem(
                      context,
                      title: 'Share Lyrics',
                      icon: PhosphorIconsRegular.quotes,
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        final player = context.read<PlayerProvider>();
                        final lyrics = track.id == player.currentTrack?.id ? player.lyrics : null;
                        if (lyrics != null && lyrics.isNotEmpty) {
                          Share.share('Lyrics for "${track.title}" by ${track.author}:\n\n$lyrics');
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Lyrics not available for this track')),
                          );
                        }
                      },
                    ),
                  ]),

                  // Section 3: Downloads and Storage
                  Consumer2<DownloadProvider, HybridCacheService>(
                    builder: (context, downloadProvider, hybridCache, _) {
                      final isDownloaded = downloadProvider.downloadedTrackIds.contains(track.id);
                      final isExported = downloadProvider.exportedTrackIds.contains(track.id);
                      final isExporting = downloadProvider.activeExports.containsKey(track.id);

                      final list = <Widget>[];

                      // Download Tile
                      list.add(AppleMusicSheet.buildMenuItem(
                        context,
                        title: 'Download',
                        icon: isDownloaded ? PhosphorIconsFill.checkCircle : PhosphorIconsRegular.downloadSimple,
                        iconColor: isDownloaded ? Colors.green : Colors.white,
                        onTap: () {
                          if (!isDownloaded) {
                            downloadProvider.downloadTrack(track, 'downloads');
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
                      ));

                      // Export Tile
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
                          'Export to Folder',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: Colors.white),
                        ),
                        subtitle: Text(
                          'Save as .m4a with album art to external folder',
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                        ),
                        trailing: trailingIcon,
                        onTap: () {
                          if (isExported) {
                            downloadProvider.unexportTrack(track);
                            Navigator.pop(sheetContext);
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(content: Text('Removed from exports')),
                            );
                          } else if (!isExporting) {
                            downloadProvider.exportTrack(track);
                            Navigator.pop(sheetContext);
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(content: Text('Exporting to folder...')),
                            );
                          } else {
                            Navigator.pop(sheetContext);
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(content: Text('Currently exporting')),
                            );
                          }
                        },
                      ));

                      return AppleMusicSheet.buildSection(context, list);
                    },
                  ),

                  // Section 4: Cache Management
                  Consumer2<DownloadProvider, HybridCacheService>(
                    builder: (context, downloadProvider, hybridCache, _) {
                      final isCached = hybridCache.isCached(track.id) ||
                          hybridCache.isDownloadedInSqlite(track.id) ||
                          downloadProvider.downloadedTrackIds.contains(track.id);
                      if (!isCached) return const SizedBox.shrink();
                      return AppleMusicSheet.buildSection(context, [
                        AppleMusicSheet.buildMenuItem(
                          context,
                          title: 'Remove from Cache',
                          icon: PhosphorIconsRegular.trash,
                          textColor: const Color(0xFFEF4444),
                          iconColor: const Color(0xFFEF4444),
                          subtitle: 'Frees local storage; track will re-download next time',
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
                        ),
                      ]);
                    },
                  ),

                  // Section 5: Thumbs Down
                  AppleMusicSheet.buildSection(context, [
                    AppleMusicSheet.buildMenuItem(
                      context,
                      title: 'Suggest Less',
                      icon: PhosphorIconsRegular.thumbsDown,
                      textColor: const Color(0xFFEF4444),
                      iconColor: const Color(0xFFEF4444),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          SnackBar(content: Text('We will recommend less of "${track.title}"')),
                        );
                      },
                    ),
                  ]),

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
