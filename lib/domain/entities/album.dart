import 'video.dart';

class Album {
  final String id;
  final String title;
  final String? artistName;
  final String? year;
  final String? thumbnailUrl;
  final List<Track> tracks;

  const Album({
    required this.id,
    required this.title,
    this.artistName,
    this.year,
    this.thumbnailUrl,
    this.tracks = const [],
  });
}
