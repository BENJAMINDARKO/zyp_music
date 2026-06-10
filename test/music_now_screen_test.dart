import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:zyp_music/presentation/providers/home_feed_provider.dart';
import 'package:zyp_music/presentation/providers/charts_provider.dart';
import 'package:zyp_music/core/services/hybrid_cache_service.dart';
import 'package:zyp_music/presentation/providers/playlist_provider.dart';
import 'package:zyp_music/presentation/providers/download_provider.dart';
import 'package:zyp_music/data/datasources/local/playlist_database.dart';
import 'package:zyp_music/domain/entities/video.dart';
import 'package:zyp_music/domain/entities/album.dart';
import 'package:zyp_music/domain/entities/artist.dart';
import 'package:zyp_music/ui/screens/music_now_screen.dart';

class _MockChartsProvider extends ChangeNotifier implements ChartsProvider {
  @override
  List<Track> get ghanaTopSongs => [
        Track(
          id: 'tr1',
          title: 'Trending Track 1',
          author: 'Artist A',
          thumbnailUrl: 'http://example.com/t1.jpg',
        ),
      ];
  @override List<Track> get globalTopSongs => [];
  @override List<Album> get featuredAlbums => [];
  @override List<String> get ghanaTopArtists => [];
  @override bool get isLoadingGhana => false;
  @override bool get isLoadingGlobal => false;
  @override bool get isLoadingAlbums => false;
  @override Future<String?> searchArtistId(String artistName) async => null;
  @override Future<void> fetchGhanaTopSongs({bool forceRefresh = false}) async {}
  @override Future<void> fetchGlobalTopSongs({bool forceRefresh = false}) async {}
  @override Future<void> fetchFeaturedAlbums({bool forceRefresh = false}) async {}
}

class _SeededHomeFeedProvider extends ChangeNotifier implements HomeFeedProvider {
  @override
  List<HistoryArtistEntry>? get topArtistsFromHistory => [
        const HistoryArtistEntry(
          artistName: 'Artist X',
          playCount: 15,
          sampleTrackId: 'sx1',
          thumbnailUrl: null,
        ),
        const HistoryArtistEntry(
          artistName: 'Artist Y',
          playCount: 10,
          sampleTrackId: 'sy1',
          thumbnailUrl: null,
        ),
      ];

  @override
  List<TopGenreTrack>? get topSongsPerTopGenre => [
        const TopGenreTrack(
          trackId: 'tg1',
          title: 'Genre Track 1',
          artistName: 'Genre Artist',
          thumbnailUrl: null,
          primaryGenre: 'Afrobeat',
          playCount: 20,
        ),
      ];

  @override
  List<PopularItem>? get popularAlbumsAndSingles => [
        const PopularItem(
          kind: 'album',
          id: 'al1',
          title: 'Cool Album',
          artistName: 'Album Artist',
          thumbnailUrl: null,
          playCount: 30,
        ),
        const PopularItem(
          kind: 'single',
          id: 'si1',
          title: 'Hot Single',
          artistName: 'Single Artist',
          thumbnailUrl: null,
          playCount: 25,
        ),
      ];

  @override bool get isLoadingTopSongsPerTopGenre => false;
  @override bool get isLoadingPopularAlbumsAndSingles => false;
  @override bool get isLoadingListeningStats => false;
  @override bool get isLoadingTopArtistsFromHistory => false;

  bool _loadAllCalled = false;
  bool get loadAllCalled => _loadAllCalled;

  @override Future<void> loadAll() async { _loadAllCalled = true; }
  @override Future<void> loadTopSongsPerTopGenre({int genreLimit = 6}) async {}
  @override Future<void> loadPopularAlbumsAndSingles({int limit = 10}) async {}
  @override Future<void> loadListeningStats() async {}
  @override Future<void> loadTopArtistsFromHistory({int limit = 10}) async {}

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
  }

  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SeededPlaylistProvider extends ChangeNotifier implements PlaylistProvider {
  @override
  List<Artist> get favoriteArtists => [
        const Artist(id: 'art1', name: 'Top Artist 1'),
        const Artist(id: 'art2', name: 'Top Artist 2'),
        const Artist(id: 'art3', name: 'Top Artist 3'),
      ];

  @override List<Track> get favoriteTracks => [];
  @override List<Album> get favoriteAlbums => [];
  @override bool isFavorite(String id) => false;
  @override bool isAlbumFavorite(String id) => false;
  @override bool isArtistFavorite(String id) => false;
  @override Future<Set<String>> fetchFavoriteIds() async => {};
  @override Future<Artist> getArtist(String id) => throw UnimplementedError();
  @override Future<void> toggleFavorite(Track track, {DownloadProvider? downloadProvider}) async {}
  @override Future<void> toggleFavoriteAlbum(Album album, {DownloadProvider? downloadProvider}) async {}
  @override Future<void> toggleFavoriteArtist(Artist artist, {DownloadProvider? downloadProvider}) async {}
  @override Future<void> fetchFavoriteTracks() async {}
  @override Future<void> fetchFavoriteAlbums() async {}
  @override Future<void> fetchFavoriteArtists() async {}
  @override dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Widget _buildTestApp({
  required ChartsProvider chartsProvider,
  required HomeFeedProvider homeFeedProvider,
  required PlaylistProvider playlistProvider,
}) {
  return MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<ChartsProvider>.value(value: chartsProvider),
        ChangeNotifierProvider<HomeFeedProvider>.value(value: homeFeedProvider),
        ChangeNotifierProvider<PlaylistProvider>.value(value: playlistProvider),
        ChangeNotifierProvider<DownloadProvider>.value(value: _MockDownloadProvider()),
        ChangeNotifierProvider<HybridCacheService>.value(value: _MockHybridCacheService()),
      ],
      child: const MusicNowScreen(),
    ),
  );
}

class _MockDownloadProvider extends ChangeNotifier implements DownloadProvider {
  @override dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _MockHybridCacheService extends ChangeNotifier implements HybridCacheService {
  @override bool isCached(String trackId) => false;
  @override bool isDownloadedInSqlite(String trackId) => false;
  @override Stream<CachedStateEvent> get stateStream => const Stream.empty();
  @override CachedState getCachedState(String trackId) => CachedState.idle;
  @override dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  testWidgets('Music Now shows 5 sections in correct order', (tester) async {
    final charts = _MockChartsProvider();
    final feed = _SeededHomeFeedProvider();
    final playlist = _SeededPlaylistProvider();

    await tester.pumpWidget(_buildTestApp(
      chartsProvider: charts,
      homeFeedProvider: feed,
      playlistProvider: playlist,
    ));
    await tester.pump();

    expect(find.text('Trending Now'), findsOneWidget);
    expect(find.text('Suggested Artists'), findsOneWidget);
    expect(find.text('Start Listening'), findsOneWidget);
    expect(find.text('Top Artists'), findsOneWidget);
    expect(find.text('Popular Albums & Singles'), findsOneWidget);

    final trendingRect = tester.getRect(find.text('Trending Now'));
    final suggestedRect = tester.getRect(find.text('Suggested Artists'));
    final startRect = tester.getRect(find.text('Start Listening'));
    final topRect = tester.getRect(find.text('Top Artists'));
    final popularRect = tester.getRect(find.text('Popular Albums & Singles'));

    expect(trendingRect.top, lessThan(suggestedRect.top));
    expect(suggestedRect.top, lessThan(startRect.top));
    expect(startRect.top, lessThan(topRect.top));
    expect(topRect.top, lessThan(popularRect.top));
  });

  testWidgets('initState triggers HomeFeedProvider.loadAll', (tester) async {
    final charts = _EmptyChartsProvider();
    final feed = _SeededHomeFeedProvider();
    final playlist = _EmptyPlaylistProvider();

    await tester.pumpWidget(_buildTestApp(
      chartsProvider: charts,
      homeFeedProvider: feed,
      playlistProvider: playlist,
    ));
    await tester.pump();

    expect((feed as _SeededHomeFeedProvider).loadAllCalled, isTrue);
  });

  testWidgets('Sections with empty data are hidden', (tester) async {
    final charts = _EmptyChartsProvider();
    final feed = _EmptyHomeFeedProvider();
    final playlist = _EmptyPlaylistProvider();

    await tester.pumpWidget(_buildTestApp(
      chartsProvider: charts,
      homeFeedProvider: feed,
      playlistProvider: playlist,
    ));
    await tester.pump();

    expect(find.text('Trending Now'), findsNothing);
    expect(find.text('Suggested Artists'), findsNothing);
    expect(find.text('Start Listening'), findsNothing);
    expect(find.text('Top Artists'), findsNothing);
    expect(find.text('Popular Albums & Singles'), findsNothing);
  });
}

class _EmptyChartsProvider extends ChangeNotifier implements ChartsProvider {
  @override List<Track> get ghanaTopSongs => [];
  @override List<Track> get globalTopSongs => [];
  @override List<Album> get featuredAlbums => [];
  @override List<String> get ghanaTopArtists => [];
  @override bool get isLoadingGhana => false;
  @override bool get isLoadingGlobal => false;
  @override bool get isLoadingAlbums => false;
  @override Future<String?> searchArtistId(String artistName) async => null;
  @override Future<void> fetchGhanaTopSongs({bool forceRefresh = false}) async {}
  @override Future<void> fetchGlobalTopSongs({bool forceRefresh = false}) async {}
  @override Future<void> fetchFeaturedAlbums({bool forceRefresh = false}) async {}
}

class _EmptyHomeFeedProvider extends ChangeNotifier implements HomeFeedProvider {
  @override List<HistoryArtistEntry>? get topArtistsFromHistory => const [];
  @override List<TopGenreTrack>? get topSongsPerTopGenre => const [];
  @override List<PopularItem>? get popularAlbumsAndSingles => const [];
  @override bool get isLoadingTopSongsPerTopGenre => false;
  @override bool get isLoadingPopularAlbumsAndSingles => false;
  @override bool get isLoadingListeningStats => false;
  @override bool get isLoadingTopArtistsFromHistory => false;
  @override Future<void> loadAll() async {}
  @override Future<void> loadTopSongsPerTopGenre({int genreLimit = 6}) async {}
  @override Future<void> loadPopularAlbumsAndSingles({int limit = 10}) async {}
  @override Future<void> loadListeningStats() async {}
  @override Future<void> loadTopArtistsFromHistory({int limit = 10}) async {}
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyPlaylistProvider extends ChangeNotifier implements PlaylistProvider {
  @override List<Artist> get favoriteArtists => [];
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
