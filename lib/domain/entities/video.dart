enum TrackSource { youtube, youtube_music }

class SourceRef {
  final TrackSource provider;
  final String streamId;
  final String quality;
  bool isOnline;

  SourceRef({
    required this.provider,
    required this.streamId,
    required this.quality,
    this.isOnline = true,
  });
}

class Track {
  final String id;
  final String title;
  final String? thumbnailUrl;

  /// Track duration in seconds, nullable.
  ///
  /// **C1 honest-nulls invariant:** `null` means "unknown" — the
  /// YouTube API did not return a duration for this track (some
  /// live streams, unlisted videos, pre-buffered gapless tracks
  /// whose metadata was dropped on the way through). `Duration.zero`
  /// means "explicitly zero" which is a meaningful value
  /// (intentionally empty audio, rare in practice but possible).
  ///
  /// UI code that displays a duration must check for `null` and
  /// render a placeholder (e.g. `'—:—'`) — see
  /// [formatDuration] in `lib/core/utils/format_duration.dart`.
  /// Coercing `null` to `Duration.zero` at the API boundary
  /// would destroy this distinction and resurrect the
  /// pre-C1 bug where every unknown-duration track rendered
  /// as `0:00`.
  final Duration? duration;
  final String? author;
  final String? albumId;
  final String? album;
  final String? albumArtist;
  final int? year;
  final int index;
  final TrackSource source;
  final List<SourceRef> sources;
  final SourceRef? activeSource;

  /// Primary genre tag for the AI DJ routing layer. Sourced from
  /// `dj_listening_history` by the [LocalCrateMiner] when mining the
  /// candidate pool; the rest of the codebase leaves it null. The
  /// routing service in Phase 2 reads this field to score candidates
  /// for the Same-Genre, Same-Artist, Similar-Songs, and Smart-DJ
  /// modes. Stored on the entity (not the history ledger) so the
  /// crate miner can populate it per-mine-call without an extra DB
  /// round-trip per candidate.
  final String? genre;

  /// Per-track tempo marker (beats per minute) used by the
  /// Phase 4 DSP crossfade engine for pitch-corrected tempo
  /// matching. Populated lazily by [PlaylistDatabase.getTrackBpm]
  /// (authoritative `track_metadata.bpm`, falling back to
  /// `MAX(dj_listening_history.bpm)`); the rest of the codebase
  /// leaves it null. The DSP engine treats a null BPM as
  /// "no tempo matching" — the crossfade runs at 1.0x.
  final double? bpm;

  /// ISO 3166-1 alpha-2 country code for the track's primary
  /// artist, sourced from MusicBrainz's `country` field at enrichment
  /// time and looked up at mine-time by [LocalCrateMiner] against
  /// the `artist_genres.country_code` column. Nullable for bands,
  /// historical artists, and any pre-Spec 2E cache row. Used by
  /// [CountryBonusService] in Same-Genre scoring — Smart DJ
  /// deliberately ignores it. Spec 2E §2.
  final String? country;

  const Track({
    required this.id,
    required this.title,
    this.thumbnailUrl,
    this.duration,
    this.author,
    this.albumId,
    this.album,
    this.albumArtist,
    this.year,
    this.index = 0,
    this.source = TrackSource.youtube,
    this.sources = const [],
    this.activeSource,
    this.genre,
    this.bpm,
    this.country,
  });

  Track copyWith({
    String? id,
    String? title,
    String? thumbnailUrl,
    Duration? duration,
    String? author,
    String? albumId,
    String? album,
    String? albumArtist,
    int? year,
    int? index,
    TrackSource? source,
    List<SourceRef>? sources,
    SourceRef? activeSource,
    String? genre,
    double? bpm,
    String? country,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      duration: duration ?? this.duration,
      author: author ?? this.author,
      albumId: albumId ?? this.albumId,
      album: album ?? this.album,
      albumArtist: albumArtist ?? this.albumArtist,
      year: year ?? this.year,
      index: index ?? this.index,
      source: source ?? this.source,
      sources: sources ?? this.sources,
      activeSource: activeSource ?? this.activeSource,
      genre: genre ?? this.genre,
      bpm: bpm ?? this.bpm,
      country: country ?? this.country,
    );
  }
}
