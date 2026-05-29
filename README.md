# ytmusix — YouTube Music Streamer

A Flutter mobile app that streams audio from public YouTube playlists. No backend, no ads, just your playlists.

## Features

- **Playlist import** — paste a YouTube playlist URL into the inline input bar (with `+` to load, `✕` to clear); parses up to 100 tracks
- **Audio streaming** — downloads and caches YouTube audio to a local file for playback
- **Google login** — sign into your Google account via in-app WebView to access private/restricted content
- **Cookie-based auth** — saved to device, persists across sessions
- **Queue management** — play, pause, skip, previous, track completion auto-advance
- **Local SQLite cache** — playlists stored offline for quick reload
- **Dark theme** — Spotify-inspired dark UI

## How it works

| Step | What happens |
|------|-------------|
| 1. Paste URL | Extracts playlist ID, calls YouTube InnerTube API (WEB client v2.20250601.00.00) |
| 2. Parse tracks | Walks `playlistVideoListRenderer` for up to 100 videos |
| 3. Tap a track | Gets the muxed (audio+video) progressive stream URL |
| 4. Download | Streams the mp4 to a temp file with auth cookies & User-Agent headers |
| 5. Play | Feeds the local file to `just_audio`'s ExoPlayer backend |

> `AudioSource.uri()` with custom headers doesn't work on Android because ExoPlayer drops headers on YouTube CDN redirects. Downloading to a local file bypasses this.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter (Dart) |
| Architecture | Hexagonal (domain/data/presentation) |
| State | Provider |
| YouTube API | youtube_explode_dart 3.1.0 (patched client version) |
| Audio | just_audio 0.9.43 |
| Storage | sqflite + shared_preferences |
| Auth | WebView cookie extraction |
| HTTP | http package |

## Getting Started

### Prerequisites

- Flutter SDK ^3.12.0
- Android Studio / Xcode
- A physical device or emulator

### Setup

```bash
git clone <repo-url>
cd ytmusix-flowos
flutter pub get
```

### Pub Cache Patch

This app patches the `youtube_explode_dart` package's InnerTube client version in the pub cache:

**File:** `$PUB_CACHE/hosted/pub.dev/youtube_explode_dart-3.1.0/lib/src/reverse_engineering/youtube_http_client.dart`

Change the `client` context to use `"WEB"` with version `"2.20250601.00.00"`:

```dart
'clientName': "WEB",
'clientVersion': "2.20250601.00.00",
```

Without this patch, the browse API returns an empty `contents` section and playlists fail to load.

### Run

```bash
flutter run
```

### Login (optional)

1. Tap **Settings** (gear icon)
2. Tap **Login with Google**
3. Sign into your Google account in the WebView
4. Restart the app for cookies to take effect

Required for age-restricted or private content.

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
│   ├── screens/              # HomeScreen, SettingsScreen, LoginScreen
│   └── providers/            # PlayerProvider, PlaylistProvider
└── service/
    └── auth_service.dart     # SharedPreferences cookie storage
```

## Known Issues

- **Audio downloads fully before playing** — the entire muxed stream (~3-8 MB) downloads to a temp file before playback starts. Streaming via `AudioSource.uri()` fails due to ExoPlayer dropping Custom headers on 302 redirects.
- **YouTube rate limiting** — frequent stream requests may get 429 errors; 3 retries with backoff are implemented.
- **RD (radio mix) playlists** — use a hardcoded track list as a placeholder until the browse API is tested with new client version.
- **Pub cache patch** — overwritten when `flutter pub upgrade` runs; must be re-applied manually.

## License

Personal / educational use.
