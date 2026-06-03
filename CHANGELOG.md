# Changelog

All notable changes to the `zyp_music` project are documented in this file.

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
