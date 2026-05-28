class Track {
  final String id;
  final String title;
  final String? thumbnailUrl;
  final Duration duration;
  final String? author;
  final int index;

  const Track({
    required this.id,
    required this.title,
    this.thumbnailUrl,
    this.duration = Duration.zero,
    this.author,
    this.index = 0,
  });
}
