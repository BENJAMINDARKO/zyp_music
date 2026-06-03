# Music Player — Algorithm & Feature Specification
> Hand this file to your agentic coder as a complete implementation brief.

---

## Table of Contents
1. [Unified Search Algorithm](#1-unified-search-algorithm)
2. [Source Priority & Fallback Engine](#2-source-priority--fallback-engine)
3. [Persistent Source Selection](#3-persistent-source-selection)
4. [Download Algorithm](#4-download-algorithm)
5. [Offline Cache (Keep Alive)](#5-offline-cache-keep-alive)
6. [Settings Persistence](#6-settings-persistence)
7. [Data Models](#7-data-models)

---

## 1. Unified Search Algorithm

### Goal
When a user types a query (e.g. *"Kendrick Lamar Not Like Us"*), the app fans out to all configured sources in parallel, then **deduplicates and merges** the results into unified tabs — so the user never sees the same track listed multiple times from different sources.

### Search Tabs

| Tab | Contents | Sources |
|-----|----------|---------|
| **Tracks** | Deduplicated songs/audio files | Tidal, Qobuz, Deezer, YouTube Music |
| **Albums** | Deduplicated albums | Tidal, Qobuz, Deezer, YouTube Music |
| **Playlists** | Playlists containing matching tracks | Tidal, Qobuz, Deezer, YouTube Music |
| **Artists** | Matching artist + similar artists | Tidal, Qobuz, Deezer, YouTube Music |
| **Videos** | Music videos, live sessions | YouTube (video, not YTMusic) |

> **Rule:** YouTube Music audio results merge into Tracks/Albums/Playlists alongside Tidal, Qobuz, and Deezer.  
> YouTube video results (non-audio) go **only** to the Videos tab.

---

### Search Flow (Step by Step)

```
User types query
      │
      ▼
[Fan-out: fire all source API calls in parallel]
  ├── Tidal.search(query)
  ├── Qobuz.search(query)
  ├── Deezer.search(query)
  ├── YouTubeMusic.search(query)
  └── YouTube.searchVideos(query)   ← Videos tab only
      │
      ▼
[Collect results as they arrive — show partial results immediately]
      │
      ▼
[Deduplication Engine]  ← see rules below
      │
      ▼
[Render into tabs: Tracks | Albums | Playlists | Artists | Videos]
```

---

### Deduplication Rules

Two results are considered the **same track** if they match on:

```
normalise(title) === normalise(title)
AND
normalise(artist) === normalise(artist)
AND
abs(duration_seconds_A - duration_seconds_B) < 5   // within 5 seconds
```

**Normalisation function:**
```js
function normalise(str) {
  return str
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, '')   // strip punctuation
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/\b(feat|ft|featuring|with|vs|&)\b.*$/, '') // strip feat. suffix
}
```

**When duplicates are found:**
- Keep **one** unified card in the UI.
- Internally store the list of all available sources for that track (used by the Fallback Engine in §2).
- Attach source badges (e.g. small icons: Tidal, Qobuz, Deezer, YTMusic) to the card so the user can see availability without seeing duplicate rows.

**Album deduplication:** match on `normalise(album_title) + normalise(artist) + release_year`.

---

### Search Result Card Structure

```json
{
  "id": "unified_track_abc123",
  "type": "track",
  "title": "Not Like Us",
  "artist": "Kendrick Lamar",
  "album": "GNX",
  "album_art": "https://...",
  "duration_seconds": 274,
  "release_year": 2024,
  "sources": [
    { "provider": "tidal",        "stream_id": "...", "quality": "lossless" },
    { "provider": "qobuz",        "stream_id": "...", "quality": "hi-res" },
    { "provider": "deezer",       "stream_id": "...", "quality": "flac" },
    { "provider": "youtube_music","stream_id": "...", "quality": "aac_256" }
  ],
  "active_source": null   // set by Fallback Engine at play time
}
```

---

## 2. Source Priority & Fallback Engine

### Goal
When a track is played, the engine picks the **best available source** based on a configurable priority order. If that source goes offline mid-playback or fails to load, it silently falls back to the next available source — without the user having to do anything.

---

### Default Priority Order (user can reorder in Settings)

```
1. Tidal        (lossless / MQA)
2. Qobuz        (hi-res FLAC)
3. Deezer       (FLAC / MP3 320)
4. YouTube Music (AAC 256 / Opus)
```

---

### Playback Resolution Flow

```
User taps play on unified track card
        │
        ▼
[Read track.sources[] sorted by priority order]
        │
        ▼
[Try Source #1]
   ├── SUCCESS → set track.active_source = source #1, begin stream
   └── FAIL (timeout 3s / HTTP error / offline)
          │
          ▼
       [Try Source #2]
          ├── SUCCESS → set track.active_source = source #2, begin stream
          └── FAIL
                 │
                 ▼
              [Try Source #3] ... and so on
                 │
                 └── ALL FAIL → show "Track unavailable" toast
```

**Mid-playback failure:**
- If a stream dies mid-song, store `current_position_seconds`.
- Silently resolve next available source.
- Resume from `current_position_seconds` on the new source.
- Show a small non-intrusive toast: *"Switched to [Source Name]"*.

---

### Source Health Check

Run a lightweight ping every **60 seconds** in the background:

```js
async function checkSourceHealth(provider) {
  try {
    const res = await fetch(provider.ping_url, { signal: AbortSignal.timeout(3000) })
    provider.is_online = res.ok
  } catch {
    provider.is_online = false
  }
}
```

Use `is_online` flags to **skip** offline sources immediately without waiting for a timeout when resolving playback.

---

## 3. Persistent Source Selection

### Goal
Once a source is resolved for a track, **that choice sticks** for the entire session and across navigation — mini player, full-screen player, album view, artist view. Clicking an album title or artist name does not trigger a re-resolution.

---

### Implementation

Maintain a **global playback session store** (in-memory + persisted to local storage):

```js
const playbackSession = {
  // key = unified track id, value = resolved source object
  resolvedSources: Map<string, SourceObject>,

  resolve(trackId) {
    if (this.resolvedSources.has(trackId)) {
      return this.resolvedSources.get(trackId)   // return cached, don't re-resolve
    }
    const source = FallbackEngine.resolve(trackId)
    this.resolvedSources.set(trackId, source)
    persistToStorage('playback_session', this.resolvedSources)
    return source
  },

  clear() {
    this.resolvedSources.clear()
    removeFromStorage('playback_session')
  }
}
```

**Rules:**
- Any navigation event (mini player → full screen, album click, artist click) calls `playbackSession.resolve(trackId)` — which returns the already-resolved source instantly.
- Only call `FallbackEngine.resolve()` for **new** tracks not yet in the session.
- Clear the session when the user explicitly switches source manually or on app cold start.

---

### Navigation Source Consistency

When the user clicks an **album name** from the player:
1. Open Album view.
2. For the currently playing track already in the session → keep its resolved source.
3. For other tracks in that album → pre-resolve using the **same provider** as the current track (preferred), falling back if unavailable.

```js
function resolveAlbumTracks(album, preferredProvider) {
  return album.tracks.map(track => {
    const sourceMatchingProvider = track.sources.find(s => s.provider === preferredProvider && s.is_online)
    return sourceMatchingProvider
      ? { ...track, active_source: sourceMatchingProvider }
      : FallbackEngine.resolve(track.id)   // fall back normally
  })
}
```

---

## 4. Download Algorithm

### Goal
Allow the user to download any track/album/playlist to a folder they choose on their device, in a format and quality that can be configured **per source** in Settings.

---

### Download Settings Structure (per source)

Stored in user settings. Each source has its own quality option:

```json
{
  "download_settings": {
    "global_download_folder": "/storage/emulated/0/Music/MyApp",
    "sources": {
      "tidal": {
        "quality": "lossless",         // options: "lossless" | "hi_res" | "high" | "normal"
        "format": "flac"               // options: "flac" | "m4a" | "mp3"
      },
      "qobuz": {
        "quality": "hi_res_24bit",     // options: "hi_res_24bit" | "lossless_16bit" | "mp3_320" | "mp3_128"
        "format": "flac"
      },
      "deezer": {
        "quality": "flac",             // options: "flac" | "mp3_320" | "mp3_128" | "aac_64"
        "format": "flac"
      },
      "youtube_music": {
        "quality": "best",             // options: "best" | "aac_256" | "aac_128" | "mp3_192"
        "format": "m4a"                // options: "m4a" | "mp3" | "aac"
      }
    }
  }
}
```

> **Important:** Each source's quality setting is **independent**. Changing Tidal quality does not affect Deezer quality.

---

### Settings UI Layout (Downloads Tab)

```
Settings → Downloads
├── 📁 Download Folder         [Pick Folder button]  /path/to/folder
├── ─────────────────────────────────────────────
├── 🎵 Tidal Quality
│   ├── Quality:  [HiFi Lossless ▼]
│   └── Format:   [FLAC ▼]
├── ─────────────────────────────────────────────
├── 🎵 Qobuz Quality
│   ├── Quality:  [Hi-Res 24-bit ▼]
│   └── Format:   [FLAC ▼]
├── ─────────────────────────────────────────────
├── 🎵 Deezer Quality
│   ├── Quality:  [FLAC ▼]
│   └── Format:   [FLAC ▼]
├── ─────────────────────────────────────────────
└── 🎵 YouTube Music Quality
    ├── Quality:  [Best Available ▼]
    └── Format:   [M4A ▼]
```

---

### Download Flow

```
User taps Download on a track/album/playlist
        │
        ▼
[Determine source to download from]
  → Use track.active_source if already resolved
  → Otherwise run FallbackEngine.resolve()
        │
        ▼
[Read quality/format from download_settings.sources[provider]]
        │
        ▼
[Request download stream from provider API with chosen quality]
        │
        ▼
[Write to: global_download_folder / Artist / Album / TrackNumber - Title.format]
  e.g.  /Music/MyApp/Kendrick Lamar/GNX/01 - Not Like Us.flac
        │
        ▼
[Embed ID3/metadata tags]
  → title, artist, album, track number, year, genre, album art (embedded)
        │
        ▼
[Add file to local library index]
  → so the app can play it offline without re-downloading
        │
        ▼
[Show download complete notification]
```

---

### File Naming Convention

```
{artist_name}/{album_name}/{track_number} - {track_title}.{format}
```

- Strip illegal filename characters: `/ \ : * ? " < > |`
- Replace them with `_` or remove them.
- Track number zero-padded to 2 digits: `01`, `02`, `12`.

---

### Download Queue Manager

- Downloads run **sequentially per source** to avoid rate-limiting (max 2 concurrent downloads from the same provider).
- Downloads from **different sources** can run in parallel.
- Persist the queue to storage so it survives app restarts.
- Show a download tray with progress bars.

```json
{
  "download_queue": [
    { "id": "dl_001", "track_id": "unified_abc", "provider": "tidal",  "status": "downloading", "progress": 0.45 },
    { "id": "dl_002", "track_id": "unified_xyz", "provider": "qobuz",  "status": "queued",      "progress": 0 },
    { "id": "dl_003", "track_id": "unified_def", "provider": "deezer", "status": "complete",    "progress": 1.0 }
  ]
}
```

---

## 5. Offline Cache (Keep Alive)

### Goal
Cache recently played tracks so the user can listen without an internet connection.

---

### Cache Strategy

**Two-layer cache:**

| Layer | What | Size Limit | Eviction |
|-------|------|-----------|---------|
| Memory cache | Currently playing track + next 2 tracks (full buffer) | ~30 MB | Cleared on app close |
| Disk cache | Last N tracks played, most recent first | Configurable (default 500 MB) | LRU — evict oldest when full |

---

### Cache Population

```
Track begins playing
        │
        ├── Stream first 30 seconds (for instant start)
        │
        ├── Continue streaming to memory buffer
        │
        └── Simultaneously write to disk cache at:
            {cache_dir}/{provider}/{track_id}.{format}
```

**Pre-cache next track:** when current track has 30 seconds remaining, begin buffering the next track in the queue into the memory cache.

---

### Playback Resolution (Offline-Aware)

```
User plays track
        │
        ▼
[Check disk cache first]
  ├── HIT  → play from cache immediately (no network needed)
  └── MISS → run FallbackEngine (network required)
```

---

### Cache Manifest

Maintain a JSON index so the app knows what's cached:

```json
{
  "cache_manifest": [
    {
      "track_id": "unified_abc123",
      "title": "Not Like Us",
      "artist": "Kendrick Lamar",
      "provider": "tidal",
      "format": "flac",
      "file_path": "cache/tidal/abc123.flac",
      "size_bytes": 38400000,
      "cached_at": "2026-06-02T10:00:00Z",
      "last_accessed": "2026-06-02T11:30:00Z"
    }
  ]
}
```

---

## 6. Settings Persistence

### Problem
App restarts and updates wipe user settings.

### Solution
Use a **versioned settings schema** stored in persistent local storage (SQLite or the platform's key-value store), with a migration system so updates never destroy existing settings.

---

### Settings Storage

```js
// On every settings change:
function saveSetting(key, value) {
  storage.set(`settings.${key}`, JSON.stringify(value))
  storage.set('settings.last_saved', new Date().toISOString())
}

// On app start:
function loadSettings() {
  const version = storage.get('settings.schema_version') || 0
  if (version < CURRENT_SCHEMA_VERSION) {
    migrateSettings(version, CURRENT_SCHEMA_VERSION)
  }
  return readAllSettings()
}
```

---

### Migration System

Each app update that changes the settings schema must include a migration:

```js
const CURRENT_SCHEMA_VERSION = 3

const migrations = {
  1: (settings) => {
    // v0 → v1: add download_settings if missing
    if (!settings.download_settings) {
      settings.download_settings = DEFAULT_DOWNLOAD_SETTINGS
    }
    return settings
  },
  2: (settings) => {
    // v1 → v2: rename 'quality' to 'stream_quality'
    settings.stream_quality = settings.quality
    delete settings.quality
    return settings
  },
  3: (settings) => {
    // v2 → v3: add source priority order
    if (!settings.source_priority) {
      settings.source_priority = ['tidal', 'qobuz', 'deezer', 'youtube_music']
    }
    return settings
  }
}

function migrateSettings(fromVersion, toVersion) {
  let settings = readAllSettings()
  for (let v = fromVersion + 1; v <= toVersion; v++) {
    settings = migrations[v](settings)
  }
  saveAllSettings(settings)
  storage.set('settings.schema_version', toVersion)
}
```

---

### Settings Backup (Optional but Recommended)

Export all settings to a JSON file the user can save:

```js
function exportSettings() {
  const settings = readAllSettings()
  const blob = new Blob([JSON.stringify(settings, null, 2)], { type: 'application/json' })
  downloadFile(blob, `myapp-settings-backup-${Date.now()}.json`)
}

function importSettings(file) {
  const settings = JSON.parse(file)
  validateSettings(settings)   // check schema
  saveAllSettings(settings)
  reloadApp()
}
```

---

## 7. Data Models

### Unified Track

```ts
interface UnifiedTrack {
  id: string                    // generated: "unified_" + hash(title+artist)
  type: 'track' | 'album' | 'playlist' | 'artist' | 'video'
  title: string
  artist: string
  album?: string
  album_art?: string
  duration_seconds: number
  release_year?: number
  sources: SourceRef[]
  active_source?: SourceRef     // set at resolution time
}

interface SourceRef {
  provider: 'tidal' | 'qobuz' | 'deezer' | 'youtube_music' | 'youtube'
  stream_id: string
  quality: string
  is_online: boolean
}
```

### Download Job

```ts
interface DownloadJob {
  id: string
  track_id: string
  provider: string
  quality: string
  format: 'flac' | 'mp3' | 'aac' | 'm4a'
  destination_path: string
  status: 'queued' | 'downloading' | 'complete' | 'failed'
  progress: number              // 0.0 – 1.0
  error?: string
  created_at: string
  completed_at?: string
}
```

### App Settings

```ts
interface AppSettings {
  schema_version: number
  source_priority: string[]
  download_settings: {
    global_download_folder: string
    sources: Record<string, { quality: string; format: string }>
  }
  cache_settings: {
    disk_cache_limit_mb: number
    enabled: boolean
  }
  playback_session: Record<string, SourceRef>
}
```

---

## Implementation Notes for the Agentic Coder

1. **Fan-out search:** Use `Promise.allSettled()` not `Promise.all()` — you want results from sources that succeed even if one source throws.
2. **Deduplication:** Run after each batch of results arrives (streaming dedup), not once at the end — this makes the UI feel fast.
3. **Source health checks:** Store health state in a singleton service shared across search, playback, and download modules.
4. **Download folder picker:** On Android use `ACTION_OPEN_DOCUMENT_TREE`; on iOS use the Files API; on desktop use the native file dialog.
5. **Settings persistence:** Never store settings only in component state. Always write to persistent storage immediately on change.
6. **Migrations:** Run `migrateSettings()` as the very first thing on app start, before any other module reads settings.
7. **Cache eviction:** Run LRU eviction as a background task when the app goes to the background, not during active playback.
