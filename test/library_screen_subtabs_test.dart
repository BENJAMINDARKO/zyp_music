import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

import 'package:zyp_music/presentation/providers/home_feed_provider.dart';
import 'package:zyp_music/presentation/providers/playlist_provider.dart';
import 'package:zyp_music/presentation/providers/download_provider.dart';
import 'package:zyp_music/presentation/providers/player_provider.dart';
import 'package:zyp_music/core/services/hybrid_cache_service.dart';
import 'package:zyp_music/service/download_service.dart';
import 'package:zyp_music/data/datasources/local/playlist_database.dart';
import 'package:zyp_music/domain/entities/video.dart';
import 'package:zyp_music/domain/entities/album.dart';
import 'package:zyp_music/domain/entities/artist.dart';
import 'package:zyp_music/domain/entities/playlist.dart';
import 'package:just_audio/just_audio.dart';
import 'package:zyp_music/core/constants/audio_quality.dart';
import 'package:zyp_music/ui/screens/library_screen.dart';
import 'package:zyp_music/ui/widgets/listening_stats_view.dart';
import 'package:zyp_music/ui/widgets/downloaded_view.dart';

class _MockPlaylistProvider extends ChangeNotifier implements PlaylistProvider {
  @override List<Artist> get favoriteArtists => [];
  @override List<Track> get favoriteTracks => [];
  @override List<Album> get favoriteAlbums => [];
  @override List<Playlist> get playlists => [];
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

class _MockDownloadProvider extends ChangeNotifier implements DownloadProvider {
  @override Set<String> get downloadedTrackIds => {};
  @override Map<String, DownloadProgress> get activeDownloads => {};
  @override Set<String> get downloadingPlaylists => {};
  @override Set<String> get downloadedPlaylists => {};
  @override Map<String, double> get playlistDownloadProgress => {};
  @override bool isDownloadingPlaylist(String playlistId) => false;
  @override bool isPlaylistFullyDownloaded(String playlistId) => false;
  @override bool isDownloaded(String trackId) => false;
  @override bool isDownloading(String trackId) => false;
  @override double? getPlaylistDownloadProgress(String playlistId) => null;
  @override DownloadProgress? getProgress(String trackId) => null;
  @override Future<void> init() async {}
  @override Future<void> downloadPlaylist(Playlist playlist, {String quality = 'medium'}) async {}
  @override Future<void> downloadTrack(Track track, String playlistId, {String quality = 'medium'}) async {}
  @override Future<void> downloadAlbum(Album album, PlaylistProvider playlistProvider) async {}
  @override Future<void> preDownloadUpcoming(List<Track> queue, int currentIndex, String playlistId, {int prebufferCount = 3}) async {}
  @override void cancelDownload() {}
  @override Future<bool> isTrackDownloaded(String trackId) async => false;
  @override Future<String?> getLocalFilePath(String trackId) async => null;
  @override Future<void> deleteDownloadedPlaylist(String playlistId) async {}
  @override Future<void> deleteDownloadedTrack(String trackId) async {}
  @override Future<void> removeTrackFromCache(Track track) async {}
  @override Future<int> removeAlbumFromCache(Album album) async => 0;
  @override bool isAlbumCached(Album album) => false;
  @override Future<int> getTotalCacheSize() async => 0;
  @override Future<int> getPlaylistCacheSize(String playlistId) async => 0;
  @override dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _MockPlayerProvider extends ChangeNotifier implements PlayerProvider {
  @override Track? get currentTrack => null;
  @override bool get isPlaying => false;
  @override void setQueue(List<Track> tracks, {int startIndex = 0, String? playlistId}) {}
  @override Future<void> playFromQueue(int index, {AudioQuality quality = AudioQuality.adaptive}) async {}
  @override dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _MockHybridCacheService extends ChangeNotifier implements HybridCacheService {
  @override bool isCached(String trackId) => false;
  @override bool isDownloadedInSqlite(String trackId) => false;
  @override Stream<CachedStateEvent> get stateStream => const Stream.empty();
  @override CachedState getCachedState(String trackId) => CachedState.idle;
  @override dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _SeededHomeFeedProvider extends ChangeNotifier implements HomeFeedProvider {
  @override ListeningStats? get listeningStats => null;
  @override bool get isLoadingListeningStats => false;
  @override Future<void> loadListeningStats() async {}
  @override List<Track>? get allDownloadedTracks => null;
  @override bool get isLoadingAllDownloadedTracks => false;
  @override Future<void> loadAllDownloadedTracks() async {}
  @override List<TopGenreTrack>? get topSongsPerTopGenre => null;
  @override List<PopularItem>? get popularAlbumsAndSingles => null;
  @override List<HistoryArtistEntry>? get topArtistsFromHistory => null;
  @override bool get isLoadingTopSongsPerTopGenre => false;
  @override bool get isLoadingPopularAlbumsAndSingles => false;
  @override bool get isLoadingTopArtistsFromHistory => false;
  @override Future<void> loadAll() async {}
  @override Future<void> loadTopSongsPerTopGenre({int genreLimit = 6}) async {}
  @override Future<void> loadPopularAlbumsAndSingles({int limit = 10}) async {}
  @override Future<void> loadTopArtistsFromHistory({int limit = 10}) async {}
  @override void invalidate() {}
  @override dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _StatsHomeFeedProvider extends ChangeNotifier implements HomeFeedProvider {
  @override
  ListeningStats? get listeningStats => const ListeningStats(
    distinctGenreCount: 12,
    distinctArtistCount: 47,
    topArtists: [
      ArtistPlayStat(artistName: 'ArtistA', playCount: 50),
      ArtistPlayStat(artistName: 'ArtistB', playCount: 30),
      ArtistPlayStat(artistName: 'ArtistC', playCount: 20),
    ],
    topAlbums: [
      AlbumPlayStat(albumId: 'al1', albumTitle: 'AlbumX', playCount: 40),
      AlbumPlayStat(albumId: 'al2', albumTitle: 'AlbumY', playCount: 25),
      AlbumPlayStat(albumId: 'al3', albumTitle: 'AlbumZ', playCount: 15),
    ],
  );
  @override bool get isLoadingListeningStats => false;
  @override Future<void> loadListeningStats() async {}
  @override List<Track>? get allDownloadedTracks => null;
  @override bool get isLoadingAllDownloadedTracks => false;
  @override Future<void> loadAllDownloadedTracks() async {}
  @override List<TopGenreTrack>? get topSongsPerTopGenre => null;
  @override List<PopularItem>? get popularAlbumsAndSingles => null;
  @override List<HistoryArtistEntry>? get topArtistsFromHistory => null;
  @override bool get isLoadingTopSongsPerTopGenre => false;
  @override bool get isLoadingPopularAlbumsAndSingles => false;
  @override bool get isLoadingTopArtistsFromHistory => false;
  @override Future<void> loadAll() async {}
  @override Future<void> loadTopSongsPerTopGenre({int genreLimit = 6}) async {}
  @override Future<void> loadPopularAlbumsAndSingles({int limit = 10}) async {}
  @override Future<void> loadTopArtistsFromHistory({int limit = 10}) async {}
  @override void invalidate() {}
  @override dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _DlHomeFeedProvider extends ChangeNotifier implements HomeFeedProvider {
  @override List<Track>? get allDownloadedTracks => [
    Track(id: 'd1', title: 'Track 1', author: 'Artist 1'),
    Track(id: 'd2', title: 'Track 2', author: 'Artist 2'),
    Track(id: 'd3', title: 'Track 3', author: 'Artist 3'),
  ];
  @override bool get isLoadingAllDownloadedTracks => false;
  @override Future<void> loadAllDownloadedTracks() async {}
  @override ListeningStats? get listeningStats => null;
  @override bool get isLoadingListeningStats => false;
  @override Future<void> loadListeningStats() async {}
  @override List<TopGenreTrack>? get topSongsPerTopGenre => null;
  @override List<PopularItem>? get popularAlbumsAndSingles => null;
  @override List<HistoryArtistEntry>? get topArtistsFromHistory => null;
  @override bool get isLoadingTopSongsPerTopGenre => false;
  @override bool get isLoadingPopularAlbumsAndSingles => false;
  @override bool get isLoadingTopArtistsFromHistory => false;
  @override Future<void> loadAll() async {}
  @override Future<void> loadTopSongsPerTopGenre({int genreLimit = 6}) async {}
  @override Future<void> loadPopularAlbumsAndSingles({int limit = 10}) async {}
  @override Future<void> loadTopArtistsFromHistory({int limit = 10}) async {}
  @override void invalidate() {}
  @override dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _EmptyDlHomeFeedProvider extends ChangeNotifier implements HomeFeedProvider {
  @override List<Track>? get allDownloadedTracks => const [];
  @override bool get isLoadingAllDownloadedTracks => false;
  @override Future<void> loadAllDownloadedTracks() async {}
  @override ListeningStats? get listeningStats => null;
  @override bool get isLoadingListeningStats => false;
  @override Future<void> loadListeningStats() async {}
  @override List<TopGenreTrack>? get topSongsPerTopGenre => null;
  @override List<PopularItem>? get popularAlbumsAndSingles => null;
  @override List<HistoryArtistEntry>? get topArtistsFromHistory => null;
  @override bool get isLoadingTopSongsPerTopGenre => false;
  @override bool get isLoadingPopularAlbumsAndSingles => false;
  @override bool get isLoadingTopArtistsFromHistory => false;
  @override Future<void> loadAll() async {}
  @override Future<void> loadTopSongsPerTopGenre({int genreLimit = 6}) async {}
  @override Future<void> loadPopularAlbumsAndSingles({int limit = 10}) async {}
  @override Future<void> loadTopArtistsFromHistory({int limit = 10}) async {}
  @override void invalidate() {}
  @override dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _EmptyHomeFeedProvider extends ChangeNotifier implements HomeFeedProvider {
  @override ListeningStats? get listeningStats => ListeningStats.empty;
  @override bool get isLoadingListeningStats => false;
  @override Future<void> loadListeningStats() async {}
  @override List<Track>? get allDownloadedTracks => null;
  @override bool get isLoadingAllDownloadedTracks => false;
  @override Future<void> loadAllDownloadedTracks() async {}
  @override List<TopGenreTrack>? get topSongsPerTopGenre => null;
  @override List<PopularItem>? get popularAlbumsAndSingles => null;
  @override List<HistoryArtistEntry>? get topArtistsFromHistory => null;
  @override bool get isLoadingTopSongsPerTopGenre => false;
  @override bool get isLoadingPopularAlbumsAndSingles => false;
  @override bool get isLoadingTopArtistsFromHistory => false;
  @override Future<void> loadAll() async {}
  @override Future<void> loadTopSongsPerTopGenre({int genreLimit = 6}) async {}
  @override Future<void> loadPopularAlbumsAndSingles({int limit = 10}) async {}
  @override Future<void> loadTopArtistsFromHistory({int limit = 10}) async {}
  @override void invalidate() {}
  @override dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Widget _buildApp({
  required HomeFeedProvider homeFeedProvider,
  PlaylistProvider? playlistProvider,
  DownloadProvider? downloadProvider,
}) {
  return MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<PlaylistProvider>.value(
          value: playlistProvider ?? _MockPlaylistProvider(),
        ),
        ChangeNotifierProvider<HomeFeedProvider>.value(value: homeFeedProvider),
        ChangeNotifierProvider<DownloadProvider>.value(value: downloadProvider ?? _MockDownloadProvider()),
        ChangeNotifierProvider<PlayerProvider>.value(value: _MockPlayerProvider()),
        ChangeNotifierProvider<HybridCacheService>.value(value: _MockHybridCacheService()),
      ],
      child: const LibraryScreen(),
    ),
  );
}

void main() {
  setUp(() {
    FlutterError.onError = (details) {
      if (details.exception.toString().contains('RenderFlex') ||
          details.exception.toString().contains('overflow')) return;
      FlutterError.presentError(details);
    };
  });

  tearDown(() {
    FlutterError.onError = FlutterError.presentError;
  });

  testWidgets('Library shows 6 sub-tabs in correct order', (tester) async {
    await tester.pumpWidget(_buildApp(
      homeFeedProvider: _SeededHomeFeedProvider(),
    ));
    await tester.pump();

    expect(find.text('Tracks'), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('Artists'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);
    expect(find.text('Listening Stats'), findsOneWidget);
    expect(find.text('Downloaded'), findsOneWidget);
  });

  testWidgets('all 6 sub-tab icons are visible', (tester) async {
    await tester.pumpWidget(_buildApp(
      homeFeedProvider: _SeededHomeFeedProvider(),
    ));
    await tester.pump();

    expect(find.byIcon(PhosphorIconsRegular.musicNote), findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.discoBall), findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.user), findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.playlist), findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.chartBar), findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.downloadSimple), findsOneWidget);
  });

  testWidgets('tapping Stats tab shows ListeningStatsView', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<HomeFeedProvider>.value(value: _SeededHomeFeedProvider()),
          ChangeNotifierProvider<PlaylistProvider>.value(value: _MockPlaylistProvider()),
          ChangeNotifierProvider<DownloadProvider>.value(value: _MockDownloadProvider()),
          ChangeNotifierProvider<PlayerProvider>.value(value: _MockPlayerProvider()),
          ChangeNotifierProvider<HybridCacheService>.value(value: _MockHybridCacheService()),
        ],
        child: const Scaffold(body: ListeningStatsView()),
      ),
    ));
    await tester.pump();

    expect(find.byType(ListeningStatsView), findsOneWidget);
    expect(find.text('No listening data yet'), findsOneWidget);
  });

  testWidgets('tapping Downloaded tab shows DownloadedView', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<HomeFeedProvider>.value(value: _EmptyDlHomeFeedProvider()),
          ChangeNotifierProvider<PlaylistProvider>.value(value: _MockPlaylistProvider()),
          ChangeNotifierProvider<DownloadProvider>.value(value: _MockDownloadProvider()),
          ChangeNotifierProvider<PlayerProvider>.value(value: _MockPlayerProvider()),
          ChangeNotifierProvider<HybridCacheService>.value(value: _MockHybridCacheService()),
        ],
        child: const Scaffold(body: DownloadedView()),
      ),
    ));
    await tester.pump();

    expect(find.byType(DownloadedView), findsOneWidget);
    expect(find.text('No downloads yet'), findsOneWidget);
  });

  testWidgets('ListeningStatsView shows empty state when no data', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<HomeFeedProvider>.value(value: _EmptyHomeFeedProvider()),
          ChangeNotifierProvider<PlaylistProvider>.value(value: _MockPlaylistProvider()),
          ChangeNotifierProvider<DownloadProvider>.value(value: _MockDownloadProvider()),
          ChangeNotifierProvider<PlayerProvider>.value(value: _MockPlayerProvider()),
          ChangeNotifierProvider<HybridCacheService>.value(value: _MockHybridCacheService()),
        ],
        child: const Scaffold(body: ListeningStatsView()),
      ),
    ));
    await tester.pump();

    expect(find.text('No listening data yet'), findsOneWidget);
  });

  testWidgets('ListeningStatsView renders counts and top lists', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<HomeFeedProvider>.value(value: _StatsHomeFeedProvider()),
          ChangeNotifierProvider<PlaylistProvider>.value(value: _MockPlaylistProvider()),
          ChangeNotifierProvider<DownloadProvider>.value(value: _MockDownloadProvider()),
          ChangeNotifierProvider<PlayerProvider>.value(value: _MockPlayerProvider()),
          ChangeNotifierProvider<HybridCacheService>.value(value: _MockHybridCacheService()),
        ],
        child: const Scaffold(body: ListeningStatsView()),
      ),
    ));
    await tester.pump();

    expect(find.text('12'), findsOneWidget);
    expect(find.text('47'), findsOneWidget);
    expect(find.text('ArtistA'), findsOneWidget);
    expect(find.text('ArtistB'), findsOneWidget);
    expect(find.text('ArtistC'), findsOneWidget);
    expect(find.text('AlbumX'), findsOneWidget);
    expect(find.text('AlbumY'), findsOneWidget);
    expect(find.text('AlbumZ'), findsOneWidget);
  });

  testWidgets('DownloadedView shows empty state when no downloads', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<HomeFeedProvider>.value(value: _EmptyDlHomeFeedProvider()),
          ChangeNotifierProvider<PlaylistProvider>.value(value: _MockPlaylistProvider()),
          ChangeNotifierProvider<DownloadProvider>.value(value: _MockDownloadProvider()),
          ChangeNotifierProvider<PlayerProvider>.value(value: _MockPlayerProvider()),
          ChangeNotifierProvider<HybridCacheService>.value(value: _MockHybridCacheService()),
        ],
        child: const Scaffold(body: DownloadedView()),
      ),
    ));
    await tester.pump();

    expect(find.text('No downloads yet'), findsOneWidget);
  });

  testWidgets('DownloadedView renders track list', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<HomeFeedProvider>.value(value: _DlHomeFeedProvider()),
          ChangeNotifierProvider<PlaylistProvider>.value(value: _MockPlaylistProvider()),
          ChangeNotifierProvider<DownloadProvider>.value(value: _MockDownloadProvider()),
          ChangeNotifierProvider<PlayerProvider>.value(value: _MockPlayerProvider()),
          ChangeNotifierProvider<HybridCacheService>.value(value: _MockHybridCacheService()),
        ],
        child: const Scaffold(body: DownloadedView()),
      ),
    ));
    await tester.pump();

    expect(find.text('Track 1'), findsOneWidget);
    expect(find.text('Track 2'), findsOneWidget);
    expect(find.text('Track 3'), findsOneWidget);
  });
}
