import 'video.dart';

class Playlist {
  final String id;
  final String title;
  final String? description;
  final String? thumbnailUrl;
  final String? author;
  final int videoCount;
  final List<Track> tracks;

  Playlist({
    required this.id,
    required this.title,
    this.description,
    this.thumbnailUrl,
    this.author,
    this.videoCount = 0,
    this.tracks = const [],
  });
}
