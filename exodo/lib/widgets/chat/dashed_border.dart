import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Painter técnico de línea de trazo discontinuo (Norma ISO 128 / UNE 1032)
/// utilizado para demarcar el perímetro interno de la pantalla y el contorno
/// del cajón de escritura en Modo Incógnito.
class DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;
  final double borderRadius;

  const DashedBorderPainter({
    required this.color,
    this.strokeWidth = 2.0,
    this.dashLength = 6.0,
    this.gapLength = 4.0,
    this.borderRadius = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a <= 0 || strokeWidth <= 0 || size.width <= 0 || size.height <= 0) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final half = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      half,
      half,
      math.max(0.0, size.width - strokeWidth),
      math.max(0.0, size.height - strokeWidth),
    );

    final Path path;
    if (borderRadius > 0) {
      final r = math.max(0.0, borderRadius - half);
      path = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)));
    } else {
      path = Path()..addRect(rect);
    }

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashLength, metric.length);
        final extract = metric.extractPath(distance, next);
        canvas.drawPath(extract, paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dashLength != dashLength ||
        oldDelegate.gapLength != gapLength ||
        oldDelegate.borderRadius != borderRadius;
  }
}
