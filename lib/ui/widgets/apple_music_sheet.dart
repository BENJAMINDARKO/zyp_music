import 'dart:ui';

import 'package:flutter/material.dart';

/// Prism/Aurora themed frosted-glass bottom sheet wrapper.
///
/// Drop-in replacement for the old `AppleMusicSheet` while keeping the same
/// class name so existing Auto DJ picker / context menu calls do not break.
class AppleMusicSheet extends StatelessWidget {
  const AppleMusicSheet({
    super.key,
    required this.child,
    this.title,
    this.maxHeightFraction = 0.85,
  });

  final Widget child;
  final String? title;
  final double maxHeightFraction;

  static const Color _ink = Color(0xFF05040B);
  static const Color _ink2 = Color(0xFF111129);
  static const Color _cyan = Color(0xFF5EEAD4);
  static const Color _violet = Color(0xFF9F7AEA);
  static const Color _pink = Color(0xFFFF5CC8);
  static const Color _peach = Color(0xFFF6B17A);
  static const Color _lime = Color(0xFFE0FD7D);
  static const Color _danger = Color(0xFFFF5B6E);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * maxHeightFraction;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: Colors.white.withOpacity(.15),
                      width: 1,
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(.14),
                        Colors.white.withOpacity(.055),
                        _ink2.withOpacity(.62),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(.42),
                        blurRadius: 70,
                        offset: const Offset(0, 28),
                      ),
                      BoxShadow(
                        color: _cyan.withOpacity(.10),
                        blurRadius: 42,
                        offset: const Offset(-18, -16),
                      ),
                      BoxShadow(
                        color: _pink.withOpacity(.08),
                        blurRadius: 46,
                        offset: const Offset(20, 20),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      const Positioned.fill(child: _PrismSheetAtmosphere()),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 10),
                          _buildGrabber(),
                          if (title != null && title!.trim().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _buildTitle(context, title!),
                            const SizedBox(height: 12),
                            _buildPrismDivider(),
                          ] else ...[
                            const SizedBox(height: 10),
                          ],
                          Flexible(
                            child: DefaultTextStyle(
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Colors.white.withOpacity(.88),
                                      ) ??
                                  TextStyle(
                                    color: Colors.white.withOpacity(.88),
                                    fontSize: 14,
                                  ),
                              child: child,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildGrabber() {
    return Container(
      width: 58,
      height: 6,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(.28),
            _cyan.withOpacity(.70),
            _pink.withOpacity(.55),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: _cyan.withOpacity(.22),
            blurRadius: 16,
          ),
        ],
      ),
    );
  }

  static Widget _buildTitle(BuildContext context, String title) {
    final baseStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: -.35,
              color: Colors.white,
            ) ??
        const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 18,
          letterSpacing: -.35,
          color: Colors.white,
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: ShaderMask(
              shaderCallback: (rect) {
                return const LinearGradient(
                  colors: [_cyan, Colors.white, _pink, _peach],
                ).createShader(rect);
              },
              blendMode: BlendMode.srcIn,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: baseStyle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildPrismDivider() {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            Colors.white.withOpacity(.08),
            _cyan.withOpacity(.22),
            _pink.withOpacity(.18),
            Colors.transparent,
          ],
        ),
      ),
    );
  }

  /// Prism-styled context menu item.
  ///
  /// Keeps the helper name so existing calls like:
  /// `AppleMusicSheet.buildMenuItem(...)` continue to work.
  static Widget buildMenuItem(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback? onTap, {
    String? subtitle,
    Widget? trailing,
    bool destructive = false,
    bool enabled = true,
    Color? iconColor,
    Color? titleColor,
    EdgeInsetsGeometry contentPadding = const EdgeInsets.symmetric(
      horizontal: 14,
      vertical: 8,
    ),
  }) {
    final effectiveIconColor = !enabled
        ? Colors.white.withOpacity(.24)
        : destructive
            ? _danger
            : iconColor ?? _cyan;

    final effectiveTitleColor = !enabled
        ? Colors.white.withOpacity(.30)
        : destructive
            ? _danger
            : titleColor ?? Colors.white.withOpacity(.94);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        splashColor: _cyan.withOpacity(.08),
        highlightColor: Colors.white.withOpacity(.04),
        child: Padding(
          padding: contentPadding,
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(.08)),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: destructive
                        ? [
                            _danger.withOpacity(.16),
                            _danger.withOpacity(.06),
                          ]
                        : [
                            effectiveIconColor.withOpacity(.18),
                            Colors.white.withOpacity(.045),
                          ],
                  ),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: effectiveIconColor,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: effectiveTitleColor,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.15,
                              ) ??
                          TextStyle(
                            color: effectiveTitleColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.15,
                          ),
                    ),
                    if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: enabled
                                      ? Colors.white.withOpacity(.52)
                                      : Colors.white.withOpacity(.24),
                                  height: 1.25,
                                ) ??
                            TextStyle(
                              color: enabled
                                  ? Colors.white.withOpacity(.52)
                                  : Colors.white.withOpacity(.24),
                              fontSize: 12,
                              height: 1.25,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              trailing ??
                  Icon(
                    Icons.chevron_right_rounded,
                    color: enabled
                        ? Colors.white.withOpacity(.34)
                        : Colors.white.withOpacity(.18),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  /// Groups menu items into a rounded Prism glass section.
  ///
  /// Keeps the helper name so existing context menu grouping calls continue
  /// to work.
  static Widget buildSection(
    BuildContext context,
    List<Widget> items, {
    EdgeInsetsGeometry margin = const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 6,
    ),
  }) {
    if (items.isEmpty) return const SizedBox.shrink();

    final separated = <Widget>[];

    for (var i = 0; i < items.length; i++) {
      separated.add(items[i]);
      if (i != items.length - 1) {
        separated.add(
          Padding(
            padding: const EdgeInsets.only(left: 68, right: 12),
            child: Container(
              height: .75,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(.03),
                    Colors.white.withOpacity(.08),
                    _cyan.withOpacity(.10),
                    Colors.white.withOpacity(.03),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(.10)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(.095),
            Colors.white.withOpacity(.035),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.18),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          children: [
            Positioned(
              right: -46,
              bottom: -52,
              child: Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _cyan.withOpacity(.08),
                  boxShadow: [
                    BoxShadow(
                      color: _pink.withOpacity(.08),
                      blurRadius: 30,
                    ),
                  ],
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: separated,
            ),
          ],
        ),
      ),
    );
  }
}

class _PrismSheetAtmosphere extends StatelessWidget {
  const _PrismSheetAtmosphere();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: -90,
            top: -80,
            child: _GlowOrb(color: AppleMusicSheet._pink.withOpacity(.16)),
          ),
          Positioned(
            right: -90,
            top: 18,
            child: _GlowOrb(color: AppleMusicSheet._cyan.withOpacity(.15)),
          ),
          Positioned(
            right: -60,
            bottom: -80,
            child: _GlowOrb(color: AppleMusicSheet._peach.withOpacity(.12)),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _PrismGridPainter(),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      height: 190,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color,
            blurRadius: 60,
            spreadRadius: 12,
          ),
        ],
      ),
    );
  }
}

class _PrismGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(.025)
      ..strokeWidth = 1;

    const step = 42.0;

    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
