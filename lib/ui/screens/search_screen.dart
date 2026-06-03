import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../../domain/entities/video.dart';
import '../../domain/entities/album.dart';
import '../../domain/entities/artist.dart';
import '../../domain/entities/playlist.dart';
import '../../core/utils/format_duration.dart';
import '../widgets/track_context_menu.dart';
import 'album_screen.dart';
import 'playlist_screen.dart';
import 'artist_screen.dart';
import '../widgets/bottom_player.dart';

class SearchScreen extends StatefulWidget {
  final String initialQuery;

  const SearchScreen({super.key, this.initialQuery = ''});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;

  List<Track> _trackResults = [];
  List<Album> _albumResults = [];
  List<Artist> _artistResults = [];
  List<Playlist> _playlistResults = [];
  List<Track> _otherResults = [];

  bool _isLoading = false;
  String? _error;
  String _currentQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_handleTabSelection);
    _searchController.text = widget.initialQuery;
    if (widget.initialQuery.isNotEmpty) {
      _performSearch(widget.initialQuery);
    }
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) return;
    if (_currentQuery.isNotEmpty) {
      _fetchResultsForCurrentTab();
    }
  }

  @override
  void didUpdateWidget(SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialQuery != oldWidget.initialQuery && widget.initialQuery.isNotEmpty) {
      _searchController.text = widget.initialQuery;
      _performSearch(widget.initialQuery);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    
    setState(() {
      _currentQuery = query;
      _trackResults.clear();
      _albumResults.clear();
      _artistResults.clear();
      _playlistResults.clear();
      _otherResults.clear();
    });

    await _fetchResultsForCurrentTab();
  }

  Future<void> _fetchResultsForCurrentTab() async {
    if (_currentQuery.trim().isEmpty) return;

    final index = _tabController.index;
    
    // Check if we already fetched for this tab
    if (index == 0 && _trackResults.isNotEmpty) return;
    if (index == 1 && _albumResults.isNotEmpty) return;
    if (index == 2 && _artistResults.isNotEmpty) return;
    if (index == 3 && _playlistResults.isNotEmpty) return;
    if (index == 4 && _otherResults.isNotEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final provider = context.read<PlaylistProvider>();
      
      switch (index) {
        case 0:
          final res = await provider.searchTracks(_currentQuery);
          _trackResults = res;
          break;
        case 1:
          final res = await provider.searchAlbums(_currentQuery);
          _albumResults = res;
          break;
        case 2:
          final res = await provider.searchArtists(_currentQuery);
          _artistResults = res;
          break;
        case 3:
          final res = await provider.searchPlaylists(_currentQuery);
          _playlistResults = res;
          break;
        case 4:
          final res = await provider.search(_currentQuery);
          _otherResults = res;
          break;
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = "Failed to search: $e";
        _isLoading = false;
      });
    }
  }

  void _playTrack(Track track) {
    final player = context.read<PlayerProvider>();
    player.setQueue([track]);
    player.playFromQueue(0);
  }

  Widget _buildTrackList(List<Track> tracks) {
    if (tracks.isEmpty && !_isLoading && _error == null) {
      return const Center(child: Text("No tracks found.", style: TextStyle(color: Colors.white54)));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: (track.thumbnailUrl?.isNotEmpty ?? false)
                ? CachedNetworkImage(
                    imageUrl: track.thumbnailUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Container(
                      width: 48, height: 48, color: Colors.grey[800],
                      child: const Icon(Icons.music_note, color: Colors.white54),
                    ),
                  )
                : Container(
                    width: 48, height: 48, color: Colors.grey[800],
                    child: const Icon(Icons.music_note, color: Colors.white54),
                  ),
          ),
          title: Text(track.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(track.author ?? 'Unknown Artist', style: const TextStyle(color: Colors.white54), maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Text(formatDuration(track.duration), style: const TextStyle(color: Colors.white54)),
          onTap: () => _playTrack(track),
          onLongPress: () => TrackContextMenu.show(context, track),
        );
      },
    );
  }

  Widget _buildAlbumList() {
    if (_albumResults.isEmpty && !_isLoading && _error == null) {
      return const Center(child: Text("No albums found.", style: TextStyle(color: Colors.white54)));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: _albumResults.length,
      itemBuilder: (context, index) {
        final album = _albumResults[index];
        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: (album.thumbnailUrl?.isNotEmpty ?? false)
                ? CachedNetworkImage(
                    imageUrl: album.thumbnailUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Container(
                      width: 48, height: 48, color: Colors.grey[800],
                      child: const Icon(Icons.album, color: Colors.white54),
                    ),
                  )
                : Container(
                    width: 48, height: 48, color: Colors.grey[800],
                    child: const Icon(Icons.album, color: Colors.white54),
                  ),
          ),
          title: Text(album.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${album.artistName ?? 'Unknown'} • ${album.year ?? ''}', style: const TextStyle(color: Colors.white54), maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AlbumScreen(albumId: album.id),
              ),
            );
          },
          onLongPress: () async {
            await context.read<PlaylistProvider>().toggleFavoriteAlbum(album);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Added ${album.title} to favorites')),
              );
            }
          },
        );
      },
    );
  }

  Widget _buildArtistList() {
    if (_artistResults.isEmpty && !_isLoading && _error == null) {
      return const Center(child: Text("No artists found.", style: TextStyle(color: Colors.white54)));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: _artistResults.length,
      itemBuilder: (context, index) {
        final artist = _artistResults[index];
        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: (artist.thumbnailUrl?.isNotEmpty ?? false)
                ? CachedNetworkImage(
                    imageUrl: artist.thumbnailUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Container(
                      width: 48, height: 48, color: Colors.grey[800],
                      child: const Icon(Icons.person, color: Colors.white54),
                    ),
                  )
                : Container(
                    width: 48, height: 48, color: Colors.grey[800],
                    child: const Icon(Icons.person, color: Colors.white54),
                  ),
          ),
          title: Text(artist.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ArtistScreen(artistId: artist.id),
              ),
            );
          },
          onLongPress: () async {
            await context.read<PlaylistProvider>().toggleFavoriteArtist(artist);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Added ${artist.name} to favorites')),
              );
            }
          },
        );
      },
    );
  }

  Widget _buildPlaylistList() {
    if (_playlistResults.isEmpty && !_isLoading && _error == null) {
      return const Center(child: Text("No playlists found.", style: TextStyle(color: Colors.white54)));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: _playlistResults.length,
      itemBuilder: (context, index) {
        final playlist = _playlistResults[index];
        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: (playlist.thumbnailUrl?.isNotEmpty ?? false)
                ? CachedNetworkImage(
                    imageUrl: playlist.thumbnailUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Container(
                      width: 48, height: 48, color: Colors.grey[800],
                      child: const Icon(Icons.queue_music, color: Colors.white54),
                    ),
                  )
                : Container(
                    width: 48, height: 48, color: Colors.grey[800],
                    child: const Icon(Icons.queue_music, color: Colors.white54),
                  ),
          ),
          title: Text(playlist.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(playlist.author ?? 'Unknown', style: const TextStyle(color: Colors.white54), maxLines: 1, overflow: TextOverflow.ellipsis),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white54),
        titleSpacing: 0,
        title: Container(
          height: 40,
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1F1F1F),
            borderRadius: BorderRadius.circular(4),
          ),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            autofocus: widget.initialQuery.isEmpty,
            decoration: InputDecoration(
              hintText: 'Search for tracks, artists, albums...',
              hintStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 20),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white54, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _currentQuery = '';
                        });
                      },
                    )
                  : null,
            ),
            onSubmitted: _performSearch,
            onChanged: (val) {
              setState(() {}); // Update suffix icon
            },
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle, color: Colors.white54),
            onPressed: () {},
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: const Color(0xFFEAB308),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          dividerColor: const Color(0xFF2A2A2A),
          tabs: const [
            Tab(text: "Tracks"),
            Tab(text: "Albums"),
            Tab(text: "Artists"),
            Tab(text: "Playlists"),
            Tab(text: "Other"),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFEAB308)))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTrackList(_trackResults),
                    _buildAlbumList(),
                    _buildArtistList(),
                    _buildPlaylistList(),
                    _buildTrackList(_otherResults),
                  ],
                ),
      extendBody: true,
      bottomNavigationBar: const BottomPlayer(),
    );
  }
}
