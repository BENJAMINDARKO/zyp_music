import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_theme.dart';
import '../../presentation/providers/download_provider.dart';
import '../../presentation/providers/home_feed_provider.dart';
import '../../presentation/providers/settings_provider.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../../presentation/providers/charts_provider.dart';
import '../../domain/entities/video.dart';
import '../../domain/entities/album.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/artist.dart';
import '../widgets/track_download_icon.dart';
import '../widgets/album_download_icon.dart';
import '../widgets/track_export_icon.dart';
import '../widgets/album_export_icon.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/album_context_menu.dart';
import '../widgets/animated_daily_prism_stack.dart';
import '../widgets/jump_back_in_compact.dart';
import '../widgets/jump_back_in_sheet.dart';
import '../../presentation/providers/jump_back_in_provider.dart';
import 'album_screen.dart';
import 'artist_screen.dart';
import 'playlist_screen.dart';
import "../../core/utils/thumbnail_url.dart";
import '../widgets/playing_track_mask.dart';
import '../widgets/explicit_icon.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _countryPickerShown = false;
  String _activeFilter = 'all'; // 'all', 'music', 'downloaded', 'afrobeats', 'forYou'

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_countryPickerShown) {
      final settings = context.read<SettingsProvider>();
      if (settings.preferredGl == null) {
        _countryPickerShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _showCountryPicker(context));
      }
    }
  }

  Future<void> _showCountryPicker(BuildContext context) async {
    final code = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _CountryPickerSheet(),
    );
    if (code != null && mounted) {
      final settings = context.read<SettingsProvider>();
      await settings.setPreferredGl(code);
      final feed = context.read<HomeFeedProvider>();
      feed.setGl(code);
      feed.refreshYTMusicHome();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Chips
          _buildFilterChips(),
          
          // Feed Body (Animated Switcher)
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: SingleChildScrollView(
                key: ValueKey(_activeFilter),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 180), // extra bottom padding for floating players
                child: _buildActiveFeed(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final chips = [
      {'id': 'all', 'label': 'All'},
      {'id': 'music', 'label': 'Music'},
      {'id': 'downloaded', 'label': 'Downloaded'},
      {'id': 'afrobeats', 'label': 'Afrobeats'},
      {'id': 'forYou', 'label': 'For You'},
    ];

    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final chip = chips[index];
          final isSelected = _activeFilter == chip['id'];
          return GestureDetector(
            onTap: () {
              setState(() {
                _activeFilter = chip['id']!;
              });
              if (_activeFilter == 'downloaded') {
                context.read<HomeFeedProvider>().loadAllDownloadedTracks();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isSelected ? Colors.transparent : Colors.white.withOpacity(0.12),
                  width: 1,
                ),
                gradient: isSelected
                    ? const LinearGradient(
                        colors: [ZypAuroraColors.cyan, ZypAuroraColors.lime],
                      )
                    : null,
                color: isSelected ? null : Colors.white.withOpacity(0.075),
              ),
              child: Center(
                child: Text(
                  chip['label']!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: isSelected ? Colors.black : Colors.white.withOpacity(0.82),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActiveFeed() {
    switch (_activeFilter) {
      case 'all':
        return _buildAllFeed();
      case 'music':
        return _buildMusicFeed();
      case 'downloaded':
        return _buildDownloadedFeed();
      case 'afrobeats':
        return _buildAfrobeatsFeed();
      case 'forYou':
        return _buildForYouFeed();
      default:
        return _buildAllFeed();
    }
  }

  // --- All Feed ---
  Widget _buildAllFeed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Daily Prism Card
        _buildDailyCard(),
        const SizedBox(height: 16),
        
        // Jump back in (Quick Grid)
        Consumer<JumpBackInProvider>(
          builder: (context, jb, _) {
            if (!jb.hasData) return const SizedBox.shrink();
            return Column(
              children: [
                JumpBackInCompactGrid(
                  items: jb.compactItems,
                  onMore: () => JumpBackInSheet.show(
                    context,
                    recommendations: jb.recommendations,
                    onRefresh: () => jb.load(
                      currentGenre: null,
                    ),
                    isRefreshing: jb.isLoading,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            );
          },
        ),

        // Suggested Songs
        _buildSuggestedSongsSection(),
        const SizedBox(height: 16),

        // Featured Albums
        _buildFeaturedAlbumsSection(),
        const SizedBox(height: 16),

        // Artists
        _buildArtistsSection(),
        const SizedBox(height: 16),

        // Liked Songs
        _buildLikedSongsSection(),
      ],
    );
  }

  // --- Music Feed ---
  Widget _buildMusicFeed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFeedSummaryCard(
          title: 'New Signals',
          desc: 'Fresh releases, trending tracks, and mood stations without leaving Home.',
          orbColor: ZypAuroraColors.cyan,
        ),
        const SizedBox(height: 16),
        _buildSuggestedSongsSection(),
        const SizedBox(height: 16),
        _buildFeaturedAlbumsSection(),
        const SizedBox(height: 16),
        _buildSectionHeader('Mood Stations'),
        _buildMoodStationsGrid(),
        const SizedBox(height: 16),
        _buildArtistsSection(),
      ],
    );
  }

  // --- Downloaded Feed ---
  Widget _buildDownloadedFeed() {
    return Consumer<HomeFeedProvider>(
      builder: (context, feed, _) {
        final tracks = feed.allDownloadedTracks ?? [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOfflineCapsuleCard(tracks.length),
            const SizedBox(height: 16),
            _buildSectionHeader('Recently Downloaded'),
            _buildCustomSuggestedSongsGrid(tracks),
            const SizedBox(height: 16),
            _buildSectionHeader('Downloaded Albums'),
            _buildDownloadedAlbumsSection(),
            const SizedBox(height: 16),
            _buildSectionHeader('Offline Playlists'),
            _buildOfflinePlaylistsList(),
          ],
        );
      },
    );
  }

  // --- Afrobeats Feed ---
  Widget _buildAfrobeatsFeed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFeedSummaryCard(
          title: 'Afrobeats Pulse',
          desc: 'Warm, rhythmic, Accra-to-Lagos discovery with ZYP\'s frosted glass, aurora accents, and warmer personality.',
          orbColor: ZypAuroraColors.pink,
        ),
        const SizedBox(height: 16),
        // Subgenre Chips
        _buildSubgenreChips(),
        const SizedBox(height: 16),
        _buildSuggestedSongsSection(),
        const SizedBox(height: 16),
        _buildFeaturedAlbumsSection(),
        const SizedBox(height: 16),
        _buildArtistsSection(),
      ],
    );
  }

  // --- For You Feed ---
  Widget _buildForYouFeed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPersonalBriefingCard(),
        const SizedBox(height: 16),
        _buildSuggestedSongsSection(),
        const SizedBox(height: 16),
        _buildSectionHeader('Personalized recommendations'),
        _buildLikedSongsSection(),
      ],
    );
  }

  // --- Helpers & Visual Components ---

  Widget _buildSectionHeader(String title, {String? actionText, VoidCallback? onAction}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.6,
              color: Colors.white,
            ),
          ),
          if (actionText != null && onAction != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionText,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: ZypAuroraColors.cyan,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDailyCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ZypAuroraColors.glassSoft,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: ZypAuroraColors.stroke),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.09),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: const Text(
                    'MADE FOR YOU',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 10),
                const Text.rich(
                  TextSpan(
                    text: 'Daily ',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      height: 0.9,
                      letterSpacing: -0.75,
                      color: Colors.white,
                    ),
                    children: [
                      TextSpan(
                        text: 'Prism',
                        style: TextStyle(
                          color: ZypAuroraColors.cyan,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'A familiar daily mix flow, but with ZYP\'s frosted glass, aurora accents, and warmer personality.',
                  style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.62), height: 1.38),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          // Layered Stack Artwork
          SizedBox(
            width: 112,
            height: 112,
              child: const AnimatedDailyPrismStack(),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedSummaryCard({required String title, required String desc, required Color orbColor}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ZypAuroraColors.glassSoft,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: ZypAuroraColors.stroke),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.09),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: const Text(
                    'DISCOVERY',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    height: 0.92,
                    letterSpacing: -0.75,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  desc,
                  style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.62), height: 1.38),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: SweepGradient(
                colors: [
                  orbColor,
                  ZypAuroraColors.violet,
                  ZypAuroraColors.pink,
                  ZypAuroraColors.peach,
                  orbColor,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: orbColor.withOpacity(0.22),
                  blurRadius: 42,
                  offset: const Offset(0, 18),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineCapsuleCard(int totalTracks) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ZypAuroraColors.glassSoft,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: ZypAuroraColors.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.09),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: const Text(
              'OFFLINE CAPSULE',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white70),
            ),
          ),
          const SizedBox(height: 10),
          const Text.rich(
            TextSpan(
              text: 'No signal? ',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                height: 0.9,
                letterSpacing: -0.7,
                color: Colors.white,
              ),
              children: [
                TextSpan(
                  text: 'Still playing.',
                  style: TextStyle(
                    color: ZypAuroraColors.cyan,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your saved music, smart cache, and offline playlists.',
            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.62)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _buildOfflineStatCell(totalTracks.toString(), 'tracks')),
              const SizedBox(width: 8),
              Expanded(child: _buildOfflineStatCell('12', 'albums')),
              const SizedBox(width: 8),
              Expanded(child: _buildOfflineStatCell('1.4GB', 'cached')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineStatCell(String value, String label) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.5, color: ZypAuroraColors.cyan),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.62)),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalBriefingCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ZypAuroraColors.glassSoft,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: ZypAuroraColors.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.09),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: const Text(
              'PERSONAL BRIEFING',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white70),
            ),
          ),
          const SizedBox(height: 10),
          const Text.rich(
            TextSpan(
              text: 'Welcome back, ',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                height: 0.9,
                letterSpacing: -0.75,
                color: Colors.white,
              ),
              children: [
                TextSpan(
                  text: 'Listener.',
                  style: TextStyle(
                    color: ZypAuroraColors.peach,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'We\'ve synthesized a fresh blend of Afrobeats, soft synths, and lofi focus tracks tailored to your late-night mood.',
            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.62), height: 1.46),
          ),
        ],
      ),
    );
  }

  Widget _buildSubgenreChips() {
    final genres = ['Amapiano', 'Afro-fusion', 'Alté', 'Streetpop', 'Hiplife', 'Highlife'];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: genres.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
              color: Colors.white.withOpacity(0.075),
            ),
            child: Center(
              child: Text(
                genres[index],
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white70),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMoodStationsGrid() {
    final moods = [
      {'title': 'Chrome Rain', 'desc': 'Glossy focus tracks with wet synths.', 'color': ZypAuroraColors.cyan},
      {'title': 'Sugar Eclipse', 'desc': 'Bright hooks, dark bass, zero beige.', 'color': ZypAuroraColors.pink},
      {'title': 'Solar Lo-Fi', 'desc': 'Warm dust, cassette glow, soft kick.', 'color': ZypAuroraColors.lime},
      {'title': 'Violet Velocity', 'desc': 'Night-drive pulse and starfield drums.', 'color': ZypAuroraColors.violet},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.4,
      ),
      itemCount: moods.length,
      itemBuilder: (context, index) {
        final mood = moods[index];
        final glowColor = mood['color'] as Color;
        return Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: ZypAuroraColors.glassSoft,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.11)),
            boxShadow: [
              BoxShadow(
                color: glowColor.withOpacity(0.08),
                blurRadius: 16,
                offset: const Offset(4, 4),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                mood['title'] as String,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: -0.35, color: Colors.white),
              ),
              Text(
                mood['desc'] as String,
                style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.62), height: 1.34),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSuggestedSongsSection() {
    return Consumer<ChartsProvider>(
      builder: (context, charts, child) {
        final songs = charts.ghanaTopSongs;
        if (charts.isLoadingGhana && songs.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: ZypAuroraColors.cyan));
        }
        if (songs.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Suggested Songs', actionText: 'More', onAction: () {}),
            _buildCustomSuggestedSongsGrid(songs),
          ],
        );
      },
    );
  }

  Widget _buildCustomSuggestedSongsGrid(List<Track> songs) {
    if (songs.isEmpty) {
      return Container(
        height: 100,
        alignment: Alignment.center,
        child: const Text('No suggested songs available', style: TextStyle(color: Colors.white54)),
      );
    }
    return SizedBox(
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
          return _SuggestedSongTile(track: songs[index]);
        },
      ),
    );
  }

  Widget _buildFeaturedAlbumsSection() {
    return Consumer<ChartsProvider>(
      builder: (context, charts, child) {
        final albums = charts.featuredAlbums;
        if (charts.isLoadingAlbums && albums.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: ZypAuroraColors.cyan));
        }
        if (albums.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Featured Albums', actionText: 'View', onAction: () {}),
            SizedBox(
              height: 242,
              child: GridView.builder(
                scrollDirection: Axis.horizontal,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 116 / 82,
                ),
                itemCount: albums.length,
                itemBuilder: (context, index) {
                  return _FeaturedAlbumCard(album: albums[index]);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDownloadedAlbumsSection() {
    return Consumer<PlaylistProvider>(
      builder: (context, pp, _) {
        final albums = pp.favoriteAlbums; // Fallback to favorite albums for downloaded view
        if (albums.isEmpty) {
          return Container(
            height: 100,
            alignment: Alignment.center,
            child: const Text('No downloaded albums', style: TextStyle(color: Colors.white54)),
          );
        }
        return SizedBox(
          height: 242,
          child: GridView.builder(
            scrollDirection: Axis.horizontal,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 116 / 82,
            ),
            itemCount: albums.length,
            itemBuilder: (context, index) {
              return _FeaturedAlbumCard(album: albums[index]);
            },
          ),
        );
      },
    );
  }

  Widget _buildArtistsSection() {
    return Consumer<PlaylistProvider>(
      builder: (context, pp, child) {
        final artists = pp.favoriteArtists;
        if (artists.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Artists you like', actionText: 'See all', onAction: () {}),
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: artists.length,
                separatorBuilder: (_, __) => const SizedBox(width: 16),
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 41,
                          backgroundColor: Colors.white.withOpacity(0.08),
                          backgroundImage: artist.thumbnailUrl != null
                              ? CachedNetworkImageProvider(
                                  rewriteThumbnailSize(artist.thumbnailUrl),
                                )
                              : null,
                          child: artist.thumbnailUrl == null
                              ? Text(
                                  artist.name.isNotEmpty ? artist.name[0].toUpperCase() : '?',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24),
                                )
                              : null,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: 82,
                          child: Text(
                            artist.name,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.78),
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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

  Widget _buildLikedSongsSection() {
    return Consumer<PlaylistProvider>(
      builder: (context, pp, child) {
        final tracks = pp.favoriteTracks;
        if (tracks.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Liked Songs', actionText: 'Open', onAction: () {}),
            Container(
              decoration: BoxDecoration(
                color: ZypAuroraColors.glassSoft,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: ZypAuroraColors.stroke),
              ),
              padding: const EdgeInsets.all(8),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: tracks.take(5).length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  return _buildTrackRow(context, tracks[index]);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOfflinePlaylistsList() {
    return Consumer<PlaylistProvider>(
      builder: (context, pp, _) {
        final playlists = pp.playlists;
        if (playlists.isEmpty) {
          return Container(
            height: 100,
            alignment: Alignment.center,
            child: const Text('No offline playlists', style: TextStyle(color: Colors.white54)),
          );
        }
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: playlists.length,
          itemBuilder: (context, index) {
            final playlist = playlists[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: ZypAuroraColors.glassSoft,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withOpacity(0.09)),
              ),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 52,
                    height: 52,
                    color: Colors.white.withOpacity(0.1),
                    child: const Icon(Icons.playlist_play, color: Colors.white54),
                  ),
                ),
                title: Text(playlist.title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                subtitle: Text('${playlist.tracks.length} tracks • downloaded', style: TextStyle(color: Colors.white.withOpacity(0.62))),
                trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => PlaylistScreen(playlistId: playlist.id)));
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTrackRow(BuildContext context, Track track) {
    return PlayingTrackMask(
      track: track,
      child: GestureDetector(
        onTap: () {
          final player = context.read<PlayerProvider>();
          player.playTrackWithNewSession(track);
        },
        onLongPress: () {
          TrackContextMenu.show(context, track);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.052),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.075)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: (track.thumbnailUrl?.isNotEmpty ?? false)
                    ? CachedNetworkImage(
                        imageUrl: rewriteThumbnailSize(track.thumbnailUrl, 120),
                        width: 42,
                        height: 42,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _fallbackTrackIcon(),
                      )
                    : _fallbackTrackIcon(),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      track.title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.author ?? 'Unknown Artist',
                      style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.62)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(PhosphorIconsRegular.heart, color: ZypAuroraColors.pink, size: 20),
                    onPressed: () {},
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(PhosphorIconsRegular.dotsThreeVertical, color: Colors.white54, size: 20),
                    onPressed: () => TrackContextMenu.show(context, track),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackTrackIcon() => Container(
        width: 42,
        height: 42,
        color: Colors.white.withOpacity(0.08),
        child: const Icon(Icons.music_note, color: Colors.white24, size: 18),
      );
}

class _SuggestedSongTile extends StatelessWidget {
  final Track track;
  const _SuggestedSongTile({required this.track});

  @override
  Widget build(BuildContext context) {
    return PlayingTrackMask(
      track: track,
      child: GestureDetector(
        onTap: () {
          final player = context.read<PlayerProvider>();
          player.playTrackWithNewSession(track);
        },
        onLongPress: () {
          TrackContextMenu.show(context, track);
        },
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: ZypAuroraColors.glassSoft,
            borderRadius: BorderRadius.circular(21),
            border: Border.all(color: ZypAuroraColors.stroke),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: (track.thumbnailUrl?.isNotEmpty ?? false)
                    ? CachedNetworkImage(
                        imageUrl: rewriteThumbnailSize(track.thumbnailUrl, 120),
                        width: 46,
                        height: 46,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _fallbackIcon(),
                      )
                    : _fallbackIcon(),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      track.title,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, height: 1.06, color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.author ?? 'Unknown Artist',
                      style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.62)),
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

  Widget _fallbackIcon() => Container(
        width: 46,
        height: 46,
        color: Colors.white.withOpacity(0.08),
        child: const Icon(Icons.music_note, color: Colors.white24, size: 20),
      );
}

class _FeaturedAlbumCard extends StatelessWidget {
  final Album album;
  const _FeaturedAlbumCard({required this.album});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AlbumScreen(albumId: album.id)),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: ZypAuroraColors.glassSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ZypAuroraColors.stroke),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: (album.thumbnailUrl?.isNotEmpty ?? false)
                    ? CachedNetworkImage(
                        imageUrl: rewriteThumbnailSize(album.thumbnailUrl, 200),
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _fallbackIcon(),
                      )
                    : _fallbackIcon(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 7, 7, 1),
              child: Text(
                album.title,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, height: 1.08, color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              child: Text(
                album.artistName ?? 'Unknown Artist',
                style: TextStyle(fontSize: 9.5, color: Colors.white.withOpacity(0.62)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackIcon() => Container(
        color: Colors.white.withOpacity(0.08),
        child: const Icon(Icons.album, color: Colors.white24, size: 24),
      );
}

class _CountryPickerSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select Your Region',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Personalised recommendations for your region',
                        style: TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ...SettingsProvider.countryOptions.map((c) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: const Icon(PhosphorIconsRegular.globeHemisphereWest, color: Colors.white70),
                  title: Text(c['name']!, style: const TextStyle(color: Colors.white)),
                  trailing: Text(c['code']!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () => Navigator.pop(context, c['code']),
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
