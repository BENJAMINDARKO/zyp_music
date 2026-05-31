import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/utils/format_duration.dart';
import '../../domain/entities/video.dart';
import '../providers/player_provider.dart';
import '../providers/playlist_provider.dart';
import '../providers/settings_provider.dart';
import 'player_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  List<Track> _results = [];
  bool _isSearching = false;
  bool _hasSearched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });
    final provider = context.read<PlaylistProvider>();
    final results = await provider.search(query);
    if (mounted) {
      setState(() {
        _results = results;
        _isSearching = false;
      });
    }
  }

  void _playTrack(Track track) {
    final player = context.read<PlayerProvider>();
    final quality = context.read<SettingsProvider>().audioQuality;
    player.setQueue([track], startIndex: 0);
    player.playTrack(track, quality: quality);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen()));
  }

  void _playTrackNext(Track track) {
    final player = context.read<PlayerProvider>();
    final newQueue = List<Track>.from(player.queue);
    newQueue.insert(player.currentIndex + 1, track);
    player.setQueue(newQueue, startIndex: player.currentIndex, playlistId: player.currentPlaylistId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${track.title}" added to queue'), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search YouTube')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search for music...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _controller.clear();
                          setState(() {});
                        },
                      )
                    : null,
              ),
              onSubmitted: (_) => _search(),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSearching ? null : _search,
                icon: _isSearching
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search),
                label: Text(_isSearching ? 'Searching...' : 'Search'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _buildResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text('Search for music on YouTube', style: TextStyle(color: Colors.grey[400])),
          ],
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text('No results found', style: TextStyle(color: Colors.grey[400])),
      );
    }
    return RefreshIndicator(
      onRefresh: _search,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _results.length,
        itemBuilder: (context, index) {
          final track = _results[index];
          return ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                track.thumbnailUrl ?? '',
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 48, height: 48,
                  color: Colors.grey[800],
                  child: const Icon(Icons.music_note),
                ),
              ),
            ),
            title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${track.author ?? "Unknown"} · ${formatDuration(track.duration)}',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'play') _playTrack(track);
                if (value == 'queue') _playTrackNext(track);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'play', child: ListTile(leading: Icon(Icons.play_arrow), title: Text('Play now'))),
                const PopupMenuItem(value: 'queue', child: ListTile(leading: Icon(Icons.queue_music), title: Text('Play next'))),
              ],
            ),
            onTap: () => _playTrack(track),
          );
        },
      ),
    );
  }
}
