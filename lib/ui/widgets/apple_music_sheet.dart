import 'dart:ui';
import 'package:flutter/material.dart';

class AppleMusicSheet extends StatelessWidget {
  final Widget child;
  final String? title;
  final double maxHeightFraction;

  const AppleMusicSheet({
    super.key,
    required this.child,
    this.title,
    this.maxHeightFraction = 0.85,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.of(context).size.height * maxHeightFraction;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 40.0, sigmaY: 40.0),
      child: Material(
        color: Colors.black.withOpacity(0.75),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildGrabber(context),
              if (title != null) ...[
                _buildTitle(context, title!),
                _buildDivider(context),
              ],
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrabber(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.5,
      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
    );
  }
}
