import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:zyp_music/domain/entities/video.dart';
import 'package:zyp_music/domain/entities/album.dart';
import 'package:zyp_music/domain/entities/artist.dart';
import 'package:zyp_music/domain/entities/playlist.dart';
import 'package:zyp_music/presentation/providers/charts_provider.dart';
import 'package:zyp_music/presentation/providers/playlist_provider.dart';
import 'package:zyp_music/presentation/providers/download_provider.dart';
import 'package:zyp_music/service/download_service.dart';
import 'package:zyp_music/core/services/hybrid_cache_service.dart';
import 'package:zyp_music/domain/repositories/playlist_repository.dart';
import 'package:zyp_music/ui/screens/home_screen.dart';

class _MockChartsProvider extends ChangeNotifier implements ChartsProvider {
  @override List<Track> ghanaTopSongs = [];
  @override List<Track> globalTopSongs = [];
  @override List<Album> featuredAlbums = [];
  @override List<String> ghanaTopArtists = [];
  @override bool isLoadingGhana = false;
  @override bool isLoadingGlobal = false;
  @override bool isLoadingAlbums = false;
  @override Future<void> fetchGhanaTopSongs({bool forceRefresh = false}) async {}
  @override Future<void> fetchGlobalTopSongs({bool forceRefresh = false}) async {}
  @override Future<void> fetchFeaturedAlbums({bool forceRefresh = false}) async {}
  @override Future<String?> searchArtistId(String artistName) async => null;
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
  @override void dispose() { super.dispose(); }
}

class _MockPlaylistRepo implements PlaylistRepository {
  @override Future<List<Playlist>> getSavedPlaylists() async => [];
  @override Future<Set<String>> getFavoriteIds() async => {};
  @override Future<List<Track>> getFavoriteTracks() async => [];
  @override Future<List<Album>> getFavoriteAlbums() async => [];
  @override Future<List<Artist>> getFavoriteArtists() async => [];
  @override Future<Playlist> getPlaylist(String id) => throw UnimplementedError();
  @override Future<Playlist> getFromUrl(String url) => throw UnimplementedError();
  @override Future<void> savePlaylist(Playlist p) async {}
  @override Future<void> deletePlaylist(String id) async {}
  @override Future<void> renamePlaylist(String id, String newName) async {}
  @override Future<void> updateTrackInPlaylist(String playlistId, Track track) async {}
  @override
  Future<void> saveTrack(String playlistId, Track track) async {}
  @override
  Future<void> saveTracks(String playlistId, List<Track> tracks) async {}
  @override
  Future<void> saveLocalFileTrack(String playlistId, Track track, String filePath) async {}
  @override Future<List<Track>> getCachedTracks(String pid) async => [];
  @override Future<Playlist?> getCachedPlaylist(String pid) async => null;
  @override Future<List<Track>> search(String q) async => [];
  @override Future<List<Track>> searchTracks(String q) async => [];
  @override Future<List<Album>> searchAlbums(String q) async => [];
  @override Future<List<Artist>> searchArtists(String q) async => [];
  @override Future<List<Playlist>> searchPlaylists(String q) async => [];
  @override Future<Album> getAlbum(String id) => throw UnimplementedError();
  @override Future<Artist> getArtist(String id) => throw UnimplementedError();
  @override Future<List<Track>> getEditorsPicks() async => [];
  @override Future<void> toggleFavorite(Track t) async {}
  @override Future<bool> isFavorite(String id) async => false;
  @override Future<void> toggleFavoriteAlbum(Album a) async {}
  @override Future<bool> isAlbumFavorite(String id) async => false;
  @override Future<void> toggleFavoriteArtist(Artist a) async {}
  @override Future<bool> isArtistFavorite(String id) async => false;
  @override Future<void> updatePlaylistTitle(String id, String t) async {}
  @override Future<void> removeTrack(String pid, String tid) async {}
  @override Future<void> reorderTracks(String pid, List<String> ids) async {}
}

class _SeededPlaylistProvider extends PlaylistProvider {
  _SeededPlaylistProvider() : super(_MockPlaylistRepo());

  List<Track> _favTracks = [];
  List<Artist> _favArtists = [];
  List<Album> _favAlbums = [];

  set seededFavTracks(List<Track> v) { _favTracks = v; notifyListeners(); }
  set seededFavArtists(List<Artist> v) { _favArtists = v; notifyListeners(); }
  set seededFavAlbums(List<Album> v) { _favAlbums = v; notifyListeners(); }

  @override
  List<Track> get favoriteTracks => _favTracks;
  @override
  List<Artist> get favoriteArtists => _favArtists;
  @override
  List<Album> get favoriteAlbums => _favAlbums;
  @override
  bool isFavorite(String trackId) => _favTracks.any((t) => t.id == trackId);
  @override
  Future<void> toggleFavorite(Track track, {DownloadProvider? downloadProvider}) async {}
  @override
  Future<void> toggleFavoriteAlbum(Album album, {DownloadProvider? downloadProvider}) async {}
  @override
  Future<void> loadSavedPlaylists() async {}
  @override
  Future<void> loadFavorites() async {}
}

final _testTracks = [
  Track(id: 's1', title: 'Suggested One', author: 'Artist A'),
  Track(id: 's2', title: 'Suggested Two', author: 'Artist B'),
];

final _testAlbums = [
  Album(id: 'a1', title: 'Album One', artistName: 'Artist A'),
];

final _testArtists = [
  Artist(id: 'r1', name: 'Artist A'),
];

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

  testWidgets('renders 5 section headers in order', (tester) async {
    tester.view.physicalSize = const Size(480, 844);
    tester.view.devicePixelRatio = 1.0;

    final chartsProvider = _MockChartsProvider();
    chartsProvider.ghanaTopSongs = _testTracks;
    chartsProvider.globalTopSongs = _testTracks;
    chartsProvider.featuredAlbums = _testAlbums;

    final playlistProvider = _SeededPlaylistProvider();
    playlistProvider.seededFavTracks = _testTracks;
    playlistProvider.seededFavArtists = _testArtists;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ChartsProvider>.value(value: chartsProvider),
          ChangeNotifierProvider<PlaylistProvider>.value(value: playlistProvider),
          ChangeNotifierProvider.value(value: _MockDownloadProvider()),
          ChangeNotifierProvider.value(value: HybridCacheService()),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    // Drain any RenderFlex overflow errors from card layouts
    while (tester.takeException() != null) {}

    final headerTexts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where((d) => d != null)
        .cast<String>()
        .toList();

    final expected = [
      'Suggested Songs',
      'Liked Songs',
      'Featured Albums',
      'Favourite Artists',
      'Global Hot',
    ];

    for (final h in expected) {
      expect(find.text(h), findsOneWidget);
    }

    final indices =
        expected.map((h) => headerTexts.indexOf(h)).toList();
    for (var i = 1; i < indices.length; i++) {
      expect(indices[i], greaterThan(indices[i - 1]),
          reason:
              'Section "${expected[i]}" should appear after "${expected[i - 1]}"');
    }
  });
}
