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
  final Duration duration;
  final String? author;
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

  const Track({
    required this.id,
    required this.title,
    this.thumbnailUrl,
    this.duration = Duration.zero,
    this.author,
    this.album,
    this.albumArtist,
    this.year,
    this.index = 0,
    this.source = TrackSource.youtube,
    this.sources = const [],
    this.activeSource,
    this.genre,
    this.bpm,
  });

  Track copyWith({
    String? id,
    String? title,
    String? thumbnailUrl,
    Duration? duration,
    String? author,
    String? album,
    String? albumArtist,
    int? year,
    int? index,
    TrackSource? source,
    List<SourceRef>? sources,
    SourceRef? activeSource,
    String? genre,
    double? bpm,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      duration: duration ?? this.duration,
      author: author ?? this.author,
      album: album ?? this.album,
      albumArtist: albumArtist ?? this.albumArtist,
      year: year ?? this.year,
      index: index ?? this.index,
      source: source ?? this.source,
      sources: sources ?? this.sources,
      activeSource: activeSource ?? this.activeSource,
      genre: genre ?? this.genre,
      bpm: bpm ?? this.bpm,
    );
  }
}
