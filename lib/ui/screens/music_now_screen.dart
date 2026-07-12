import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../presentation/providers/home_feed_provider.dart';
import '../../presentation/providers/charts_provider.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../../data/datasources/local/playlist_database.dart';
import '../../domain/entities/video.dart';
import '../../domain/entities/album.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/artist.dart';
import '../../domain/entities/auto_dj_mode.dart';
import '../widgets/shared_cards.dart';
import "../screens/artist_screen.dart";
import "../screens/album_screen.dart";
import "../screens/playlist_screen.dart";
import "../../core/utils/thumbnail_url.dart";
import '../widgets/playing_track_mask.dart';

import '../widgets/global_top_bar.dart';

class MusicNowScreen extends StatefulWidget {
  const MusicNowScreen({super.key});

  @override
  State<MusicNowScreen> createState() => _MusicNowScreenState();
}

class _MusicNowScreenState extends State<MusicNowScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final homeFeed = context.read<HomeFeedProvider>();
      homeFeed.loadAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTrendingNowSection(context),
              _buildSuggestedArtistsSection(context),
              _buildStartListeningSection(context),
              _buildTopArtistsSection(context),
              _buildPopularAlbumsAndSinglesSection(context),
              _buildYTMusicSectionsHeader(context),
              _buildYTMusicSections(context),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildTrendingNowSection(BuildContext context) {
    return Consumer<ChartsProvider>(
      builder: (context, charts, _) {
        final items = charts.ghanaTopSongs;
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(context, 'Trending Now'),
            SizedBox(
              height: 220,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  return SizedBox(
                    width: 140,
                    child: TrackCard(track: items[index]),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSuggestedArtistsSection(BuildContext context) {
    return Consumer<HomeFeedProvider>(
      builder: (context, feed, _) {
        final artists = feed.topArtistsFromHistory ?? const [];
        if (artists.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(context, 'Suggested Artists'),
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: artists.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final entry = artists[index];
                  return GestureDetector(
                    onTap: () => _navigateToArtist(context, entry),
                    child: _HistoryArtistCard(entry: entry),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStartListeningSection(BuildContext context) {
    return Consumer<HomeFeedProvider>(
      builder: (context, feed, _) {
        final tracks = feed.topSongsPerTopGenre ?? const [];
        if (tracks.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(context, 'Start Listening'),
            SizedBox(
              height: 220,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: tracks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  return SizedBox(
                    width: 140,
                    child: _TopGenreTrackCard(track: track),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTopArtistsSection(BuildContext context) {
    return Consumer<PlaylistProvider>(
      builder: (context, pp, _) {
        final artists = pp.favoriteArtists;
        if (artists.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(context, 'Top Artists'),
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: artists.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final artist = artists[index];
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ArtistScreen(artistId: artist.id),
                        ),
                      );
                    },
                    child: _buildArtistCircle(artist),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildArtistCircle(Artist artist) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 36,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.primary.withOpacity(0.2),
          backgroundImage: artist.thumbnailUrl != null
              ? CachedNetworkImageProvider(
                  rewriteThumbnailSize(artist.thumbnailUrl),
                )
              : null,
          child: artist.thumbnailUrl == null
              ? Text(
                  artist.name.isNotEmpty ? artist.name[0].toUpperCase() : '?',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : null,
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 72,
          child: Text(
            artist.name,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildPopularAlbumsAndSinglesSection(BuildContext context) {
    return Consumer<HomeFeedProvider>(
      builder: (context, feed, _) {
        final items = feed.popularAlbumsAndSingles ?? const [];
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(context, 'Popular Albums & Singles'),
            SizedBox(
              height: 220,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  return SizedBox(
                    width: 140,
                    child: _PopularItemCard(item: items[index]),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _navigateToArtist(BuildContext context, HistoryArtistEntry entry) async {
    final chartsProvider = context.read<ChartsProvider>();
    final artistId = await chartsProvider.searchArtistId(entry.artistName);
    if (!context.mounted) return;
    if (artistId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ArtistScreen(artistId: artistId)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not find artist: ${entry.artistName}')),
      );
    }
  }
}

Widget _sectionHeader(BuildContext context, String title) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
    ),
  );
}

Widget _buildYTMusicSectionsHeader(BuildContext context) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
    child: Row(
      children: [
        Text(
          'Explore',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        Consumer<HomeFeedProvider>(
          builder: (context, feed, _) {
            final loading = feed.isLoadingYTMusicHome;
            return IconButton(
              icon: loading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    )
                  : Icon(PhosphorIcons.arrowClockwise,
                      color: Theme.of(context).colorScheme.onSurface),
              onPressed:
                  loading ? null : () => feed.refreshYTMusicHome(),
              tooltip: 'Refresh sections',
            );
          },
        ),
      ],
    ),
  );
}

Widget _buildYTMusicSections(BuildContext context) {
  return Consumer<HomeFeedProvider>(
    builder: (context, feed, _) {
      final sections = feed.ytHomeSections;
      if (sections == null || sections.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: sections.take(4).map((section) {
          final renamed = section.title == 'Long listens'
              ? 'Human DJ'
              : section.title;
          return _buildYTMusicSectionRow(context, YTFeedSection(renamed, section.items));
        }).toList(),
      );
    },
  );
}

Widget _buildYTMusicSectionRow(BuildContext context, YTFeedSection section) {
  if (section.items.isEmpty) return const SizedBox.shrink();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionHeader(context, section.title),
      SizedBox(
        height: 180,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: section.items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final item = section.items[index];
            return SizedBox(
              width: 140,
              child: _ytItemCard(item),
            );
          },
        ),
      ),
    ],
  );
}

Widget _ytItemCard(YTFeedItem item) {
  if (item.track != null) {
    return TrackCard(track: item.track!);
  } else if (item.album != null) {
    return _YTAlbumCard(album: item.album!);
  } else if (item.playlist != null) {
    return _YTPlaylistCard(playlist: item.playlist!);
  }
  return const SizedBox.shrink();
}

class _YTAlbumCard extends StatelessWidget {
  final Album album;
  const _YTAlbumCard({required this.album});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF141414),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AlbumScreen(albumId: album.id)),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFF1F1F1F),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  child: album.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: rewriteThumbnailSize(album.thumbnailUrl),
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const Icon(PhosphorIconsRegular.discoBall, color: Colors.white24, size: 48),
                      )
                    : const Center(child: Icon(PhosphorIconsRegular.discoBall, color: Colors.white24, size: 48)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.title,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    album.artistName ?? 'Unknown Artist',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YTPlaylistCard extends StatelessWidget {
  final Playlist playlist;
  const _YTPlaylistCard({required this.playlist});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF141414),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PlaylistScreen(playlistId: playlist.id)),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFF1F1F1F),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  child: playlist.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: rewriteThumbnailSize(playlist.thumbnailUrl),
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const Icon(PhosphorIconsRegular.playlist, color: Colors.white24, size: 48),
                      )
                    : const Center(child: Icon(PhosphorIconsRegular.playlist, color: Colors.white24, size: 48)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.title,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    playlist.author ?? 'Unknown',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryArtistCard extends StatelessWidget {
  final HistoryArtistEntry entry;

  const _HistoryArtistCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 40,
          backgroundColor: theme.colorScheme.primary.withOpacity(0.2),
          backgroundImage: entry.thumbnailUrl != null
              ? CachedNetworkImageProvider(
                  rewriteThumbnailSize(entry.thumbnailUrl!),
                )
              : null,
          child: entry.thumbnailUrl == null
              ? Text(
                  entry.artistName.isNotEmpty
                      ? entry.artistName[0].toUpperCase()
                      : '?',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : null,
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 80,
          child: Text(
            entry.artistName,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _TopGenreTrackCard extends StatelessWidget {
  final TopGenreTrack track;

  const _TopGenreTrackCard({required this.track});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = Track(
      id: track.trackId,
      title: track.title ?? 'Unknown Track',
      author: track.artistName,
      thumbnailUrl: track.thumbnailUrl,
    );
    return PlayingTrackMask(
      track: t,
      child: Material(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            final player = context.read<PlayerProvider>();
            player.setAutoDJMode(AutoDJMode.sameGenre);
            player.playTrackWithNewSession(t);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1F1F1F),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(8),
                        ),
                        child: track.thumbnailUrl != null
                            ? CachedNetworkImage(
                                imageUrl: rewriteThumbnailSize(
                                  track.thumbnailUrl!,
                                ),
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => const Icon(
                                  PhosphorIconsRegular.musicNote,
                                  color: Colors.white24,
                                  size: 48,
                                ),
                              )
                            : const Center(
                                child: Icon(
                                  PhosphorIconsRegular.musicNote,
                                  color: Colors.white24,
                                  size: 48,
                                ),
                              ),
                      ),
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            track.primaryGenre,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title ?? 'Unknown Track',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.artistName ?? 'Unknown Artist',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
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
      ),
    );
  }
}

class _PopularItemCard extends StatelessWidget {
  final PopularItem item;

  const _PopularItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: const Color(0xFF141414),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (item.isAlbum) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AlbumScreen(albumId: item.id)),
            );
          } else {
            final track = Track(
              id: item.id,
              title: item.title ?? 'Unknown Track',
              author: item.artistName,
              thumbnailUrl: item.thumbnailUrl,
            );
            final player = context.read<PlayerProvider>();
            player.playTrackWithNewSession(track);
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFF1F1F1F),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8),
                      ),
                      child: item.thumbnailUrl != null
                          ? CachedNetworkImage(
                              imageUrl: rewriteThumbnailSize(
                                item.thumbnailUrl!,
                              ),
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => const Icon(
                                PhosphorIconsRegular.musicNote,
                                color: Colors.white24,
                                size: 48,
                              ),
                            )
                          : Center(
                              child: Icon(
                                item.isAlbum
                                    ? PhosphorIconsRegular.discoBall
                                    : PhosphorIconsRegular.musicNote,
                                color: Colors.white24,
                                size: 48,
                              ),
                            ),
                    ),
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: item.isAlbum
                              ? Colors.blue.withOpacity(0.85)
                              : theme.colorScheme.secondary.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.isAlbum ? 'Album' : 'Single',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title ?? 'Unknown',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.artistName ?? 'Unknown Artist',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
