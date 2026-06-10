import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../presentation/providers/home_feed_provider.dart';
import '../../data/datasources/local/playlist_database.dart';

class ListeningStatsView extends StatefulWidget {
  const ListeningStatsView({super.key});

  @override
  State<ListeningStatsView> createState() => _ListeningStatsViewState();
}

class _ListeningStatsViewState extends State<ListeningStatsView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeFeedProvider>().loadListeningStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeFeedProvider>(
      builder: (context, feed, _) {
        final stats = feed.listeningStats;

        if (feed.isLoadingListeningStats && stats == null) {
          return const Center(child: CircularProgressIndicator());
        }

        if (stats == null || stats.distinctArtistCount == 0) {
          return _buildEmptyState(context);
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, 'Your last 30 days'),
              const SizedBox(height: 24),
              _buildCountsRow(context, stats),
              const SizedBox(height: 32),
              _buildTopArtistsSection(context, stats.topArtists),
              const SizedBox(height: 32),
              _buildTopAlbumsSection(context, stats.topAlbums),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.titleMedium?.copyWith(
        color: theme.colorScheme.onSurface.withOpacity(0.7),
      ),
    );
  }

  Widget _buildCountsRow(BuildContext context, ListeningStats stats) {
    return Row(
      children: [
        Expanded(
          child: _buildCountCard(
            context,
            value: stats.distinctGenreCount.toString(),
            label: 'distinct genres',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildCountCard(
            context,
            value: stats.distinctArtistCount.toString(),
            label: 'distinct artists',
          ),
        ),
      ],
    );
  }

  Widget _buildCountCard(BuildContext context, {
    required String value,
    required String label,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopArtistsSection(BuildContext context, List<ArtistPlayStat> artists) {
    if (artists.isEmpty) return const SizedBox.shrink();

    final maxPlays = artists.first.playCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context, 'Top artists'),
        const SizedBox(height: 16),
        ...artists.asMap().entries.map((entry) {
          final index = entry.key;
          final artist = entry.value;
          return _buildRankedBar(
            context: context,
            rank: index + 1,
            label: artist.artistName,
            value: artist.playCount,
            maxValue: maxPlays,
          );
        }),
      ],
    );
  }

  Widget _buildTopAlbumsSection(BuildContext context, List<AlbumPlayStat> albums) {
    if (albums.isEmpty) return const SizedBox.shrink();

    final maxPlays = albums.first.playCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context, 'Top albums'),
        const SizedBox(height: 16),
        ...albums.asMap().entries.map((entry) {
          final index = entry.key;
          final album = entry.value;
          return _buildRankedBar(
            context: context,
            rank: index + 1,
            label: album.albumTitle ?? 'Unknown album',
            value: album.playCount,
            maxValue: maxPlays,
          );
        }),
      ],
    );
  }

  Widget _buildRankedBar({
    required BuildContext context,
    required int rank,
    required String label,
    required int value,
    required int maxValue,
  }) {
    final theme = Theme.of(context);
    final fraction = maxValue > 0 ? value / maxValue : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '$rank',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '$value',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Container(
              height: 4,
              color: theme.colorScheme.surface,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fraction,
                child: Container(color: theme.colorScheme.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'No listening data yet',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Play some tracks to see your listening stats.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
