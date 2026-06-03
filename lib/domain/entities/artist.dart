import 'video.dart';
import 'album.dart';

class Artist {
  final String id;
  final String name;
  final String? thumbnailUrl;
  final List<Track> topTracks;
  final List<Album> albums;

  const Artist({
    required this.id,
    required this.name,
    this.thumbnailUrl,
    this.topTracks = const [],
    this.albums = const [],
  });
}
