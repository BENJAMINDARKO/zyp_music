## [1.2.21] - 2026-07-10

### Changed
- **Album Page Background & Dynamic Color**: Configured the album cover image to extend as a full-page background under a dark translucent gradient, making the track list background reflect the artwork colors instead of being solid black. Wired PaletteGenerator to dynamically extract the album's dominant color to tint the centered translucent play button.

## [1.2.20] - 2026-07-10

### Added
- **Manual Update Check**: Added a "Check for Updates" button under Settings > System > System & Storage that checks for updates from GitHub and provides manual feedback via SnackBars and Dialogs.

## [1.2.19] - 2026-07-10

### Changed
- **Album Page Redesign**: Styled the album cover background with a centered circular play button, a love icon on the bottom-left, a download icon on the bottom-right, and a centered album title. Replaced caret left icon with thin left arrow. Added circular track thumbnail indicators and configured track love icons to turn green when toggled.

## [1.2.18] - 2026-07-10

### Added
- **Complete Album/Playlist Playback**: Tapping "Play All" or any track inside an Album or Playlist now queues the entire list and begins playing from the selected track, instead of queueing only that single track.

## [1.2.17] - 2026-07-10

### Changed
- **Search Interaction**: Configured search queries to trigger only when pressing the keyboard's "Enter" or "Search" key, replacing the automatic character debounce. Added search action type for native software keyboards.

## [1.2.16] - 2026-07-10

### Fixed
- **Responsive Layout Design**: Refactored the Now Playing and Fullscreen Lyrics layouts to place the bottom controls naturally in the main layout column, completely preventing content overlap. Configured dynamic album art scaling using LayoutBuilder to fit smaller screens.

## [1.2.15] - 2026-07-10

### Added
- **OTA Verification Release**: Triggered a test release to verify OTA update installation workflow.

## [1.2.14] - 2026-07-10

### Fixed
- **CI Signing Configuration**: Configured explicit `release` signing config block in `build.gradle.kts` targeting the decoded keystore path directly, resolving unsigned APK builds in GitHub Actions.

## [1.2.13] - 2026-07-10

### Fixed
- **OTA Update Crash**: Added `<provider>` FileProvider declaration to `AndroidManifest.xml` and configured `filepaths.xml` resource mapping to resolve OS installer crashes on download completion.

## [1.2.12] - 2026-07-10

### Added
- **Share Lyrics as Image**: Added ability to long-press a lyric line to enter selection mode, select multiple lines, and share them as a beautifully formatted image with dynamic color theming based on the album art (with 5 other manual color presets).

### Fixed
- **Persistent Keystore in CI**: Configured GitHub Actions to restore a fixed, persistent debug keystore from repository secrets, ensuring consistent APK signatures across runs for clean over-the-air updates.

## [1.2.11] - 2026-07-09

### Added
- **Auto-Update Permissions**: Added runtime check and prompt for `requestInstallPackages` permission using `permission_handler` before launching update download to ensure installation window can appear on Android.

### Changed
- **Track Tap Behavior**: Tapping a track now starts a clean listening session (clearing the listening history and resetting the play queue to just that track). Queue and history are only maintained when songs or albums are explicitly added via "Add to Queue".

### Fixed
- **FileProvider Authority**: Configured explicit `androidProviderAuthority` for `ota_update` to match the application's package name (`com.zyx.music.ota_update_provider`).

## [1.2.10] - 2026-07-08

### Fixed
- **Player Repeat Modes**: Configured LoopMode.off mapping for Repeat All and Repeat None, allowing lookahead gapless mixer to manage queue transition and wrap-around smoothly.
- **Offline Repeating**: Enabled `LockCachingAudioSource` for remote streams to support loop caching and offline repeating.
- **Swipe-to-Remove**: Wrapped History and Play Queue lists in Dismissible widgets allowing right-swipe to remove tracks.
- **Track Duration Display**: Fixed seekbar duration initialization and gapless transition updates.

## [1.2.9] - 2026-07-08

### Added
- **Android Auto-Update Feature:** Implemented startup version checking and automatic APK updating. When the app starts, it checks for updates on GitHub Releases, prompts the user via an AlertDialog if a new version is found, downloads the update with a visual progress bar, and automatically launches the Android package installer.

### Fixed
- **Repeat Button Functionality:** Overrode repeat/loop modes natively in `MusicAudioHandler` using `LoopMode.one` and `LoopMode.off`, preserved repeat settings across player replacement/swaps, and added queue wrap-around to correctly repeat the entire playlist (Repeat All).

### Removed
- **Low-Latency Vocal Subtraction Feature:** Removed the experimental vocal remover processor, deleted associated services and native processors, cleaned up unused MethodChannels in `MainActivity.kt`, and removed UI slider components.

## [1.2.8] - 2026-06-19

### Added
- **Restored CD & Karaoke UI:** Reinstated the spinning album CD and Karaoke mode button row at the top of the fullscreen lyrics view, ensuring persistent visibility when other player controls fade out.
- **Translucent Glassmorphic Sheets:** Implemented unified static builders inside `AppleMusicSheet` to group action tiles into structured, highly rounded, and translucent card sections with right-aligned icons.

### Changed
- **Dynamic Lyric & Queue Layout Bounds:** Constrained the lyrics view (`SyncedLyricsWidget`) and the playlist queue (`_buildInlineQueueView`) with custom bottom paddings to completely prevent scrollable items from leaking/rendering behind active player controls.

## [1.2.7] - 2026-06-12

### Changed
- **Search Logic Separation:** Separated search results so that YouTube Music results appear exclusively in Tracks, Albums, Artists, and Playlists tabs, while generic YouTube results are kept to the "Other" tab.
- **Export Filenames:** Updated export filename format to strictly use the track title (e.g., "Track Name.m4a") to prevent media players from displaying the artist name twice.
- **Settings Theme Consistency:** Updated Settings screen toggles and tab indicators to match the Home menu's primary color theme instead of hardcoded yellow.

### Fixed
- **Metadata Container Mismatch:** Fixed a critical bug where exported files were fetching WebM streams instead of MP4, causing metadata/artwork injection (ID3 tags) to silently fail. 
- **Playlist Picker UI:** Replaced the legacy playlist picker dialog with the modern, drag-to-close bottom sheet for adding tracks to playlists.
- **Export Toggle Logic:** Pressing an active (green) thumbs-up export icon now correctly deletes the exported file from your device and resets the button state, allowing clean re-exports.

## [1.2.6] - 2026-06-11

### Added
- **Export to Folder:** Added the ability to export cached tracks and albums directly to a user-selected folder as `.m4a` files.
- **ID3 Tag Injection:** Implemented automatic metadata injection using `audiotags` so exported tracks contain accurate Album Art, Title, Artist, and Album tags.
- **Context Menu Export:** Added "Export to Folder" button (with 👍 icon) to track and album long-press context menus across the app UI.

### Fixed
- **Local Cache Export Crash:** Fixed an issue where exporting tracks from local storage would fail due to network redirect errors.
- **Menu Rendering Bug:** Fixed a Flutter assertion error in `AppleMusicSheet` (ink splashes hidden by DecoratedBox) by moving background properties to the Material widget.


## [1.2.5] - 2026-06-11

### Added
- **Playlist Swipe-to-Delete:** Added a swipe-to-delete gesture (swipe left) to easily remove songs from playlists (including imported playlists).
- **Queue Highlighting:** The Up Next queue now highlights the currently playing track with the primary theme color.

### Changed
- **Search Box Design:** Replaced the rectangular search text field with a pill-shaped container to match the app's modern design language.
- **Search Pagination:** Implemented recursive pagination in the YouTube data source to bypass the 20-result limit and fetch more comprehensive search results.

### Fixed
- **AutoDJ Same Genre Logic:** Refactored the 'Same Genre' mode to anchor its proximity scoring on the original seed track's properties rather than the current track, preventing the engine from drifting and losing the genre context.
- **AutoDJ Infinite Loops:** Explicitly added the current playing track to the AutoDJ exclusion set for all modes. This guarantees the engine will never recommend the currently playing song as the next song, resolving the 2-song infinite rotation loops (especially in Shuffle Library and Same Genre modes).

# Changelog

All notable changes to the `zyp_music` project are documented in this file.

## [1.2.5] — 2026-06-10

### Fixed
- **Search Bar Theme:** Stripped global `InputDecorationTheme` overrides that were hiding the custom pill-shaped search bar.
- **Imported Playlist Editing:** Removed a destructive synchronization loop where opening an imported playlist would overwrite the local database with the live YouTube version, erasing local track deletions.
- **Search Result Limits:** Modified the search engine to aggressively fetch additional pages under the hood, vastly increasing the number of displayed results (e.g. 60+ instead of just 20).
- **Suggested Artists Thumbnail Fix:** Artists in the Suggested section now correctly load their thumbnail images from the cache if they were previously downloaded.
- **Full Screen Lyrics Scrolling Fix:** Fixed a bug where full-screen lyrics would not scroll to the active line.

### Added
- **Major UI Overhaul:** Implemented a major visual redesign to make the app feel modern, sleek, and premium.
- **"Your Music" Offline Upload Button:** Added an "Upload Offline Library" button to the Playlist tab.
- **Third-Party Playlist Import UI:** Added an "Import Playlist" button in the Playlist tab to paste a URL.



### Added
- **Major UI Redesign:** Implemented a massive visual overhaul across the entire app with a premium, modern aesthetic (Apple Music inspired).
- **"Listen Now" Hub:** Added a brand new personalized "Listen Now" screen (`MusicNowScreen`).
- **Listening Stats:** Added a dedicated listening stats view that tracks your most played artists, albums, and genres.
- **Playback Speed Control:** Added a playback speed selector so you can adjust the tempo of any track.
- **New Iconography System:** Swapped out the old icons for a sleek, unified `phosphoricons` suite and custom SVGs.
- **Smooth Bottom Sheets:** Upgraded modals and flyouts to use smooth, draggable Apple Music-style bottom sheets.

### Changed
- **Unified Theme:** Updated `AppTheme`, shared cards, and global backgrounds to ensure strict visual consistency across Home, Library, Artist, and Search screens.
- **Streamlined Player UI:** Refactored the full-screen player and bottom mini-player for a cleaner, more intuitive layout.
- **Lyrics View Revamp:** Consolidated the lyrics experience with a new `LyricsTimingSlider` and a streamlined `SingleLineLyricsWidget`.
- **Context Menus Polished:** Redesigned the Track and Album context menus to match the new UI language.

### Removed
- **Legacy UI Components:** Deleted outdated layout elements like `custom_lyrics_modal`, `miniplayer_flyout_container`, and `miniplayer_lyrics_view` to simplify the codebase and interface.

---

## [1.2.1] — 2026-06-10

### Fixed
- **Cold Start Playback UI Freeze:** Fixed an issue where tapping play after a cold start (when the app was completely closed and reopened) would cause the audio to play but the play button and seek bar would remain frozen in a paused state. The user interface now correctly syncs with the audio immediately on the first tap.
- **Background Audio State Reliability:** Upgraded the internal audio state management to use more reliable data streams (`BehaviorSubject` via `rxdart`). This prevents rare edge cases where the app's visual state gets disconnected from what the audio player is actually doing in the background.

---

## [1.2.0] — 2026-06-07

### feat(auto-dj): overhaul recommendation engine across all six modes

Implements an eight-spec series (2A–2H) that rebuilds the Auto DJ
recommendation engine from the data layer up. Addresses the
user-reported bug where Smart DJ produced five consecutive same-artist
tracks, plus broader improvements to all five active modes.

#### What changed by mode

- **Smart DJ:** rewritten scoring formula
  (0.40 artist_diversity + 0.40 genre_similarity + 0.20 temporal),
  with post-scoring artist hard cap and cold-start handling. The
  same-artist run bug is now structurally impossible.

- **Same Genre:** added country/region similarity bonus
  (1.0 same-country / 0.85 same-region / 0.7 different-region).
  Black Sherif now chains to Sarkodie and Burna Boy ahead of Drake.

- **Same Artist:** year-distance scoring spreads picks across the
  artist's career instead of clustering by release era.

- **Shuffle Library:** optional genre filter with discoverable sub-menu UI
  showing genres ranked by track count.

- **Similar Songs:** benefits passively from reliable normalized genre
  data; existing logic now hits real matches instead of falling
  through to first-result.

- **Off:** unchanged.

#### Infrastructure added

- MusicBrainz genre normalization with 130-entry dictionary
- Genre proximity matrix with 81 clusters, 219 edges
- Country/region asset with 235 ISO codes across 16 regions
- Background enrichment service with debounced refresh
- Top-Liked-Songs cache refresh on favorite/unfavorite changes
- Mixer pipeline now propagates session history for diversity scoring

#### Data pipeline fixes

- `dj_listening_history.primary_genre` now populated with normalized
  matrix keys (was always "Unknown", making the genre signal dead)
- Artist genres cached with confidence scores and country codes
- Schema migrations 13→14→15 with backward compatibility

#### Test coverage

210 tests passing (was ~100). Includes exhaustive 219-edge graph
validation, Black Sherif bug regression test, and Gate 7b
cross-consistency check between dictionary and matrix.

#### Deferred (filed as follow-up tickets)

- BPM extraction for crossfade tempo matching
- `display_name` column cleanup migration
- `TrackCandidate` metadata audit (genre + country)

---

## [1.1.13] — 2026-06-06

### Added
- **Honest duration display:** When a track's length isn't known yet, the app now shows `—:—` instead of a misleading `0:00`. Cached and downloaded tracks automatically get their real duration measured from the audio file once it's on disk.
- **New app icon:** Refreshed the launcher icon, the in-app drawer logo, and the icon that appears in the notification panel.

### Fixed
- **Cold-launch track durations:** Tracks rebuilt from local memory at startup no longer report a fake `0:00` length — they show `—:—` until the real duration is available.

---

## [1.1.12] — 2026-06-06

### Added
- **Pipeline-Rebuild Race Fix in Gapless Mixer:** `GaplessQueueMixer` now tracks an `_isPipelineRebuilding` flag plus an asymmetric `isLookaheadDirty` recovery bit. The three production `setAudioSource` call sites (`attach`, `playTrack`, `adoptPlayer`) wrap their `await` in a `try/finally` that sets/clears the flag in the atomic success-closure of the native reconfigure, so concurrent `queueNextTrack` injections can detect a transient `ConcatenatingMediaSource` detach and back off instead of colliding with the platform channel. The dirty bit is only raised on a rebuild-skip (cold-boot null skips remain untouched, preserving the regular scheduler's re-fire path).
- **`GaplessQueueMixer.retryPendingInjection()`:** Recovery hook called from `PlayerProvider`'s position-stream listener on every tick. No-op unless the dirty bit is set, the pipeline is settled, and the native concatenation has re-initialised. Pairs the deferred track's `AudioSource` from the source builder, calls `_concatenation.add(...)`, and clears the dirty bit on success; on a still-colliding retry the dirty bit is left set so the next tick tries again.
- **Same-Genre Stochastic Pool Selection:** The previously deterministic "first-hit" BFS in `AutoDjRoutingService._sameGenre` is now a full-graph candidate-harvesting sweep (BFS up to depth 3) followed by a fitness-proportional roulette-wheel selector. Per-candidate weight is `W_path * A_penalty` where `W_path` is the genre-graph proximity and `A_penalty` is the new 3-track extended-memory artist-decay matrix (`0.15` / `0.40` / `0.65` / `1.0` for the immediate-last / two-ago / three-ago history slots / no-match). When heavy penalties collapse the cumulative sum to `0.0` the engine picks a random `nextInt` index from the full harvested set, eliminating the alphabetised `rawCandidates.first` lock.
- **Injected `Random` for Deterministic Tests:** `AutoDjRoutingService` constructor accepts an optional `Random? random` parameter (renamed from the prior `rng`); the new `_sameGenre` path uses it for both the roulette pointer and the random-index fallback. Tests inject `Random(42)` (or any other seed) for reproducible assertions.
- **`resolveNext` `history` Parameter:** New optional `List<Track> history = const <Track>[]` parameter on `AutoDjRoutingService.resolveNext(...)`. Only the Same-Genre mode consumes it. Callers must pass an immutable list.
- **`QueueManager.rememberPlayedTrack(Track)` + `_sessionHistory`:** New internal session history list on `QueueManager` (capped at the most-recent 3 tracks, newest-first insertion order). `generateNextAutoDJTrack` pushes the current track into the list and forwards an unmodifiable snapshot to `resolveNext`. The mirror of the existing `_recentSessionIds` id-set so the artist-decay matrix can read full `Track` objects (artist strings) and not just ids.
- **Smart-DJ Bootstrap-Fusion Cache (Liked-Song Affinity):** `AutoDjRoutingService` now stores three boot-populated caches: `int _cachedHistoryCount`, `List<String> _topLikedArtists`, `List<String> _topLikedGenres`. The new `likedAffinityWeight` getter implements the spec's linear-decay bias `β = max(0.0, 0.6 * (1.0 - H/150))` — at H=0 the engine runs 60% Liked / 40% Live, at H=75 it slides to 30/70, and at H≥150 the bias collapses to 0 and the engine runs in pure-Markov mode.
- **Null-Genre Defensive Reallocation:** New static `AutoDjRoutingService.likedAffinityFor(...)` helper computes the per-candidate $L_{affinity}$ score using the normal-intersection matrix (0.6 artist + 0.4 genre = 0.0..1.0). When a candidate's `genre` is `null`, empty, or the literal `"Unknown"`, the engine reallocates the missing 0.4 genre weight onto the artist component — a matching artist therefore scores a perfect 1.0, a non-matching artist scores 0.0. Tracks with partial metadata are never mathematically penalised.
- **`Smart DJ compute()` Isolate Scoring:** `_smartDj` now serialises its scoring context (candidates, markov state, full history) into a primitive-only `_SmartDjScoreInput` payload (`List<String>` for the top-5 caches, `List<Map<String, dynamic>>` for everything else) and hands it to a top-level `_smartDjIsolateScore` callback via `compute()`. Inside the isolate, the lightweight data shapes are reconstructed, the Markov + Liked-Song fusion is computed, and a flat `List<Map<String, dynamic>>` of `{trackId, score}` is returned. No live `Track` / `DJHistoryEntry` / database references cross the boundary. A in-process fallback path runs the same algorithm if the platform refuses the isolate spawn.
- **`PlayerProvider.setRoutingService(AutoDjRoutingService)`:** New late-binding setter matching the existing `setHistoryLedger` / `setMixer` pattern. Bound once during app boot from `app.dart` so the provider can both bootstrap the engine's fusion cache and bump `_cachedHistoryCount` on every committed history row.
- **`PlayerProvider.setPlaylistRepository(PlaylistRepository)`:** New late-binding setter that wires the local `favorite_tracks` table reader into the provider so the boot-time Top-5 Liked Artists / Genres aggregation can run.
- **`_maybeBootstrapSmartDjFusion()` Cache Initializer:** Idempotent async method on `PlayerProvider` that fires once both routing-service and playlist-repository references are in place. Reads `_historyLedger.rowCount()` for the initial history count, reads `getFavoriteTracks()` and computes the Top 5 Artists / Genres in-memory (mirroring the spec's `GROUP BY author ORDER BY COUNT(*) DESC LIMIT 5` aggregate over the existing public API), and pushes the primitive `List<String>` results + the history count into the engine via `AutoDjRoutingService.bootstrapLikedSongs(...)`.
- **`AutoDjRoutingService.bootstrapLikedSongs(...)` and `notifyHistoryRowCommitted()`:** Public cache-mutator entry points so the provider can populate the engine's fusion caches at boot and bump `_cachedHistoryCount` every time the application commits a new row to `dj_listening_history`. The notify method is intentionally a one-liner so the call site reads as a single intent statement.

### Changed
- **Same-Genre Mode Is Now Stochastic:** Eliminated the deterministic "first-hit" BFS termination that was locking the engine onto a single Rock row at the head of the crate. The mode is now a true mix of (a) graph-priority BFS ordering, (b) genre-proximity weight, (c) the artist-decay matrix, and (d) proportional roulette selection — visibly anti-grouping across 50-iteration test runs.
- **Gapless Mixer `setAudioSource` Callsite Audit:** The three production `setAudioSource` call sites in `GaplessQueueMixer` (and the mixer-owned pipeline-rebuild lifecycle) are now wrapped in a strict `try/finally` race-shield so the native `ConcatenatingMediaSource` is never observed mid-detach from a concurrent `queueNextTrack`. Suppressed exceptions during the `add()` (lower-stakes) and the deferred-injection retry (legitimate platform collisions) are now caught and routed through the position-stream dirty-bit recovery.
- **Constructor Signature on `AutoDjRoutingService`:** Now accepts optional `initialHistoryCount: int = 0`, `topLikedArtists: List<String> = const []`, `topLikedGenres: List<String> = const []` parameters. The optional default values preserve backward compatibility — existing tests that do not pass the fusion caches continue to compile and run in pure-Markov mode.
- **QueueManager `generateNextAutoDJTrack` Signature:** Internally now records the current track into `_sessionHistory` and forwards an unmodifiable snapshot of that list to the routing service as the `history` parameter. External callers see no signature change.
- **PlayerProvider `_logCurrentTrackHistory`:** The successful resolution of `await ledger.logTrack(...)` is now followed by `_routingService?.notifyHistoryRowCommitted()` — the increment lives inside the success closure of the only production write path to `dj_listening_history`, per the spec's invalidation-audit rule. A throw from `logTrack` (lower-stakes path) leaves the counter untouched, so the engine never over-counts failed writes.
- **Mixer `nextTrackResolver` (in `main.dart`):** The mixer's gapless-lookahead trigger now passes `history: const <Track>[]` to `resolveNext` because the lookahead fires before the QueueManager has had a chance to register the upcoming track into the session history. The artist-penalty matrix therefore runs with an empty feed from this path; the QueueManager-driven call site (`generateNextAutoDJTrack`) is the canonical pipeline and supplies a populated history.
- **`AppLogger`-Style Suppression of the Random Fallback Path:** When the candidate pool is uniformly suppressed and the cumulative weight collapses to 0.0, the engine now logs the random-index pick with a dedicated `[MixerRaceShield] Cumulative score collapsed to 0; random fallback selected index $i → $trackId` line so the post-mortem stream makes the random selection observable.
- **Wiring Chain in `app.dart`:** The `PlayerProvider` `ChangeNotifierProvider` builder now splits the routing-service and playlist-repository setters out of the `..set` cascade so the bootstrap method's "both dependencies present" guard fires only after the base wiring is complete. The new `routingService` parameter on `ZYPMusic` is optional — unit tests that exercise `ZYPMusic` in isolation can still run without the AI DJ engine.

### Fixed
- **Same-Genre Persistent Two-Track Loop:** Under the pre-refactor "first-hit" BFS the engine returned the same Rock row every iteration when the crate was small, producing a visible "two-track loop" in long sessions. The full BFS sweep + artist-decay matrix + roulette wheel now demonstrably rotates through the pool — the test suite asserts that the seed-artist track is picked strictly less than half the time across 50 iterations and that at least one different-artist rotation occurs.
- **Gapless Mixer Platform-Channel Collisions at 80% Playback:** Two `MixerGuard` platform-channel collisions were observed in the playback logs (`NullPointerException` from Media3's `ConcatenatingMediaSource.addMediaSources`) immediately after `_positionSub` ticks. The pipeline-rebuild race shield eliminates the window in which a `queueNextTrack` can hit a transiently-detached concatenation. The deferred injection is replayed on the next position tick once the pipeline settles.

### Tests
- **New Same-Genre `anti-grouping` Test:** 50-iteration run with `Random(42)`, asserts (a) the seed-artist row is picked < 50% of the time, (b) at least one different-artist rotation occurs, and (c) every pick is a real crate id (no invented tracks).
- **New Same-Genre `edge case` Test:** All-Cur pool with all-Cur history; asserts picks spread across the pool (more than one unique id) and that index 0 is not selected more than 90% of the time — proves the algorithm does not lock onto `rawCandidates.first`.
- **All 101 Pre-Existing Tests Continue to Pass:** No regressions in the gapless-queue-mixer, shuffle-library-rolling-window, or existing smart-DJ tests after the refactor.

---

## [1.1.11] — 2026-06-05

### Added
- **Media State Persistence with Hive:** Implemented cold-start initialization boot recovery and active playback state persistence using a specialized metadata Hive box (`media_state_persistence`). Saves the active track, position in milliseconds, queue details, current index, and queue IDs.
- **Silently Rebuild State on Boot:** Restores the player queue and track state silently in the background on startup, setting the cursor exactly to the last stopped position while resting in a stable `Paused` state to avoid lockups.
- **Sync Restored Queue to Audio Handler:** Pushes the restored queue stack dynamically to `MusicAudioHandler` upon startup.

### Changed
- **Throttled Persistence Rate:** Updated active playback position persistence throttling from 5 seconds to 2 seconds.
- **Race Condition Resolution:** Sequenced history loading after active track state restoration to ensure restored session is not overridden.
- **Cleanup SharedPreferences:** Detached and removed old `SharedPreferences` active track persistence.

## [1.1.10] — 2026-06-05

### Fixed
- **Active Track Position Persistence on Cold Launch:** Rewrote the `_saveActiveTrackState` / `_loadActiveTrackState` pipeline to correctly round-trip three distinct fields — `position`, `duration`, and `isPlaying` — via three new SharedPreferences keys (`active_track_position_seconds`, `active_track_duration_seconds`, `active_track_is_playing`). The previous implementation conflated the saved playback position with the track's duration, causing every restored track to report `00:00 → 00:00` (the seek bar could not display the true length) and the position itself was never restored. The restore path now also writes the saved position back to `_position` so the seek bar thumb lands at the correct offset on the very first frame of cold launch.
- **First Play After Cold Launch Starts from the Saved Position:** `PlayerProvider.togglePlayPause` no longer calls a no-op `_audioRepository.resume()` on an idle audio handler. When a cold-launch restore left a `_pendingResumePosition` in memory, the play tap is routed through `playTrack(track, startAt: pending)` so the handler is initialised, the audio loads, and `seek(pending)` is invoked before playback begins — eliminating the "song loads but won't resume / position at 00:00" failure mode.
- **Position Not Persisted When the App is Killed by the OS:** The previous implementation only flushed state on `AppLifecycleState.detached`, which Android rarely fires before a force-kill. `_saveActiveTrackState` is now also triggered on `AppLifecycleState.paused` and `AppLifecycleState.inactive`, on every manual `togglePlayPause` (pause side), on every audio-stream paused edge (catches OS-driven pauses like headphone unplugs), and on a throttled 5-second timer driven by the position tick. `dispose()` performs a final fire-and-forget flush so the last position survives a hot reload / process tear-down.

### Added
- **`PlayerProvider.playTrack(startAt: Duration?)` Parameter:** Optional `startAt` parameter on the existing `playTrack(Track, {quality})` signature. When supplied, the position is set to the supplied value (instead of `Duration.zero`) and `_audioRepository.seek(startAt)` is invoked immediately after the audio handler initialises. The cold-launch resume path is the canonical consumer; the parameter is also exposed for any future "play this track at chapter X" use case.
- **`PlayerProvider._pendingResumePosition`:** New private field that carries the persisted playback position from `_loadActiveTrackState` to the first `togglePlayPause` (play) call. Cleared after consumption so subsequent plays do not seek to a stale value.
- **"Remove from Cache" Track Context Menu Entry:** New `ListTile` in `TrackContextMenu` rendered only when the track is actually held in either the Hive transient tracker or the SQLite library (`HybridCacheService.isCached || isDownloadedInSqlite || DownloadProvider.downloadedTrackIds.contains`). Icon: `Icons.delete_outline` (red `0xFFEF4444`). Tap fires `DownloadProvider.removeTrackFromCache(track)` and shows a "Removed … from cache" snackbar. Track is re-downloadable on next play.
- **"Remove from Cache" Album Context Menu Entry:** New `ListTile` in `AlbumContextMenu` rendered only when `DownloadProvider.isAlbumCached(album)` returns true (at least one track in the album is cached across the same dual-source check). Tap fires `DownloadProvider.removeAlbumFromCache(album)` which iterates over `album.tracks` and removes each one. Snackbar reports the actual number of tracks removed.
- **`HybridCacheService.removeTrackCompletely(trackId)`:** Single-call pipeline that (1) deletes the on-disk audio file at `<docs>/audio_cache/<id>.<ext>`, (2) deletes the deterministic lyrics file at `<docs>/<id>-lyrics.lrc` plus any tracked lyrics path, (3) drops the Hive box entry via `evictFromTracker`, (4) removes the SQLite `downloaded_tracks` row via `libraryDatabase.removeDownloadedTrack`, (5) refreshes the sync SQLite mirror, and (6) emits a `CachedState.removed` state event so `Consumer2<DownloadProvider, HybridCacheService>` widgets in the context menu can re-render without a full provider refresh. Idempotent — missing files or non-existent rows are no-ops, not errors.
- **`DownloadProvider.removeTrackFromCache(Track)`:** Public provider entry point for the track context menu. Wraps `HybridCacheService.removeTrackCompletely` and also drops the track from the in-memory `_downloadedTrackIds` / `_activeDownloads` mirrors before calling `notifyListeners`.
- **`DownloadProvider.removeAlbumFromCache(Album)`:** Public provider entry point for the album context menu. Iterates over `album.tracks`, purges each via `HybridCacheService.removeTrackCompletely` (only for tracks that are actually cached — saves redundant disk I/O on tracks that were never downloaded), and returns the count of tracks actually removed.
- **`DownloadProvider.isAlbumCached(Album)`:** Boolean helper that scans an album's tracks against the dual-source state. Used by the album context menu to decide whether the "Remove from Cache" entry should be visible.
- **`CachedState.removed`:** New enum value on `CachedState` emitted when `removeTrackCompletely` runs. Downstream consumers can listen on `HybridCacheService.stateStream` to react to a cache eviction (the existing `removed` glyph on the download icon now lights up automatically because the icon's `isAlreadyDownloaded` check returns false once the entry is gone).

## [1.1.9] — 2026-06-04

### Added
- **"Auto Queue" Context Menu Item:** New `ListTile` inserted between "Start Auto DJ" and "Add to Queue" in both `TrackContextMenu` and `AlbumContextMenu`. Icon: `Icons.auto_mode` (white). Display name: "Auto Queue". Business description: "Automatically queues and appends matching tracks seamlessly to the end of your active queue." The section ordering now matches the spec's exact layout rule (1. Start Auto DJ, 2. Auto Queue, 3. Add to Queue).
- **`PlayerProvider.startAutoQueue(Track seedTrack)`:** The migrated functional entry point. If a track is already playing or paused in memory, the existing recommendation engine is armed so the next track is generated and appended to the queue after the current one finishes — playback is not interrupted. If the queue is empty, the engine cold-starts from `seedTrack` via `coldStartAutoQueue`.
- **`PlayerProvider.coldStartAutoQueue(Track seedTrack)`:** Cold-start initializer. Resets the active queue to a single seed, enables the recommendation engine, and fires `playTrack(seedTrack)` so the audio is loaded, lyrics are fetched, and playback begins immediately. Eliminates the dead-air window the user would otherwise face when engaging Auto Queue from an empty queue.
- **`PlayerProvider.isAutoQueueActive` Getter:** Boolean surface for the context-menu snackbar messaging — wording reflects whether the queue was extended or cold-started.
- **Auto Queue State Persistence:** New `_saveAutoQueueState()` / `_loadAutoQueueState()` methods on `PlayerProvider` backed by a SharedPreferences key (`auto_queue_active`). The engine re-arms on cold launch if it was previously engaged.
- **Active Track State Persistence:** New `_saveActiveTrackState()` / `_loadActiveTrackState()` methods persisting the current track's id, title, author, thumbnail, and playback position to SharedPreferences. On cold launch, the miniplayer is restored to the last-known active track (without auto-resuming playback — the user presses play to continue).
- **`WidgetsBindingObserver` on `PlayerProvider`:** New `didChangeAppLifecycleState` hook persists both the Auto Queue state and the active track metadata on `AppLifecycleState.detached` (true cold termination). Other lifecycle transitions (backgrounded, inactive) are intentionally ignored — the OS may resume the process without a true cold start.

### Changed
- **`TrackContextMenu` Section Ordering:** The top action block now reads `Start Auto DJ → Auto Queue → Add to Queue`. The "Start Auto DJ" tile is retained as a placeholder for future logic and shows a "coming soon" snackbar on tap. The "Add to Queue" tile is unchanged.
- **`AlbumContextMenu` Section Ordering:** Same restructuring as `TrackContextMenu`. The "Auto Queue" tile seeds the engine with `tracks.first` — cold-starts when `player.queue.isEmpty`, otherwise just arms the engine.
- **Old `startAutoDJ(...)` Cleared to No-Op:** The previous Auto DJ background-song-selection / prediction-loop entry point on `PlayerProvider` is now a no-op. Its functional block has been migrated to `startAutoQueue` / `coldStartAutoQueue`. Kept as a no-op so any external callers (tests, legacy widgets) continue to compile and run without side-effects.
- **`PlayerProvider` Lifecycle Registration:** The provider now mixes in `WidgetsBindingObserver` and registers / unregisters itself with `WidgetsBinding.instance` in the constructor / `dispose`. The persistent-state loaders fire right after the existing `loadRecentlyPlayed` block so the engine and miniplayer resume their previous state across cold launches.
- **Context Menu Migration Spec Compliance:** The migration is strictly contained to the context menu content menu and the Auto Queue state controllers. The miniplayer layout, the full-screen monochrome theme, the audio output / mixers, and the existing `QueueManager.generateNextAutoDJTrack` loop are untouched. The miniplayer and full-screen Auto DJ toggle icons continue to call `toggleAutoDJ()` on the same `QueueManager` and drive the same engine the new "Auto Queue" context-menu entry arms.

---

## [1.1.8] — 2026-06-04

### Added
- **`CustomAudioSeekbar.inactiveColor` Param:** New optional `Color inactiveColor` parameter (default `Colors.white24` for backward compatibility with the two `BottomPlayer` callers at `bottom_player.dart:184,499`). Threaded through `_SeekbarPainter` and used for every unplayed track segment across `_paintMinimal`, `_paintGradient`, `_paintWaveform`, `_paintWavy`, and `_paintSegmented`. `shouldRepaint` updated so color changes trigger a repaint.

### Changed
- **High-Contrast Monochrome Full-Screen Player Theme:** Reworked `PlayingScreen` into a layered, high-contrast monochrome look that strips out the dynamic palette-accent extraction. The body `Stack` now stacks three background layers beneath the existing UI — a full-bleed `CachedNetworkImage` of the current track's artwork, a 40/40 Gaussian `BackdropFilter` blur, and a `Colors.black.withOpacity(0.75)` dark scrim. All primary controls (play/pause) and the active toggle / accessory state (Auto DJ, Karaoke, Favorite heart, Shuffle, Repeat, Lyrics-mode mic, add-to-playlist, queue) render solid `Colors.white`; inactive toggles / accessories render `Colors.white.withOpacity(0.35)`. The play/pause primary control is now a solid white circle with a black icon and a white-tinted shadow. The seek bar's played segment is `Colors.white` and the unplayed segment is `Colors.white.withOpacity(0.30)` (or black @ 0.30 when `invertSeekbarColor` is on).
- **Full-Screen Player `dominantColor` Consumption Stripped:** `player.dominantColor` is no longer read inside the `PlayingScreen` widget tree. The local `activeColor` resolves to `Colors.white`, the visualizer receives `Colors.white` directly, and the `PlayingScreen` no longer derives accent colors from album art. The `PaletteGenerator` call inside `PlayerProvider` is intentionally left intact for the other widgets that still consume it (bottom player, miniplayer lyrics view, miniplayer timer view, custom lyrics modal). The now-unused `Color activeColor` parameter on `_buildMediaControls` was removed.
- **Miniplayer Icon Row Rearranged:** The Auto DJ button moved from the top row (between Favorite and Lyrics) to the far left of the bottom control row, ahead of Shuffle. Top row is now `heart → mic → playlist_add → timer → queue` (5 icons). Bottom row is `Auto DJ → Shuffle → Skip Previous → Play/Pause → Skip Next → Repeat → Cast`.
- **Auto DJ Icon Always Visible, Color-Only Toggle:** The conditional `_hasManualQueueRemaining(player)` gate that hid the Auto DJ icon in the empty / single-play state was removed per user request. The icon is now always rendered, with a constant `Icons.auto_awesome` shape — the toggle state is communicated strictly through color (`0xFFEAB308` yellow when enabled, `Colors.white54` when disabled), as the spec requires. The unused `_hasManualQueueRemaining` helper was deleted.
- **Home Tab Bar Aligned with Hamburger Icon:** Removed the inner `Scaffold > AppBar(bottom: TabBar)` from `HomeScreen`. The `DefaultTabController` now wraps a `Column` whose first child is a `Container(alignment: Alignment.centerLeft, child: TabBar(...))` and second child is the `TabBarView`. The tab row shares the same left edge as the `MainLayout`'s AppBar leading icon, so "Home", "Global Hot", and "Featured Albums" are visually aligned with the hamburger.
- **Miniplayer Bottom Action Bar — Proportional Flex Spacing:** The bottom control row is now a single `Padding(horizontal: 16, vertical: 8)` wrapping a `Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: center)` with the 7 controls in spec order. Stripped the two `Expanded` wrappers, the inner `Row(mainAxisSize: MainAxisSize.min)` around the transport cluster, and the two `SizedBox(width: 8)` spacers flanking the play/pause circle. All hitboxes are ≥ 40dp (the five `IconButton`s default to 48dp; the play/pause `Container` is 48x48). State-dependent color logic is untouched.

---

## [1.1.6] — 2026-06-04

### Added
- **Write-Time Lyrics Validation Pass:** `HybridCacheService.validateLyricsWrite(...)` is a new static assertion that runs after every lyrics fetch. It returns `true` only when all three conditions hold: the payload string is non-empty, the on-disk LRC file at `<docs>/<trackId>-lyrics.lrc` exists and is non-empty, and the in-box `timedLyrics` blob equals the payload that was just written. This is the explicit cross-check the spec calls out for "verify the lyrics payload (`timed_lyrics` text block) is not null or empty" + "Run an immediate assertion pass (`File.exists()` for LRC files or `box.get(trackId).timedLyrics != null` for database fields)".
- **`lyricsVerified` Field on `CacheTrackerModel`:** New Hive adapter field id 5 with default `true`. Persists the result of the most recent write-time validation so the offline cascade can self-heal: a track whose validator fails flips the flag to `false`, and the next prebuffer / favorite call re-fires the fetch. Legacy records (written before this schema bump) surface with `lyricsVerified = true` via a null-coalesce in the read path, so a one-shot migration is not required.
- **`HybridCacheService.markLyricsMissing(trackId)`:** Explicit marker for "we know this track's lyrics payload failed validation". Called by the lyrics repository on the final failed validation attempt of `_fetchAndCacheLyricsWithValidation`, and used by future eviction passes as a signal to drop the lyrics on a casual-tier purge.
- **`HybridCacheService.isLyricsVerified(trackId)`:** Synchronous getter the prebuffer / favorite hooks consult before re-firing a fetch — once a track's lyrics are verified, subsequent prebuffer calls short-circuit instead of hammering the LrcLib API.
- **Offline Lyrics Read Cascade — File → Hive Blob → null:** New public `AudioRepositoryImpl.getLyricsOffline(Track)` (added to the `AudioRepository` interface) is the explicit offline-only read path. Order: (1) deterministic trackId-keyed LRC file at `<docs>/<trackId>-lyrics.lrc` with the same non-empty + LRC-timestamp / plain-text structural check the online path uses, (2) `HybridCacheService.getLyrics(trackId)` in-box `timedLyrics` blob — the belt-and-braces fallback for the case where the file is missing (manual delete, partial cleanup) but the Hive record survived, (3) `null` so the presentation layer renders "Lyrics not available". Never calls the network, never modifies either storage tier, and never throws on a miss.
- **Connectivity-Gated Lyrics Fetch:** `AudioRepositoryImpl.getLyrics(track)` now consults `ConnectivityService.isOffline` at the top of the method. When the device is offline, the network fetch is skipped entirely and the offline cascade runs instead — the spec §2 invariant that "the lyrics repository must completely bypass network client calls and read exclusively from local data entities" is enforced before the LrcLib client is even instantiated. Late-bound via a new `AudioRepositoryImpl.attachConnectivity(...)` setter so the existing `ConnectivityService` ctor (which already holds a ref to the audio repository) can be wired up without a cycle.
- **Lyrics Fetch on Prebuffer (Spec §1):** `AudioRepositoryImpl.preloadTrack(track)` now also fires `unawaited(preloadTrackLyrics(track))` after the audio prebuffer kicks off. `preloadTrackLyrics` is fire-and-forget — a failed lyrics fetch never aborts the audio cache write. Honors the `isLyricsVerified` short-circuit so already-verified tracks are not re-fetched on every prebuffer tick.
- **Lyrics Fetch on Favorite (Spec §1):** `PlaylistRepositoryImpl.toggleFavorite(Track)` now fires `unawaited(_audioRepository.preloadTrackLyrics(track))` immediately after the SQLite toggle, so favoriting a track is treated as a cache transaction and the structural lyrics validation runs. The favorite toggle is non-blocking and a failed lyrics fetch does not roll back the favorite. The repository's new `audioRepository` constructor parameter is optional — existing call sites that do not wire it (tests) continue to compile and run.

### Changed
- **`AudioRepositoryImpl.getLyrics(Track)` Refactor:** The online path is now split into two stages. Stage 1: try the on-disk LRC via the new `_readCachedLyricsFile(trackId, lyricsPath)` helper, which returns `null` on missing / empty / corrupt content so the caller can fall through cleanly. Stage 2: network fetch via the new `_fetchAndCacheLyricsWithValidation(track, lyricsPath)` helper, which loops up to two attempts and runs `HybridCacheService.validateLyricsWrite` after each write. On validation failure the loop retries; on the final failure the lyrics state is flagged via `markLyricsMissing` and the best-effort payload is returned.
- **`AudioRepositoryImpl.refreshLyrics(Track)`:** Now a thin delegate to `_fetchAndCacheLyricsWithValidation`, so the manual "Refresh Lyrics" UI action runs through the same validation + retry pipeline the cache transactions use.
- **`HybridCacheService.setLyrics(...)`:** Now stamps `lyricsVerified: true` on the persisted record, so the optimistic default ("this write was committed cleanly") is reflected in the box. The `markLyricsMissing` flip is the explicit failure path; there is no longer an implicit "we don't know" middle state.
- **`HybridCacheService.markSuccessAfterWrite(...)`:** Preserves the `existing?.lyricsVerified` flag in the rebuilt record. An audio write does not re-stamp the lyrics state — it carries it forward — so a record whose lyrics were verified remains verified after a successful audio cache hit.
- **`AudioRepository` Interface:** Added `getLyricsOffline(Track)` and `preloadTrackLyrics(Track)` so the typed repository reference held by `PlaylistRepositoryImpl` is statically bound (was previously `dynamic`). Both methods carry the `@override` annotation.
- **`main.dart` Wiring Order:** Repository is constructed first with no live connectivity ref, then `ConnectivityService` is built holding a ref to the repo, then `audioRepository.attachConnectivity(connectivityService)` late-binds the connectivity ref, then `connectivityService.initialize()` runs the synchronous initial probe. `PlaylistRepositoryImpl` is constructed after the connectivity probe so the audio repo is fully wired. No constructor cycle, no behaviour change for the existing offline-mode push path (`setOfflineMode` is still called by `ConnectivityService._handleChange`).

### Fixed
- **Lyrics Failed to Load Offline Despite Being Cached:** Root cause was twofold. (1) The read cascade ran `file → network` unconditionally — when offline, every fetch hit the network client and failed, even though the lyrics were sitting in the LRC file or the Hive blob. (2) The cascade had no fallback to the in-box `timedLyrics` blob, so a track whose file was deleted (manual cleanup, partial eviction) but whose Hive record survived rendered as "Lyrics not available" even though the payload was on disk inside the box. The new `getLyricsOffline` cascade (file → Hive blob → null) is the explicit fix; it is the only path the offline presentation layer can take, and the connectivity service gates it at the top of `getLyrics` so the network client is never even constructed.
- **Silent Lyrics Write Failures Went Undetected:** When the LrcLib fetch returned a payload but the on-disk write or the Hive mirror write silently failed (disk full, permission denied, partial file), the next read would find nothing and the user would have no idea the cache transaction was broken. The new `validateLyricsWrite` assertion runs `File.exists()` and the in-box blob equality check immediately after the write, and on failure the lyrics repository retries the fetch once. Only after the second failed attempt does it give up — at which point `markLyricsMissing` flips the box flag so future consumers can self-heal.
- **Prebuffer Cached Lyrics-Less Tracks Silently:** When the lookahead prebuffer engine cached a track's audio, the Hive tracker box was updated with `cachedAt` and `isFavorite` but the lyrics payload was never written. A user who tapped the next track in offline mode would see "Lyrics not available" for a track the system had *just* decided to cache. `preloadTrack` now also fires `preloadTrackLyrics` so the structural validation pass runs alongside the audio prebuffer.
- **Favoriting a Track Did Not Cache Its Lyrics:** Favoriting is a cache transaction per the spec ("user download, favoriting, or background look-ahead preloading") but the old favorite path only flipped a SQLite + Hive flag. Lyrics would be missing on the next offline play even though the track was permanently in the user's library. `toggleFavorite` now fires `preloadTrackLyrics` after the SQLite flip, with the same fire-and-forget safety guarantees as the prebuffer path.
- **Schema Bump Was Not Forward-Compatible:** `CacheTrackerModel` did not declare a field count, so any future field addition would have required a manual migration. The adapter now writes an explicit `writeByte(6)` field count, and the read path null-coalesces unknown fields to their defaults — adding field id 6 in a future release will not require touching the existing 0..5 records.

---

## [1.1.4.2] — 2026-06-04

### Changed
- **Default Lyrics Engine:** Migrated entirely to LrcLib as the primary and sole lyrics engine.
- **LrcLib Reliability:** Increased LrcLib connection timeout to 15 seconds and added detailed logging to `LyricsRemoteDataSource` to assist with network debugging.
- **Removed YouTube Music Lyrics Engine:** Deleted `YoutubeFetcher` (`youtube_fetcher.dart`) and its initialization from `main.dart`. The brittle YouTube Music lyrics engine was causing `youtubei/null/search` errors and has been fully replaced.

---

## [1.1.4.1] — 2026-06-04

### Changed
- **Lyric Font Color — Plain White Lock-In:** Removed the dominant-color extraction path for lyric typography in both the full-screen player and the miniplayer lyric layer. Every lyric line now renders in pure white (`#FFFFFF`) regardless of album artwork palette.
  - Active line: white, bold, full opacity (1.0), large size.
  - Upcoming lines: white, regular weight, 0.4 opacity, normal size.
  - Passed lines: white, regular weight, 0.25 opacity, normal size.

### Fixed
- **Unreadable Lyrics on Bright Album Art:** When the dominant color extracted from the album artwork skewed bright (yellow, white, light blue, etc.), the active lyric line was rendered in that color against the dark blurred background and became illegible. Plain white at the three opacity tiers above reads cleanly against any dark blurred background.
- **Blurred First Line on Lyrics Load:** The previous fade/blur entrance left the first lyric line partially transparent and clipped at the top of the visible area on initial load, making it unreadable until the entrance animation completed. Replaced with a 3-dot pulsing entrance sequence (dot 1 at t=0, dot 2 at t=400ms, dot 3 at t=800ms, dots scroll up + fade out at t=1400ms over 600ms) that hands off to a fully-visible first line arriving at the top position at t=1600ms.
- **Active Line Centering Drift:** Active lyric lines were being scrolled to the vertical center of the container, which pushed the first line off-screen and made the upcoming context invisible. Re-aligned to the upper third (H * 0.25 from the top) with a smooth 300ms ease-in-out animation per line advance.
- **Hard Bottom Clip on Long Lyrics:** Bottom edge of the lyric container was hard-clipping the last visible line. Added a soft gradient fade to transparent on the bottom edge only; the top edge remains unblurred and unclipped at all times.
- **Seek-Through Lyrics Drift:** On track seek (timeline scrub), the active line did not jump to the new position and the scroll animation re-played from the wrong offset. The active line now jumps immediately to the correct synced position and the scroll animation re-runs from that new position without re-triggering the dot entrance sequence.
- **Stuck Dot Loader on Slow Fetch:** When lyrics were still being fetched, the dot entrance either never started or froze mid-sequence. The 3-dot loader now holds open (continues pulsing) until the lyrics payload arrives, then hands off to the first line as normal.
- **No-Lyrics Path Now Visible:** Tracks without synced lyrics previously showed a blank lyric area. Now displays "Lyrics not available" in white at 0.5 opacity, centered.
- **Unsynced Lyric Lines Scrolled:** Unsynced lyrics (lines without timestamps) were being treated like synced lines and the scroll controller was attempting to advance against a null active index. Unsynchronized lines now render as static text with no active-line highlight and scroll is disabled.
- **Multi-Line Wrapping Broken Scroll Count:** Lyric lines that wrapped to two or more visual rows were being counted as multiple lines by the scroll controller, causing the active position to land mid-block. Wrapped lines are now counted as a single line for scroll purposes and the bold/active state applies to the full wrapped block.

---

## [1.1.5] — 2026-06-04

### Added
- **Global Reactive Connectivity Listener:** New `ConnectivityService` (`lib/core/services/connectivity_service.dart`) extends `ChangeNotifier`, owns a single long-lived `connectivity_plus` subscription, and exposes the current transport state as a typed `NetworkState` (`unknown` / `online` / `offline`) plus a broadcast `Stream<NetworkState>` for future consumers. Constructed once in `main.dart` after every collaborator is alive and `initialize()`d before `runApp`, so the system is locked to the right starting mode from frame one.
- **Connectivity Bootstrap on Startup:** `ConnectivityService.initialize()` runs `Connectivity.checkConnectivity()` synchronously, pushes the result through `_handleChange(isInitialProbe: true)`, and then attaches to `onConnectivityChanged`. This replaces the old implicit "check once during init" behaviour with a reactive stream that survives the entire app lifetime.
- **Toggle Switch on the Audio Repository:** `AudioRepositoryImpl.setOfflineMode(bool)` is the explicit boundary the spec calls out. It stores a private `_isOffline` flag with a public `isOffline` getter, is a no-op when the value is unchanged, and never touches the audio-decoding / playback / cache-lookup code paths. The interface in `lib/domain/repositories/audio_repository.dart` is left untouched.
- **YouTube Network-Client Wake-Up:** `YoutubeRemoteDataSource.refreshNetworkClientHeaders()` closes the existing `_yt` client (swallowing double-close) and re-runs `init()` to rebuild both the `YoutubeExplode` and `YTMusic` clients against a fresh cookie read. Required dropping `late final` → `late` on `_yt` / `_ytMusic`. No audio playback is interrupted.
- **Lyrics Retry Hook:** `LyricsRemoteDataSource.retryPendingConnections()` is the explicit contract for the listener on the LrcLib side. The data source is stateless (fresh `http.Client` per call), so the method is a no-op network-wise but logs the wake-up event for observability.
- **`connectivity_plus` Dependency:** Added `connectivity_plus: ^6.0.0` to `pubspec.yaml` (resolved to `6.1.5` in the lock). The `connectivity_plus_platform_interface` transitive dependency is also pinned in `pubspec.lock`.
- **`ACCESS_NETWORK_STATE` Permission:** Added to `android/app/src/main/AndroidManifest.xml` so the `connectivity_plus` Android plugin can subscribe to transport changes from a non-foreground process.
- **Connectivity Service in `MultiProvider`:** `ZYPMusic` now accepts a `ConnectivityService` instance and exposes it via `ChangeNotifierProvider.value` alongside the other top-level notifiers, so the UI layer can `context.watch<ConnectivityService>()` for status badges without subscribing to the stream directly.
- **Hybrid SQLite + Hive Eviction Guard:** `HybridCacheService` is now constructed with a `libraryDatabase` (PlaylistDatabase) reference and exposes a new `evaluateAndEvictCasualCache()` flow. After every successful casual-tier write, the service checks `hiveCacheBox.length <= casualLimit` (200), sorts the qualifying non-favorite values by `cachedAt` ascending, takes the oldest `evictionBatchSize` (10), and cross-checks each track against SQLite — only deleting the physical audio + lyrics files when the track is *neither* favorited *nor* bound to a downloaded album. Hive-flag fallback is honored so legacy entries without a corresponding SQLite row are still evicted.
- **Public File Deletion API:** New `HybridCacheService.deleteLocalAudioFile(trackId)` and `deleteLocalLyricsFile(trackId)` methods (formerly private aliases). The lyrics deletion resolves the tracked `lyricsFilePath` from Hive first, then falls back to the deterministic `<docs>/<trackId>-lyrics.lrc` filename for belt-and-braces coverage. Used by the new eviction guard and exposed for future cleanup flows.
- **Cached-Track Probe:** `HybridCacheService.getCachedTrackIds()` returns the current `cache_tracker_box` keys as a `Set<String>`, giving the new Auto DJ offline pool an O(1) lookup against what's already on disk.
- **QueueManager — Explicit Auto DJ Engine:** New `lib/core/services/queue_manager.dart` (`ChangeNotifier`) owns the Auto DJ lifecycle. Public surface is `isAutoDJEnabled`, `start()`, `enable()`, `disable()`, `toggle()`, and `generateNextAutoDJTrack(current)`. A `metadataResolver` callback lets the engine resolve a `Track` from a trackId for the offline pool without depending on the data layer. Online-first (`audioRepository.getUpNexts`) with deterministic offline fallback when the network is down.
- **Cross-Database Offline Pool:** `QueueManager._selectOfflineTrack()` composes the offline pool from three sources — Hive `cache_tracker_box` keys, SQLite `getFavoriteTrackIds()`, and SQLite `getAllDownloadedTrackIds()` — deduplicated and shuffled. The current track is removed before selection, and a minimal placeholder `Track(id, title: 'Cached Track', source: youtube)` is used when no metadata is available so the engine never stalls on a missing entry.
- **Auto DJ Long-Press Menus:** `TrackContextMenu` is rewritten with two new actions — **Start Auto DJ** (gold `Icons.auto_awesome`) and **Add to Queue** (`Icons.playlist_play`). "Add to Queue" never engages Auto DJ; "Start Auto DJ" is the only path that flips `isAutoDJEnabled` to `true` from the track long-press sheet.
- **AlbumContextMenu:** New `lib/ui/widgets/album_context_menu.dart` mirrors the track menu for album long-presses, with **Start Auto DJ** (resolves to a synthetic track from `Album.toPlaylist()` or a single placeholder when the album has no resolved tracks), **Add to Queue**, and **Favorite Album**. Wired into `_AlbumCard.onLongPress` on the Home screen.
- **Miniplayer Auto DJ Toggle Slot:** `BottomPlayer` inserts the Auto DJ icon between the Favorite and Lyric action buttons. The slot is gated on `_hasManualQueueRemaining(player)` so single-tap finite playback keeps the bar visually clean — the icon only appears when there's at least one more item in the manual queue.
- **Full-Screen Auto DJ Toggle:** `PlayingScreen`'s top header `Icons.more_vert` is replaced with a persistent Auto DJ toggle. Gold when active, white when dim, and acts as a one-tap `toggleAutoDJ()` from the full-screen player.
- **`flutter analyze` Cleanliness:** Net reduction from 31 → 28 analyzer issues. The old auto-fetching `next()` path was removed, taking 3 pre-existing dead-code warnings in `audio_repository_impl.dart`'s `getUpNexts` with it. The new files (`queue_manager.dart`, `album_context_menu.dart`) compile clean with no new warnings.

### Changed
- **`YoutubeRemoteDataSource` field mutability:** `late final YoutubeExplode _yt;` and `late final ytm.YTMusic _ytMusic;` became `late YoutubeExplode _yt;` and `late ytm.YTMusic _ytMusic;` so `refreshNetworkClientHeaders()` can reassign them after closing the previous instance. No call site changed; the existing `init()` body still performs the first assignment and `_yt.close()` is now reused inside `dispose()` and `refreshNetworkClientHeaders()`.
- **Init Block in `main.dart`:** After the download provider is initialised, `ConnectivityService` is constructed with the existing `audioRepository`, `remoteDataSource`, and `lyricsDataSource` and `await connectivityService.initialize()` is called before `runApp`. The instance is passed into `ZYPMusic` so it can be put into the provider tree.
- **`ZYPMusic` Constructor:** Added a required `connectivityService` parameter and a corresponding `ChangeNotifierProvider.value(value: connectivityService)` entry in the `MultiProvider` providers list, slotted right after `hybridCache`.
- **`CacheTrackerModel` Schema — Lyrics Path Persistence:** New `lyricsFilePath` field (Hive adapter field id 4) added to `CacheTrackerModel`. The deterministic `<docs>/<trackId>-lyrics.lrc` filename remains the primary lookup; the stored path is the belt-and-braces fallback. On-disk format is stable — adding a new field at the end of the adapter does not break existing records.
- **`HybridCacheService` Constructor:** `libraryDatabase` is now a required named parameter. The old private alias constants `_maxCasualEntries` / `_evictBatchSize` are removed in favor of the public `casualLimit` (200) and `evictionBatchSize` (10) instance fields, so the values are observable for tests and the public eviction flow without analyzer noise.
- **`AudioRepositoryImpl` Lyrics Pathing:** The repository now resolves lyrics through `_lyricsFilePathFor(trackId)` (trackId-keyed, e.g. `<docs>/<id>-lyrics.lrc`) and pushes the resolved path into `HybridCacheService.setLyrics(trackId, lrc, filePath: …)`. The repository layer no longer relies on `<title>-lyrics.lrc` naming, so renaming a track in the future can never desync the lyric file from its cache record.
- **`main.dart` Wiring:** `localDatabase` (PlaylistDatabase) is instantiated once at the top of `main.dart` and passed to both `HybridCacheService(libraryDatabase: localDatabase)` and `QueueManager(..., libraryDatabase: localDatabase)`. The `QueueManager` is constructed after `ConnectivityService` and `await QueueManager.start()` is called before `runApp`. The instance is forwarded into `ZYPMusic` for the provider tree.
- **`ZYPMusic` Constructor (QueueManager):** Added a required `queueManager` parameter and a corresponding `ChangeNotifierProvider.value(value: queueManager)` entry in the `MultiProvider` providers list, slotted right after `connectivityService`. `PlayerProvider` is now constructed with the named `queueManager:` argument.
- **`PlayerProvider` Refactor:** Accepts an optional `QueueManager` and exposes `startAutoDJ()`, `appendToQueue(Track)`, `toggleAutoDJ()`, and `isAutoDJEnabled`. `setQueue()` and `clearQueue()` call `disableAutoDJ()` to enforce the "explicit Auto DJ" contract — every other queue mutation path is strict finite playback. `next()` is now a no-op at the end of the manual queue; only the audio completion handler drives Auto DJ generation.
- **Audio Completion Routing:** The completion handler now branches in this order: Loop One → manual `next()` → Loop All → Auto DJ → stop. Auto DJ is consulted only when the queue is fully consumed and Auto DJ is enabled, and `generateNextAutoDJTrack(currentTrack)` is invoked with the just-finished track. Loop All *fully* blocks Auto DJ, so the user has to explicitly toggle Auto DJ to resume endless playback after a queue cycle.
- **PlayerProvider / QueueManager Listeners:** `PlayerProvider` subscribes to `QueueManager` in its constructor and calls `notifyListeners()` on every `isAutoDJEnabled` flip, so the miniplayer and full-screen toggles stay in lockstep with the engine state without polling.
- **`_recentlyPlayed` as Metadata Resolver:** `PlayerProvider` wires `metadataResolver: (id) => _recentlyPlayed.firstWhereOrNull((t) => t.id == id)` into the `QueueManager`, so the offline pool resolves to real `Track` objects (with title, artist, artwork) when the user has played the track before. Cached tracks outside the recently-played list fall back to the minimal placeholder.

### Fixed
- **App Stuck Offline After Network Restoration:** If the app was launched with no active connection, `_ytMusic.initialize()` failed during `main.dart` startup (logged but not fatal), leaving the system stuck on broken network clients for the rest of the session. Even after Wi-Fi / mobile data came back, every subsequent search, stream, and metadata call would still fail and the user had to kill and relaunch the app. The new `ConnectivityService` now detects the `offline -> online` transition and explicitly wakes the network clients — `refreshNetworkClientHeaders()` rebuilds the YouTube/YTMusic clients and `retryPendingConnections()` re-arms the lyrics source — restoring online search, remote endpoints, and remote streaming without dropping current audio playback. The transition is fully automatic: no user interaction, no app reload, no UI page refresh.
- **Initial Offline Boot No Longer Mis-Transitions:** The previous code path would have called `setOfflineMode(false)` (a no-op) and then `refreshNetworkClientHeaders()` on a healthy first launch, doing redundant work. The new `wasOffline` guard in `_handleChange` skips the wake-up path when the initial probe shows the device is already online, so the wake-up is now reserved strictly for the `offline -> online` transition.
- **Casual Cache Could Evict Library Tracks:** Before this change, `HybridCacheService` was Hive-only. A track favorited on the very first play — *before* it had a chance to be written to the SQLite favorites table by a later migration — was vulnerable to the casual-tier LRU eviction, and the audio + lyric files on disk were deleted out from under the user. The new cross-DB guard reads SQLite *first*, treats EITHER `isTrackFavorite(id)` OR `isTrackDownloaded(id)` as "saved in library", and skips the file deletion when the track is in the library. The Hive `isFavorite` flag is still honored as a fast path so legacy entries without a SQLite row are still protected.
- **Implicit Auto-Advance on Manual `next()`:** The old `next()` method silently called `AudioRepository.getUpNexts` to fetch remote recommendations when the manual queue ran out, so a single tap on a track could turn into a covert auto-play session. The new `next()` is a strict no-op past the end of the queue; the only way to engage Auto DJ is the explicit `Start Auto DJ` long-press action or the toggles in the miniplayer / full-screen player.
- **Album Long-Press Had No Menu:** Long-pressing an album card on the Home screen had no handler wired up. The new `AlbumContextMenu` is the single source of truth for album-level Start Auto DJ / Add to Queue / Favorite actions, and it's reachable from `_AlbumCard.onLongPress` for both featured and chart album cards.
- **Lyric File Path Drift on Track Rename:** Because the old lyrics file was named after the track title (`<title>-lyrics.lrc`), renaming a track could leave a phantom `.lrc` on disk while new writes went to a fresh path. The trackId-keyed `_lyricsFilePathFor(trackId)` makes the path stable across title edits, and the stored `lyricsFilePath` in Hive gives the eviction flow a deterministic delete target even if a legacy `<title>-lyrics.lrc` file is somehow still on disk.

---

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
