import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/slide_workspace_models.dart';

class DrawingLayerPainter extends CustomPainter {
  final List<WorkspaceObject> strokes;
  final ValueListenable<SlideStroke?>? activeStroke;

  DrawingLayerPainter({
    required this.strokes,
    required this.activeStroke,
  }) : super(repaint: activeStroke);

  @override
  void paint(Canvas canvas, Size size) {
    for (final obj in [
      ...strokes,
      if (activeStroke?.value != null) activeStroke!.value!
    ]) {
      if (obj is SlideStroke && obj.tool != WorkspaceTool.eraser) {
        _paintStroke(
          canvas,
          obj,
          predict: strokes.isEmpty && activeStroke != null,
        );
      }
    }
  }

  void _paintStroke(Canvas canvas, SlideStroke stroke, {bool predict = false}) {
    final rawPoints = [for (final p in stroke.points) p.offset];
    if (predict) _appendPredictedTail(rawPoints);

    if (rawPoints.isEmpty) return;

    // A single tap (or a very deliberate dot from a pencil) still needs
    // to show something instead of silently vanishing.
    if (rawPoints.length == 1) {
      final dot = Paint()
        ..color = stroke.color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true
        ..blendMode = BlendMode.srcOver;
      canvas.drawCircle(rawPoints.first, stroke.width / 2, dot);
      return;
    }

    final points = _smoothed(rawPoints);

    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..blendMode = BlendMode.srcOver;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    // Catmull-Rom knots converted to cubic Bezier segments. This produces
    // a C1-continuous handwritten curve without delaying the Pencil tip.
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i == 0 ? 0 : i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = points[i + 2 < points.length ? i + 2 : i + 1];
      final control1 = p1 + (p2 - p0) / 6;
      final control2 = p2 - (p3 - p1) / 6;
      path.cubicTo(
        control1.dx,
        control1.dy,
        control2.dx,
        control2.dy,
        p2.dx,
        p2.dy,
      );
    }

    canvas.drawPath(path, paint);
  }

  /// PencilKit-style visual prediction. The projected point is used only by
  /// the live layer and is never persisted, so the final vector remains exact.
  void _appendPredictedTail(List<Offset> points) {
    if (points.length < 2) return;
    final previous = points[points.length - 2];
    final latest = points.last;
    final velocity = latest - previous;
    final distance = velocity.distance;
    if (distance < .25) return;
    // One ProMotion frame ahead (8.3ms) with a conservative distance cap.
    final predictedDistance = (distance * .55).clamp(.4, 12.0);
    points.add(latest + velocity / distance * predictedDistance);
  }

  /// Weighted moving-average pass that softens jitter from finger/touch
  /// input (which is noisier than a stylus) without adding lag: each
  /// point pulls slightly toward its neighbors while the very first and
  /// last points are left untouched, so the stroke still starts and ends
  /// exactly under the pointer.
  List<Offset> _smoothed(List<Offset> points) {
    if (points.length < 3) return points;
    final result = List<Offset>.filled(points.length, Offset.zero);
    result[0] = points.first;
    result[points.length - 1] = points.last;
    for (var i = 1; i < points.length - 1; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final next = points[i + 1];
      result[i] = Offset(
        (prev.dx + curr.dx * 2 + next.dx) / 4,
        (prev.dy + curr.dy * 2 + next.dy) / 4,
      );
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant DrawingLayerPainter oldDelegate) =>
      oldDelegate.strokes != strokes ||
      oldDelegate.activeStroke != activeStroke;
}

class SpineDiagramPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width * .58;
    final top = size.height * .08;
    final segmentHeight = size.height * .065;
    final colors = [
      const Color(0xFFC7A47A),
      const Color(0xFF7EB6C9),
      const Color(0xFF7EA960),
      const Color(0xFF9E71AA),
      const Color(0xFFD0963A),
    ];

    for (var i = 0; i < 22; i++) {
      final y = top + i * segmentHeight;
      final group = i < 7
          ? 0
          : i < 13
              ? 1
              : i < 18
                  ? 2
                  : i < 21
                      ? 3
                      : 4;
      final offset = 34 * _curve(i / 21);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(centerX + offset, y),
            width: 50 - group * 3,
            height: 22),
        const Radius.circular(12),
      );
      final paint = Paint()
        ..color = colors[group]
        ..style = PaintingStyle.fill;
      final border = Paint()
        ..color = const Color(0xFF252044).withValues(alpha: .55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      canvas.drawRRect(rect, paint);
      canvas.drawRRect(rect, border);
      canvas.drawCircle(Offset(centerX + offset - 27, y), 5, paint);
      canvas.drawCircle(Offset(centerX + offset + 27, y), 5, paint);
    }

    _label(canvas, size, 'Cervical\n(7 vertebrae)', .06, .19, centerX - 62,
        top + segmentHeight * 3);
    _label(canvas, size, 'Thoracic\n(12 vertebrae)', .06, .43, centerX - 58,
        top + segmentHeight * 10);
    _label(canvas, size, 'Lumbar\n(5 vertebrae)', .06, .66, centerX - 40,
        top + segmentHeight * 16);
    _label(canvas, size, 'Sacrum\n(5 fused vertebrae)', .06, .81, centerX - 20,
        top + segmentHeight * 19);
    _label(canvas, size, 'Coccyx\n(4 fused vertebrae)', .06, .93, centerX + 5,
        top + segmentHeight * 21);
  }

  double _curve(double t) => (t - .28) * (t - .28) * 1.8 - .18;

  void _label(Canvas canvas, Size size, String text, double x, double y,
      double lineEndX, double lineEndY) {
    final line = Paint()
      ..color = const Color(0xFF171345).withValues(alpha: .5)
      ..strokeWidth = 1.2;
    final start = Offset(size.width * (x + .28), size.height * y);
    canvas.drawLine(start, Offset(lineEndX, lineEndY), line);

    final span = TextSpan(
      text: text,
      style: const TextStyle(
        color: Color(0xFF171345),
        fontSize: 13,
        height: 1.35,
        fontWeight: FontWeight.w700,
      ),
    );
    final painter = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center)
      ..layout(maxWidth: 120);
    painter.paint(canvas, Offset(size.width * x, size.height * y - 18));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
