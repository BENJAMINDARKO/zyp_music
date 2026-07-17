import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/jump_back_in_service.dart';

class JumpBackInSheet extends StatelessWidget {
  final List<JumpBackInRecommendation> recommendations;
  final VoidCallback? onRefresh;
  final bool isRefreshing;

  const JumpBackInSheet({
    super.key,
    required this.recommendations,
    this.onRefresh,
    this.isRefreshing = false,
  });

  static Future<void> show(BuildContext context, {
    required List<JumpBackInRecommendation> recommendations,
    VoidCallback? onRefresh,
    bool isRefreshing = false,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (_) => JumpBackInSheet(
        recommendations: recommendations,
        onRefresh: onRefresh,
        isRefreshing: isRefreshing,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.86,
      ),
      margin: EdgeInsets.only(
        left: 10,
        right: 10,
        bottom: 10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.14),
            Colors.white.withOpacity(0.045),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 60,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 58,
                    height: 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: Colors.white.withOpacity(0.28),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Smart Jump Back In',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.07,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Expanded explanation and recommendation feed powered by your listening stats.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.62),
                  ),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: recommendations.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      if (index < recommendations.length) {
                        return _ExpandedCard(
                          recommendation: recommendations[index],
                        );
                      }
                      return _HowItWorksCard(
                        onRefresh: onRefresh,
                        isRefreshing: isRefreshing,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpandedCard extends StatelessWidget {
  final JumpBackInRecommendation recommendation;

  const _ExpandedCard({required this.recommendation});

  @override
  Widget build(BuildContext context) {
    final scorePercent = (recommendation.matchScore * 100).round();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white.withOpacity(0.06),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (recommendation.artwork != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image(
                    image: recommendation.artwork!,
                    width: 46,
                    height: 46,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          colors: [ZypAuroraColors.violet, ZypAuroraColors.cyan],
                        ),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [ZypAuroraColors.violet, ZypAuroraColors.cyan],
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recommendation.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      recommendation.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.62),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: ZypAuroraColors.cyan.withOpacity(0.14)),
                  color: ZypAuroraColors.cyan.withOpacity(0.10),
                ),
                child: Text(
                  '$scorePercent%',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: ZypAuroraColors.cyan,
                  ),
                ),
              ),
            ],
          ),
          if (recommendation.reasons.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: recommendation.reasons.map((r) {
                final reasonScore = (r.weight * 100).round();
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: Colors.white.withOpacity(0.06),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Text(
                    '${r.label} — $reasonScore%',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.white.withOpacity(0.74),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            const Row(
              children: [
                Text(
                  'Match',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.white54,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: _ScoreBar(value: 1.0),
                ),
                SizedBox(width: 8),
                Text(
                  'Score',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Text(
                  'Match',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.white54,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ScoreBar(value: recommendation.matchScore),
                ),
                const SizedBox(width: 8),
                Text(
                  '$scorePercent%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  final double value;

  const _ScoreBar({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 8,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withOpacity(0.1),
      ),
      clipBehavior: Clip.hardEdge,
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [ZypAuroraColors.cyan, ZypAuroraColors.pink, ZypAuroraColors.peach],
            ),
          ),
        ),
      ),
    );
  }
}

class _HowItWorksCard extends StatelessWidget {
  final VoidCallback? onRefresh;
  final bool isRefreshing;

  const _HowItWorksCard({this.onRefresh, this.isRefreshing = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white.withOpacity(0.06),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'How this works',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              if (onRefresh != null)
                GestureDetector(
                  onTap: isRefreshing ? null : onRefresh,
                  child: isRefreshing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ZypAuroraColors.cyan,
                          ),
                        )
                      : const Icon(
                          Icons.refresh_rounded,
                          size: 18,
                          color: ZypAuroraColors.cyan,
                        ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'ZYP uses time of day, recent plays, replay count, completion rate, '
            'skips, genres, and mood tags to recommend what you should play right now.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.62),
              height: 1.42,
            ),
          ),
        ],
      ),
    );
  }
}
