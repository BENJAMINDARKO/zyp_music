import 'package:flutter/material.dart';

const _cols = 12;
const _rows = 10;

const _pixels = [
  [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
  [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0],
  [1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1],
  [1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1],
  [1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1],
  [1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1],
  [1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1],
  [1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1],
  [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0],
  [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
];

const _roundedCorners = [
  [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
  [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0],
  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
  [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0],
  [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
];

class PixelLogo extends StatelessWidget {
  final double size;

  const PixelLogo({super.key, this.size = 80});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pixelSize = size / _cols;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PixelLogoPainter(
          theme.colorScheme.primary,
          theme.colorScheme.onPrimary,
          pixelSize,
        ),
      ),
    );
  }
}

class _PixelLogoPainter extends CustomPainter {
  final Color bgColor;
  final Color playColor;
  final double pixelSize;

  _PixelLogoPainter(this.bgColor, this.playColor, this.pixelSize);

  static const _cornerColor = Color(0xFF212121);

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final bgPaint = Paint()..color = bgColor;
    final playPaint = Paint()..color = playColor;
    final cornerPaint = Paint()..color = _cornerColor;

    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final x = c * pixelSize;
        final y = r * pixelSize;
        final rect = Rect.fromLTWH(x, y, pixelSize, pixelSize);

        if (_roundedCorners[r][c] == 0) {
          canvas.drawRect(rect, cornerPaint);
        } else if (_pixels[r][c] == 1) {
          canvas.drawRect(rect, bgPaint);
        } else {
          canvas.drawRect(rect, playPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelLogoPainter oldDelegate) =>
      oldDelegate.bgColor != bgColor ||
      oldDelegate.playColor != playColor ||
      oldDelegate.pixelSize != pixelSize;
}

class LogoWithHeadset extends StatelessWidget {
  final double size;

  const LogoWithHeadset({super.key, this.size = 100});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        PixelLogo(size: size),
        Positioned(
          right: size * 0.05,
          bottom: size * 0.05,
          child: Container(
            padding: EdgeInsets.all(size * 0.08),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.headset,
              color: theme.colorScheme.primary,
              size: size * 0.28,
            ),
          ),
        ),
      ],
    );
  }
}
