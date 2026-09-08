import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  StylusMetricStats — captures mean + std-dev for a single touch metric.
// ─────────────────────────────────────────────────────────────────────────────
class StylusMetricStats {
  final double mean;
  final double stdDev;
  final bool available; // false when device never reported non-zero values

  const StylusMetricStats({
    required this.mean,
    required this.stdDev,
    required this.available,
  });

  factory StylusMetricStats.fromJson(Map<String, dynamic> json) {
    return StylusMetricStats(
      mean: (json['mean'] as num).toDouble(),
      stdDev: (json['stdDev'] as num).toDouble(),
      available: json['available'] as bool,
    );
  }

  Map<String, dynamic> toJson() => {
        'mean': mean,
        'stdDev': stdDev,
        'available': available,
      };

  /// Returns a similarity contribution in [0, 1] for the given value.
  /// If stdDev is near-zero or metric is not available, returns 1.0 (neutral).
  double similarity(double value) {
    if (!available || stdDev < 0.0001) return 1.0;
    final z = (value - mean).abs() / stdDev;
    // Gaussian-like decay: z=0 → 1.0, z=2 → ~0.14
    return math.exp(-0.5 * z * z);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  StylusProfile — the learned fingerprint of the user's capacitive stylus.
// ─────────────────────────────────────────────────────────────────────────────
class StylusProfile {
  final StylusMetricStats size;
  final StylusMetricStats radiusMajor;
  final StylusMetricStats radiusMinor;
  final StylusMetricStats pressure;

  /// Minimum weighted similarity score to accept a touch as "stylus".
  /// Computed from the calibration spread — tighter data → higher threshold.
  final double classificationThreshold;

  /// How many metrics the device actually reported useful data for.
  final int availableMetrics;

  /// Confidence level of this profile (0.0–1.0).
  /// Low confidence = device provides poor discriminability.
  final double profileConfidence;

  const StylusProfile({
    required this.size,
    required this.radiusMajor,
    required this.radiusMinor,
    required this.pressure,
    required this.classificationThreshold,
    required this.availableMetrics,
    required this.profileConfidence,
  });

  factory StylusProfile.fromJson(Map<String, dynamic> json) {
    return StylusProfile(
      size: StylusMetricStats.fromJson(json['size'] as Map<String, dynamic>),
      radiusMajor: StylusMetricStats.fromJson(
          json['radiusMajor'] as Map<String, dynamic>),
      radiusMinor: StylusMetricStats.fromJson(
          json['radiusMinor'] as Map<String, dynamic>),
      pressure:
          StylusMetricStats.fromJson(json['pressure'] as Map<String, dynamic>),
      classificationThreshold:
          (json['classificationThreshold'] as num).toDouble(),
      availableMetrics: json['availableMetrics'] as int,
      profileConfidence: (json['profileConfidence'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'size': size.toJson(),
        'radiusMajor': radiusMajor.toJson(),
        'radiusMinor': radiusMinor.toJson(),
        'pressure': pressure.toJson(),
        'classificationThreshold': classificationThreshold,
        'availableMetrics': availableMetrics,
        'profileConfidence': profileConfidence,
      };

  /// Returns a similarity score in [0, 1] for the given touch event metrics.
  double computeSimilarity({
    required double size,
    required double radiusMajor,
    required double radiusMinor,
    required double pressure,
  }) {
    final scores = <double>[];
    if (this.size.available) scores.add(this.size.similarity(size));
    if (this.radiusMajor.available) {
      scores.add(this.radiusMajor.similarity(radiusMajor));
    }
    if (this.radiusMinor.available) {
      scores.add(this.radiusMinor.similarity(radiusMinor));
    }
    if (this.pressure.available) scores.add(this.pressure.similarity(pressure));
    if (scores.isEmpty) return 0.5; // no discriminating metrics at all
    return scores.reduce((a, b) => a + b) / scores.length;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CalibrationSample — one touch point recorded during calibration.
// ─────────────────────────────────────────────────────────────────────────────
class CalibrationSample {
  final double size;
  final double radiusMajor;
  final double radiusMinor;
  final double pressure;
  final Offset position;
  final Duration timestamp;

  const CalibrationSample({
    required this.size,
    required this.radiusMajor,
    required this.radiusMinor,
    required this.pressure,
    required this.position,
    required this.timestamp,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  CalibrationResult — outcome returned by analyzeCalibration().
// ─────────────────────────────────────────────────────────────────────────────
enum CalibrationStatus { success, insufficientData, lowConfidence }

class CalibrationResult {
  final CalibrationStatus status;
  final StylusProfile? profile;
  final String? message;

  const CalibrationResult({
    required this.status,
    this.profile,
    this.message,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  CapacitiveStylusService — singleton, global entry point.
// ─────────────────────────────────────────────────────────────────────────────
class CapacitiveStylusService extends ChangeNotifier {
  static final CapacitiveStylusService _instance =
      CapacitiveStylusService._();
  factory CapacitiveStylusService() => _instance;
  CapacitiveStylusService._();

  static const String _keyEnabled = 'capacitive_stylus_enabled';
  static const String _keyCalibrated = 'capacitive_stylus_calibrated';
  static const String _keyProfile = 'capacitive_stylus_profile';

  bool _enabled = false;
  bool _calibrated = false;
  StylusProfile? _profile;
  bool _loaded = false;

  // ── Public getters ──────────────────────────────────────────────────────────
  bool get isEnabled => _enabled;
  bool get isCalibrated => _calibrated;
  StylusProfile? get profile => _profile;
  bool get isReady => _enabled && _calibrated && _profile != null;

  // ── Initialisation ──────────────────────────────────────────────────────────

  /// Must be called once at app startup (e.g. in initState of root widget).
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_keyEnabled) ?? false;
    _calibrated = prefs.getBool(_keyCalibrated) ?? false;
    final profileJson = prefs.getString(_keyProfile);
    if (profileJson != null) {
      try {
        _profile = StylusProfile.fromJson(
            json.decode(profileJson) as Map<String, dynamic>);
      } catch (_) {
        _profile = null;
        _calibrated = false;
      }
    }
    notifyListeners();
  }

  // ── Enable / Disable ────────────────────────────────────────────────────────

  /// Called by the calibration screen after a successful calibration.
  Future<void> enableWithProfile(StylusProfile newProfile) async {
    _profile = newProfile;
    _enabled = true;
    _calibrated = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, true);
    await prefs.setBool(_keyCalibrated, true);
    await prefs.setString(_keyProfile, json.encode(newProfile.toJson()));
    notifyListeners();
  }

  /// Called when the user turns OFF the toggle in Pen Settings.
  /// Wipes everything and reverts to default behaviour.
  Future<void> disable() async {
    _enabled = false;
    _calibrated = false;
    _profile = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, false);
    await prefs.setBool(_keyCalibrated, false);
    await prefs.remove(_keyProfile);
    notifyListeners();
  }

  // ── Classification ──────────────────────────────────────────────────────────

  /// Returns true if [event] should be treated as a capacitive stylus stroke.
  /// Only meaningful when [isReady] is true.
  bool classifyTouchAsStylus(PointerDownEvent event) {
    if (!isReady) return false;
    if (event.kind != PointerDeviceKind.touch) return false;
    final p = _profile!;
    final similarity = p.computeSimilarity(
      size: event.size,
      radiusMajor: event.radiusMajor,
      radiusMinor: event.radiusMinor,
      pressure: event.pressure,
    );
    // Debug log — only in debug builds
    if (kDebugMode) {
      debugPrint(
        '[CapStylus] touch classify: size=${event.size.toStringAsFixed(3)} '
        'rMaj=${event.radiusMajor.toStringAsFixed(2)} '
        'rMin=${event.radiusMinor.toStringAsFixed(2)} '
        'pressure=${event.pressure.toStringAsFixed(3)} '
        '→ similarity=${(similarity * 100).toStringAsFixed(1)}% '
        '(threshold=${(p.classificationThreshold * 100).toStringAsFixed(1)}%)',
      );
    }
    return similarity >= p.classificationThreshold;
  }

  // ── Calibration Analysis ────────────────────────────────────────────────────

  /// Analyses collected [samples] and builds a [StylusProfile].
  /// Returns a [CalibrationResult] describing success or failure.
  CalibrationResult analyzeCalibration(List<CalibrationSample> samples) {
    if (samples.length < 10) {
      return const CalibrationResult(
        status: CalibrationStatus.insufficientData,
        message: 'Not enough stroke data. Please draw a longer line.',
      );
    }

    final sizes = samples.map((s) => s.size).toList();
    final radMaj = samples.map((s) => s.radiusMajor).toList();
    final radMin = samples.map((s) => s.radiusMinor).toList();
    final pressures = samples.map((s) => s.pressure).toList();

    final sizeStats = _computeStats(sizes);
    final radMajStats = _computeStats(radMaj);
    final radMinStats = _computeStats(radMin);
    final pressureStats = _computeStats(pressures);

    int availableMetrics = 0;
    if (sizeStats.available) availableMetrics++;
    if (radMajStats.available) availableMetrics++;
    if (radMinStats.available) availableMetrics++;
    if (pressureStats.available) availableMetrics++;

    if (kDebugMode) {
      debugPrint('[CapStylus] Calibration analysis:');
      debugPrint('  samples: ${samples.length}');
      debugPrint(
          '  size: mean=${sizeStats.mean.toStringAsFixed(4)} std=${sizeStats.stdDev.toStringAsFixed(4)} avail=${sizeStats.available}');
      debugPrint(
          '  rMaj: mean=${radMajStats.mean.toStringAsFixed(2)} std=${radMajStats.stdDev.toStringAsFixed(2)} avail=${radMajStats.available}');
      debugPrint(
          '  rMin: mean=${radMinStats.mean.toStringAsFixed(2)} std=${radMinStats.stdDev.toStringAsFixed(2)} avail=${radMinStats.available}');
      debugPrint(
          '  pressure: mean=${pressureStats.mean.toStringAsFixed(4)} std=${pressureStats.stdDev.toStringAsFixed(4)} avail=${pressureStats.available}');
      debugPrint('  availableMetrics: $availableMetrics');
    }

    // Compute profile confidence based on:
    //   (1) How many metrics are available
    //   (2) Coefficient of variation (low CV = consistent stylus = reliable)
    final double profileConfidence = _computeProfileConfidence(
      sizeStats: sizeStats,
      radMajStats: radMajStats,
      radMinStats: radMinStats,
      pressureStats: pressureStats,
      availableMetrics: availableMetrics,
      sampleCount: samples.length,
    );

    if (kDebugMode) {
      debugPrint(
          '  profileConfidence: ${(profileConfidence * 100).toStringAsFixed(1)}%');
    }

    if (profileConfidence < 0.2) {
      return const CalibrationResult(
        status: CalibrationStatus.lowConfidence,
        message:
            'Your device does not provide enough touch data to reliably distinguish the stylus. '
            'Try drawing more slowly or use a different capacitive stylus.',
      );
    }

    // Compute adaptive threshold:
    // Higher confidence → stricter threshold (we trust the profile)
    // Lower confidence → more lenient threshold (we have less data)
    final double threshold = _computeAdaptiveThreshold(
      profileConfidence: profileConfidence,
      availableMetrics: availableMetrics,
    );

    final profile = StylusProfile(
      size: sizeStats,
      radiusMajor: radMajStats,
      radiusMinor: radMinStats,
      pressure: pressureStats,
      classificationThreshold: threshold,
      availableMetrics: availableMetrics,
      profileConfidence: profileConfidence,
    );

    return CalibrationResult(
      status: CalibrationStatus.success,
      profile: profile,
    );
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  StylusMetricStats _computeStats(List<double> values) {
    if (values.isEmpty) {
      return const StylusMetricStats(mean: 0, stdDev: 0, available: false);
    }
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            values.length;
    final stdDev = math.sqrt(variance);

    // A metric is "available" if at least 30% of values are non-zero and
    // the mean is meaningfully above zero.
    final nonZeroCount = values.where((v) => v > 0.001).length;
    final available =
        nonZeroCount >= (values.length * 0.3).ceil() && mean > 0.001;

    return StylusMetricStats(mean: mean, stdDev: stdDev, available: available);
  }

  double _computeProfileConfidence({
    required StylusMetricStats sizeStats,
    required StylusMetricStats radMajStats,
    required StylusMetricStats radMinStats,
    required StylusMetricStats pressureStats,
    required int availableMetrics,
    required int sampleCount,
  }) {
    if (availableMetrics == 0) return 0.0;

    // Metric availability score
    final metricScore = availableMetrics / 4.0;

    // Sample count score (saturates at 50+ samples)
    final sampleScore = (sampleCount / 50.0).clamp(0.0, 1.0);

    // Consistency score: lower coefficient of variation → more consistent
    // CV = stdDev / mean. Low CV means reliable discrimination.
    double cvScore = 0.0;
    int cvCount = 0;

    for (final stats in [sizeStats, radMajStats, radMinStats, pressureStats]) {
      if (stats.available && stats.mean > 0) {
        final cv = stats.stdDev / stats.mean;
        // CV < 0.2 = very consistent, CV > 1.0 = very noisy
        cvScore += (1.0 - cv.clamp(0.0, 1.0));
        cvCount++;
      }
    }
    final consistencyScore = cvCount > 0 ? cvScore / cvCount : 0.0;

    // Weighted combination
    return (metricScore * 0.40 + sampleScore * 0.25 + consistencyScore * 0.35)
        .clamp(0.0, 1.0);
  }

  double _computeAdaptiveThreshold({
    required double profileConfidence,
    required int availableMetrics,
  }) {
    // High confidence → 0.55 (strict: clear stylus signal)
    // Low confidence  → 0.35 (lenient: vague signal, accept more)
    final base = 0.35 + (profileConfidence * 0.20);
    // If only 1 metric available, be slightly more lenient
    final metricPenalty = availableMetrics == 1 ? 0.05 : 0.0;
    return (base - metricPenalty).clamp(0.30, 0.65);
  }
}
