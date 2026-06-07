import '../../domain/entities/video.dart';

class TrackModel {
  final String id;
  final String title;
  final String? thumbnailUrl;

  /// Nullable to preserve the C1 honest-nulls invariant —
  /// `null` means "the YouTube API did not return a duration"
  /// (live streams, unlisted videos, etc.), `0` means
  /// "explicitly zero seconds" which is rare but possible.
  /// See [Track.duration] for the entity-side contract.
  final int? durationSeconds;
  final String? author;
  final String? album;
  final String? albumArtist;
  final int? year;
  final int index;
  final TrackSource source;

  TrackModel({
    required this.id,
    required this.title,
    this.thumbnailUrl,
    this.durationSeconds,
    this.author,
    this.album,
    this.albumArtist,
    this.year,
    this.index = 0,
    this.source = TrackSource.youtube,
  });

  factory TrackModel.fromMap(Map<String, dynamic> map) {
    return TrackModel(
      id: map['id'] as String,
      title: map['title'] as String,
      thumbnailUrl: map['thumbnailUrl'] as String?,
      // Preserves `null` from the SQLite row (C1). Legacy rows
      // written before this migration will surface with `0`
      // here — the UI layer treats both `0` and `null` as
      // "unknown" for display (see [formatDuration]).
      durationSeconds: map['durationSeconds'] as int?,
      author: map['author'] as String?,
      album: map['album'] as String?,
      albumArtist: map['albumArtist'] as String?,
      year: map['year'] as int?,
      index: map['idx'] as int? ?? 0,
      source: TrackSource.youtube,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'thumbnailUrl': thumbnailUrl,
      'durationSeconds': durationSeconds,
      'author': author,
      'album': album,
      'albumArtist': albumArtist,
      'year': year,
      'idx': index,
      'source': 'youtube',
    };
  }

  Track toEntity() {
    return Track(
      id: id,
      title: title,
      thumbnailUrl: thumbnailUrl,
      // Preserve the null. `null` (unknown) and `Duration.zero`
      // (explicitly zero) are distinct per the C1 spec.
      duration: durationSeconds == null
          ? null
          : Duration(seconds: durationSeconds!),
      author: author,
      album: album,
      albumArtist: albumArtist,
      year: year,
      index: index,
      source: source,
    );
  }
}
