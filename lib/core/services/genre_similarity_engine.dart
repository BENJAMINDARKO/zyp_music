import 'genre_proximity_graph.dart';

class GenreSimilarityEngine {
  final GenreProximityGraph _graph;

  GenreSimilarityEngine(this._graph);

  int get loadedKeyCount => _graph.knownGenres.length;

  double score(List<String> setA, List<String> setB) {
    if (setA.isEmpty || setB.isEmpty) return 0.0;

    double maxScore = 0.0;
    for (final a in setA) {
      for (final b in setB) {
        final s = _graph.getTransitiveProximity(a, b);
        if (s > maxScore) maxScore = s;
        if (maxScore >= 1.0) return 1.0;
      }
    }
    return maxScore;
  }
}
