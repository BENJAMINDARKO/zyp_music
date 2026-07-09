import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../../domain/entities/playlist.dart';
import '../../core/utils/format_duration.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/bottom_player.dart';
import '../widgets/track_download_icon.dart';
import '../widgets/track_export_icon.dart';
import '../../presentation/providers/download_provider.dart';
import "../../core/utils/thumbnail_url.dart";
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
    final track = _playlist!.tracks[index];
    player.playTrackWithNewSession(track);
  }

  void _playAll() {
    if (_playlist == null || _playlist!.tracks.isEmpty) return;
    _playTrack(0);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Color(0xFFEAB308))),
        extendBody: true,
      );
    }

    if (_error != null || _playlist == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(PhosphorIconsRegular.caretLeft, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: Text(
            _error ?? "Playlist not found.",
            style: const TextStyle(color: Colors.red),
          ),
        ),
        extendBody: true,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: Colors.black,
            expandedHeight: 300,
            pinned: true,
            actions: [
              PopupMenuButton<String>(
                icon: Icon(PhosphorIconsRegular.dotsThreeVertical, color: Theme.of(context).colorScheme.onSurface),
                onSelected: (value) async {
                  final provider = context.read<PlaylistProvider>();
                  if (value == 'rename') {
                    final controller = TextEditingController(text: _playlist!.title);
                    final newName = await showDialog<String>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Rename Playlist'),
                        content: TextField(
                          controller: controller,
                          autofocus: true,
                          decoration: const InputDecoration(hintText: 'Playlist Name'),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
                        ],
                      ),
                    );
                    if (newName != null && newName.isNotEmpty && mounted) {
                      await provider.renamePlaylist(_playlist!.id, newName);
                      _loadPlaylist();
                    }
                  } else if (value == 'duplicate') {
                    final newPlaylist = await provider.duplicatePlaylist(_playlist!.id);
                    if (newPlaylist != null && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Duplicated to ${newPlaylist.title}')));
                    }
                  } else if (value == 'delete') {
                    await provider.deletePlaylist(_playlist!.id);
                    if (mounted) Navigator.pop(context);
                  } else if (value == 'queue') {
                    final player = context.read<PlayerProvider>();
                    player.appendToQueue(_playlist!.tracks);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added ${_playlist!.tracks.length} tracks to queue')));
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'rename', child: Text('Rename Playlist')),
                  const PopupMenuItem(value: 'duplicate', child: Text('Duplicate Playlist')),
                  const PopupMenuItem(value: 'queue', child: Text('Add to Queue')),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete Playlist', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (_playlist!.thumbnailUrl != null)
                    CachedNetworkImage(
                      imageUrl: rewriteThumbnailSize(_playlist!.thumbnailUrl, 1200),
                      fit: BoxFit.cover,
                    ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.5),
                          Colors.black,
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 24,
                    left: 24,
                    right: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _playlist!.title,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _playlist!.author ?? 'Unknown Author',
                          style: const TextStyle(
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _playAll,
                          icon: const Icon(PhosphorIconsFill.play, color: Colors.black),
                          label: const Text("Play", style: TextStyle(color: Colors.black)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEAB308),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            leading: IconButton(
              icon: Icon(PhosphorIconsRegular.caretLeft, color: Theme.of(context).colorScheme.onSurface),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 120),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = _playlist!.tracks[index];
                  return PlayingTrackMask(
                    track: track,
                    child: Dismissible(
                      key: ValueKey('${track.id}_$index'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: Colors.red,
                        child: const Icon(PhosphorIconsRegular.trash, color: Colors.white),
                      ),
                      onDismissed: (_) async {
                        await context.read<PlaylistProvider>().removeTrackFromPlaylist(_playlist!.id, track.id);
                        _loadPlaylist();
                      },
                      child: ListTile(
                        leading: SizedBox(
                          width: 40,
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (track.isExplicit) const ExplicitIcon(),
                          ],
                        ),
                        subtitle: Text(
                          track.author ?? 'Unknown Artist',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Consumer<PlaylistProvider>(
                              builder: (context, playlistProvider, _) {
                                final isFav = playlistProvider.isFavorite(track.id);
                                return IconButton(
                                  icon: Icon(
                                    isFav ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                                    color: isFav ? const Color(0xFFEAB308) : Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
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
                            ),
                            PopupMenuButton<String>(
                              icon: Icon(PhosphorIconsRegular.dotsThreeVertical, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54)),
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
                        onTap: () => _playTrack(index),
                        onLongPress: () => TrackContextMenu.show(context, track),
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
      extendBody: true,
    );
  }
}
