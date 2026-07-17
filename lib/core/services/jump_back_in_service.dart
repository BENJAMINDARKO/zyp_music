import 'dart:math';
import 'package:flutter/material.dart';

enum TimeBucket {
  morning,
  afternoon,
  evening,
  night,
  lateNight;

  String get label {
    switch (this) {
      case TimeBucket.morning: return 'Morning';
      case TimeBucket.afternoon: return 'Afternoon';
      case TimeBucket.evening: return 'Evening';
      case TimeBucket.night: return 'Night';
      case TimeBucket.lateNight: return 'Late Night';
    }
  }
}

TimeBucket currentTimeBucket() {
  final h = DateTime.now().hour;
  if (h >= 5 && h <= 11) return TimeBucket.morning;
  if (h <= 16) return TimeBucket.afternoon;
  if (h <= 20) return TimeBucket.evening;
  if (h <= 23) return TimeBucket.night;
  return TimeBucket.lateNight;
}

enum JumpBackInType { track, album, playlist, artist, mood }

class RecommendationReason {
  final String label;
  final String description;
  final double weight;

  const RecommendationReason({
    required this.label,
    required this.description,
    this.weight = 1.0,
  });
}

class JumpBackInRecommendation {
  final String id;
  final JumpBackInType type;
  final String title;
  final String subtitle;
  final ImageProvider? artwork;
  final double matchScore;
  final List<RecommendationReason> reasons;
  final VoidCallback? onPlay;

  const JumpBackInRecommendation({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    this.artwork,
    required this.matchScore,
    required this.reasons,
    this.onPlay,
  });
}

class JumpBackInCandidate {
  final String id;
  final JumpBackInType type;
  final String title;
  final String subtitle;
  final String? genre;
  final String? artist;
  final String? thumbnailUrl;
  final int playCount;
  final bool isFavorite;
  final DateTime? lastPlayed;
  final double? energyLevel;

  const JumpBackInCandidate({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    this.genre,
    this.artist,
    this.thumbnailUrl,
    this.playCount = 0,
    this.isFavorite = false,
    this.lastPlayed,
    this.energyLevel,
  });
}

class JumpBackInEngine {
  static const _genreTimeBuckets = <String, List<TimeBucket>>{
    'Afrobeat': [TimeBucket.afternoon, TimeBucket.evening, TimeBucket.night],
    'Afrobeats': [TimeBucket.afternoon, TimeBucket.evening, TimeBucket.night],
    'Hip Hop': [TimeBucket.afternoon, TimeBucket.evening, TimeBucket.night],
    'Hip-Hop': [TimeBucket.afternoon, TimeBucket.evening, TimeBucket.night],
    'Rap': [TimeBucket.afternoon, TimeBucket.evening, TimeBucket.night],
    'Pop': [TimeBucket.morning, TimeBucket.afternoon, TimeBucket.evening],
    'R&B': [TimeBucket.evening, TimeBucket.night, TimeBucket.lateNight],
    'Gospel': [TimeBucket.morning, TimeBucket.afternoon],
    'Reggae': [TimeBucket.afternoon, TimeBucket.evening],
    'Dancehall': [TimeBucket.evening, TimeBucket.night],
    'Highlife': [TimeBucket.afternoon, TimeBucket.evening],
    'Amapiano': [TimeBucket.evening, TimeBucket.night, TimeBucket.lateNight],
    'Electronic': [TimeBucket.night, TimeBucket.lateNight],
    'Rock': [TimeBucket.afternoon, TimeBucket.evening],
    'Jazz': [TimeBucket.evening, TimeBucket.night],
    'Classical': [TimeBucket.morning, TimeBucket.evening],
    'Soul': [TimeBucket.evening, TimeBucket.night],
    'Folk': [TimeBucket.morning, TimeBucket.afternoon],
    'Country': [TimeBucket.afternoon, TimeBucket.evening],
    'Alternative': [TimeBucket.afternoon, TimeBucket.evening, TimeBucket.night],
    'Indie': [TimeBucket.afternoon, TimeBucket.evening],
    'Drill': [TimeBucket.night, TimeBucket.lateNight],
  };

  static const _energyByGenre = <String, double>{
    'Afrobeat': 0.7, 'Afrobeats': 0.75, 'Hip Hop': 0.7, 'Rap': 0.75,
    'Pop': 0.6, 'R&B': 0.45, 'Gospel': 0.5, 'Reggae': 0.4,
    'Dancehall': 0.7, 'Highlife': 0.55, 'Amapiano': 0.65,
    'Electronic': 0.8, 'Rock': 0.75, 'Jazz': 0.3, 'Classical': 0.2,
    'Soul': 0.4, 'Folk': 0.35, 'Country': 0.4, 'Alternative': 0.55,
    'Indie': 0.5, 'Drill': 0.85, 'Unknown': 0.5,
  };

  static const _timeEnergyMap = {
    TimeBucket.morning: 0.35,
    TimeBucket.afternoon: 0.65,
    TimeBucket.evening: 0.55,
    TimeBucket.night: 0.45,
    TimeBucket.lateNight: 0.3,
  };

  static double _normalize(int value, int max) =>
      max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0;

  static double _genreTimeFit(String? genre) {
    if (genre == null) return 0.5;
    final gl = genre.toLowerCase();
    final bucketed = _genreTimeBuckets.entries
        .where((e) => gl.contains(e.key.toLowerCase()))
        .expand((e) => e.value)
        .toSet();
    if (bucketed.isEmpty) return 0.5;
    return bucketed.contains(currentTimeBucket()) ? 1.0 : 0.3;
  }

  static double _genreMoodFit(String? genre) {
    if (genre == null) return 0.5;
    final gl = genre.toLowerCase();
    final energy = _energyByGenre.entries
        .where((e) => gl.contains(e.key.toLowerCase()))
        .map((e) => e.value)
        .firstOrNull ?? 0.5;
    final target = _timeEnergyMap[currentTimeBucket()] ?? 0.5;
    return 1.0 - (energy - target).abs();
  }

  static List<JumpBackInRecommendation> score({
    required List<JumpBackInCandidate> candidates,
    String? currentGenre,
    int maxResults = 20,
  }) {
    final now = DateTime.now();
    final scored = <_Scored>[];

    for (final c in candidates) {
      final hoursSincePlayed = c.lastPlayed != null
          ? now.difference(c.lastPlayed!).inHours
          : 8760;

      final recentness = c.lastPlayed != null
          ? max(0.0, 1.0 - (hoursSincePlayed / 168))
          : 0.0;

      final replayBoost = _normalize(c.playCount, 50);
      final favoriteBoost = c.isFavorite ? 0.20 : 0.0;

      final affinity = (replayBoost * 0.35 +
              recentness * 0.30 +
              favoriteBoost +
              (replayBoost * 0.15))
          .clamp(0.0, 1.0);

      final freshness = c.lastPlayed != null
          ? (hoursSincePlayed / 24).clamp(0.0, 1.0)
          : 0.8;

      final timeFit = _genreTimeFit(c.genre);
      final moodFit = _genreMoodFit(c.genre);

      final cg = c.genre;
      final sameGenre = currentGenre != null &&
          cg != null &&
          cg.toLowerCase().contains(currentGenre.toLowerCase());
      final sessionFit = sameGenre ? 0.8 : 0.3;

      final score = (affinity * 0.35 +
              timeFit * 0.25 +
              moodFit * 0.20 +
              sessionFit * 0.15 +
              freshness * 0.05)
          .clamp(0.0, 1.0);

      final reasons = <RecommendationReason>[
        if (c.lastPlayed != null && hoursSincePlayed < 24)
          const RecommendationReason(
            label: 'Recently played',
            description: 'Picked up where you left off',
            weight: 0.9,
          )
        else if (timeFit > 0.7)
          RecommendationReason(
            label: 'Time match — ${currentTimeBucket().label}',
            description: 'Perfect for right now',
            weight: 0.85,
          ),
        if (c.isFavorite)
          const RecommendationReason(
            label: 'Favorite',
            description: 'One of your saved tracks',
            weight: 0.8,
          ),
        if (c.playCount >= 3)
          RecommendationReason(
            label: '${c.playCount} plays',
            description: 'You keep coming back to this',
            weight: 0.75,
          ),
        if (c.genre != null && c.genre != 'Unknown')
          RecommendationReason(
            label: c.genre!,
            description: 'Matches your ${c.genre!.toLowerCase()} mood',
            weight: 0.7,
          ),
        if (c.lastPlayed != null && hoursSincePlayed >= 72)
          const RecommendationReason(
            label: 'Rediscover',
            description: "You haven't listened in a while",
            weight: 0.6,
          ),
        if (replayBoost > 0.5)
          RecommendationReason(
            label: 'Replay favorite',
            description: 'You replay this often',
            weight: 0.65,
          ),
      ];
      if (reasons.isEmpty) {
        reasons.add(const RecommendationReason(
          label: 'Recommended for you',
          description: 'Based on your listening history',
          weight: 0.5,
        ));
      }

      scored.add(_Scored(c, score, reasons));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));

    return scored.take(maxResults).map((s) => JumpBackInRecommendation(
      id: s.candidate.id,
      type: s.candidate.type,
      title: s.candidate.title,
      subtitle: s.candidate.subtitle,
      artwork: s.candidate.thumbnailUrl != null
          ? NetworkImage(s.candidate.thumbnailUrl!)
          : null,
      matchScore: s.score,
      reasons: s.reasons,
    )).toList();
  }
}

class _Scored {
  final JumpBackInCandidate candidate;
  final double score;
  final List<RecommendationReason> reasons;
  _Scored(this.candidate, this.score, this.reasons);
}
