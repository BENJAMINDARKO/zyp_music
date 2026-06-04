# Changelog

All notable changes to the `zyp_music` project are documented in this file.

## [1.1.4] — 2026-06-04

### Added
- **Tidal Public Catalog Metadata:** New `TidalMetadataDataSource` performs unauthenticated `GET` requests against Tidal's public v1 catalog API to read track title, artist, album, duration, and album cover. Uses Tidal's `client_credentials` OAuth flow with in-memory token caching, and maps only the five spec-matrix fields into a `TrackModel`. Audio streaming, fallback logic, and playback routing are untouched.
- **Tidal Metadata Two-Tier Cache:** In-memory session cache for repeat lookups in the same app launch, plus a `SharedPreferences` cache (7-day freshness window) keyed by track ID. Honors an explicit `force` refresh flag and falls back to the expired persisted entry on network failure — same resilience contract as `ChartsRepositoryImpl._getWithCache`.
- **High-Resolution Cover Rewrite (1280x1280):** Tidal cover IDs (e.g. `0e8e70e0-c5d3-4c30-95c0-70c5d3bc308a`) are rewritten to `https://resources.tidal.com/images/<segments>/1280x1280.jpg`. If the payload arrives as a fully-qualified URL, the canonical `/{NxN}/` segment is regex-replaced; otherwise the segment is appended before the file extension.
- **Hive-Backed Hybrid Cache:** Added `cache_tracker_box` memory-mapped NoSQL box (typeId 1) with a hand-written `CacheTrackerModel` TypeAdapter storing four fields — `trackId (0)`, `cachedAt (1)`, `isFavorite (2)`, `timedLyrics (3)` — and a `HybridCacheService` orchestrator exposing `markCaching` / `markNotCaching` / `markSuccessAfterWrite` / `markFavorite` / `setLyrics` / `getLyrics` / `isCached` / `isActivelyCaching` / `getCachedState` plus a broadcast `stateStream` for per-track state events.
- **Favorites Tier (Persistent, Protected):** `markFavorite` sets `isFavorite=true`. Favorite entries are completely immune to LRU eviction and bypass the casual-tier cap.
- **Casual Tier (Bounded LRU, 200 cap):** On every successful cache write, the service counts non-favorite entries; if the count exceeds 200 it sorts by `cachedAt` ascending, picks the 10 oldest, deletes their physical audio files in `<docs>/audio_cache/`, and batch-deletes the box keys in a single `box.deleteAll(keys)` call. No blank reset of valid entries.
- **Persistent Karaoke Lyrics Storage:** `HybridCacheService.setLyrics(trackId, lrc)` / `getLyrics(trackId)` persist the raw LRC blob inside the same Hive record. Lyrics are dropped together with the audio file during LRU eviction, and survive across sessions for favorite tracks.
- **Dynamic Lookahead Preload Loop (Slider-Driven):** A track-changed listener on `PlayerProvider` reads the new `prebufferCountClamped` (1..5) and, for each of the next N tracks, checks `hybridCache.isCached(trackId)` before firing `AudioRepository.preloadTrack` as a fire-and-forget background download. Hive lookups keep the hot path O(1).
- **Settings > Audio > Caching & PreBuffer Slider:** Bound to 1..5 (was 1..10). `setPrebufferCount` clamps on write; `prebufferCountClamped` getter enforces the bounds on read so any legacy persisted value above 5 is silently contained.
- **Download Icon State Machine Fix:** `TrackDownloadIcon` and `AlbumDownloadIcon` are now `StatefulWidget`s that subscribe to `HybridCacheService.stateStream` (filtered by track ID) for sub-frame rebuilds. Idle → outline icon, caching → `CircularProgressIndicator`, success → `Icons.check_circle` — all gated against `box.containsKey(trackId)` so already-cached tracks render the checkmark on first layout.
- **Interactive Download Commit Flow:** Tap on the download icon performs the spec §1 sequence: read `trackId`, check `box.containsKey`, return early on hit, otherwise fire the download pipeline and flip the icon to the spinner state in the same frame. `DownloadProvider.downloadTrack` calls `hybridCache.markCaching` synchronously before the file write loop so the user gets instant visual confirmation.
- **Filesystem Reconcile on Box Open:** `HybridCacheService.init()` opens the Hive box, then runs a deferred `_reconcileWithFilesystem()` that scans `<docs>/audio_cache/` and `box.putAll`s a fresh record for every orphan file (skips `*.tmp` / `*.part` / 0-byte entries). Purely additive — never modifies or removes existing records or files. This is what makes the pre-buffer engine's previously-orphaned cache entries show as downloaded on next launch.

### Changed
- **Wavy Seekbar — Hybrid Dynamic Two-Tier:** `_paintWavy` no longer draws a uniform bezier wave across the whole bar. It now computes `X_split = size.width * value` and switches equations at the boundary: the played segment (0..X_split) is a true sine wave `Y(x) = cy + A·sin(ω·x + φ)` sampled at 1px steps, and the unplayed segment (X_split..size.width) is a single horizontal `drawLine`. Both segments share identical `strokeWidth = 3`, `isAntiAlias = true`, and `StrokeCap.round` so the seam is clean.
- **Pre-Buffer → Hive Synchronization:** `AudioCacheService.cacheStream` now exposes a `Future<void> Function(String trackId, String filePath)? onCacheSuccess` hook. `AudioRepositoryImpl`'s constructor wires it to `HybridCacheService.markSuccessAfterWrite(expectedFilePath: …)`, so every future pre-buffer write registers in the Hive box automatically — preventing the pre-buffer / icon desync at its source.
- **Download Icon Widgets:** Replaced the `Consumer2`-only binding with a `StatefulWidget` that combines a Provider consumer with a `stateStream` subscription and a `didUpdateWidget` re-bind. The `TrackDownloadIcon` accepts an optional `playlistId` parameter to disambiguate storage location for tracks shared across playlists.
- **Album Download Icon:** Aggregate state now combines three signals — `DownloadProvider.isDownloadingPlaylist(albumId)`, all-tracks-cached-in-Hive, and any per-track `_activeCaching` flag — so the icon never gets stuck spinning when only one track in the album is downloading.
- **Tidal 2-Tier Cache:** Tidal track info now follows the same tiered lookup pattern as the project's chart/search caches — `in-memory → SharedPreferences (≤ 7d) → network → expired-prefs fallback on network failure` — instead of going straight to the network on every lookup.

### Fixed
- **Pre-buffered tracks displayed as not downloaded:** Tracks that were cached by the lookahead pre-buffer engine (or downloaded before the Hive tier was wired up) physically existed in `<docs>/audio_cache/` and played offline correctly, but the download icon stayed on the outline state because the Hive `cache_tracker_box` had no record of them. The forward `onCacheSuccess` hook prevents new occurrences, and the `_reconcileWithFilesystem` pass on `init()` back-fills existing orphans on the very next launch — no boot wipe, no schema migration.

---

## [1.1.0] — 2026-06-03

### Added
- **Automated Lyrics Caching:** Lyrics fetched from the network are now saved locally to a `.lrc` file (e.g. `${track.title}-lyrics.lrc`). Subsequent playbacks read directly from disk with zero latency.
- **Lyrics Caching at Download Time:** Download workflows (`downloadTrack` and `downloadPlaylist`) now fetch and write lyric files locally alongside their audio files, making them fully available for offline playback.
- **Audio Sync Startup Delay:** Playback initialization now awaits lyrics fetching (with a 1.5s timeout) and delays audio start by `1400ms` if lyrics are present to sync playback perfectly with the first lyric line's arrival.

### Changed
- **Plain-White Lyrics Typography:** Swapped the dominant color font logic for plain white (`#FFFFFF`) with custom opacity states (1.0 bold active, 0.4 regular upcoming, 0.25 regular passed) for clean readability.
- **Pulsing Dot Loading Entrance:** Replaced the initial text blur with a vertical 3-dot pulsing entrance timeline (dots pulse at 800ms loop, translate up, and fade out at 1400ms as the lyrics slide up).
- **First Line Positioning & Fade:** Removed top-edge blur/fade completely. The first line starts directly at the top of the container. Added a soft gradient transparent fade to the bottom edge only.
- **Upper-Third Active Line Alignment:** Active lyric lines are now scrolled to exactly H * 0.25 (upper third) of the container.
- **Queue Playback Clearing:** Removing the currently playing track from the queue now stops playback completely if it was the last track, or automatically advances and plays the next track.

---

## [1.0.0] — 2026-06-03

### Added
- **Global Sleep Timer:** Refactored timer view to bind to `PlayerProvider`'s global state, keeping countdown running in the background. Added dynamic Start button color matching the album art, a numeric `TextField` for direct keyboard input, and +/- 5 minute controls.
- **Glassmorphic Add to Playlist Modal:** Redesigned playlist modal using a transparent background, `BackdropFilter` with `sigma: 30` blur, and a dark overlay, resolving list scroll collisions.
- **Miniplayer Lyrics Toolbar:** Rewrote toolbar headers, moving offset sync buttons to a secondary row to prevent layout cut-offs.
- **Artwork Status Overlays:** Added favorite/heart and download status icons on top of `_TrackCard` and `_AlbumCard` artwork, enabling instant color changes when favorited.
- **Hero Transition Animations:** Connected the miniplayer album art and the full-screen rotating disc using `Hero` animation tags (`'now-playing-art'`) for seamless transitions.
- **Up Next Sheet Overhaul:** Repositioned media controls into Scaffold `bottomNavigationBar` and converted the Up Next queue to a persistent bottom sheet sitting flush above playback buttons.
