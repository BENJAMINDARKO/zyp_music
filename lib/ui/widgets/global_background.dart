import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../presentation/providers/player_provider.dart';
import "../../core/utils/thumbnail_url.dart";

class GlobalBackground extends StatelessWidget {
  const GlobalBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, player, child) {
        final track = player.currentTrack;
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final baseColor = isDarkMode ? const Color(0xFF0A0A0A) : Colors.white;

        if (track == null || track.thumbnailUrl == null) {
          return Container(color: baseColor);
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            Container(color: baseColor), // Base fallback
            CachedNetworkImage(
              imageUrl: rewriteThumbnailSize(track.thumbnailUrl, 1200),
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(color: baseColor),
            ),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(color: Colors.black.withOpacity(0.75)), // PlayingScreen's darkness
            ),
          ],
        );
      },
    );
  }
}
