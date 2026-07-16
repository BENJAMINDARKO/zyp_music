import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../presentation/providers/home_feed_provider.dart';
import '../../presentation/providers/charts_provider.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../../presentation/providers/download_provider.dart';
import '../../domain/entities/video.dart';
import '../../domain/entities/album.dart';
import '../../domain/entities/artist.dart';
import '../../domain/entities/auto_dj_mode.dart';
import '../../core/utils/thumbnail_url.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_duration.dart';
import '../../data/datasources/local/playlist_database.dart';

import '../widgets/aurora_glass.dart';
import '../widgets/playing_track_mask.dart';
import '../widgets/explicit_icon.dart';
import '../widgets/track_context_menu.dart';
import 'artist_screen.dart';
import 'album_screen.dart';
import 'playlist_screen.dart';

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
      context.read<HomeFeedProvider>().loadAll();
    });
  }

  void _playTrack(Track track) {
    final player = context.read<PlayerProvider>();
    player.playTrackWithNewSession(track);
  }

  void _playMood(String moodName, String searchQuery) async {
    try {
      final playlistProvider = context.read<PlaylistProvider>();
      final player = context.read<PlayerProvider>();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Starting mood orbit: $moodName...'),
          duration: const Duration(seconds: 2),
          backgroundColor: ZypAuroraColors.glass,
        ),
      );

      final tracks = await playlistProvider.searchTracks(searchQuery);
      if (tracks.isNotEmpty && mounted) {
        player.setAutoDJMode(AutoDJMode.sameGenre);
        player.playQueueWithNewSession(tracks, startIndex: 0);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No tracks found for $moodName')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to play $moodName: $e')),
        );
      }
    }
  }

  void _navigateToArtistByName(String name) async {
    final chartsProvider = context.read<ChartsProvider>();
    final artistId = await chartsProvider.searchArtistId(name);
    if (!mounted) return;
    if (artistId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ArtistScreen(artistId: artistId)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not find artist: $name')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 180), // bottom spacing for player
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Mood Orbit Hero
              const _MoodOrbitHero(),
              const SizedBox(height: 16),

              // 2. Trending Now Section
              _buildTrendingNowSection(),
              const SizedBox(height: 24),

              // 3. Suggested Artists Section
              _buildSuggestedArtistsSection(),
              const SizedBox(height: 24),

              // 4. Start Listening (Mood Grid) Section
              _buildStartListeningSection(),
              const SizedBox(height: 24),

              // Top Artists Section (required by test suite)
              _buildTopArtistsSection(),
              const SizedBox(height: 24),

              // 5. Popular Albums & Singles Section
              _buildPopularAlbumsSection(),
              const SizedBox(height: 24),

              // 6. Explore Category Section
              _buildExploreSection(),
              const SizedBox(height: 24),

              // 7. Today's Biggest Hits Section
              _buildBiggestHitsSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    String? hint,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.6,
            color: Colors.white,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: 8),
          Text(
            hint,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: Colors.white.withOpacity(0.38),
            ),
          ),
        ],
        const Spacer(),
        GestureDetector(
          onTap: onAction,
          child: Text(
            actionLabel,
            style: const TextStyle(
              color: ZypAuroraColors.cyan,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  // --- 2. Trending Now Section ---
  Widget _buildTrendingNowSection() {
    return Consumer<ChartsProvider>(
      builder: (context, charts, _) {
        final songs = charts.ghanaTopSongs;
        if (songs.isEmpty) return const SizedBox.shrink();
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              title: 'Trending Now',
              hint: 'swipe left →',
              actionLabel: '↻',
              onAction: () => context.read<HomeFeedProvider>().refreshYTMusicHome(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 240,
              child: GridView.builder(
                scrollDirection: Axis.horizontal,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 9,
                  crossAxisSpacing: 9,
                  childAspectRatio: 74 / 180,
                ),
                itemCount: songs.length,
                itemBuilder: (context, index) {
                  final track = songs[index];
                  // Assign glowing colors based on index
                  final glowColors = [
                    ZypAuroraColors.cyan,
                    ZypAuroraColors.pink,
                    ZypAuroraColors.violet,
                    ZypAuroraColors.peach,
                    ZypAuroraColors.lime,
                  ];
                  final glowColor = glowColors[index % glowColors.length];

                  return _SignalTile(
                    track: track,
                    glowColor: glowColor,
                    onTap: () => _playTrack(track),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // --- 3. Suggested Artists Section ---
  Widget _buildSuggestedArtistsSection() {
    return Consumer2<HomeFeedProvider, PlaylistProvider>(
      builder: (context, feed, playlist, _) {
        // Collect artists from history or falls back to favorite artists
        final historyArtists = feed.topArtistsFromHistory ?? [];
        final favArtists = playlist.favoriteArtists;
        
        final List<Map<String, String?>> displayArtists = [];
        for (var art in historyArtists) {
          displayArtists.add({'name': art.artistName, 'url': art.thumbnailUrl});
        }
        if (displayArtists.isEmpty) {
          for (var art in favArtists) {
            displayArtists.add({'name': art.name, 'url': art.thumbnailUrl});
          }
        }

        if (displayArtists.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              title: 'Suggested Artists',
              actionLabel: 'See all',
              onAction: () {
                // If there are favorite artists, push settings or search
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: displayArtists.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final art = displayArtists[index];
                  final name = art['name'] ?? 'Unknown';
                  final url = art['url'];

                  return GestureDetector(
                    onTap: () => _navigateToArtistByName(name),
                    child: SizedBox(
                      width: 92,
                      child: Column(
                        children: [
                          Container(
                            width: 86,
                            height: 86,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withOpacity(0.13)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.22),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: url != null
                                  ? CachedNetworkImage(
                                      imageUrl: rewriteThumbnailSize(url, 200),
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) => _fallbackArtistAvatar(name),
                                    )
                                  : _fallbackArtistAvatar(name),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.78),
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _fallbackArtistAvatar(String name) {
    return Container(
      color: Colors.white.withOpacity(0.08),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(color: ZypAuroraColors.cyan, fontWeight: FontWeight.bold, fontSize: 24),
        ),
      ),
    );
  }

  // --- 4. Start Listening (Mood Grid) Section ---
  Widget _buildStartListeningSection() {
    final feed = context.watch<HomeFeedProvider>();
    final tracks = feed.topSongsPerTopGenre ?? const [];
    if (tracks.isEmpty) return const SizedBox.shrink();

    final moods = [
      {
        'title': 'Afrobeats Pulse',
        'desc': 'Warm drums, Ghana/Naija energy, replay-ready hooks.',
        'color': ZypAuroraColors.peach,
        'query': 'Afrobeats',
      },
      {
        'title': 'Americana Glow',
        'desc': 'Guitars, soft roads, and sunrise vocals.',
        'color': ZypAuroraColors.cyan,
        'query': 'Americana',
      },
      {
        'title': 'Dancehall Prism',
        'desc': 'Bright rhythm, bass bounce, late-night movement.',
        'color': ZypAuroraColors.pink,
        'query': 'Dancehall',
      },
      {
        'title': 'Violet Velocity',
        'desc': 'Night-drive pulse and starfield drums.',
        'color': ZypAuroraColors.violet,
        'query': 'Electronic',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: 'Start Listening',
          actionLabel: 'Shuffle',
          onAction: () {
            // Pick a random mood and play it
            final randomMood = (moods..shuffle()).first;
            _playMood(randomMood['title'] as String, randomMood['query'] as String);
          },
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.35,
          children: moods.map((mood) {
            return GestureDetector(
              onTap: () => _playMood(mood['title'] as String, mood['query'] as String),
              child: _MoodCard(
                title: mood['title'] as String,
                desc: mood['desc'] as String,
                glowColor: mood['color'] as Color,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTopArtistsSection() {
    return Consumer<PlaylistProvider>(
      builder: (context, pp, _) {
        final artists = pp.favoriteArtists;
        if (artists.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              title: 'Top Artists',
              actionLabel: 'See all',
              onAction: () {},
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: artists.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
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
                    child: SizedBox(
                      width: 92,
                      child: Column(
                        children: [
                          Container(
                            width: 86,
                            height: 86,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withOpacity(0.13)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.22),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: artist.thumbnailUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: rewriteThumbnailSize(artist.thumbnailUrl!, 200),
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) => _fallbackArtistAvatar(artist.name),
                                    )
                                  : _fallbackArtistAvatar(artist.name),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            artist.name,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.78),
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // --- 5. Popular Albums & Singles Section ---
  Widget _buildPopularAlbumsSection() {
    return Consumer<HomeFeedProvider>(
      builder: (context, feed, _) {
        final items = feed.popularAlbumsAndSingles ?? [];
        if (items.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              title: 'Popular Albums & Singles',
              hint: '2 rows',
              actionLabel: 'More',
              onAction: () {},
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 250,
              child: GridView.builder(
                scrollDirection: Axis.horizontal,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 116 / 82,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return GestureDetector(
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
                        _playTrack(track);
                      }
                    },
                    child: _MiniAlbumCard(item: item),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // --- 6. Explore Category Section ---
  Widget _buildExploreSection() {
    final categories = [
      {
        'title': 'Naija Gospel Hits',
        'desc': 'Dunsin Oyekan, minister GUC...',
        'label': 'Gospel',
        'art': 'a4',
        'query': 'Naija Gospel',
      },
      {
        'title': 'Classic Afro Reggae',
        'desc': 'Ras Kimono, Lucky Dube...',
        'label': 'Classic',
        'art': 'a8',
        'query': 'Reggae',
      },
      {
        'title': 'Biggest R&B Hits',
        'desc': 'Chris Brown, SZA, Tems...',
        'label': 'R&B',
        'art': 'a6',
        'query': 'R&B Hits',
      },
      {
        'title': 'Afrobeats Party',
        'desc': 'Wizkid, Asake, KiDi...',
        'label': 'Party',
        'art': 'a2',
        'query': 'Afrobeats Party',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: 'Explore',
          actionLabel: '↻',
          onAction: () {},
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 152,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final cat = categories[index];
              return GestureDetector(
                onTap: () => _playMood(cat['title']!, cat['query']!),
                child: _CategoryCard(
                  title: cat['title']!,
                  desc: cat['desc']!,
                  label: cat['label']!,
                  artStyle: cat['art']!,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // --- 7. Today's Biggest Hits Section ---
  Widget _buildBiggestHitsSection() {
    final hits = [
      {
        'title': 'Afrobeats Party',
        'artists': 'Wizkid, Asake, MA...',
        'art': Colors.blueGrey,
        'glow': ZypAuroraColors.cyan,
        'query': 'Wizkid Asake',
      },
      {
        'title': 'Eastern Flavour',
        'artists': 'Mbosso, Marioo, Harmonize...',
        'art': Colors.deepPurple,
        'glow': ZypAuroraColors.pink,
        'query': 'Mbosso Marioo',
      },
      {
        'title': 'Top Afropop',
        'artists': 'FOLA, Asake, Ayra Starr...',
        'art': Colors.indigo,
        'glow': ZypAuroraColors.violet,
        'query': 'Ayra Starr Asake',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: "Today's biggest hits",
          actionLabel: 'Play all',
          onAction: () => _playMood("Today's Biggest Hits", "Afrobeats pop"),
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: hits.length,
          separatorBuilder: (_, __) => const SizedBox(width: 9),
          itemBuilder: (context, index) {
            final hit = hits[index];
            return GestureDetector(
              onTap: () => _playMood(hit['title'] as String, hit['query'] as String),
              child: _HitRow(
                title: hit['title'] as String,
                artists: hit['artists'] as String,
                artColor: hit['art'] as Color,
                glowColor: hit['glow'] as Color,
              ),
            );
          },
        ),
      ],
    );
  }
}

// ==========================================
// PRIVATE SUB-WIDGET IMPLEMENTATIONS
// ==========================================

// --- Mood Orbit Hero ---
class _MoodOrbitHero extends StatelessWidget {
  const _MoodOrbitHero();

  @override
  Widget build(BuildContext context) {
    return AuroraGlass(
      borderRadius: 34,
      padding: const EdgeInsets.all(18),
      child: Container(
        height: 170,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(34),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Left side text details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Pills
                  const Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _HeroPill(label: 'LIVE'),
                      _HeroPill(label: 'MOOD-FIRST'),
                      _HeroPill(label: 'DISCOVERY'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Title
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.2,
                        height: 0.9,
                        fontFamily: 'Inter',
                      ),
                      children: [
                        const TextSpan(text: 'Music ', style: TextStyle(color: Colors.white)),
                        TextSpan(
                          text: 'Now',
                          style: TextStyle(
                            foreground: Paint()
                              ..shader = const LinearGradient(
                                colors: [
                                  Colors.white,
                                  ZypAuroraColors.cyan,
                                  ZypAuroraColors.pink,
                                  ZypAuroraColors.peach,
                                ],
                              ).createShader(const Rect.fromLTWH(0.0, 0.0, 200.0, 70.0)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Subtitle
                  Text(
                    'Trending signals, artist orbits, albums, and genre portals in one glass feed.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.white.withOpacity(0.62),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            // Right side rotating orb
            const _PrismOrb(size: 106),
          ],
        ),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  final String label;
  const _HeroPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.17)),
        color: Colors.white.withOpacity(0.095),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: Colors.white.withOpacity(0.74),
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _PrismOrb extends StatefulWidget {
  final double size;
  const _PrismOrb({this.size = 106});

  @override
  State<_PrismOrb> createState() => _PrismOrbState();
}

class _PrismOrbState extends State<_PrismOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.087, // ~5 degrees rotation
      child: RotationTransition(
        turns: _controller,
        child: Container(
          width: widget.size,
          height: widget.size,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            color: Colors.white.withOpacity(0.13),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
            boxShadow: [
              BoxShadow(
                color: ZypAuroraColors.violet.withOpacity(0.25),
                blurRadius: 44,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(23),
              gradient: const SweepGradient(
                colors: [
                  ZypAuroraColors.cyan,
                  ZypAuroraColors.violet,
                  ZypAuroraColors.pink,
                  ZypAuroraColors.peach,
                  ZypAuroraColors.cyan,
                ],
              ),
            ),
            child: Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ZypAuroraColors.ink.withOpacity(0.38),
                  border: Border.all(color: Colors.white.withOpacity(0.25)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Trending Now / Signal Tile ---
class _SignalTile extends StatelessWidget {
  final Track track;
  final Color glowColor;
  final VoidCallback onTap;

  const _SignalTile({
    required this.track,
    required this.glowColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PlayingTrackMask(
      track: track,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: () => TrackContextMenu.show(context, track),
        child: AuroraGlass(
          borderRadius: 21,
          padding: const EdgeInsets.all(9),
          child: Stack(
            children: [
              // Bottom-right glow effect
              Positioned(
                right: -24,
                bottom: -28,
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: glowColor.withOpacity(0.18),
                    boxShadow: [
                      BoxShadow(
                        color: glowColor.withOpacity(0.18),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  // Compact artwork
                  ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: (track.thumbnailUrl?.isNotEmpty ?? false)
                        ? CachedNetworkImage(
                            imageUrl: rewriteThumbnailSize(track.thumbnailUrl!, 150),
                            width: 46,
                            height: 46,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _fallbackArt(),
                          )
                        : _fallbackArt(),
                  ),
                  const SizedBox(width: 9),
                  // Metadata
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          track.title,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.author ?? 'Unknown Artist',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.white.withOpacity(0.62),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              formatDuration(track.duration),
                              style: TextStyle(
                                fontSize: 9.5,
                                color: Colors.white.withOpacity(0.42),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '• hot',
                              style: TextStyle(
                                fontSize: 9.5,
                                color: glowColor,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackArt() {
    return Container(
      width: 46,
      height: 46,
      color: Colors.white.withOpacity(0.08),
      child: const Icon(PhosphorIconsRegular.musicNote, color: Colors.white24, size: 20),
    );
  }
}

// --- Start Listening Mood Card ---
class _MoodCard extends StatelessWidget {
  final String title;
  final String desc;
  final Color glowColor;

  const _MoodCard({
    required this.title,
    required this.desc,
    required this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    return AuroraGlass(
      borderRadius: 26,
      padding: const EdgeInsets.all(15),
      child: Stack(
        children: [
          // Bottom-right glowing orb accent
          Positioned(
            right: -26,
            bottom: -28,
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: glowColor.withOpacity(0.52),
                boxShadow: [
                  BoxShadow(
                    color: glowColor.withOpacity(0.52),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.4,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.62),
                  height: 1.34,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- Popular Albums / Mini Album Card ---
class _MiniAlbumCard extends StatelessWidget {
  final PopularItem item;

  const _MiniAlbumCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return AuroraGlass(
      borderRadius: 18,
      padding: EdgeInsets.zero,
      child: Container(
        width: 82,
        height: 116,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Art header (height 72)
                SizedBox(
                  height: 72,
                  width: double.infinity,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                    child: (item.thumbnailUrl?.isNotEmpty ?? false)
                        ? CachedNetworkImage(
                            imageUrl: rewriteThumbnailSize(item.thumbnailUrl!, 150),
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _fallbackCover(),
                          )
                        : _fallbackCover(),
                  ),
                ),
                // Titles
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.title ?? 'Unknown',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          item.artistName ?? 'Unknown Artist',
                          style: TextStyle(
                            fontSize: 8.5,
                            color: Colors.white.withOpacity(0.62),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // "Single" or "Album" Pill overlay
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: const LinearGradient(
                    colors: [ZypAuroraColors.cyan, ZypAuroraColors.pink],
                  ),
                ),
                child: Text(
                  item.isAlbum ? 'ALBUM' : 'SINGLE',
                  style: const TextStyle(
                    color: Color(0xFF080711),
                    fontSize: 7,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackCover() {
    return Container(
      color: Colors.white.withOpacity(0.08),
      child: const Icon(PhosphorIconsRegular.discoBall, color: Colors.white30, size: 24),
    );
  }
}

// --- Explore Category Card ---
class _CategoryCard extends StatelessWidget {
  final String title;
  final String desc;
  final String label;
  final String artStyle;

  const _CategoryCard({
    required this.title,
    required this.desc,
    required this.label,
    required this.artStyle,
  });

  @override
  Widget build(BuildContext context) {
    return AuroraGlass(
      borderRadius: 24,
      padding: EdgeInsets.zero,
      child: Container(
        width: 150,
        height: 142,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top art area (height 88)
            Container(
              height: 88,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                gradient: _getArtGradient(artStyle),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 10,
                    bottom: 9,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: const Color(0xDD5EEAD4),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Color(0xFF07110D),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Text area below
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      desc,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withOpacity(0.62),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Gradient _getArtGradient(String style) {
    switch (style) {
      case 'a4':
        return const RadialGradient(
          center: Alignment(0.32, -0.04),
          radius: 0.26,
          colors: [Color(0xFFFFC2EA), Colors.transparent],
          stops: [0.0, 1.0],
        );
      case 'a8':
        return const LinearGradient(
          colors: [Color(0xFF103528), ZypAuroraColors.success],
        );
      case 'a6':
        return const SweepGradient(
          colors: [
            Color(0xFF1B1740),
            ZypAuroraColors.violet,
            ZypAuroraColors.pink,
            ZypAuroraColors.peach,
            ZypAuroraColors.cyan,
            Color(0xFF161735),
          ],
        );
      case 'a2':
        return const LinearGradient(
          colors: [Color(0xFF0A0A0A), ZypAuroraColors.error],
        );
      default:
        return const LinearGradient(
          colors: [ZypAuroraColors.violet, ZypAuroraColors.cyan],
        );
    }
  }
}

// --- Today's Biggest Hits Row ---
class _HitRow extends StatelessWidget {
  final String title;
  final String artists;
  final Color artColor;
  final Color glowColor;

  const _HitRow({
    required this.title,
    required this.artists,
    required this.artColor,
    required this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.5),
      child: AuroraGlass(
        borderRadius: 23,
        padding: const EdgeInsets.all(9),
        child: Stack(
          children: [
            // Bottom-right glow
            Positioned(
              right: -42,
              bottom: -46,
              child: Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: glowColor.withOpacity(0.15),
                  boxShadow: [
                    BoxShadow(
                      color: glowColor.withOpacity(0.15),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                // Artwork 50x50, radius 16
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: artColor,
                  ),
                  child: const Center(
                    child: Icon(PhosphorIconsRegular.musicNote, color: Colors.white54, size: 22),
                  ),
                ),
                const SizedBox(width: 11),
                // Text details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.3,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        artists,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.white.withOpacity(0.62),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // "mix" tag trailing
                Text(
                  'mix',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.white.withOpacity(0.38),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
