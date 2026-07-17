import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import '../config/metadata_sync_config.dart';

class GenreProximityGraph {
  static const String _assetPath = 'assets/data/genre_proximity_matrix.json';
  static const double decayFactor = 0.90;

  Map<String, Map<String, double>>? _matrix;

  Future<void> initialize() async {
    if (_matrix != null) return;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final dynamicFile =
          File('${docDir.path}/${MetadataSyncConfig.proximityFilename}');

      String raw;
      if (await dynamicFile.exists()) {
        raw = await dynamicFile.readAsString();
      } else {
        raw = await rootBundle.loadString(_assetPath);
      }

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _matrix = {};
      for (final entry in decoded.entries) {
        final neighborsMap =
            (entry.value as Map<String, dynamic>)['neighbors']
                as Map<String, dynamic>?;
        if (neighborsMap == null) continue;
        _matrix![entry.key] = neighborsMap.map(
          (k, v) => MapEntry(k, (v as num).toDouble()),
        );
      }
    } catch (e, st) {
      _matrix = {};
      print('[GenreProximityGraph] Failed to load matrix: $e\n$st');
    }
  }

  double getTransitiveProximity(String? genreA, String? genreB) {
    if (genreA == null || genreB == null) return 0.0;
    final s = genreA.trim();
    final t = genreB.trim();
    if (s.toLowerCase() == t.toLowerCase()) return 1.0;

    final matrix = _matrix;
    if (matrix == null) return 0.0;
    if (!matrix.containsKey(s) || !matrix.containsKey(t)) return 0.0;

    final direct = matrix[s]?[t];
    if (direct != null) return direct;

    final Map<String, double> maxSimTo = {s: 1.0};
    final Queue<String> queue = Queue()..add(s);
    final Map<String, int> hopsTo = {s: 0};
    double bestTargetSimilarity = 0.0;

    while (queue.isNotEmpty) {
      final curr = queue.removeFirst();
      final currSim = maxSimTo[curr] ?? 0.0;
      final currHops = hopsTo[curr] ?? 0;

      if (curr == t) {
        bestTargetSimilarity =
            math.max(bestTargetSimilarity, currSim);
        continue;
      }

      if (currHops >= 3) continue;

      final neighbors = matrix[curr];
      if (neighbors == null) continue;

      for (final entry in neighbors.entries) {
        final neighbor = entry.key;
        final edgeWeight = entry.value;

        final nextSim = currSim * edgeWeight * decayFactor;
        final nextHops = currHops + 1;

        if (nextSim > (maxSimTo[neighbor] ?? 0.0)) {
          maxSimTo[neighbor] = nextSim;
          hopsTo[neighbor] = nextHops;
          if (!queue.contains(neighbor)) {
            queue.add(neighbor);
          }
        }
      }
    }

    return bestTargetSimilarity;
  }

  void loadMatrixForTesting(Map<String, Map<String, double>> matrix) {
    _matrix = Map<String, Map<String, double>>.from(
      matrix.map(
        (k, v) => MapEntry(k, Map<String, double>.from(v)),
      ),
    );
  }

  Set<String> get knownGenres =>
      _matrix?.keys.toSet() ?? <String>{};

  Map<String, double> neighborsOf(String? genre) {
    if (genre == null) return const <String, double>{};
    final matrix = _matrix;
    if (matrix == null) return const <String, double>{};
    return matrix[genre] ?? const <String, double>{};
  }

  List<MapEntry<String, double>> neighborsByDescendingProximity(
      String? genre) {
    final raw = neighborsOf(genre);
    final entries = raw.entries.toList()
      ..sort((a, b) {
        final byScore = b.value.compareTo(a.value);
        if (byScore != 0) return byScore;
        return a.key.compareTo(b.key);
      });
    return entries;
  }

  Iterable<String> searchBreadth(String? startGenre) sync* {
    if (startGenre == null) return;
    final matrix = _matrix;
    if (matrix == null) return;
    final seedIsKnown = matrix.containsKey(startGenre);
    final seen = <String>{};
    if (seedIsKnown) {
      seen.add(startGenre);
      yield startGenre;
    }
    final queue = <_BfsNode>[
      for (final entry in neighborsByDescendingProximity(startGenre))
        _BfsNode(entry.key, 1, entry.value),
    ];
    while (queue.isNotEmpty) {
      queue.sort((a, b) {
        final byDepth = a.depth.compareTo(b.depth);
        if (byDepth != 0) return byDepth;
        final byProx = b.pathProximity.compareTo(a.pathProximity);
        if (byProx != 0) return byProx;
        return a.genre.compareTo(b.genre);
      });
      final node = queue.removeAt(0);
      if (!seen.add(node.genre)) continue;
      yield node.genre;
      if (node.depth >= 3) continue;
      for (final entry in neighborsByDescendingProximity(node.genre)) {
        if (seen.contains(entry.key)) continue;
        final minProx = entry.value < node.pathProximity
            ? entry.value
            : node.pathProximity;
        queue.add(_BfsNode(entry.key, node.depth + 1, minProx));
      }
    }
  }
}

class _BfsNode {
  final String genre;
  final int depth;
  final double pathProximity;
  const _BfsNode(this.genre, this.depth, this.pathProximity);
}
