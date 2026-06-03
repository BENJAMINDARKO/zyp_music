# zyp_music — YouTube Music Streamer

`zyp_music` is a modern, lightweight Flutter mobile application that streams and downloads audio directly from public YouTube playlists, search results, individual videos, and auto-generated mixes. Designed to be completely ad-free and offline-first, it caches your music so you can listen without redundant data usage or network interruptions.

## Inspiration & Sourced Features

`zyp_music` is heavily inspired by **[Monochrome.tf](https://monochrome.tf)** for its overall design aesthetic and audio experiences.

The app is built on top of and inspired by several open-source audio players and streaming utilities:
- **Primary Codebase & Architecture**: Sourced and inspired from **ytmusix** by niiabe ([niiabe/ytmusix-flowos](https://github.com/niiabe/ytmusix-flowos)).
- **Feature Roadmap & Enhancements**: Sourced from:
  - **monochrome-music/monochrome** (animated album cover art, customized audio visualizer, Genius integration for synced karaoke lyrics, real-time listening parties, and account sync)

A detailed future feature roadmap can be found in [docs/futureroadmap.txt](file:///Users/mmm/zyp_music/docs/futureroadmap.txt).

---

## Features

### Playback & Audio
- **Offline-first** — plays from local files when downloaded, streams only when unavailable; no redundant redirect resolution.
- **Background Playback & Lockscreen controls** — Android media notification with play/pause/skip buttons using `audio_service`.
- **Play/pause state indicators** — toggle icon reflects playback status on home screen, playlist screen, player bar, and expanded player.
- **Queue management** — play, pause, skip, previous, shuffle, repeat (loop one, loop all), and auto-advance on track completion.
- **Sleep timer** — 15m/30m/60m/custom timer to auto-stop playback.
- **Pre-download ahead** — silently pre-downloads the next tracks in the queue so there's no delay between songs.

### Import & Search
- **YouTube search** — search YouTube directly from the app, play results instantly.
- **URL import** — paste a video, playlist, or mix URL to add to your library.
- **Auto-save to library** — searched and played tracks are automatically saved to your homescreen as single-track playlists.

### Downloads & Cache
- **Per-track download** — download individual tracks directly from the playlist list.
- **Playlist download** — bulk download with per-track progress, percentage, and cancel support.
- **Download status colors** — green icon when fully downloaded, orange while downloading, spinner for in-progress tracks.
- **Home screen download** — download playlists directly from the home screen card (with cached tracks).
- **Cache management** — view total cache size in settings; clear per-playlist or all cached downloads.

### Playlist Management
- **Sort playlists** — by title, date added, or track count.
- **Import/Export** — backup and restore your library as JSON, XML, or Markdown.
- **Swipe to delete** — remove playlists with a swipe.
- **Rename playlists** — edit playlist title inline.
- **Reorder tracks** — long-press drag to reorder tracks within a playlist.
- **Remove individual tracks** — swipe-to-delete on any track.
- **Star / Favorites** — star/unstar tracks anywhere (playlist, player, search); dedicated "Favorites" playlist card on home screen.

### UI
- **Now-playing card** — home screen shows current track with thumbnail, controls, progress bar; tap for expanded player.
- **Expanded player** — full-screen with album art, seek slider, large playback controls.
- **Mini player** — persistent bar at the bottom of the playlist screen.
- **Recently played** — horizontal scrolling list of recently played tracks.
- **Dark theme** — Spotify-inspired dark UI with custom pixel-art logo.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter (Dart) |
| Architecture | Hexagonal (domain/data/presentation) |
| State | Provider |
| YouTube API | `youtube_explode_dart` 3.1.0 (patched client version) |
| Audio playback | `just_audio` 0.9.46 |
| Lockscreen/notification | `audio_service` 0.18.18 |
| Storage | sqflite (SQLite) |
| Secure storage | flutter_secure_storage |
| Downloads | path_provider + http |
| Auth | WebView cookie extraction |

## Prerequisites

- Flutter SDK ^3.12.0
- Android device or emulator

## Setup

```bash
git clone https://github.com/BENJAMINDARKO/zyp_music.git
cd zyp_music
flutter pub get
```

### Pub Cache Patch (youtube_explode_dart)

The `youtube_explode_dart` package needs a patch to return non-empty browse API results:

**File:** `$PUB_CACHE/hosted/pub.dev/youtube_explode_dart-3.1.0/lib/src/reverse_engineering/youtube_http_client.dart`

Change the InnerTube client context to:
```dart
'clientName': "WEB",
'clientVersion': "2.20250601.00.00",
```

Without this patch, the browse API returns empty `contents` and mix playlists fail to load.

> **Note:** This patch is overwritten on `flutter pub upgrade` — must be re-applied.

### Run (Debug)

```bash
flutter run
```

### Build Release APK

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk` (<75MB)

## Project Structure

```
lib/
├── app.dart                            # App widget and theme setup
├── main.dart                           # Entry point, initializes DI and AudioService
├── core/
│   ├── constants/
│   │   ├── app_constants.dart
│   │   ├── audio_quality.dart
│   │   ├── playlist_sort_mode.dart
│   │   └── repeat_mode.dart
│   ├── navigation/
│   │   └── navigator_key.dart          # Global key for context-less navigation
│   ├── services/
│   │   └── audio_cache_service.dart    # Manages local audio download/playback caching
│   ├── theme/
│   │   └── app_theme.dart              # Main application styling and themes
│   └── utils/
│       ├── app_logger.dart
│       ├── format_duration.dart
│       ├── network_utils.dart
│       └── normalise.dart
├── data/
│   ├── datasources/
│   │   ├── local/
│   │   │   └── playlist_database.dart  # SQLite database implementation
│   │   └── remote/
│   │       ├── authenticated_client.dart
│   │       ├── charts_remote_datasource.dart
│   │       ├── lyrics_remote_datasource.dart
│   │       ├── tidal_remote_datasource.dart
│   │       ├── youtube_audio_extractor.dart
│   │       └── youtube_remote_datasource.dart
│   ├── models/
│   │   ├── playlist_model.dart
│   │   └── video_model.dart
│   └── repositories/
│       ├── audio_repository_impl.dart
│       ├── charts_repository_impl.dart
│       └── playlist_repository_impl.dart
├── domain/
│   ├── entities/
│   │   ├── album.dart
│   │   ├── artist.dart
│   │   ├── lyric_line.dart
│   │   ├── playlist.dart
│   │   └── video.dart
│   └── repositories/
│       ├── audio_repository.dart
│       └── playlist_repository.dart
├── presentation/
│   └── providers/
│       ├── charts_provider.dart
│       ├── download_provider.dart
│       ├── miniplayer_visibility_provider.dart
│       ├── player_provider.dart
│       ├── playlist_provider.dart
│       └── settings_provider.dart
├── service/
│   ├── audio_handler.dart              # Bridge between audio_service and player
│   ├── auth_service.dart
│   ├── download_service.dart
│   └── oauth_service.dart
├── services/
│   ├── playback_session.dart
│   └── youtube_service.dart
└── ui/
    ├── layout/
    │   └── main_layout.dart
    ├── screens/
    │   ├── album_screen.dart
    │   ├── artist_screen.dart
    │   ├── home_screen.dart
    │   ├── library_screen.dart
    │   ├── playing_screen.dart
    │   ├── playlist_screen.dart
    │   ├── settings_screen.dart
    │   ├── search_screen.dart
    │   └── youtube_login_webview.dart
    └── widgets/
        ├── add_to_playlist_modal.dart
        ├── audio_visualizer.dart
        ├── bottom_player.dart
        ├── custom_audio_seekbar.dart
        ├── custom_lyrics_modal.dart
        ├── glass_sidebar.dart
        ├── global_background.dart
        ├── playlist_picker_dialog.dart
        ├── synced_lyrics_widget.dart
        └── track_context_menu.dart
```

## Testing

```bash
flutter test
```

_(No tests currently — test directory removed during refactoring.)_

## Known Issues / Bugs

- **Playlist**: Currently broken and does not load/play correctly.
- **Offline playing**: Playing downloaded/cached files offline is currently broken.
- **Caching**: Audio caching is not functional.
- **System theme**: The system theme is broken and does not apply correctly.
- **Pub cache patch** — overwritten when `flutter pub upgrade` runs; must be re-applied manually.
- **Samsung GPU `BufferQueue` timeout** — harmless Adreno driver spam in logcat on Exynos devices; does not affect playback.

## License

Personal / educational use.