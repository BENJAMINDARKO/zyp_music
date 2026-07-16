import 'dart:io';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:audiotags/audiotags.dart';
import 'package:path_provider/path_provider.dart';

import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../../presentation/providers/download_provider.dart';
import '../../presentation/providers/home_feed_provider.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/album.dart';
import '../../domain/entities/artist.dart';
import '../../domain/entities/video.dart';
import '../../core/utils/format_duration.dart';
import '../../core/utils/thumbnail_url.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/playlist_scraper_service.dart';
import '../../../data/datasources/remote/youtube_remote_datasource.dart';

import '../widgets/aurora_glass.dart';
import '../widgets/library/aurora_track_row.dart';
import '../widgets/library/aurora_album_grid.dart';
import '../widgets/library/library_toolbar.dart';
import '../widgets/listening_stats_view.dart';
import '../widgets/downloaded_view.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/playing_track_mask.dart';
import '../widgets/explicit_icon.dart';
import 'playlist_screen.dart';
import 'album_screen.dart';
import 'artist_screen.dart';
import 'playlist_import_preview_screen.dart';

enum LibraryTab {
  tracks('Tracks'),
  albums('Albums'),
  artists('Artists'),
  playlists('Playlists'),
  stats('Listening Stats'),
  downloaded('Downloaded');

  final String label;
  const LibraryTab(this.label);
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  LibraryTab _selectedTab = LibraryTab.tracks;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _sortBy = 'title'; // title, artist
  bool _filterFavoritesOnly = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _hasToolbar(LibraryTab tab) {
    return tab == LibraryTab.tracks ||
        tab == LibraryTab.albums ||
        tab == LibraryTab.artists ||
        tab == LibraryTab.playlists ||
        tab == LibraryTab.downloaded;
  }

  void _showSortBottomSheet() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: ZypAuroraColors.glass,
      barrierColor: Colors.black26,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return AuroraGlass(
          borderRadius: 28,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sort Library By',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('Title', style: TextStyle(color: Colors.white)),
                trailing: _sortBy == 'title' ? const Icon(PhosphorIconsFill.check, color: ZypAuroraColors.cyan) : null,
                onTap: () {
                  setState(() => _sortBy = 'title');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Artist / Creator', style: TextStyle(color: Colors.white)),
                trailing: _sortBy == 'artist' ? const Icon(PhosphorIconsFill.check, color: ZypAuroraColors.cyan) : null,
                onTap: () {
                  setState(() => _sortBy = 'artist');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: ZypAuroraColors.glass,
      barrierColor: Colors.black26,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AuroraGlass(
              borderRadius: 28,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Filter Library',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Favorites Only', style: TextStyle(color: Colors.white)),
                    activeColor: ZypAuroraColors.cyan,
                    value: _filterFavoritesOnly,
                    onChanged: (val) {
                      setModalState(() => _filterFavoritesOnly = val);
                      setState(() => _filterFavoritesOnly = val);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 165),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Hero Card
                    _buildHeroCard(),
                    const SizedBox(height: 20),

                    // 2. Horizontal Sticky Tab Chips
                    _buildTabChips(),
                    const SizedBox(height: 12),

                    // 3. Library Toolbar
                    if (_hasToolbar(_selectedTab))
                      LibraryToolbar(
                        searchController: _searchController,
                        onSearchChanged: (val) => setState(() => _searchQuery = val),
                        onSortPressed: _showSortBottomSheet,
                        onFilterPressed: _showFilterBottomSheet,
                      ),
                    const SizedBox(height: 12),

                    // 4. Current Tab Content
                    _buildTabContent(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _selectedTab == LibraryTab.playlists
          ? Container(
              margin: const EdgeInsets.only(bottom: 165), // Offset above bottom mini player
              child: FloatingActionButton(
                backgroundColor: ZypAuroraColors.cyan,
                onPressed: () => _showPlaylistActionMenu(context),
                child: const Icon(PhosphorIconsRegular.plus, color: Colors.black),
              ),
            )
          : null,
    );
  }

  Widget _buildHeroCard() {
    return AuroraGlass(
      borderRadius: 32,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: const Text(
                    'YOUR VAULT',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: ZypAuroraColors.cyan,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [ZypAuroraColors.cyan, ZypAuroraColors.lime],
                  ).createShader(bounds),
                  child: const Text(
                    'Wave Library',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Saved tracks, downloads, playlists, albums, and listening stats in the Aurora language.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.58),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          _LibraryPrismSpark(),
        ],
      ),
    );
  }

  IconData _getTabIcon(LibraryTab tab) {
    switch (tab) {
      case LibraryTab.tracks:
        return PhosphorIconsRegular.musicNote;
      case LibraryTab.albums:
        return PhosphorIconsRegular.discoBall;
      case LibraryTab.artists:
        return PhosphorIconsRegular.user;
      case LibraryTab.playlists:
        return PhosphorIconsRegular.playlist;
      case LibraryTab.stats:
        return PhosphorIconsRegular.chartBar;
      case LibraryTab.downloaded:
        return PhosphorIconsRegular.downloadSimple;
    }
  }

  Widget _buildTabChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: LibraryTab.values.map((tab) {
          final selected = tab == _selectedTab;
          final color = selected ? const Color(0xFF080711) : Colors.white.withOpacity(0.58);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedTab = tab;
                  _searchQuery = '';
                  _searchController.clear();
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected ? Colors.transparent : Colors.white.withOpacity(0.10),
                  ),
                  gradient: selected
                      ? const LinearGradient(
                          colors: [ZypAuroraColors.cyan, ZypAuroraColors.lime],
                        )
                      : null,
                  color: selected ? null : Colors.white.withOpacity(0.055),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getTabIcon(tab),
                      size: 15,
                      color: color,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tab.label,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTab) {
      case LibraryTab.tracks:
        return _buildTracksTab();
      case LibraryTab.albums:
        return _buildAlbumsTab();
      case LibraryTab.artists:
        return _buildArtistsTab();
      case LibraryTab.playlists:
        return _buildPlaylistsTab();
      case LibraryTab.stats:
        return const ListeningStatsView();
      case LibraryTab.downloaded:
        return _buildDownloadedTab();
    }
  }

  Widget _buildTracksTab() {
    return Consumer<PlaylistProvider>(
      builder: (context, provider, child) {
        var favorites = provider.favoriteTracks;

        // Apply Search Filter
        if (_searchQuery.isNotEmpty) {
          favorites = favorites.where((t) =>
              t.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              (t.author?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false)
          ).toList();
        }

        // Apply Sort
        if (_sortBy == 'artist') {
          favorites.sort((a, b) => (a.author ?? '').compareTo(b.author ?? ''));
        } else {
          favorites.sort((a, b) => a.title.compareTo(b.title));
        }

        if (favorites.isEmpty) {
          return _buildEmptyState(
            'No matching tracks found',
            'Favorite a track or change your filters to see them here.',
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: favorites.length,
          itemBuilder: (context, index) {
            return AuroraTrackRow(track: favorites[index]);
          },
        );
      },
    );
  }

  Widget _buildAlbumsTab() {
    return Consumer<PlaylistProvider>(
      builder: (context, provider, child) {
        var albums = provider.favoriteAlbums;

        // Apply Search Filter
        if (_searchQuery.isNotEmpty) {
          albums = albums.where((a) =>
              a.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              (a.artistName?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false)
          ).toList();
        }

        // Apply Sort
        if (_sortBy == 'artist') {
          albums.sort((a, b) => (a.artistName ?? '').compareTo(b.artistName ?? ''));
        } else {
          albums.sort((a, b) => a.title.compareTo(b.title));
        }

        return AuroraAlbumGrid(albums: albums);
      },
    );
  }

  Widget _buildArtistsTab() {
    return Consumer<PlaylistProvider>(
      builder: (context, provider, child) {
        var artists = provider.favoriteArtists;

        // Apply Search Filter
        if (_searchQuery.isNotEmpty) {
          artists = artists.where((a) => a.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
        }

        if (artists.isEmpty) {
          return _buildEmptyState(
            'No liked artists yet.',
            'When you follow artists, their signals will appear here.',
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: artists.length,
          itemBuilder: (context, index) {
            final artist = artists[index];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ArtistScreen(artistId: artist.id),
                    ),
                  );
                },
                child: AuroraGlass(
                  borderRadius: 20,
                  padding: const EdgeInsets.all(9),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(25),
                        child: (artist.thumbnailUrl?.isNotEmpty ?? false)
                            ? CachedNetworkImage(
                                imageUrl: rewriteThumbnailSize(artist.thumbnailUrl, 150),
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => _fallbackArtistCover(),
                              )
                            : _fallbackArtistCover(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          artist.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(PhosphorIconsFill.heart, color: ZypAuroraColors.pink, size: 20),
                        onPressed: () {
                          provider.toggleFavoriteArtist(artist);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPlaylistsTab() {
    return Consumer<PlaylistProvider>(
      builder: (context, provider, child) {
        var playlists = provider.playlists;

        // Apply Search Filter
        if (_searchQuery.isNotEmpty) {
          playlists = playlists.where((p) => p.title.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
        }

        if (playlists.isEmpty) {
          return _buildEmptyState(
            "You don't have any playlists yet.",
            'Tap + to create, upload, or import playlist archives.',
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: playlists.length,
          itemBuilder: (context, index) {
            final playlist = playlists[index];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlaylistScreen(playlistId: playlist.id),
                    ),
                  );
                },
                child: AuroraGlass(
                  borderRadius: 20,
                  padding: const EdgeInsets.all(9),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: (playlist.thumbnailUrl?.isNotEmpty ?? false)
                            ? CachedNetworkImage(
                                imageUrl: rewriteThumbnailSize(playlist.thumbnailUrl, 150),
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => _fallbackPlaylistCover(),
                              )
                            : _fallbackPlaylistCover(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              playlist.title,
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              playlist.author ?? 'Local Playlist',
                              style: TextStyle(color: Colors.white.withOpacity(0.58), fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      _buildPlaylistMenuButton(playlist),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDownloadedTab() {
    return Consumer<HomeFeedProvider>(
      builder: (context, feed, child) {
        if (feed.allDownloadedTracks == null && !feed.isLoadingAllDownloadedTracks) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            feed.loadAllDownloadedTracks();
          });
        }

        var downloaded = feed.allDownloadedTracks ?? [];

        // Apply Search Filter
        if (_searchQuery.isNotEmpty) {
          downloaded = downloaded.where((t) =>
              t.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              (t.author?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false)
          ).toList();
        }

        if (feed.isLoadingAllDownloadedTracks && feed.allDownloadedTracks == null) {
          return const Center(child: CircularProgressIndicator(color: ZypAuroraColors.cyan));
        }

        if (downloaded.isEmpty) {
          return _buildEmptyState(
            'No offline tracks found',
            'Tracks you download will be saved here for offline playback.',
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: downloaded.length,
          itemBuilder: (context, index) {
            return AuroraTrackRow(track: downloaded[index]);
          },
        );
      },
    );
  }

  Widget _buildPlaylistMenuButton(Playlist playlist) {
    final provider = context.read<PlaylistProvider>();
    return PopupMenuButton<String>(
      icon: Icon(PhosphorIconsRegular.dotsThreeVertical, color: Colors.white.withOpacity(0.54)),
      color: const Color(0xFF111129),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => [
        if (playlist.title != 'Downloads' && playlist.title != 'Uploads' && playlist.title != 'Favorites')
          const PopupMenuItem(value: 'edit', child: Text('Rename', style: TextStyle(color: Colors.white))),
        if (playlist.title != 'Downloads' && playlist.title != 'Uploads' && playlist.title != 'Favorites')
          const PopupMenuItem(value: 'duplicate', child: Text('Duplicate', style: TextStyle(color: Colors.white))),
        const PopupMenuItem(value: 'queue', child: Text('Add to Queue', style: TextStyle(color: Colors.white))),
        if (playlist.title != 'Downloads' && playlist.title != 'Uploads' && playlist.title != 'Favorites')
          const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.white))),
      ],
      onSelected: (value) async {
        if (value == 'edit') {
          final controller = TextEditingController(text: playlist.title);
          showDialog(
            context: context,
            builder: (c) => AlertDialog(
              backgroundColor: const Color(0xFF111129),
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
                  child: const Text('Rename', style: TextStyle(color: ZypAuroraColors.cyan)),
                ),
              ],
            ),
          );
        } else if (value == 'duplicate') {
          provider.duplicatePlaylist(playlist.id);
        } else if (value == 'queue') {
          final p = await provider.getCachedTracks(playlist.id);
          if (p != null && p.isNotEmpty) {
            if (context.mounted) {
              context.read<PlayerProvider>().appendToQueue(p);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added ${p.length} tracks to queue')));
            }
          }
        } else if (value == 'delete') {
          provider.deletePlaylist(playlist.id);
        }
      },
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: AuroraGlass(
        borderRadius: 24,
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIconsRegular.ghost,
                color: Colors.white.withOpacity(0.35),
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.58),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackPlaylistCover() {
    return Container(
      width: 50,
      height: 50,
      color: Colors.white.withOpacity(0.08),
      child: const Icon(PhosphorIconsRegular.queue, color: Colors.white30, size: 22),
    );
  }

  Widget _fallbackArtistCover() {
    return Container(
      width: 50,
      height: 50,
      color: Colors.white.withOpacity(0.08),
      child: const Icon(PhosphorIconsRegular.user, color: Colors.white30, size: 22),
    );
  }

  Widget _fallbackArtistCoverSquare() {
    return Container(
      width: 50,
      height: 50,
      color: Colors.white.withOpacity(0.08),
      child: const Icon(PhosphorIconsRegular.user, color: Colors.white30, size: 22),
    );
  }

  Widget _fallbackArtistCoverCircle() {
    return Container(
      width: 50,
      height: 50,
      color: Colors.white.withOpacity(0.08),
      child: const Icon(PhosphorIconsRegular.user, color: Colors.white30, size: 22),
    );
  }

  Widget _fallbackArtistCover2() {
    return Container(
      width: 50,
      height: 50,
      color: Colors.white.withOpacity(0.08),
      child: const Icon(PhosphorIconsRegular.user, color: Colors.white30, size: 22),
    );
  }

  Widget _fallbackArtistCover3() {
    return Container(
      width: 50,
      height: 50,
      color: Colors.white.withOpacity(0.08),
      child: const Icon(PhosphorIconsRegular.user, color: Colors.white30, size: 22),
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
        folderIconColor: ZypAuroraColors.cyan,
      );

      if (selectedDirectory != null) {
        if (!context.mounted) return;
        
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            backgroundColor: Color(0xFF111129),
            content: Row(
              children: [
                CircularProgressIndicator(color: ZypAuroraColors.cyan),
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
                    final coverFile = File('${appDir.path}/cover_${file.path.hashCode}.jpg');
                    await coverFile.writeAsBytes(pic.bytes);
                    thumbnailUrl = coverFile.path;
                  }
                }
              } catch (e) {
                debugPrint('Failed to extract ID3 for ${file.path}: $e');
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
              SnackBar(content: Text('Imported ${validFiles.length} local files to "Uploads".')),
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
        backgroundColor: const Color(0xFF111129),
        title: const Text('Import Playlist', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: urlController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Paste YouTube Music/Apple Music URL',
            hintStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: ZypAuroraColors.cyan)),
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
                    backgroundColor: Color(0xFF111129),
                    content: Row(
                      children: [
                        CircularProgressIndicator(color: ZypAuroraColors.cyan),
                        SizedBox(width: 20),
                        Text('Fetching playlist data...', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                );

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
            child: const Text('Import', style: TextStyle(color: ZypAuroraColors.cyan)),
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
        backgroundColor: const Color(0xFF111129),
        title: const Text('Create Playlist', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: titleController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Playlist Name',
            hintStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: ZypAuroraColors.cyan)),
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
            child: const Text('Create', style: TextStyle(color: ZypAuroraColors.cyan)),
          ),
        ],
      ),
    );
  }

  void _showPlaylistActionMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: ZypAuroraColors.glass,
      barrierColor: Colors.black26,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => AuroraGlass(
        borderRadius: 28,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SafeArea(
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
      ),
    );
  }
}

class _LibraryPrismSpark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const SweepGradient(
          colors: [
            ZypAuroraColors.cyan,
            ZypAuroraColors.violet,
            ZypAuroraColors.pink,
            ZypAuroraColors.peach,
            ZypAuroraColors.lime,
            ZypAuroraColors.cyan,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: ZypAuroraColors.pink.withOpacity(0.35),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: Icon(
          PhosphorIconsFill.sparkle,
          color: Colors.black.withOpacity(0.85),
          size: 26,
        ),
      ),
    );
  }
}
