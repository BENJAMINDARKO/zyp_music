import '../../domain/entities/playlist.dart';
import 'video_model.dart';

class PlaylistModel {
  final String id;
  final String title;
  final String? description;
  final String? thumbnailUrl;
  final String? author;
  final int videoCount;
  final int createdAt;
  final List<TrackModel> tracks;

  PlaylistModel({
    required this.id,
    required this.title,
    this.description,
    this.thumbnailUrl,
    this.author,
    this.videoCount = 0,
    this.createdAt = 0,
    this.tracks = const [],
  });

  factory PlaylistModel.fromMap(Map<String, dynamic> map) {
    return PlaylistModel(
      id: map['id'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      thumbnailUrl: map['thumbnailUrl'] as String?,
      author: map['author'] as String?,
      videoCount: map['videoCount'] as int? ?? 0,
      createdAt: map['createdAt'] as int? ?? 0,
      tracks: (map['tracks'] as List?)
              ?.map((t) => TrackModel.fromMap(t as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'description': description,
      'thumbnailUrl': thumbnailUrl,
      'author': author,
      'videoCount': videoCount,
      'createdAt': createdAt,
    };
  }

  Playlist toEntity() {
    return Playlist(
      id: id,
      title: title,
      description: description,
      thumbnailUrl: thumbnailUrl,
      author: author,
      videoCount: videoCount,
      tracks: tracks.map((t) => t.toEntity()).toList(),
    );
  }
}
