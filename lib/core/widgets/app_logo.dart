import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// INF's two interlocked rings, drawn from the launcher icon's paths (108-unit viewport) with
/// nothing behind them. [height] sets the size; the rings are wider than tall.
class InfLogo extends StatelessWidget {
  const InfLogo({super.key, this.height = 24});

  final double height;

  static const _aspect = _InfLogoPainter.width / _InfLogoPainter.height;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(height * _aspect, height), painter: const _InfLogoPainter());
  }
}

class _InfLogoPainter extends CustomPainter {
  const _InfLogoPainter();

  static const left = 26.5;
  static const top = 35.0;
  static const width = 55.0;
  static const height = 38.0;

  static Path _ring(List<double> p) {
    return Path()
      ..moveTo(p[0], p[1])
      ..arcToPoint(Offset(p[2], p[3]), radius: const Radius.circular(19), largeArc: true)
      ..arcToPoint(Offset(p[4], p[5]), radius: const Radius.circular(8.8))
      ..arcToPoint(Offset(p[6], p[7]), radius: const Radius.circular(11), largeArc: true, clockwise: false)
      ..arcToPoint(Offset(p[0], p[1]), radius: const Radius.circular(21.2), clockwise: false)
      ..close();
  }

  static Paint _fill(Offset from, Offset to, List<Color> colors) => Paint()
    ..isAntiAlias = true
    ..shader = ui.Gradient.linear(from, to, colors, const [0, 0.5, 1]);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / width, size.height / height);
    canvas.translate(-left, -top);
    canvas.drawPath(
      _ring(const [51.399, 72.061, 62.340, 62.799, 55.281, 59.033, 44.340, 64.939]),
      _fill(const Offset(30.5, 39), const Offset(60.5, 69), const [Color(0xFF6E8BFF), Color(0xFF3B5BDB), Color(0xFF2C3FAE)]),
    );
    canvas.drawPath(
      _ring(const [56.601, 35.939, 45.660, 45.201, 52.719, 48.967, 63.660, 43.061]),
      _fill(const Offset(47.5, 39), const Offset(77.5, 69), const [Color(0xFFFFB547), Color(0xFFFF8C00), Color(0xFFF06A00)]),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InfLogoPainter oldDelegate) => false;
}
