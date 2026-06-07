import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../domain/entities/video.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/download_provider.dart';
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
      backgroundColor: Colors.transparent, // transparent to allow backdrop filter blur
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
    return Consumer<PlaylistProvider>(
      builder: (context, provider, child) {
        final lastAddedId = provider.lastAddedPlaylistId;
        final playlists = provider.playlists;
        
        final lastAddedPlaylist = lastAddedId != null 
            ? playlists.where((p) => p.id == lastAddedId).firstOrNull 
            : null;

        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Blurred album art background
              if (track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty)
                Positioned.fill(
                  child: CachedNetworkImage(
                    imageUrl: rewriteThumbnailSize(track.thumbnailUrl, 1200),
                    fit: BoxFit.cover,
                  ),
                )
              else
                Container(color: const Color(0xFF0D1117)),

              // Dark overlay + blur filter
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    color: Colors.black.withOpacity(0.75),
                  ),
                ),
              ),

              // Content list
              SafeArea(
                child: Column(
                  children: [
                    // Top drag indicator / bar
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white30,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    
                    // Header title & close button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Row(
                        children: [
                          const Text(
                            'Add to Playlist',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white12, height: 1),

                    // Inner list
                    Expanded(
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
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.add, color: Colors.white),
                            ),
                            title: const Text(
                              'Create New Playlist',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                            onTap: () => _showCreatePlaylistDialog(context, provider),
                          ),

                          // Recent playlist section
                          if (lastAddedPlaylist != null) ...[
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: Text(
                                'RECENT',
                                style: TextStyle(
                                  color: Colors.white38,
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
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: Text(
                                'ALL PLAYLISTS',
                                style: TextStyle(
                                  color: Colors.white38,
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
                            const Center(
                              child: Text(
                                'No playlists yet.',
                                style: TextStyle(color: Colors.white38, fontSize: 14),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
                  errorWidget: (_, __, ___) => const Icon(Icons.music_note, color: Colors.white54),
                ),
              )
            : const Icon(Icons.music_note, color: Colors.white54),
      ),
      title: Text(
        playlist.title,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        '${playlist.videoCount} tracks',
        style: const TextStyle(color: Colors.white38, fontSize: 12),
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
                style: const TextStyle(color: Colors.white),
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
        title: const Text('New Playlist', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Playlist Title',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFEAB308))),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              final title = controller.text.trim();
              if (title.isNotEmpty) {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Close bottom sheet
                final newId = DateTime.now().millisecondsSinceEpoch.toString();
                // Create and rename
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
