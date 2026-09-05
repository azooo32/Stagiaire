import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../domain/entities/slide_workspace_models.dart';

/// Painter for Lecturer Notes with time-synchronized opacity (Notability style).
/// Notes that are in the future relative to current audio playback are dimmed,
/// and become deeply vivid as audio reaches their recorded timestamp.
class PdfLecturerNotesPainter extends CustomPainter {
  final List<SlideStroke> strokes;
  final int? currentAudioMs;
  final String? highlightedStrokeId;
  final double highlightProgress; // 0.0 to 1.0

  PdfLecturerNotesPainter({
    required this.strokes,
    this.currentAudioMs,
    this.highlightedStrokeId,
    this.highlightProgress = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) return;

    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;

      // 1. Calculate opacity based on audio playback time
      double effectiveOpacity = stroke.opacity;

      if (currentAudioMs != null && stroke.audioTimeMs != null) {
        if (stroke.audioTimeMs! > currentAudioMs!) {
          // Future stroke - dim to 18% opacity
          effectiveOpacity = stroke.opacity * 0.18;
        } else {
          // Active stroke - full opacity
          effectiveOpacity = stroke.opacity;
        }
      }

      final strokeColor = Color(stroke.colorValue).withValues(alpha: effectiveOpacity);

      // 2. Render stroke
      final rawPoints = [for (final p in stroke.points) p.offset];
      if (rawPoints.length == 1) {
        final dotPaint = Paint()
          ..color = strokeColor
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;
        canvas.drawCircle(rawPoints.first, stroke.width / 2, dotPaint);
      } else {
        final path = _buildSmoothPath(rawPoints);
        final paint = Paint()
          ..color = strokeColor
          ..strokeWidth = stroke.width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke
          ..isAntiAlias = true;

        canvas.drawPath(path, paint);

        // If this stroke was tapped, render a brief luminous pulse ring around it
        if (highlightedStrokeId == stroke.id && highlightProgress > 0) {
          final highlightAlpha = (1.0 - highlightProgress).clamp(0.0, 1.0);
          final highlightPaint = Paint()
            ..color = const Color(0xFF5B35F5).withValues(alpha: 0.5 * highlightAlpha)
            ..strokeWidth = stroke.width + (8.0 * highlightProgress)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
          canvas.drawPath(path, highlightPaint);
        }
      }
    }
  }

  Path _buildSmoothPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
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
    return path;
  }

  /// Hit testing: Find the nearest stroke to the tapped point within [threshold].
  static SlideStroke? findTappedStroke(
    List<SlideStroke> strokes,
    Offset tapPos, {
    double threshold = 20.0,
  }) {
    SlideStroke? bestStroke;
    double bestDistance = threshold;

    for (final stroke in strokes.reversed) {
      if (stroke.audioTimeMs == null) continue;
      if (stroke.points.isEmpty) continue;

      if (stroke.points.length == 1) {
        final d = (stroke.points.first.offset - tapPos).distance;
        if (d < bestDistance) {
          bestDistance = d;
          bestStroke = stroke;
        }
        continue;
      }

      for (var i = 0; i < stroke.points.length - 1; i++) {
        final a = stroke.points[i].offset;
        final b = stroke.points[i + 1].offset;
        final dist = _distanceToSegment(tapPos, a, b);
        if (dist < bestDistance) {
          bestDistance = dist;
          bestStroke = stroke;
        }
      }
    }

    return bestStroke;
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final l2 = (b - a).distanceSquared;
    if (l2 == 0) return (p - a).distance;

    final t = (((p.dx - a.dx) * (b.dx - a.dx) + (p.dy - a.dy) * (b.dy - a.dy)) / l2)
        .clamp(0.0, 1.0);
    final projection = Offset(a.dx + t * (b.dx - a.dx), a.dy + t * (b.dy - a.dy));
    return (p - projection).distance;
  }

  @override
  bool shouldRepaint(covariant PdfLecturerNotesPainter oldDelegate) {
    return oldDelegate.currentAudioMs != currentAudioMs ||
        oldDelegate.highlightedStrokeId != highlightedStrokeId ||
        oldDelegate.highlightProgress != highlightProgress ||
        oldDelegate.strokes != strokes;
  }
}

/// Active vanishing laser trail data for rendering
class ActiveLaserTrail {
  final List<Offset> points;
  final int startTimeMs;
  final int totalDurationMs; // ~3000ms
  final int pageNumber;

  const ActiveLaserTrail({
    required this.points,
    required this.startTimeMs,
    this.totalDurationMs = 3000,
    this.pageNumber = 1,
  });

  double getOpacity(int nowMs) {
    final elapsed = nowMs - startTimeMs;
    if (elapsed < 0) return 0.0;
    if (elapsed <= 2000) return 1.0; // Stays fully visible for 2 seconds
    if (elapsed >= totalDurationMs) return 0.0; // Fades out completely by 3 seconds
    // Linear fade from 2000ms to 3000ms
    return (1.0 - (elapsed - 2000) / (totalDurationMs - 2000)).clamp(0.0, 1.0);
  }

  bool isExpired(int nowMs) => (nowMs - startTimeMs) >= totalDurationMs;
}

/// Painter for Laser Pointers:
/// 1. Laser Dot (pulsing dot with intense white core and glowing red flare)
/// 2. Vanishing Laser Trail (white core beam + radiant red laser glow, fading after 2-3s)
class PdfLaserPainter extends CustomPainter {
  final Offset? activeLaserDot;
  final double pulsePhase; // 0.0 to 1.0 for pulsation
  final List<ActiveLaserTrail> activeTrails;
  final int currentTimestampMs;
  final List<Offset>? currentDrawingTrail; // Trail being actively drawn right now

  PdfLaserPainter({
    this.activeLaserDot,
    this.pulsePhase = 0.0,
    required this.activeTrails,
    required this.currentTimestampMs,
    this.currentDrawingTrail,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Paint stored fading trails
    for (final trail in activeTrails) {
      final opacity = trail.getOpacity(currentTimestampMs);
      if (opacity <= 0.0 || trail.points.length < 2) continue;
      _paintLaserBeam(canvas, trail.points, opacity);
    }

    // 2. Paint current trail being drawn live
    if (currentDrawingTrail != null && currentDrawingTrail!.length >= 2) {
      _paintLaserBeam(canvas, currentDrawingTrail!, 1.0);
    }

    // 3. Paint Laser Dot (Pointer 1)
    if (activeLaserDot != null) {
      _paintLaserDot(canvas, activeLaserDot!);
    }
  }

  void _paintLaserBeam(Canvas canvas, List<Offset> points, double opacity) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    // Layer 1: Wide radiant neon red flare
    final outerFlare = Paint()
      ..color = const Color(0xFFFF1744).withValues(alpha: 0.38 * opacity)
      ..strokeWidth = 14.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
    canvas.drawPath(path, outerFlare);

    // Layer 2: Focused red laser glow
    final midGlow = Paint()
      ..color = const Color(0xFFFF0055).withValues(alpha: 0.85 * opacity)
      ..strokeWidth = 6.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.drawPath(path, midGlow);

    // Layer 3: Intense white center laser core
    final core = Paint()
      ..color = Colors.white.withValues(alpha: 1.0 * opacity)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, core);
  }

  void _paintLaserDot(Canvas canvas, Offset pos) {
    // Sinusoidal pulse scale 0.85 to 1.15
    final pulseScale = 1.0 + 0.15 * math.sin(pulsePhase * 2 * math.pi);

    // Outer diffuse pulsing aura
    final auraPaint = Paint()
      ..color = const Color(0xFFFF1744).withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
    canvas.drawCircle(pos, 18.0 * pulseScale, auraPaint);

    // Mid neon red laser core
    final laserPaint = Paint()
      ..color = const Color(0xFFFF0055).withValues(alpha: 0.95)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.drawCircle(pos, 7.5, laserPaint);

    // Inner bright white point
    final whitePoint = Paint()..color = Colors.white;
    canvas.drawCircle(pos, 3.5, whitePoint);
  }

  @override
  bool shouldRepaint(covariant PdfLaserPainter oldDelegate) {
    return true; // Continuously repaints for pulsing and fading animations
  }
}
