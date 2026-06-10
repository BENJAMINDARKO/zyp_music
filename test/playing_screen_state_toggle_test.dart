import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:zyp_music/presentation/providers/player_provider.dart';
import 'package:zyp_music/presentation/providers/playlist_provider.dart';
import 'package:zyp_music/presentation/providers/download_provider.dart';
import 'package:zyp_music/service/download_service.dart';
import 'package:zyp_music/presentation/providers/miniplayer_visibility_provider.dart';
import 'package:zyp_music/presentation/providers/settings_provider.dart';
import 'package:zyp_music/core/services/hybrid_cache_service.dart';
import 'package:zyp_music/domain/repositories/audio_repository.dart';
import 'package:zyp_music/domain/entities/playlist.dart';
import 'package:zyp_music/domain/entities/album.dart';
import 'package:zyp_music/domain/entities/artist.dart';
import 'package:zyp_music/domain/entities/video.dart';
import 'package:zyp_music/ui/screens/playing_screen.dart';
import 'package:zyp_music/ui/widgets/single_line_lyrics_widget.dart';
import 'package:zyp_music/ui/widgets/lyrics_timing_slider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive/hive.dart';
import 'dart:async';

class _MockAudioRepository implements AudioRepository {
  final _skipNextCtrl = StreamController<void>.broadcast();
  final _skipPrevCtrl = StreamController<void>.broadcast();
  @override Stream<void> get onSkipNextRequested => _skipNextCtrl.stream;
  @override Stream<void> get onSkipPreviousRequested => _skipPrevCtrl.stream;
  @override Future<String> getAudioUrl(Track track, {String quality = 'adaptive'}) async => '';
  @override Future<void> playTrack(Track track, String audioUrl) async {}
  @override Future<void> play(String url) async {}
  @override Future<void> pause() async {}
  @override Future<void> resume() async {}
  @override Future<void> stop() async {}
  @override Future<void> seek(Duration position) async {}
  @override Future<void> setPlaybackSpeed(double speed) async {}
  @override Future<Duration> getPosition() async => Duration.zero;
  @override Future<Duration> getDuration() async => Duration.zero;
  @override Future<bool> isPlaying() async => false;
  @override Stream<bool> get playingStream => const Stream.empty();
  @override Stream<ProcessingState> get processingStateStream => const Stream.empty();
  @override Stream<Duration> get positionStream => const Stream.empty();
  @override Stream<Duration> get bufferedPositionStream => const Stream.empty();
  @override Stream<Duration> get durationStream => const Stream.empty();
  @override bool get currentTrackCompleted => false;

  String? _mockLyrics;
  void setMockLyrics(String? lyrics) => _mockLyrics = lyrics;

  @override Future<String?> getLyrics(Track track) async => _mockLyrics;
  @override Future<String?> getLyricsOffline(Track track) async => _mockLyrics;
  @override Future<String?> refreshLyrics(Track track) async => _mockLyrics;
  @override Future<List<Track>> getUpNexts(Track track) async => [];
  @override Future<void> preloadTrack(Track track) async {}
  @override Future<void> preloadTrackLyrics(Track track) async {}
  @override Future<AudioSource> buildAudioSource(Track track) => throw UnimplementedError();
}

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
  @override void dispose() { super.dispose(); }
}

void main() {
  setUp(() {
    Hive.init('/tmp/zyp_test_hive_ps');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    FlutterError.onError = FlutterError.presentError;
  });

  /// Builds a PlayingScreen with a loaded track for full-layout tests.
  /// If [lyrics] is provided, the mock audio repository returns it.
  Future<void> pumpWithTrack(WidgetTester tester,
      {Track? track, String? lyrics}) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2.0;

    final repo = _MockAudioRepository();
    repo.setMockLyrics(lyrics);
    final provider = PlayerProvider(
      repo,
      SettingsProvider(),
      HybridCacheService(),
    );
    track ??= Track(id: 't1', title: 'Test', author: 'Artist');
    provider.setQueue([track], startIndex: 0);
    // Fire-and-forget; errors are expected in test environment.
    unawaited(provider.playFromQueue(0));
    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<PlayerProvider>.value(value: provider),
            ChangeNotifierProvider<SettingsProvider>.value(value: SettingsProvider()),
            ChangeNotifierProvider<PlaylistProvider>.value(value: _MockPlaylistProvider()),
            ChangeNotifierProvider<DownloadProvider>.value(value: _MockDownloadProvider()),
            ChangeNotifierProvider<MiniplayerVisibilityProvider>.value(
              value: MiniplayerVisibilityProvider(),
            ),
          ],
          child: const PlayingScreen(),
        ),
      ),
    );
    // Pump frames manually; pumpAndSettle hangs on rotation animation.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('State A shows full-bleed album art by default',
      (tester) async {
    await pumpWithTrack(tester);

    expect(find.byKey(const Key('album-art')), findsOneWidget);
    expect(find.byType(LyricsTimingSlider), findsNothing);
  });

  testWidgets('SingleLineLyricsWidget is shown in State A', (tester) async {
    await pumpWithTrack(tester);

    expect(find.byType(SingleLineLyricsWidget), findsOneWidget);
  });

  testWidgets('State A shows bold title and regular-weight artist without underline',
      (tester) async {
    await pumpWithTrack(tester);

    // Title should be bold, no decoration
    final titleText = tester.widget<Text>(find.text('Test'));
    expect(titleText.style?.fontWeight, FontWeight.bold);
    expect(titleText.style?.decoration, isNull);

    // Artist should be regular weight, no decoration
    final artistText = tester.widget<Text>(find.text('Artist'));
    expect(artistText.style?.fontWeight, FontWeight.normal);
    expect(artistText.style?.decoration, isNull);
  });

  testWidgets('State A element order: art > lyric > title > artist',
      (tester) async {
    final lrc = '[00:00.00]Line one\n[00:05.00]Line two\n[00:10.00]Line three';
    await pumpWithTrack(tester, lyrics: lrc);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final artRect = tester.getRect(find.byKey(const Key('album-art')));
    final lyricRect = tester.getRect(find.byType(SingleLineLyricsWidget));
    final titleRect = tester.getRect(find.text('Test'));
    final artistRect = tester.getRect(find.text('Artist'));

    expect(artRect.bottom, lessThan(lyricRect.top));
    expect(lyricRect.bottom, lessThan(titleRect.top));
    expect(titleRect.bottom, lessThan(artistRect.top));
  });

  testWidgets('lyric line advances as position updates', (tester) async {
    final lrc = '[00:00.00]Line one\n[00:05.00]Line two\n[00:10.00]Line three';
    await pumpWithTrack(tester, lyrics: lrc);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Initially at position 0 → "Line one"
    expect(find.text('Line one'), findsOneWidget);

    // Advance past line 2's start (5s)
    final ctx = tester.element(find.byType(SingleLineLyricsWidget));
    final provider = ctx.read<PlayerProvider>();
    provider.positionNotifier.value = const Duration(milliseconds: 5500);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Line one'), findsNothing);
    expect(find.text('Line two'), findsOneWidget);

    // Advance past line 3's start (10s)
    provider.positionNotifier.value = const Duration(milliseconds: 10500);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Line three'), findsOneWidget);
  });

  testWidgets('tapping lyrics toggle transitions to State B',
      (tester) async {
    await pumpWithTrack(tester);

    await tester.tap(find.byKey(const Key('lyrics-toggle-button')));
    await tester.pump();

    expect(find.byType(LyricsTimingSlider), findsOneWidget);
  });

  testWidgets('tapping lyrics toggle again returns to State A',
      (tester) async {
    await pumpWithTrack(tester);

    await tester.tap(find.byKey(const Key('lyrics-toggle-button')));
    await tester.pump();
    expect(find.byType(LyricsTimingSlider), findsOneWidget);

    await tester.tap(find.byKey(const Key('lyrics-toggle-button')));
    await tester.pump();

    expect(find.byType(LyricsTimingSlider), findsNothing);
  });

  testWidgets('LyricsTimingSlider hidden in State A, visible in State B',
      (tester) async {
    await pumpWithTrack(tester);

    expect(find.byType(LyricsTimingSlider), findsNothing);

    await tester.tap(find.byKey(const Key('lyrics-toggle-button')));
    await tester.pump();

    expect(find.byType(LyricsTimingSlider), findsOneWidget);
  });

  testWidgets('LyricsTimingSlider drag changes sync offset',
      (tester) async {
    await pumpWithTrack(tester);

    await tester.tap(find.byKey(const Key('lyrics-toggle-button')));
    await tester.pump();

    final slider = find.byKey(const Key('lyrics-timing-slider'));
    expect(slider, findsOneWidget);

    await tester.drag(slider, const Offset(200, 0));
    await tester.pump();

    final ctx = tester.element(slider);
    final p = ctx.read<PlayerProvider>();
    expect(p.lyricsSyncOffsetMs, isNot(0));
  });
}
