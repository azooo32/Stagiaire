import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/services/capacitive_stylus_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  StylusCalibrationScreen
//
//  Shows a canvas where the user draws a wavy line with their capacitive
//  stylus. After enough stroke data is collected, the Save button activates.
//  On Save, the service analyses the data and either creates a profile
//  (success) or reports failure. The [onSuccess] callback is fired only
//  when a valid profile has been stored.
// ─────────────────────────────────────────────────────────────────────────────
class StylusCalibrationScreen extends StatefulWidget {
  /// Called when calibration completes successfully and the profile is saved.
  final VoidCallback? onSuccess;

  /// If non-null, we are re-calibrating. The old profile is kept until the
  /// new one succeeds (handled in PenSettingsScreen / caller).
  final bool isRecalibration;

  const StylusCalibrationScreen({
    super.key,
    this.onSuccess,
    this.isRecalibration = false,
  });

  @override
  State<StylusCalibrationScreen> createState() =>
      _StylusCalibrationScreenState();
}

enum _CalibrationPhase {
  drawing, // user is drawing
  analyzing, // save pressed, analyzing
  success, // analysis succeeded
  failure, // analysis failed
}

class _StylusCalibrationScreenState extends State<StylusCalibrationScreen>
    with SingleTickerProviderStateMixin {
  final List<CalibrationSample> _samples = [];
  final List<List<Offset>> _drawnStrokes = [];
  List<Offset> _currentStroke = [];

  _CalibrationPhase _phase = _CalibrationPhase.drawing;

  /// True when the user has drawn enough data for a valid calibration.
  bool _hasValidStroke = false;

  /// Minimum required pointer-move events to consider data sufficient.
  static const int _minMoveEvents = 20;
  int _totalMoveEvents = 0;

  String? _failureMessage;

  late final AnimationController _checkAnimController;
  late final Animation<double> _checkAnim;

  @override
  void initState() {
    super.initState();
    _checkAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _checkAnim = CurvedAnimation(
      parent: _checkAnimController,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _checkAnimController.dispose();
    super.dispose();
  }

  // ── Pointer handling ────────────────────────────────────────────────────────

  void _onPointerDown(PointerDownEvent event) {
    if (_phase != _CalibrationPhase.drawing) return;
    _currentStroke = [event.localPosition];
    _recordSample(event.localPosition, event);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_phase != _CalibrationPhase.drawing) return;
    _currentStroke.add(event.localPosition);

    // Record sample — use localPosition; convert PointerMoveEvent to a sample
    final sample = CalibrationSample(
      size: event.size,
      radiusMajor: event.radiusMajor,
      radiusMinor: event.radiusMinor,
      pressure: event.pressure,
      position: event.localPosition,
      timestamp: event.timeStamp,
    );
    _samples.add(sample);

    if (kDebugMode && _samples.length % 10 == 0) {
      debugPrint(
        '[CapStylus][CAL] sample ${_samples.length}: '
        'kind=${event.kind} size=${event.size.toStringAsFixed(3)} '
        'rMaj=${event.radiusMajor.toStringAsFixed(2)} '
        'rMin=${event.radiusMinor.toStringAsFixed(2)} '
        'pressure=${event.pressure.toStringAsFixed(3)}',
      );
    }

    _totalMoveEvents++;
    setState(() {
      if (!_hasValidStroke && _totalMoveEvents >= _minMoveEvents) {
        _hasValidStroke = true;
        _checkAnimController.forward();
      }
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_phase != _CalibrationPhase.drawing) return;
    if (_currentStroke.length > 1) {
      _drawnStrokes.add(List.from(_currentStroke));
    }
    _currentStroke = [];
    setState(() {});
  }

  void _recordSample(Offset localPos, PointerDownEvent event) {
    final sample = CalibrationSample(
      size: event.size,
      radiusMajor: event.radiusMajor,
      radiusMinor: event.radiusMinor,
      pressure: event.pressure,
      position: localPos,
      timestamp: event.timeStamp,
    );
    _samples.add(sample);
  }

  // ── Save logic ──────────────────────────────────────────────────────────────

  Future<void> _onSave() async {
    setState(() {
      _phase = _CalibrationPhase.analyzing;
    });

    // Small delay so the UI can paint the loading state
    await Future.delayed(const Duration(milliseconds: 300));

    final service = CapacitiveStylusService();
    final result = service.analyzeCalibration(_samples);

    if (!mounted) return;

    if (result.status == CalibrationStatus.success && result.profile != null) {
      await service.enableWithProfile(result.profile!);
      if (!mounted) return;
      setState(() {
        _phase = _CalibrationPhase.success;
      });
      // Auto-return after 1.8 s
      Future.delayed(const Duration(milliseconds: 1800), () {
        if (mounted) {
          widget.onSuccess?.call();
          Navigator.of(context).pop(true);
        }
      });
    } else {
      setState(() {
        _phase = _CalibrationPhase.failure;
        _failureMessage = result.message;
      });
    }
  }

  void _retry() {
    setState(() {
      _samples.clear();
      _drawnStrokes.clear();
      _currentStroke = [];
      _hasValidStroke = false;
      _totalMoveEvents = 0;
      _phase = _CalibrationPhase.drawing;
      _failureMessage = null;
      _checkAnimController.reset();
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF100F1F) : const Color(0xFFF5F5FF),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF18162B) : Colors.white,
        elevation: 0,
        title: Text(
          widget.isRecalibration ? 'Recalibrate Stylus' : 'Calibrate Your Stylus',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w900,
            fontSize: 17,
            color: isDark ? Colors.white : const Color(0xFF1E1E50),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.close_rounded,
              color: isDark ? Colors.white : const Color(0xFF1E1E50)),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: _buildPhaseContent(isDark),
      ),
    );
  }

  Widget _buildPhaseContent(bool isDark) {
    switch (_phase) {
      case _CalibrationPhase.drawing:
        return _buildDrawingUI(isDark);
      case _CalibrationPhase.analyzing:
        return _buildAnalyzingUI(isDark);
      case _CalibrationPhase.success:
        return _buildSuccessUI(isDark);
      case _CalibrationPhase.failure:
        return _buildFailureUI(isDark);
    }
  }

  // ── Drawing phase UI ─────────────────────────────────────────────────────────

  Widget _buildDrawingUI(bool isDark) {
    return Column(
      key: const ValueKey('drawing'),
      children: [
        // Instructions
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF6B4EFF).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.draw_outlined,
                        color: Color(0xFF6B4EFF), size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Please use your stylus to draw a slow wavy line inside the area below.',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          color: isDark ? Colors.white70 : const Color(0xFF1E1E50),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Validation indicator
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: _hasValidStroke
                    ? _buildValidationBadge(true, isDark)
                    : _buildValidationBadge(false, isDark),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),

        // Drawing canvas
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _CalibrationCanvas(
              drawnStrokes: _drawnStrokes,
              currentStroke: _currentStroke,
              isDark: isDark,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
            ),
          ),
        ),

        // Save button
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: AnimatedOpacity(
              opacity: _hasValidStroke ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 300),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _hasValidStroke ? _onSave : null,
                  icon: const Icon(Icons.save_rounded, size: 20),
                  label: const Text(
                    'Save Calibration',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6B4EFF),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        const Color(0xFF6B4EFF).withValues(alpha: 0.4),
                    disabledForegroundColor: Colors.white60,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: _hasValidStroke ? 4 : 0,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildValidationBadge(bool valid, bool isDark) {
    return AnimatedScale(
      key: ValueKey(valid),
      scale: 1.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: valid
              ? const Color(0xFF10B981).withValues(alpha: 0.12)
              : (isDark
                  ? const Color(0xFF2C2848)
                  : const Color(0xFFEEEEFF)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: valid
                ? const Color(0xFF10B981).withValues(alpha: 0.4)
                : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (valid)
              ScaleTransition(
                scale: _checkAnim,
                child: const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF10B981), size: 18),
              )
            else
              Icon(Icons.radio_button_unchecked_rounded,
                  color: isDark ? Colors.white38 : Colors.black26, size: 18),
            const SizedBox(width: 8),
            Text(
              valid ? 'Stroke detected — ready to save!' : 'Draw with your stylus to continue…',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: valid
                    ? const Color(0xFF10B981)
                    : (isDark ? Colors.white54 : Colors.black45),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Analyzing phase UI ───────────────────────────────────────────────────────

  Widget _buildAnalyzingUI(bool isDark) {
    return Center(
      key: const ValueKey('analyzing'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF6B4EFF).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor:
                    AlwaysStoppedAnimation<Color>(Color(0xFF6B4EFF)),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Analyzing stylus data…',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: isDark ? Colors.white : const Color(0xFF1E1E50),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Building your stylus profile',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }

  // ── Success phase UI ─────────────────────────────────────────────────────────

  Widget _buildSuccessUI(bool isDark) {
    return Center(
      key: const ValueKey('success'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF10B981),
              size: 52,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Stylus Calibrated!',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w900,
              fontSize: 20,
              color: isDark ? Colors.white : const Color(0xFF1E1E50),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your stylus profile has been saved.',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Returning to settings…',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  // ── Failure phase UI ─────────────────────────────────────────────────────────

  Widget _buildFailureUI(bool isDark) {
    return Center(
      key: const ValueKey('failure'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
                size: 52,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Calibration Failed',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w900,
                fontSize: 20,
                color: isDark ? Colors.white : const Color(0xFF1E1E50),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _failureMessage ??
                  'Could not build a reliable stylus profile. Please try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                height: 1.6,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text(
                  'Try Again',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6B4EFF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _CalibrationCanvas — the drawing area
// ─────────────────────────────────────────────────────────────────────────────
class _CalibrationCanvas extends StatelessWidget {
  final List<List<Offset>> drawnStrokes;
  final List<Offset> currentStroke;
  final bool isDark;
  final void Function(PointerDownEvent) onPointerDown;
  final void Function(PointerMoveEvent) onPointerMove;
  final void Function(PointerUpEvent) onPointerUp;

  const _CalibrationCanvas({
    required this.drawnStrokes,
    required this.currentStroke,
    required this.isDark,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF211E38) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF6B4EFF).withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6B4EFF).withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Dotted guide
            Positioned.fill(
              child: _WavyGuide(isDark: isDark),
            ),

            // Listener captures ALL touch/stylus input (no filtering here —
            // we want raw data from whatever the user puts on screen)
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: onPointerDown,
                onPointerMove: onPointerMove,
                onPointerUp: onPointerUp,
                child: CustomPaint(
                  painter: _CalibrationPainter(
                    drawnStrokes: drawnStrokes,
                    currentStroke: currentStroke,
                    isDark: isDark,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _CalibrationPainter
// ─────────────────────────────────────────────────────────────────────────────
class _CalibrationPainter extends CustomPainter {
  final List<List<Offset>> drawnStrokes;
  final List<Offset> currentStroke;
  final bool isDark;

  const _CalibrationPainter({
    required this.drawnStrokes,
    required this.currentStroke,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF6B4EFF)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in drawnStrokes) {
      _drawStroke(canvas, stroke, paint);
    }
    if (currentStroke.length > 1) {
      _drawStroke(canvas, currentStroke, paint);
    }
  }

  void _drawStroke(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CalibrationPainter oldDelegate) =>
      oldDelegate.drawnStrokes != drawnStrokes ||
      oldDelegate.currentStroke != currentStroke;
}

// ─────────────────────────────────────────────────────────────────────────────
//  _WavyGuide — decorative guide hint in the canvas background
// ─────────────────────────────────────────────────────────────────────────────
class _WavyGuide extends StatelessWidget {
  final bool isDark;
  const _WavyGuide({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WavyGuidePainter(isDark: isDark),
    );
  }
}

class _WavyGuidePainter extends CustomPainter {
  final bool isDark;
  const _WavyGuidePainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF6B4EFF).withValues(alpha: 0.07)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const amplitude = 28.0;
    const wavelength = 80.0;
    final centerY = size.height / 2;

    final path = Path();
    path.moveTo(32, centerY);

    for (double x = 32; x < size.width - 32; x += 2) {
      final y = centerY +
          amplitude * sinApprox((x - 32) / wavelength * 2 * 3.14159);
      if (x == 32) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);

    // Guide text
    final tp = TextPainter(
      text: TextSpan(
        text: 'Draw a wavy line here',
        style: TextStyle(
          color: const Color(0xFF6B4EFF).withValues(alpha: 0.25),
          fontSize: 13,
          fontFamily: 'Cairo',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
        canvas, Offset((size.width - tp.width) / 2, size.height * 0.15));
  }

  double sinApprox(double x) {
    // Simple sin approximation to avoid dart:math import here
    // uses Taylor series for small values, modulo for larger
    x = x % (2 * 3.14159265);
    if (x > 3.14159265) x -= 2 * 3.14159265;
    return x - (x * x * x) / 6 + (x * x * x * x * x) / 120;
  }

  @override
  bool shouldRepaint(_WavyGuidePainter old) => false;
}
