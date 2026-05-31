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

### Pub Cache Patch

The `youtube_explode_dart` package needs a patch in the pub cache to return non-empty browse API results:

**File:** `$PUB_CACHE/hosted/pub.dev/youtube_explode_dart-3.1.0/lib/src/reverse_engineering/youtube_http_client.dart`

Change the InnerTube client context to:
```dart
'clientName': "WEB",
'clientVersion': "2.20250601.00.00",
```

Without this patch, the browse API returns empty `contents` and mix playlists fail to load.

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
├── app.dart                    # App entry point + theme
├── main.dart                   # Dependency injection + AudioService.init
├── core/
│   ├── constants/              # App constants
│   └── utils/
│       └── format_duration.dart # Shared duration formatting
├── domain/
│   ├── entities/               # Track, Playlist models
│   └── repositories/           # AudioRepository, PlaylistRepository interfaces
├── data/
│   ├── datasources/
│   │   ├── remote/             # YoutubeRemoteDataSource, AuthenticatedClient
│   │   └── local/              # PlaylistDatabase (SQLite)
│   ├── models/                 # Data-layer DTOs
│   └── repositories/           # AudioRepositoryImpl, PlaylistRepositoryImpl
├── presentation/
│   ├── screens/                # HomeScreen, PlayerScreen, SettingsScreen, LoginScreen, PlaylistScreen
│   ├── providers/              # PlayerProvider, PlaylistProvider, DownloadProvider
│   └── widgets/                # PlayerBar, TrackTile, PlaylistCard, NowPlayingCard, PixelLogo
└── service/
    ├── audio_handler.dart      # MusicAudioHandler (audio_service bridge)
    ├── auth_service.dart       # flutter_secure_storage cookie storage
    └── download_service.dart   # DownloadService (offline downloads)
```

## Testing

```bash
flutter test
```

39 tests covering models, providers, utilities, services, and widgets.

## Known Issues

- **Pub cache patch** — overwritten when `flutter pub upgrade` runs; must be re-applied manually.
- **YouTube mixes** — may still not load depending on mix metadata structure (tracked in `futureroadmap.txt`).
- **Samsung GPU `BufferQueue` timeout** — harmless Adreno driver spam in logcat on Exynos devices; does not affect playback.

## Roadmap

See [`futureroadmap.txt`](futureroadmap.txt) for planned features sourced from MusicPiped, koel/player, Flow, sweyer, you-free-app, and monochrome-music/monochrome.

## License

Personal / educational use.
