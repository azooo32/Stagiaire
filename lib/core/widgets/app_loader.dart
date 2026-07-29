import 'dart:math' as math;
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// AppLoader – a reusable, animated gradient arc spinner with the app logo
// ---------------------------------------------------------------------------

/// Full-screen (or centered) loading overlay that uses the logo spinner.
class AppLoader extends StatelessWidget {
  final Color? backgroundColor;

  const AppLoader({super.key, this.backgroundColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor ?? Colors.transparent,
      child: const Center(child: LogoSpinner()),
    );
  }
}

/// A standalone spinning logo widget you can drop anywhere.
/// Uses [TickerProviderStateMixin] internally so no parent vsync needed.
class LogoSpinner extends StatefulWidget {
  final double size;
  final double logoSize;
  final Duration duration;

  const LogoSpinner({
    super.key,
    this.size = 64,
    this.logoSize = 34,
    this.duration = const Duration(milliseconds: 1400),
  });

  @override
  State<LogoSpinner> createState() => _LogoSpinnerState();
}

class _LogoSpinnerState extends State<LogoSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _GradientArcPainter(progress: _ctrl.value),
          child: Center(child: child),
        ),
      ),
      child: Image.asset(
        'assets/app_logo.png',
        width: widget.logoSize,
        height: widget.logoSize,
        fit: BoxFit.contain,
      ),
    );
  }
}

/// A tiny inline spinner (no logo) for button loading states etc.
/// Drop-in replacement for CircularProgressIndicator in tight spaces.
class MiniSpinner extends StatefulWidget {
  final double size;
  final Color color;
  final double strokeWidth;

  const MiniSpinner({
    super.key,
    this.size = 20,
    this.color = Colors.white,
    this.strokeWidth = 2.0,
  });

  @override
  State<MiniSpinner> createState() => _MiniSpinnerState();
}

class _MiniSpinnerState extends State<MiniSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _MiniArcPainter(
            progress: _ctrl.value,
            color: widget.color,
            strokeWidth: widget.strokeWidth,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Painters
// ---------------------------------------------------------------------------

class _GradientArcPainter extends CustomPainter {
  final double progress;

  const _GradientArcPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - 4;

    // Background track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF6B4EFF).withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );

    // Gradient arc
    final rect = Rect.fromCircle(center: center, radius: radius);
    const sweepAngle = math.pi * 1.6; // 288°
    final startAngle = (progress * 2 * math.pi) - (math.pi / 2);

    final gradientPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: sweepAngle,
        colors: const [
          Color(0x006B4EFF),
          Color(0xFF6B4EFF),
          Color(0xFF9B7BFF),
        ],
        stops: const [0.0, 0.7, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(startAngle);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawArc(rect, 0, sweepAngle, false, gradientPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GradientArcPainter old) => old.progress != progress;
}

class _MiniArcPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  const _MiniArcPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - strokeWidth / 2;
    const sweepAngle = math.pi * 1.5;
    final startAngle = (progress * 2 * math.pi) - (math.pi / 2);

    // Track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    // Arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_MiniArcPainter old) =>
      old.progress != progress || old.color != color;
}

