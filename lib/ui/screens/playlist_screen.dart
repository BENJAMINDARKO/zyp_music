import 'dart:io';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../../presentation/providers/download_provider.dart';
import '../../domain/entities/playlist.dart';
import '../../core/utils/format_duration.dart';
import '../../core/utils/thumbnail_url.dart';
import '../../core/theme/app_theme.dart';

import '../widgets/global_background.dart';
import '../widgets/aurora_glass.dart';
import '../widgets/prism_loader.dart';
import '../widgets/library/detail_track_row.dart';
import '../widgets/library/playlist_hero.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/track_download_icon.dart';
import '../widgets/track_export_icon.dart';
import '../widgets/playing_track_mask.dart';
import '../widgets/explicit_icon.dart';

class PlaylistScreen extends StatefulWidget {
  final String playlistId;

  const PlaylistScreen({super.key, required this.playlistId});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  Playlist? _playlist;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPlaylist();
  }

  Future<void> _loadPlaylist() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final provider = context.read<PlaylistProvider>();
      final playlist = await provider.getPlaylistFull(widget.playlistId);
      setState(() {
        _playlist = playlist;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = "Failed to load playlist: $e";
        _isLoading = false;
      });
    }
  }

  void _playTrack(int index) {
    if (_playlist == null) return;
    final player = context.read<PlayerProvider>();
    player.playQueueWithNewSession(_playlist!.tracks, startIndex: index, playlistId: _playlist!.id);
  }

  void _playAll() {
    if (_playlist == null || _playlist!.tracks.isEmpty) return;
    _playTrack(0);
  }

  void _showPlaylistOptions(BuildContext context) {
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
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(PhosphorIconsRegular.textT, color: Colors.white),
                title: const Text('Rename Playlist', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final controller = TextEditingController(text: _playlist!.title);
                  final newName = await showDialog<String>(
                    context: context,
                    builder: (c) => AlertDialog(
                      backgroundColor: const Color(0xFF111129),
                      title: const Text('Rename Playlist', style: TextStyle(color: Colors.white)),
                      content: TextField(
                        controller: controller,
                        style: const TextStyle(color: Colors.white),
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Playlist Name',
                          hintStyle: TextStyle(color: Colors.white54),
                        ),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                        TextButton(onPressed: () => Navigator.pop(c, controller.text), child: const Text('Save', style: TextStyle(color: ZypAuroraColors.cyan))),
                      ],
                    ),
                  );
                  if (newName != null && newName.isNotEmpty && mounted) {
                    await context.read<PlaylistProvider>().renamePlaylist(_playlist!.id, newName);
                    _loadPlaylist();
                  }
                },
              ),
              ListTile(
                leading: const Icon(PhosphorIconsRegular.copy, color: Colors.white),
                title: const Text('Duplicate Playlist', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final newPlaylist = await context.read<PlaylistProvider>().duplicatePlaylist(_playlist!.id);
                  if (newPlaylist != null && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Duplicated to ${newPlaylist.title}')));
                  }
                },
              ),
              ListTile(
                leading: const Icon(PhosphorIconsRegular.queue, color: Colors.white),
                title: const Text('Add to Queue', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.read<PlayerProvider>().appendToQueue(_playlist!.tracks);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added ${_playlist!.tracks.length} tracks to queue')));
                },
              ),
              ListTile(
                leading: const Icon(PhosphorIconsRegular.trash, color: Colors.red),
                title: const Text('Delete Playlist', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await context.read<PlaylistProvider>().deletePlaylist(_playlist!.id);
                  if (mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: ZypAuroraColors.ink,
        body: Stack(
          children: [
            GlobalBackground(),
            PrismLoader(
              title: 'Syncing Playlist',
              subtitle: 'Fetching tracks, album covers, and local files...',
            ),
          ],
        ),
      );
    }

    if (_error != null || _playlist == null) {
      return Scaffold(
        backgroundColor: ZypAuroraColors.ink,
        body: Stack(
          children: [
            const GlobalBackground(),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    icon: const Icon(PhosphorIconsRegular.caretLeft, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        _error ?? "Playlist not found.",
                        style: const TextStyle(color: Colors.red, fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Global Background
          const GlobalBackground(),
          
          // Main Scrollable Area
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                // Playlist Header Hero Card
                SliverToBoxAdapter(
                  child: PlaylistHero(
                    playlist: _playlist!,
                    onPlayAll: _playAll,
                    onBack: () => Navigator.of(context).pop(),
                    onMore: () => _showPlaylistOptions(context),
                  ),
                ),
                
                // Tracks list
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final track = _playlist!.tracks[index];
                        final displayIndex = index + 1;
                        
                        return PlayingTrackMask(
                          track: track,
                          child: Dismissible(
                            key: ValueKey('${track.id}_$index'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: const Icon(PhosphorIconsRegular.trash, color: Colors.white),
                            ),
                            onDismissed: (_) async {
                              await context.read<PlaylistProvider>().removeTrackFromPlaylist(_playlist!.id, track.id);
                              _loadPlaylist();
                            },
                            child: DetailTrackRow(
                              index: displayIndex,
                              track: track,
                              onTap: () => _playTrack(index),
                              trailingActions: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Consumer<PlaylistProvider>(
                                    builder: (context, playlistProvider, _) {
                                      final isFav = playlistProvider.isFavorite(track.id);
                                      return IconButton(
                                        icon: Icon(
                                          isFav ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                                          color: isFav ? ZypAuroraColors.pink : Colors.white.withOpacity(0.54),
                                          size: 20,
                                        ),
                                        onPressed: () {
                                          playlistProvider.toggleFavorite(
                                            track,
                                            downloadProvider: context.read<DownloadProvider>(),
                                          );
                                        },
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  TrackExportIcon(track: track, size: 20),
                                  const SizedBox(width: 8),
                                  TrackDownloadIcon(track: track, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    formatDuration(track.duration),
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.48),
                                      fontSize: 12,
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: Icon(PhosphorIconsRegular.dotsThreeVertical, color: Colors.white.withOpacity(0.54)),
                                    color: const Color(0xFF111129),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    onSelected: (value) async {
                                      if (value == 'remove') {
                                        await context.read<PlaylistProvider>().removeTrackFromPlaylist(_playlist!.id, track.id);
                                        _loadPlaylist();
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'remove',
                                        child: Text('Remove from playlist', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: _playlist!.tracks.length,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
