class LyricLine {
  final Duration time;
  final String words;

  LyricLine({
    required this.time,
    required this.words,
  });

  @override
  String toString() => 'LyricLine(time: $time, words: $words)';
}
