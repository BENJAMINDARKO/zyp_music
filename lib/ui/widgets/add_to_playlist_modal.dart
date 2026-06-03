import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/video.dart';
import '../../presentation/providers/playlist_provider.dart';

class AddToPlaylistModal extends StatelessWidget {
  final Track track;

  const AddToPlaylistModal({super.key, required this.track});

  static void show(BuildContext context, Track track) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => AddToPlaylistModal(track: track),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlaylistProvider>(
      builder: (context, provider, child) {
        final lastAddedId = provider.lastAddedPlaylistId;
        final playlists = provider.playlists;
        
        var lastAddedPlaylist = lastAddedId != null 
            ? playlists.where((p) => p.id == lastAddedId).firstOrNull 
            : null;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const Text(
                    'Add to Playlist',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.add, color: Colors.white),
              ),
              title: const Text('Create New Playlist', style: TextStyle(color: Colors.white)),
              onTap: () {
                _showCreatePlaylistDialog(context, provider);
              },
            ),
            if (lastAddedPlaylist != null) ...[
              const Divider(color: Colors.white12, height: 1),
              const Padding(
                padding: EdgeInsets.only(left: 16.0, top: 16.0, bottom: 8.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'RECENT',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: lastAddedPlaylist.thumbnailUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(lastAddedPlaylist.thumbnailUrl!, fit: BoxFit.cover),
                      )
                    : const Icon(Icons.music_note, color: Colors.white54),
                ),
                title: Text(lastAddedPlaylist.title, style: const TextStyle(color: Colors.white)),
                subtitle: Text('${lastAddedPlaylist.videoCount} tracks', style: const TextStyle(color: Colors.white54)),
                onTap: () {
                  provider.addTrackToPlaylist(lastAddedPlaylist!.id, track);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Added to ${lastAddedPlaylist.title} successfully')),
                  );
                },
              ),
            ],
            const Divider(color: Colors.white12, height: 1),
            const Padding(
              padding: EdgeInsets.only(left: 16.0, top: 16.0, bottom: 8.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'ALL PLAYLISTS',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  // Don't show the last added one twice if it's already in RECENT
                  if (playlist.id == lastAddedPlaylist?.id) {
                    return const SizedBox.shrink();
                  }

                  return ListTile(
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: playlist.thumbnailUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.network(playlist.thumbnailUrl!, fit: BoxFit.cover),
                          )
                        : const Icon(Icons.music_note, color: Colors.white54),
                    ),
                    title: Text(playlist.title, style: const TextStyle(color: Colors.white)),
                    subtitle: Text('${playlist.videoCount} tracks', style: const TextStyle(color: Colors.white54)),
                    onTap: () {
                      provider.addTrackToPlaylist(playlist.id, track);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Added to ${playlist.title} successfully')),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _showCreatePlaylistDialog(BuildContext context, PlaylistProvider provider) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('New Playlist', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Playlist Title',
            hintStyle: TextStyle(color: Colors.white54),
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
                // Create by saving the single track directly
                await provider.addTrackToPlaylist(newId, track);
                // The repository handles creating the playlist entry if it doesn't exist
                await provider.renamePlaylist(newId, title);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Created playlist $title')),
                );
              }
            },
            child: const Text('CREATE', style: TextStyle(color: Color(0xFFEAB308))),
          ),
        ],
      ),
    );
  }
}
