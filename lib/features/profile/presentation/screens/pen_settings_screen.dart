import 'package:flutter/material.dart';

import '../../../../core/services/capacitive_stylus_service.dart';
import 'stylus_calibration_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  PenSettingsScreen
//  Route: Profile → Settings → Pen Settings
// ─────────────────────────────────────────────────────────────────────────────
class PenSettingsScreen extends StatefulWidget {
  const PenSettingsScreen({super.key});

  @override
  State<PenSettingsScreen> createState() => _PenSettingsScreenState();
}

class _PenSettingsScreenState extends State<PenSettingsScreen> {
  final CapacitiveStylusService _service = CapacitiveStylusService();

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  @override
  void initState() {
    super.initState();
    // Make sure service is loaded (safe to call multiple times)
    _service.load().then((_) {
      if (mounted) setState(() {});
    });
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  // ── Toggle handling ──────────────────────────────────────────────────────────

  Future<void> _handleToggle(bool newValue) async {
    if (newValue == _service.isEnabled) return;

    if (newValue) {
      // Turning ON → open calibration first
      await _openCalibration(isRecalibration: false);
    } else {
      // Turning OFF → confirm, then wipe everything
      final confirmed = await _showDisableConfirmation();
      if (confirmed == true) {
        await _service.disable();
      }
    }
  }

  Future<void> _openCalibration({required bool isRecalibration}) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StylusCalibrationScreen(
          isRecalibration: isRecalibration,
        ),
        fullscreenDialog: true,
      ),
    );
    // result == true means calibration succeeded; service already updated.
    // No extra action needed here.
    if (mounted) setState(() {});
  }

  Future<bool?> _showDisableConfirmation() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _isDark ? const Color(0xFF18162B) : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Disable Capacitive Stylus?',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: _isDark ? Colors.white : const Color(0xFF1E1E50),
            ),
          ),
          content: Text(
            'This will remove your saved stylus profile and calibration data. '
            'You will need to recalibrate if you enable this again.',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              height: 1.5,
              color: _isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Disable & Reset',
                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = _isDark;
    final bg = isDark ? const Color(0xFF100F1F) : const Color(0xFFF5F5FF);
    final cardBg = isDark ? const Color(0xFF18162B) : Colors.white;
    final tileBg = isDark ? const Color(0xFF211E38) : const Color(0xFFF8FAFC);
    final textColor = isDark ? Colors.white : const Color(0xFF1E1E50);
    final mutedColor = isDark ? const Color(0xFF918BAC) : const Color(0xFF9E9EBF);
    const accentColor = Color(0xFF6B4EFF);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0,
        title: Text(
          'Pen Settings',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w900,
            fontSize: 17,
            color: textColor,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: textColor, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            _sectionHeader('Capacitive / Disc Stylus', isDark),
            const SizedBox(height: 12),

            // Main toggle tile
            _buildToggleTile(
              isDark: isDark,
              tileBg: tileBg,
              textColor: textColor,
              mutedColor: mutedColor,
              accentColor: accentColor,
            ),

            // Info banner
            const SizedBox(height: 12),
            _buildInfoBanner(isDark, accentColor),

            // Recalibrate tile — only when enabled & calibrated
            if (_service.isEnabled && _service.isCalibrated) ...[
              const SizedBox(height: 20),
              _sectionHeader('Calibration', isDark),
              const SizedBox(height: 12),
              _buildCalibrateTile(
                isDark: isDark,
                tileBg: tileBg,
                textColor: textColor,
                mutedColor: mutedColor,
                accentColor: accentColor,
              ),

              // Profile confidence info
              if (_service.profile != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _buildProfileCard(
                    isDark: isDark,
                    cardBg: cardBg,
                    textColor: textColor,
                    mutedColor: mutedColor,
                    accentColor: accentColor,
                  ),
                ),
            ],

            const SizedBox(height: 32),

            // Important notice
            _buildNotice(isDark),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, bool isDark) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        fontFamily: 'Cairo',
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: isDark ? const Color(0xFF918BAC) : const Color(0xFF9E9EBF),
      ),
    );
  }

  Widget _buildToggleTile({
    required bool isDark,
    required Color tileBg,
    required Color textColor,
    required Color mutedColor,
    required Color accentColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: tileBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: SwitchListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        value: _service.isEnabled,
        onChanged: _handleToggle,
        activeThumbColor: accentColor,
        title: Text(
          'Capacitive Stylus Support',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: textColor,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            _service.isEnabled
                ? (_service.isCalibrated
                    ? 'Active — stylus profile loaded'
                    : 'Enabled — calibration required')
                : 'Enable to use a passive capacitive stylus for drawing',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: mutedColor,
            ),
          ),
        ),
        secondary: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.draw_outlined,
            color: accentColor,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoBanner(bool isDark, Color accentColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              color: accentColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Use this for passive disc-tip capacitive styluses that appear as touch events. '
              'Apple Pencil and active styluses are always supported and unaffected by this setting.',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                height: 1.55,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalibrateTile({
    required bool isDark,
    required Color tileBg,
    required Color textColor,
    required Color mutedColor,
    required Color accentColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: tileBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onTap: () => _openCalibration(isRecalibration: true),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child:
              Icon(Icons.tune_rounded, color: accentColor, size: 20),
        ),
        title: Text(
          'Recalibrate Stylus',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: textColor,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            'Update your stylus profile with a new calibration',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: mutedColor,
            ),
          ),
        ),
        trailing: Icon(Icons.chevron_right_rounded,
            color: mutedColor, size: 22),
      ),
    );
  }

  Widget _buildProfileCard({
    required bool isDark,
    required Color cardBg,
    required Color textColor,
    required Color mutedColor,
    required Color accentColor,
  }) {
    final profile = _service.profile!;
    final confidence = profile.profileConfidence;
    final confidencePercent = (confidence * 100).round();
    final confidenceColor = confidence >= 0.6
        ? const Color(0xFF10B981)
        : confidence >= 0.35
            ? Colors.orange
            : Colors.red;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? const Color(0xFF3B365C)
              : const Color(0xFFE8E8FF),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fingerprint_rounded,
                  color: accentColor, size: 18),
              const SizedBox(width: 8),
              Text(
                'Stylus Profile',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Profile confidence bar
          Row(
            children: [
              Text(
                'Profile Confidence',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: mutedColor,
                ),
              ),
              const Spacer(),
              Text(
                '$confidencePercent%',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: confidenceColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: confidence,
              backgroundColor:
                  isDark ? const Color(0xFF2C2848) : const Color(0xFFEEEEFF),
              valueColor:
                  AlwaysStoppedAnimation<Color>(confidenceColor),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 12),

          // Available metrics
          Text(
            '${profile.availableMetrics} of 4 touch metrics available on this device',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              color: mutedColor,
            ),
          ),
          const SizedBox(height: 8),

          // Metric availability indicators
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _metricChip('Size', profile.size.available, isDark, accentColor),
              _metricChip('Radius Major', profile.radiusMajor.available, isDark, accentColor),
              _metricChip('Radius Minor', profile.radiusMinor.available, isDark, accentColor),
              _metricChip('Pressure', profile.pressure.available, isDark, accentColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricChip(
      String label, bool available, bool isDark, Color accentColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: available
            ? accentColor.withValues(alpha: 0.12)
            : (isDark
                ? const Color(0xFF2C2848)
                : const Color(0xFFEEEEFF)),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: available
              ? accentColor.withValues(alpha: 0.3)
              : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            available ? Icons.check_circle_rounded : Icons.cancel_outlined,
            size: 12,
            color: available
                ? accentColor
                : (isDark ? Colors.white38 : Colors.black26),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: available
                  ? accentColor
                  : (isDark ? Colors.white38 : Colors.black38),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotice(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline_rounded,
              color: Colors.orange, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'The stylus profile is stored only on this device. '
              'Turning this feature off will permanently delete the profile.',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                height: 1.55,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
