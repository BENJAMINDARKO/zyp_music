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
    );
  }
}
