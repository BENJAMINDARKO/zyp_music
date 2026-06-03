import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Shared blurred-background container used by all MiniPlayer flyout panels.
class MiniplayerFlyoutContainer extends StatelessWidget {
  final String? thumbnailUrl;
  final Widget child;

  const MiniplayerFlyoutContainer({
    super.key,
    required this.thumbnailUrl,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred album art background
          if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty)
            CachedNetworkImage(
              imageUrl: thumbnailUrl!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorWidget: (_, __, ___) => Container(color: const Color(0xFF0D1117)),
            )
          else
            Container(color: const Color(0xFF0D1117)),

          // Dark overlay + blur
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(color: Colors.black.withOpacity(0.7)),
          ),

          // Content
          child,
        ],
      ),
    );
  }
}
