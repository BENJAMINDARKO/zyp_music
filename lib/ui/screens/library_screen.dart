import 'dart:io';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/album.dart';
import '../../domain/entities/artist.dart';
import '../../domain/entities/video.dart';
import '../../core/utils/format_duration.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/listening_stats_view.dart';
import 'package:file_picker/file_picker.dart';
import '../../../data/datasources/remote/youtube_remote_datasource.dart';
import '../../domain/entities/video.dart';
import '../widgets/bottom_player.dart';
import '../widgets/downloaded_view.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:audiotags/audiotags.dart';
import 'package:path_provider/path_provider.dart';
import 'playlist_screen.dart';
import 'album_screen.dart';
import 'artist_screen.dart';
import '../../core/services/playlist_scraper_service.dart';
import 'playlist_import_preview_screen.dart';
import '../../presentation/providers/download_provider.dart';
import '../widgets/track_download_icon.dart';
import '../widgets/track_export_icon.dart';
import '../../core/utils/thumbnail_url.dart';
import '../widgets/playing_track_mask.dart';
import '../widgets/explicit_icon.dart';

import '../widgets/global_top_bar.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DefaultTabController(
        length: 6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: Color(0xFFEAB308),
            labelColor: Theme.of(context).colorScheme.onSurface,
            unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
            dividerColor: Color(0xFF2A2A2A),
            tabs: [
              Tab(
                icon: Icon(PhosphorIconsRegular.musicNote, size: 18),
                text: "Tracks",
              ),
              Tab(
                icon: Icon(PhosphorIconsRegular.discoBall, size: 18),
                text: "Albums",
              ),
              Tab(
                icon: Icon(PhosphorIconsRegular.user, size: 18),
                text: "Artists",
              ),
              Tab(
                icon: Icon(PhosphorIconsRegular.playlist, size: 18),
                text: "Playlists",
              ),
              Tab(
                icon: Icon(PhosphorIconsRegular.chartBar, size: 18),
                text: "Listening Stats",
              ),
              Tab(
                icon: Icon(PhosphorIconsRegular.downloadSimple, size: 18),
                text: "Downloaded",
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildLikedSongsTab(context),
                _buildLikedAlbumsTab(context),
                _buildLikedArtistsTab(context),
                _buildPlaylistsTab(context),
                const ListeningStatsView(),
                const DownloadedView(),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildLikedSongsTab(BuildContext context) {
    return Consumer<PlaylistProvider>(
      builder: (context, provider, child) {
        final favorites = provider.favoriteTracks;

        if (favorites.isEmpty) {
          return Center(
            child: Text(
              "No liked songs yet.\nFavorite a song to see it here.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), fontSize: 16),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 120, top: 16),
          itemCount: favorites.length,
          itemBuilder: (context, index) {
            final track = favorites[index];
            
              return PlayingTrackMask(
                track: track,
                child: ListTile(
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: track.thumbnailUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: CachedNetworkImage(
                            imageUrl: rewriteThumbnailSize(track.thumbnailUrl),
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) => const Icon(PhosphorIconsRegular.musicNote, color: Colors.white54),
                          ),
                        )
                      : const Icon(PhosphorIconsRegular.musicNote, color: Colors.white54),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          track.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (track.isExplicit) const ExplicitIcon(),
                    ],
                  ),
              subtitle: Text(
                track.author ?? 'Unknown Artist',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(PhosphorIconsFill.heart, color: Color(0xFFEAB308)),
                    onPressed: () {
                      final dl = context.read<DownloadProvider>();
                      provider.toggleFavorite(track, downloadProvider: dl);
                    },
                  ),
                  TrackExportIcon(track: track, size: 20),
                  TrackDownloadIcon(track: track, size: 20),
                  IconButton(
                    icon: Icon(PhosphorIconsRegular.dotsThreeVertical, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54)),
                    onPressed: () => TrackContextMenu.show(context, track),
                  ),
                ],
              ),
              onTap: () {
                final player = context.read<PlayerProvider>();
                player.setQueue(favorites);
                player.playFromQueue(index);
              },
              onLongPress: () => TrackContextMenu.show(context, track),
            ));
          },
        );
      },
    );
  }

  Widget _buildLikedAlbumsTab(BuildContext context) {
    return Consumer<PlaylistProvider>(
      builder: (context, provider, child) {
        final albums = provider.favoriteAlbums;

        if (albums.isEmpty) {
          return Center(
            child: Text(
              "No liked albums yet.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), fontSize: 16),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 120, top: 16),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            return ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: (album.thumbnailUrl?.isNotEmpty ?? false)
                    ? CachedNetworkImage(
                        imageUrl: rewriteThumbnailSize(album.thumbnailUrl),
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => Container(
                          width: 48, height: 48, color: Colors.grey[800],
                          child: const Icon(PhosphorIconsRegular.discoBall, color: Colors.white54),
                        ),
                      )
                    : Container(
                        width: 48, height: 48, color: Colors.grey[800],
                        child: const Icon(PhosphorIconsRegular.discoBall, color: Colors.white54),
                      ),
              ),
              title: Text(album.title, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${album.artistName ?? 'Unknown'} • ${album.year ?? ''}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54)), maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(PhosphorIconsFill.heart, color: Colors.red),
                    onPressed: () {
                      final dl = context.read<DownloadProvider>();
                      provider.toggleFavoriteAlbum(album, downloadProvider: dl);
                    },
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(PhosphorIconsRegular.dotsThreeVertical, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54)),
                    color: const Color(0xFF1A1A1A),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'remove', child: Text('Remove from Library')),
                      const PopupMenuItem(value: 'queue', child: Text('Add to Queue')),
                    ],
                    onSelected: (value) async {
                      if (value == 'remove') {
                        provider.toggleFavoriteAlbum(album, downloadProvider: context.read<DownloadProvider>());
                      } else if (value == 'queue') {
                        final ytService = context.read<YoutubeRemoteDataSource>();
                        try {
                          final albumFull = await ytService.getAlbum(album.id);
                          final tracks = albumFull.songs.map((s) => Track(
                            id: s.videoId,
                            title: s.name,
                            author: albumFull.artist.name,
                            duration: Duration(seconds: s.duration ?? 0),
                            album: albumFull.name,
                            thumbnailUrl: rewriteThumbnailSize(albumFull.thumbnails.lastOrNull?.url),
                          )).toList();
                          if (context.mounted) {
                            context.read<PlayerProvider>().appendToQueue(tracks);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added \${tracks.length} tracks to queue')));
                          }
                        } catch (e) {
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to load album tracks')));
                        }
                      }
                    },
                  ),
                ],
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AlbumScreen(albumId: album.id),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildLikedArtistsTab(BuildContext context) {
    return Consumer<PlaylistProvider>(
      builder: (context, provider, child) {
        final artists = provider.favoriteArtists;

        if (artists.isEmpty) {
          return Center(
            child: Text(
              "No liked artists yet.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), fontSize: 16),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 120, top: 16),
          itemCount: artists.length,
          itemBuilder: (context, index) {
            final artist = artists[index];
            return ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: (artist.thumbnailUrl?.isNotEmpty ?? false)
                    ? CachedNetworkImage(
                        imageUrl: rewriteThumbnailSize(artist.thumbnailUrl),
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => Container(
                          width: 48, height: 48, color: Colors.grey[800],
                          child: const Icon(PhosphorIconsRegular.user, color: Colors.white54),
                        ),
                      )
                    : Container(
                        width: 48, height: 48, color: Colors.grey[800],
                        child: const Icon(PhosphorIconsRegular.user, color: Colors.white54),
                      ),
              ),
              title: Text(artist.name, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(PhosphorIconsFill.heart, color: Colors.red),
                    onPressed: () {
                      provider.toggleFavoriteArtist(artist);
                    },
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(PhosphorIconsRegular.dotsThreeVertical, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54)),
                    color: const Color(0xFF1A1A1A),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'remove', child: Text('Remove from Library')),
                    ],
                    onSelected: (value) {
                      if (value == 'remove') {
                        provider.toggleFavoriteArtist(artist);
                      }
                    },
                  ),
                ],
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ArtistScreen(artistId: artist.id),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _uploadOfflineLibrary(BuildContext context) async {
    try {
      if (Platform.isAndroid) {
        final status = await Permission.manageExternalStorage.request();
        if (!status.isGranted) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Storage permission is required to select folders on Android.')),
            );
          }
          return;
        }
      }

      final String? selectedDirectory = await FilesystemPicker.open(
        title: 'Select Folder',
        context: context,
        rootDirectory: Directory(Platform.isAndroid ? '/storage/emulated/0' : '/'),
        fsType: FilesystemType.folder,
        pickText: 'Select this folder',
        folderIconColor: const Color(0xFFEAB308),
      );

      if (selectedDirectory != null) {
        if (!context.mounted) return;
        
        // Show progress dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            backgroundColor: Color(0xFF1F1F1F),
            content: Row(
              children: [
                CircularProgressIndicator(color: Color(0xFFEAB308)),
                SizedBox(width: 20),
                Text('Scanning files and extracting metadata...', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        );

        final dir = Directory(selectedDirectory);
        final List<Map<String, String>> validFiles = [];
        final validExtensions = ['.mp3', '.m4a', '.flac', '.wav', '.aac', '.ogg'];

        final files = dir.listSync(recursive: true);
        final appDir = await getApplicationDocumentsDirectory();
        
        for (var file in files) {
          if (file is File) {
            final ext = file.path.split('.').last.toLowerCase();
            if (validExtensions.contains('.$ext')) {
              String name = file.path.split('/').last;
              String? title;
              String? author;
              String? thumbnailUrl;

              try {
                final tag = await AudioTags.read(file.path);
                if (tag != null) {
                  title = tag.title;
                  author = tag.trackArtist ?? tag.albumArtist;
                  
                  if (tag.pictures.isNotEmpty) {
                    final pic = tag.pictures.first;
                    final coverFile = File('\${appDir.path}/cover_\${file.path.hashCode}.jpg');
                    await coverFile.writeAsBytes(pic.bytes);
                    thumbnailUrl = coverFile.path;
                  }
                }
              } catch (e) {
                debugPrint('Failed to extract ID3 for \${file.path}: $e');
              }

              validFiles.add({
                'path': file.path,
                'name': name,
                if (title != null) 'title': title,
                if (author != null) 'author': author,
                if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
              });
            }
          }
        }

        if (context.mounted) Navigator.of(context, rootNavigator: true).pop(); // Close progress dialog

        if (validFiles.isNotEmpty) {
          if (!context.mounted) return;
          final provider = context.read<PlaylistProvider>();
          await provider.importLocalFiles(validFiles);

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Imported \${validFiles.length} local files to "Uploads".')),
            );
          }
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No supported audio files found in folder.')),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting files: $e')),
        );
      }
    }
  }

  void _showImportPlaylistDialog(BuildContext parentContext) {
    final TextEditingController urlController = TextEditingController();
    showDialog(
      context: parentContext,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Import Playlist', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: urlController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Paste YouTube Music/Apple Music URL',
            hintStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFEAB308))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              final url = urlController.text.trim();
              if (url.isNotEmpty) {
                Navigator.pop(dialogContext); // Close input dialog
                
                showDialog(
                  context: parentContext,
                  barrierDismissible: false,
                  builder: (_) => const AlertDialog(
                    backgroundColor: Color(0xFF1F1F1F),
                    content: Row(
                      children: [
                        CircularProgressIndicator(color: Color(0xFFEAB308)),
                        SizedBox(width: 20),
                        Text('Fetching playlist data...', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                );

                // Wait for the dialog animation to complete to prevent Navigator.pop race conditions
                await Future.delayed(const Duration(milliseconds: 400));

                try {
                  final scrapeResult = await PlaylistScraperService.scrapePlaylist(url);
                  final scrapedTracks = scrapeResult['tracks'] as List<dynamic>;
                  final playlistName = scrapeResult['title'] as String;
                  
                  if (parentContext.mounted) {
                    Navigator.of(parentContext, rootNavigator: true).pop(); // Close progress dialog
                    
                    Navigator.push(
                      parentContext,
                      MaterialPageRoute(
                        builder: (_) => PlaylistImportPreviewScreen(
                          sourceUrl: url,
                          playlistName: playlistName,
                          scrapedTracks: scrapedTracks.cast<Map<String, dynamic>>(),
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (parentContext.mounted) {
                    Navigator.of(parentContext, rootNavigator: true).pop(); // Close progress dialog
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      SnackBar(content: Text('Failed to import: $e')),
                    );
                  }
                }
              }
            },
            child: const Text('Import', style: TextStyle(color: Color(0xFFEAB308))),
          ),
        ],
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final TextEditingController titleController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Create Playlist', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: titleController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Playlist Name',
            hintStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFEAB308))),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              final title = titleController.text.trim();
              if (title.isNotEmpty) {
                context.read<PlaylistProvider>().createPlaylist(title);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Created playlist "$title"')),
                );
              }
            },
            child: const Text('Create', style: TextStyle(color: Color(0xFFEAB308))),
          ),
        ],
      ),
    );
  }

  void _showPlaylistActionMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F1F1F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(PhosphorIconsRegular.listPlus, color: Colors.white),
              title: const Text('Create Playlist', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(sheetContext);
                _showCreatePlaylistDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(PhosphorIconsRegular.uploadSimple, color: Colors.white),
              title: const Text('Upload Local Folder', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(sheetContext);
                _uploadOfflineLibrary(context);
              },
            ),
            ListTile(
              leading: const Icon(PhosphorIconsRegular.link, color: Colors.white),
              title: const Text('Import Playlist', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(sheetContext);
                _showImportPlaylistDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistsTab(BuildContext context) {
    return Consumer<PlaylistProvider>(
      builder: (context, provider, child) {
        final playlists = provider.playlists;

        return Column(
          children: [
            Expanded(
              child: playlists.isEmpty
                  ? Stack(
                      children: [
                        Center(
                          child: Text(
                            "You don't have any playlists yet.\nTap + to create one.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), fontSize: 16),
                          ),
                        ),
                        Positioned(
                          bottom: 120, // Padding for bottom player
                          right: 24,
                          child: FloatingActionButton(
                            backgroundColor: const Color(0xFFEAB308),
                            onPressed: () => _showPlaylistActionMenu(context),
                            child: const Icon(PhosphorIconsRegular.plus, color: Colors.black),
                          ),
                        ),
                      ],
                    )
                  : Stack(
                      children: [
                        ListView.builder(
                          padding: const EdgeInsets.only(bottom: 120, top: 8),
                          itemCount: playlists.length,
                          itemBuilder: (context, index) {
                final playlist = playlists[index];
                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: (playlist.thumbnailUrl?.isNotEmpty ?? false)
                        ? CachedNetworkImage(
                            imageUrl: rewriteThumbnailSize(playlist.thumbnailUrl),
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) => Container(
                              width: 48, height: 48, color: Colors.grey[800],
                              child: const Icon(PhosphorIconsRegular.queue, color: Colors.white54),
                            ),
                          )
                        : Container(
                            width: 48, height: 48, color: Colors.grey[800],
                            child: const Icon(PhosphorIconsRegular.queue, color: Colors.white54),
                          ),
                  ),
                  title: Text(playlist.title, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(playlist.author ?? 'Local Playlist', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: PopupMenuButton<String>(
                    icon: Icon(PhosphorIconsRegular.dotsThreeVertical, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54)),
                    color: const Color(0xFF1A1A1A),
                    itemBuilder: (context) => [
                      if (playlist.title != 'Downloads' && playlist.title != 'Uploads' && playlist.title != 'Favorites')
                        const PopupMenuItem(value: 'edit', child: Text('Rename')),
                      if (playlist.title != 'Downloads' && playlist.title != 'Uploads' && playlist.title != 'Favorites')
                        const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                      const PopupMenuItem(value: 'queue', child: Text('Add to Queue')),
                      if (playlist.title != 'Downloads' && playlist.title != 'Uploads' && playlist.title != 'Favorites')
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                    onSelected: (value) async {
                      if (value == 'edit') {
                        final controller = TextEditingController(text: playlist.title);
                        showDialog(
                          context: context,
                          builder: (c) => AlertDialog(
                            backgroundColor: Colors.grey[900],
                            title: const Text('Rename Playlist', style: TextStyle(color: Colors.white)),
                            content: TextField(
                              controller: controller,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'New Playlist Name',
                                hintStyle: TextStyle(color: Colors.white54),
                              ),
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                              TextButton(
                                onPressed: () {
                                  if (controller.text.isNotEmpty) {
                                    provider.renamePlaylist(playlist.id, controller.text);
                                  }
                                  Navigator.pop(c);
                                },
                                child: const Text('Rename', style: TextStyle(color: Color(0xFFEAB308))),
                              ),
                            ],
                          ),
                        );
                      } else if (value == 'duplicate') {
                        provider.duplicatePlaylist(playlist.id);
                      } else if (value == 'queue') {
                        final p = await context.read<PlaylistProvider>().getCachedTracks(playlist.id);
                        if (p != null && p.isNotEmpty) {
                          context.read<PlayerProvider>().appendToQueue(p);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added \${p.length} tracks to queue')));
                        }
                      } else if (value == 'delete') {
                        provider.deletePlaylist(playlist.id);
                      }
                    },
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlaylistScreen(playlistId: playlist.id),
                      ),
                    );
                  },
                );
              },
            ),
            Positioned(
              bottom: 120,
              right: 24,
              child: FloatingActionButton(
                backgroundColor: const Color(0xFFEAB308),
                onPressed: () => _showPlaylistActionMenu(context),
                child: const Icon(PhosphorIconsRegular.plus, color: Colors.black),
              ),
            ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}
