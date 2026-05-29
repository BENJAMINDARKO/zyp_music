# ytmusix — YouTube Music Streamer

A Flutter mobile app that streams audio from public YouTube playlists. No backend, no ads.

## Features

- **Playlist import** — paste a YouTube playlist URL (PL or RD/mix) into the inline input bar
- **Audio streaming** — downloads YouTube audio to a local temp file for reliable playback (bypasses ExoPlayer header-drop on CDN redirects)
- **Google login** — in-app WebView for cookie-based auth to access private/restricted content
- **Queue management** — play, pause, skip, previous, auto-advance on track completion
- **Local SQLite cache** — playlists stored offline for quick reload
- **Dark theme** — Spotify-inspired dark UI

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter (Dart) |
| Architecture | Hexagonal (domain/data/presentation) |
| State | Provider |
| YouTube API | `youtube_explode_dart` 3.1.0 (patched client version) |
| Audio | `just_audio` 0.9.43 |
| Storage | sqflite + shared_preferences |
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

### Run

```bash
flutter run
```

## Project Structure

```
lib/
├── app.dart                  # App entry point + theme
├── main.dart                 # Dependency injection + run
├── domain/
│   ├── entities/             # Track, Playlist models
│   └── repositories/         # AudioRepository, PlaylistRepository interfaces
├── data/
│   ├── datasources/
│   │   ├── remote/           # YoutubeRemoteDataSource, AuthenticatedClient
│   │   └── local/            # PlaylistDatabase (SQLite)
│   ├── models/               # Data-layer DTOs
│   └── repositories/         # AudioRepositoryImpl, PlaylistRepositoryImpl
├── presentation/
│   ├── screens/              # HomeScreen, SettingsScreen, LoginScreen, PlaylistScreen
│   └── providers/            # PlayerProvider, PlaylistProvider
└── service/
    └── auth_service.dart     # SharedPreferences cookie storage
```

## Known Issues

- **Audio downloads fully before playing** — the entire muxed stream downloads to a temp file before playback starts. Streaming via `AudioSource.uri()` fails due to ExoPlayer dropping custom headers on 302 redirects.
- **YouTube rate limiting** — frequent stream requests may get 429 errors; 3 retries with backoff are implemented.
- **Pub cache patch** — overwritten when `flutter pub upgrade` runs; must be re-applied manually.

## License

Personal / educational use.
