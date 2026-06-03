import '../../domain/entities/video.dart';

class TrackModel {
  final String id;
  final String title;
  final String? thumbnailUrl;
  final int durationSeconds;
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
    this.durationSeconds = 0,
    this.author,
    this.album,
    this.albumArtist,
    this.year,
    this.index = 0,
    this.source = TrackSource.youtube,
  });

  factory TrackModel.fromMap(Map<String, dynamic> map) {
    TrackSource parseSource(String? sourceStr) {
      if (sourceStr == 'tidal') return TrackSource.tidal;
      return TrackSource.youtube;
    }

    return TrackModel(
      id: map['id'] as String,
      title: map['title'] as String,
      thumbnailUrl: map['thumbnailUrl'] as String?,
      durationSeconds: map['durationSeconds'] as int? ?? 0,
      author: map['author'] as String?,
      album: map['album'] as String?,
      albumArtist: map['albumArtist'] as String?,
      year: map['year'] as int?,
      index: map['idx'] as int? ?? 0,
      source: parseSource(map['source'] as String?),
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
      'source': source == TrackSource.tidal ? 'tidal' : 'youtube',
    };
  }

  Track toEntity() {
    return Track(
      id: id,
      title: title,
      thumbnailUrl: thumbnailUrl,
      duration: Duration(seconds: durationSeconds),
      author: author,
      album: album,
      albumArtist: albumArtist,
      year: year,
      index: index,
      source: source,
    );
  }
}
