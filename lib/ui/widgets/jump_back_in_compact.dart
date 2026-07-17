import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/jump_back_in_service.dart';

class JumpBackInCompactGrid extends StatelessWidget {
  final List<JumpBackInRecommendation> items;
  final VoidCallback? onMore;

  const JumpBackInCompactGrid({
    super.key,
    required this.items,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, right: 2, bottom: 10),
          child: Row(
            children: [
              const Text(
                'Jump back in',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.055,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onMore,
                child: Text(
                  'More',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: ZypAuroraColors.cyan,
                  ),
                ),
              ),
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 9,
            crossAxisSpacing: 9,
            childAspectRatio: 2.8,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) => _CompactTile(
            recommendation: items[index],
          ),
        ),
      ],
    );
  }
}

class _CompactTile extends StatelessWidget {
  final JumpBackInRecommendation recommendation;

  const _CompactTile({required this.recommendation});

  @override
  Widget build(BuildContext context) {
    final scorePercent = (recommendation.matchScore * 100).round();

    return GestureDetector(
      onTap: recommendation.onPlay,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.10),
              Colors.white.withOpacity(0.038),
            ],
          ),
        ),
        padding: const EdgeInsets.only(left: 10, right: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recommendation.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.03,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    recommendation.subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withOpacity(0.62),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: ZypAuroraColors.cyan.withOpacity(0.10),
                border: Border.all(
                  color: ZypAuroraColors.cyan.withOpacity(0.14),
                ),
              ),
              child: Text(
                '$scorePercent%',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: ZypAuroraColors.cyan,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
