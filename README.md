# ytmusix — YouTube Music Streamer

A Flutter mobile app that streams audio from public YouTube playlists, single videos, and mixes. No backend, no ads.

## Features

### Playback
- **Offline-first** — plays from local files when downloaded, streams only when unavailable; no redundant redirect resolution
- **Play/pause state indicators** — toggle icon reflects playback status on home screen, playlist screen, player bar, and expanded player
- **Queue management** — play, pause, skip, previous, auto-advance on track completion
- **Pre-download ahead** — silently downloads the next 3 tracks in the queue so there's no delay between songs
- **Lockscreen & notification controls** — Android media notification with play/pause/skip buttons

### Import & Search
- **Collapsible search bar** — search icon expands into the full URL input field, retracts after submission
- **YouTube URL import** — paste a video, playlist, or mix URL (RD mixes included)

### Downloads
- **Per-track download** — download individual tracks directly from the playlist list
- **Playlist download** — bulk download with per-track progress, percentage, and cancel support
- **Download status colors** — green icon when fully downloaded, orange while downloading, spinner for in-progress tracks
- **Home screen download** — download playlists directly from the home screen card (with cached tracks)

### UI
- **Now-playing card** — home screen shows current track with thumbnail, controls, progress bar; tap for expanded player
- **Expanded player** — full-screen with album art, seek slider, large playback controls
- **Mini player** — persistent bar at the bottom of the playlist screen
- **Dark theme** — Spotify-inspired dark UI with custom pixel-art logo
- **Playlist management** — swipe to delete, play/pause from card, auto-download flag

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
git clone https://github.com/niiabe/ytmusix-flowos.git
cd ytmusix-flowos
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

Output: `build/app/outputs/flutter-apk/app-release.apk` (~55MB)

## Project Structure

```
lib/
├── app.dart                        # App entry point + theme
├── main.dart                       # DI + AudioService.init
├── core/
│   ├── constants/
│   │   ├── app_constants.dart
│   │   ├── audio_quality.dart
│   │   ├── playlist_sort_mode.dart
│   │   └── repeat_mode.dart
│   ├── theme/
│   │   └── app_theme.dart          # Dark Spotify-inspired theme
│   └── utils/
│       ├── format_duration.dart
│       └── network_utils.dart      # Redirect resolution
├── domain/
│   ├── entities/
│   │   ├── playlist.dart
│   │   └── video.dart              # Track entity
│   └── repositories/
│       ├── audio_repository.dart
│       └── playlist_repository.dart
├── data/
│   ├── datasources/
│   │   ├── remote/
│   │   │   ├── youtube_remote_datasource.dart
│   │   │   └── authenticated_client.dart
│   │   └── local/
│   │       └── playlist_database.dart  # SQLite
│   ├── models/
│   │   ├── playlist_model.dart
│   │   └── video_model.dart
│   └── repositories/
│       ├── audio_repository_impl.dart
│       └── playlist_repository_impl.dart
├── presentation/
│   ├── screens/
│   │   ├── home_screen.dart
│   │   ├── player_screen.dart      # Full-screen player
│   │   ├── playlist_screen.dart
│   │   ├── search_screen.dart
│   │   ├── settings_screen.dart
│   │   └── login_screen.dart       # WebView Google auth
│   ├── providers/
│   │   ├── player_provider.dart
│   │   ├── playlist_provider.dart
│   │   ├── download_provider.dart
│   │   └── settings_provider.dart
│   └── widgets/
│       ├── player_bar.dart
│       ├── video_tile.dart
│       ├── playlist_card.dart
│       ├── now_playing_card.dart
│       ├── queue_sheet.dart
│       └── pixel_logo.dart
└── service/
    ├── audio_handler.dart          # MusicAudioHandler (audio_service bridge)
    ├── auth_service.dart           # flutter_secure_storage cookies
    └── download_service.dart       # Offline downloads with progress
```

## Testing

```bash
flutter test
```

39 tests covering models, providers, utilities, services, and widgets.

## Known Issues

### App
- **Pub cache patch** — overwritten when `flutter pub upgrade` runs; must be re-applied manually.
- **YouTube mixes** — may still not load depending on mix metadata structure (tracked in `futureroadmap.txt`).
- **Samsung GPU `BufferQueue` timeout** — harmless Adreno driver spam in logcat on Exynos devices; does not affect playback.

### Code Quality (tracked in `errorandFeatureRequest.txt`)
- **300ms polling** — `PlayerProvider` fires `notifyListeners()` every 300ms via `Timer.periodic` plus stream listeners. Causes ~3 forced rebuilds/sec.
- **HTTP client leak** — `MusicAudioHandler.resolveRedirects()` creates `http.Client()` without closing it.
- **DB race on init** — `PlaylistDatabase._database` can double-init under concurrent access.
- **No index on `downloaded_tracks.playlistId`** — full table scans at scale.
- **Sequential pre-downloads** — `preDownloadUpcoming` awaits each track sequentially instead of batching.

## Roadmap

See [`futureroadmap.txt`](futureroadmap.txt) for planned features sourced from MusicPiped, koel/player, Flow, sweyer, you-free-app, and monochrome-music/monochrome.

## License

Personal / educational use.