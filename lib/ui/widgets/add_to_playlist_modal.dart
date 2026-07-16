import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../domain/entities/video.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/download_provider.dart';
import 'apple_music_sheet.dart';
import "../../core/utils/thumbnail_url.dart";

class AddToPlaylistModal extends StatelessWidget {
  final Track track;
  final ScrollController? scrollController;

  const AddToPlaylistModal({
    super.key,
    required this.track,
    this.scrollController,
  });

  static void show(BuildContext context, Track track) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black54,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => AddToPlaylistModal(
          track: track,
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppleMusicSheet(
      title: 'Add to Playlist',
      child: Consumer<PlaylistProvider>(
        builder: (context, provider, child) {
          final lastAddedId = provider.lastAddedPlaylistId;
          final playlists = provider.playlists;

          final lastAddedPlaylist = lastAddedId != null
              ? playlists.where((p) => p.id == lastAddedId).firstOrNull
              : null;

          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) => SafeArea(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  // Create New button
                  ListTile(
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(PhosphorIconsRegular.plus, color: Theme.of(context).colorScheme.onSurface),
                    ),
                    title: Text(
                      'Create New Playlist',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () => _showCreatePlaylistDialog(context, provider),
                  ),

                  // Recent playlist section
                  if (lastAddedPlaylist != null) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        'RECENT',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.38),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    _buildPlaylistTile(context, provider, lastAddedPlaylist),
                  ],

                  // All playlists section
                  if (playlists.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        'ALL PLAYLISTS',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.38),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    ...playlists.where((p) => p.id != lastAddedPlaylist?.id).map((playlist) {
                      return _buildPlaylistTile(context, provider, playlist);
                    }),
                  ] else if (lastAddedPlaylist == null) ...[
                    const SizedBox(height: 40),
                    Center(
                      child: Text(
                        'No playlists yet.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.38), fontSize: 14),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlaylistTile(BuildContext context, PlaylistProvider provider, dynamic playlist) {
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(8),
        ),
        child: playlist.thumbnailUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: rewriteThumbnailSize(playlist.thumbnailUrl),
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Icon(PhosphorIconsRegular.musicNote, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54)),
                ),
              )
            : Icon(PhosphorIconsRegular.musicNote, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54)),
      ),
      title: Text(
        playlist.title,
        style: TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        '${playlist.videoCount} tracks',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.38), fontSize: 12),
      ),
      onTap: () async {
        await provider.addTrackToPlaylist(playlist.id, track);
        if (context.mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF1E1E1E),
              content: Text(
                'Added to ${playlist.title} successfully',
              ),
            ),
          );
        }
      },
    );
  }

  void _showCreatePlaylistDialog(BuildContext context, PlaylistProvider provider) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('New Playlist', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'Playlist Title',
            hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.38)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.24))),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFEAB308))),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('CANCEL', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54))),
          ),
          TextButton(
            onPressed: () async {
              final title = controller.text.trim();
              if (title.isNotEmpty) {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Close bottom sheet
                final newId = DateTime.now().millisecondsSinceEpoch.toString();
                await provider.addTrackToPlaylist(newId, track);
                await provider.renamePlaylist(newId, title);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: const Color(0xFF1E1E1E),
                      content: Text('Created playlist "$title"'),
                    ),
                  );
                }
              }
            },
            child: const Text('CREATE', style: TextStyle(color: Color(0xFFEAB308), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
