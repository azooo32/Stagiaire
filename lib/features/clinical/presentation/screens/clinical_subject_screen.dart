import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../../../core/providers/app_provider.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/widgets/app_loader.dart';
import '../../../slide_workspace/presentation/screens/station_subtitles_screen.dart';
import 'voice_screen.dart';
import 'video_screen.dart';

// --- Custom Painters for Premium Medical Icons ---

class ScalpelPainter extends CustomPainter {
  final Color color;
  ScalpelPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    // Draw scalpel handle
    final handlePath = Path()
      ..moveTo(size.width * 0.25, size.height * 0.75)
      ..lineTo(size.width * 0.6, size.height * 0.4);
    canvas.drawPath(handlePath, paint);

    // Draw scalpel blade
    final bladePath = Path()
      ..moveTo(size.width * 0.6, size.height * 0.4)
      ..quadraticBezierTo(
        size.width * 0.7,
        size.height * 0.35,
        size.width * 0.8,
        size.height * 0.2,
      )
      ..lineTo(size.width * 0.75, size.height * 0.15)
      ..quadraticBezierTo(
        size.width * 0.65,
        size.height * 0.25,
        size.width * 0.6,
        size.height * 0.4,
      )
      ..close();

    canvas.drawPath(bladePath, fillPaint);
    canvas.drawPath(bladePath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class KidneysPainter extends CustomPainter {
  final Color color;
  KidneysPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // Left Kidney (bean shape)
    final leftKidney = Path()
      ..moveTo(w * 0.35, h * 0.3)
      ..cubicTo(w * 0.15, h * 0.3, w * 0.15, h * 0.7, w * 0.35, h * 0.7)
      ..cubicTo(w * 0.42, h * 0.6, w * 0.42, h * 0.4, w * 0.35, h * 0.3)
      ..close();

    // Right Kidney (bean shape)
    final rightKidney = Path()
      ..moveTo(w * 0.65, h * 0.3)
      ..cubicTo(w * 0.85, h * 0.3, w * 0.85, h * 0.7, w * 0.65, h * 0.7)
      ..cubicTo(w * 0.58, h * 0.6, w * 0.58, h * 0.4, w * 0.65, h * 0.3)
      ..close();

    canvas.drawPath(leftKidney, fillPaint);
    canvas.drawPath(leftKidney, paint);
    canvas.drawPath(rightKidney, fillPaint);
    canvas.drawPath(rightKidney, paint);

    // Draw some ureters branohing
    final leftUreter = Path()
      ..moveTo(w * 0.38, h * 0.5)
      ..quadraticBezierTo(w * 0.45, h * 0.55, w * 0.45, h * 0.8);
    final rightUreter = Path()
      ..moveTo(w * 0.62, h * 0.5)
      ..quadraticBezierTo(w * 0.55, h * 0.55, w * 0.55, h * 0.8);

    canvas.drawPath(leftUreter, paint);
    canvas.drawPath(rightUreter, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class StomachPainter extends CustomPainter {
  final Color color;
  StomachPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // Draw stomach curve pouch
    final path = Path()
      ..moveTo(w * 0.5, h * 0.15)
      ..lineTo(w * 0.5, h * 0.25)
      ..cubicTo(w * 0.15, h * 0.3, w * 0.25, h * 0.75, w * 0.6, h * 0.8)
      ..lineTo(w * 0.75, h * 0.7)
      ..lineTo(w * 0.7, h * 0.62)
      ..cubicTo(w * 0.45, h * 0.6, w * 0.4, h * 0.35, w * 0.5, h * 0.25)
      ..close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class LiverPainter extends CustomPainter {
  final Color color;
  LiverPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(w * 0.2, h * 0.35)
      ..lineTo(w * 0.8, h * 0.25)
      ..quadraticBezierTo(w * 0.9, h * 0.5, w * 0.7, h * 0.7)
      ..quadraticBezierTo(w * 0.5, h * 0.62, w * 0.25, h * 0.68)
      ..quadraticBezierTo(w * 0.1, h * 0.5, w * 0.2, h * 0.35)
      ..close();

    final dividingLine = Path()
      ..moveTo(w * 0.55, h * 0.28)
      ..quadraticBezierTo(w * 0.5, h * 0.48, w * 0.48, h * 0.65);

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, paint);
    canvas.drawPath(dividingLine, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class VascularPainter extends CustomPainter {
  final Color color;
  VascularPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    canvas.drawLine(Offset(w * 0.5, h * 0.2), Offset(w * 0.5, h * 0.5), paint);

    final bLeft1 = Path()
      ..moveTo(w * 0.5, h * 0.32)
      ..cubicTo(w * 0.38, h * 0.3, w * 0.3, h * 0.38, w * 0.25, h * 0.48);
    final bRight1 = Path()
      ..moveTo(w * 0.5, h * 0.32)
      ..cubicTo(w * 0.62, h * 0.3, w * 0.7, h * 0.38, w * 0.75, h * 0.48);

    final bLeft2 = Path()
      ..moveTo(w * 0.5, h * 0.5)
      ..quadraticBezierTo(w * 0.4, h * 0.65, w * 0.35, h * 0.8);
    final bRight2 = Path()
      ..moveTo(w * 0.5, h * 0.5)
      ..quadraticBezierTo(w * 0.6, h * 0.65, w * 0.65, h * 0.8);

    canvas.drawPath(bLeft1, paint);
    canvas.drawPath(bRight1, paint);
    canvas.drawPath(bLeft2, paint);
    canvas.drawPath(bRight2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class RibcagePainter extends CustomPainter {
  final Color color;
  RibcagePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    canvas.drawLine(Offset(w * 0.5, h * 0.2), Offset(w * 0.5, h * 0.8), paint);

    for (int i = 0; i < 3; i++) {
      double startY = h * (0.32 + i * 0.14);
      final rib = Path()
        ..moveTo(w * 0.5, startY)
        ..quadraticBezierTo(
            w * 0.2, startY + h * 0.04, w * 0.25, startY + h * 0.12);
      canvas.drawPath(rib, paint);
    }

    for (int i = 0; i < 3; i++) {
      double startY = h * (0.32 + i * 0.14);
      final rib = Path()
        ..moveTo(w * 0.5, startY)
        ..quadraticBezierTo(
            w * 0.8, startY + h * 0.04, w * 0.75, startY + h * 0.12);
      canvas.drawPath(rib, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;
  final double dash;

  DashedBorderPainter({
    required this.color,
    this.strokeWidth = 1.5,
    this.gap = 4.0,
    this.dash = 6.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(8),
      ));

    final dashPath = _dashPath(path, dash, gap);
    canvas.drawPath(dashPath, paint);
  }

  Path _dashPath(Path source, double dashLength, double gapLength) {
    final Path dest = Path();
    for (final PathMetric metric in source.computeMetrics()) {
      double distanoe = 0.0;
      bool draw = true;
      while (distanoe < metric.length) {
        final double len = draw ? dashLength : gapLength;
        if (draw) {
          dest.addPath(
            metric.extractPath(
                distanoe, (distanoe + len).clamp(0.0, metric.length)),
            Offset.zero,
          );
        }
        distanoe += len;
        draw = !draw;
      }
    }
    return dest;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// --- Icons Enums & Helpers ---

enum IconType {
  scalpel,
  kidneys,
  stomach,
  liver,
  vascular,
  brain,
  ribcage,
  baby,
  siren
}

IconType _parseIconType(String typeStr) {
  switch (typeStr.toLowerCase()) {
    case 'scalpel':
    case 'soalpel':
      return IconType.scalpel;
    case 'kidneys':
      return IconType.kidneys;
    case 'stomach':
    case 'stomaoh':
      return IconType.stomach;
    case 'liver':
      return IconType.liver;
    case 'vascular':
      return IconType.vascular;
    case 'brain':
      return IconType.brain;
    case 'ribcage':
    case 'riboage':
      return IconType.ribcage;
    case 'baby':
      return IconType.baby;
    case 'siren':
      return IconType.siren;
    default:
      return IconType.scalpel;
  }
}

IconData _getSubjectIcon(String subject) {
  switch (subject.toLowerCase()) {
    case 'surgery':
      return Icons.colorize_outlined;
    case 'internal medicine':
      return Icons.medical_services_outlined;
    case 'obstetrics & gyne':
      return Icons.baby_changing_station_outlined;
    case 'pediatric':
    case 'pediatrio':
      return Icons.child_care_outlined;
    default:
      return Icons.subject;
  }
}

// --- Dynamic Resource Creation Sheet Helper ---

void showAddStationDialog(BuildContext context, AppProvider provider,
    {required String subject, required String sectionId}) {
  final titleController = TextEditingController();
  String selectedIconType = 'scalpel';
  String selectedStationType = 'slides';
  final isDark = provider.isDarkTheme;
  final titleColor = isDark ? Colors.white : const Color(0xFF1E1E50);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: isDark ? AppColors.surface : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              top: 24,
              left: 24,
              right: 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.border : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Add New Station',
                  style: TextStyle(
                    color: titleColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    fontFamily: 'Cairo',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                // Title Input (Station Name)
                Text(
                  'Station Name',
                  style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: titleController,
                  decoration: _buildInputDecoration(
                      'e.g., General Surgery, Urology',
                      isDark: isDark),
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black),
                ),
                const SizedBox(height: 16),

                // Icon Type Selection
                Text(
                  'Station Icon',
                  style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedIconType,
                  dropdownColor: isDark ? AppColors.surface : Colors.white,
                  decoration: _buildInputDecoration('', isDark: isDark),
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  items: [
                    'scalpel',
                    'kidneys',
                    'stomach',
                    'liver',
                    'vascular',
                    'brain',
                    'ribcage',
                    'baby',
                    'siren'
                  ]
                      .map((type) => DropdownMenuItem(
                            value: type,
                            child: Text(
                              type.substring(0, 1).toUpperCase() +
                                  type.substring(1),
                              style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black),
                            ),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setModalState(() => selectedIconType = val);
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Station Type Selection (Slides vs PDF)
                Text(
                  'نوع المحطة / Station Type',
                  style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedStationType,
                  dropdownColor: isDark ? AppColors.surface : Colors.white,
                  decoration: _buildInputDecoration('', isDark: isDark),
                  style: TextStyle(color: isDark ? Colors.white : Colors.black, fontFamily: 'Cairo'),
                  items: const [
                    DropdownMenuItem(
                      value: 'slides',
                      child: Text('🖼️ شرائح تفاعلية (Slides)'),
                    ),
                    DropdownMenuItem(
                      value: 'pdf',
                      child: Text('📄 مستندات (PDF Workspace)'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setModalState(() => selectedStationType = val);
                    }
                  },
                ),
                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: () {
                    final title = titleController.text.trim();
                    if (title.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Please enter a station name')),
                      );
                      return;
                    }

                    // Add Slide Station with default 10 slides
                    provider.addClinicalSlideStation(
                      subject,
                      title,
                      10, // default slides count
                      selectedIconType,
                      sectionId: sectionId,
                      stationType: selectedStationType,
                    );

                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Added $title station successfully!')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6B4EFF),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Add Station',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

void showAddSectionDialog(BuildContext context, AppProvider provider,
    {required String subject}) {
  final titleController = TextEditingController();
  String selectedType = 'voice'; // 'voice', 'video', 'slide'
  final isDark = provider.isDarkTheme;
  final titleColor = isDark ? Colors.white : const Color(0xFF1E1E50);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: isDark ? AppColors.surface : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              top: 24,
              left: 24,
              right: 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.border : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Add New Section',
                  style: TextStyle(
                    color: titleColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    fontFamily: 'Cairo',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                // 1. Content Type Selector Row
                Text(
                  'Select Content Type',
                  style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Voice Note
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setModalState(() => selectedType = 'voice'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: selectedType == 'voice'
                                ? const Color(0xFF6B4EFF)
                                    .withValues(alpha: 0.08)
                                : (isDark
                                    ? AppColors.surface3
                                    : const Color(0xFFF8FAFC)),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selectedType == 'voice'
                                  ? const Color(0xFF6B4EFF)
                                  : (isDark
                                      ? AppColors.border
                                      : const Color(0xFFE2E8F0)),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.mic,
                                  color: selectedType == 'voice'
                                      ? const Color(0xFF6B4EFF)
                                      : (isDark
                                          ? AppColors.textMuted
                                          : const Color(0xFF9E9EBF))),
                              const SizedBox(height: 6),
                              Text(
                                'Voice',
                                style: TextStyle(
                                  color: selectedType == 'voice'
                                      ? const Color(0xFF6B4EFF)
                                      : titleColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Video
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setModalState(() => selectedType = 'video'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: selectedType == 'video'
                                ? const Color(0xFF6B4EFF)
                                    .withValues(alpha: 0.08)
                                : (isDark
                                    ? AppColors.surface3
                                    : const Color(0xFFF8FAFC)),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selectedType == 'video'
                                  ? const Color(0xFF6B4EFF)
                                  : (isDark
                                      ? AppColors.border
                                      : const Color(0xFFE2E8F0)),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.videocam,
                                  color: selectedType == 'video'
                                      ? const Color(0xFF6B4EFF)
                                      : (isDark
                                          ? AppColors.textMuted
                                          : const Color(0xFF9E9EBF))),
                              const SizedBox(height: 6),
                              Text(
                                'Video',
                                style: TextStyle(
                                  color: selectedType == 'video'
                                      ? const Color(0xFF6B4EFF)
                                      : titleColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Slide
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setModalState(() => selectedType = 'slide'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: selectedType == 'slide'
                                ? const Color(0xFF6B4EFF)
                                    .withValues(alpha: 0.08)
                                : (isDark
                                    ? AppColors.surface3
                                    : const Color(0xFFF8FAFC)),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selectedType == 'slide'
                                  ? const Color(0xFF6B4EFF)
                                  : (isDark
                                      ? AppColors.border
                                      : const Color(0xFFE2E8F0)),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.slideshow,
                                  color: selectedType == 'slide'
                                      ? const Color(0xFF6B4EFF)
                                      : (isDark
                                          ? AppColors.textMuted
                                          : const Color(0xFF9E9EBF))),
                              const SizedBox(height: 6),
                              Text(
                                'Slide',
                                style: TextStyle(
                                  color: selectedType == 'slide'
                                      ? const Color(0xFF6B4EFF)
                                      : titleColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Title Input
                Text(
                  'Section Title',
                  style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: titleController,
                  decoration: _buildInputDecoration('Enter section title',
                      isDark: isDark),
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black),
                ),
                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: () {
                    final title = titleController.text.trim();
                    if (title.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Please enter a section title')),
                      );
                      return;
                    }

                    provider.addClinicalSection(
                      subject,
                      title,
                      selectedType,
                      selectedType == 'voice'
                          ? 'mic'
                          : (selectedType == 'video' ? 'video' : 'slide'),
                    );

                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content:
                              Text('Added section "$title" successfully!')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6B4EFF),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Add Section',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

void showGeneralAddDialog(BuildContext context, AppProvider provider,
    {required String subject}) {
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  String selectedType = 'voice'; // 'voice', 'video', 'slide'
  String selectedIconType = 'scalpel';
  String? selectedSectionId;
  final isDark = provider.isDarkTheme;
  final titleColor = isDark ? Colors.white : const Color(0xFF1E1E50);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: isDark ? AppColors.surface : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          // Filter sections of the currently selected type
          final matchingSections = provider.clinicalSections
              .where((s) => s.contentType == selectedType)
              .toList();

          // Reset selected section if it's no longer valid for the current type
          if (selectedSectionId == null && matchingSections.isNotEmpty) {
            selectedSectionId = matchingSections.first.id;
          } else if (selectedSectionId != null &&
              !matchingSections.any((s) => s.id == selectedSectionId)) {
            selectedSectionId =
                matchingSections.isNotEmpty ? matchingSections.first.id : null;
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              top: 24,
              left: 24,
              right: 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.border : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Add New Content',
                  style: TextStyle(
                    color: titleColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    fontFamily: 'Cairo',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                // 1. Content Type Selector Row
                Text(
                  'Select Content Type',
                  style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Voice Note
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setModalState(() {
                          selectedType = 'voice';
                          selectedSectionId = null;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: selectedType == 'voice'
                                ? const Color(0xFF6B4EFF)
                                    .withValues(alpha: 0.08)
                                : (isDark
                                    ? AppColors.surface3
                                    : const Color(0xFFF8FAFC)),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selectedType == 'voice'
                                  ? const Color(0xFF6B4EFF)
                                  : (isDark
                                      ? AppColors.border
                                      : const Color(0xFFE2E8F0)),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.mic,
                                  color: selectedType == 'voice'
                                      ? const Color(0xFF6B4EFF)
                                      : (isDark
                                          ? AppColors.textMuted
                                          : const Color(0xFF9E9EBF))),
                              const SizedBox(height: 6),
                              Text(
                                'Voice',
                                style: TextStyle(
                                  color: selectedType == 'voice'
                                      ? const Color(0xFF6B4EFF)
                                      : titleColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Video
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setModalState(() {
                          selectedType = 'video';
                          selectedSectionId = null;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: selectedType == 'video'
                                ? const Color(0xFF6B4EFF)
                                    .withValues(alpha: 0.08)
                                : (isDark
                                    ? AppColors.surface3
                                    : const Color(0xFFF8FAFC)),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selectedType == 'video'
                                  ? const Color(0xFF6B4EFF)
                                  : (isDark
                                      ? AppColors.border
                                      : const Color(0xFFE2E8F0)),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.videocam,
                                  color: selectedType == 'video'
                                      ? const Color(0xFF6B4EFF)
                                      : (isDark
                                          ? AppColors.textMuted
                                          : const Color(0xFF9E9EBF))),
                              const SizedBox(height: 6),
                              Text(
                                'Video',
                                style: TextStyle(
                                  color: selectedType == 'video'
                                      ? const Color(0xFF6B4EFF)
                                      : titleColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Slide
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setModalState(() {
                          selectedType = 'slide';
                          selectedSectionId = null;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: selectedType == 'slide'
                                ? const Color(0xFF6B4EFF)
                                    .withValues(alpha: 0.08)
                                : (isDark
                                    ? AppColors.surface3
                                    : const Color(0xFFF8FAFC)),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selectedType == 'slide'
                                  ? const Color(0xFF6B4EFF)
                                  : (isDark
                                      ? AppColors.border
                                      : const Color(0xFFE2E8F0)),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.slideshow,
                                  color: selectedType == 'slide'
                                      ? const Color(0xFF6B4EFF)
                                      : (isDark
                                          ? AppColors.textMuted
                                          : const Color(0xFF9E9EBF))),
                              const SizedBox(height: 6),
                              Text(
                                'Slide',
                                style: TextStyle(
                                  color: selectedType == 'slide'
                                      ? const Color(0xFF6B4EFF)
                                      : titleColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 2. Select Section Dropdown
                Text(
                  'Select Section',
                  style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 6),
                if (matchingSections.isEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'No sections created for this type yet. Please add a section of this type first!',
                      style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  DropdownButtonFormField<String>(
                    value: selectedSectionId,
                    dropdownColor: isDark ? AppColors.surface : Colors.white,
                    decoration: _buildInputDecoration('', isDark: isDark),
                    style:
                        TextStyle(color: isDark ? Colors.white : Colors.black),
                    items: matchingSections
                        .map((seo) => DropdownMenuItem(
                              value: seo.id,
                              child: Text(seo.title,
                                  style: TextStyle(
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black)),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() => selectedSectionId = val);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // Name/Title
                Text(
                  'Name / Title',
                  style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: titleController,
                  decoration: _buildInputDecoration('Enter name / title',
                      isDark: isDark),
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black),
                ),
                const SizedBox(height: 16),

                // Description / Subtitle
                Text(
                  'Description / Subtitle',
                  style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: descriptionController,
                  decoration: _buildInputDecoration(
                      'Enter details or description',
                      isDark: isDark),
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black),
                ),
                const SizedBox(height: 16),

                // Slide Icon selector (Only visible if slide type selected)
                if (selectedType == 'slide') ...[
                  Text(
                    'Slide Icon',
                    style: TextStyle(
                        color: titleColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        fontFamily: 'Cairo'),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: selectedIconType,
                    dropdownColor: isDark ? AppColors.surface : Colors.white,
                    decoration: _buildInputDecoration('', isDark: isDark),
                    style:
                        TextStyle(color: isDark ? Colors.white : Colors.black),
                    items: [
                      'scalpel',
                      'kidneys',
                      'stomach',
                      'liver',
                      'vascular',
                      'brain',
                      'ribcage',
                      'baby',
                      'siren'
                    ]
                        .map((type) => DropdownMenuItem(
                              value: type,
                              child: Text(
                                type.substring(0, 1).toUpperCase() +
                                    type.substring(1),
                                style: TextStyle(
                                    color:
                                        isDark ? Colors.white : Colors.black),
                              ),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() => selectedIconType = val);
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                ],

                ElevatedButton(
                  onPressed: matchingSections.isEmpty
                      ? null
                      : () {
                          final title = titleController.text.trim();
                          final desc = descriptionController.text.trim();
                          if (title.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Please enter a name')),
                            );
                            return;
                          }

                          if (selectedType == 'voice') {
                            provider.addClinicalVoiceNote(
                              subject,
                              title,
                              desc.isNotEmpty ? desc : 'History',
                              '03:45', // simulated default duration
                              sectionId: selectedSectionId,
                            );
                          } else if (selectedType == 'video') {
                            provider.addClinicalVideo(
                              subject,
                              title,
                              '12:30', // simulated default duration
                              sectionId: selectedSectionId,
                            );
                          } else if (selectedType == 'slide') {
                            provider.addClinicalSlideStation(
                              subject,
                              title,
                              10, // default slides count
                              selectedIconType,
                              sectionId: selectedSectionId,
                            );
                          }

                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Added $title successfully!')),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6B4EFF),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Add Content',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

void showAddOptionsSheet(BuildContext context, AppProvider provider,
    {required String subject}) {
  final isDark = provider.isDarkTheme;
  showModalBottomSheet(
    context: context,
    backgroundColor: isDark ? AppColors.surface : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.border : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.folder_open_outlined,
                  color: isDark
                      ? const Color(0xFF8B75FF)
                      : const Color(0xFF6B4EFF)),
              title: Text(
                'Add New Section (إضافة قسم جديد)',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black),
              ),
              onTap: () {
                Navigator.pop(context);
                showAddSectionDialog(context, provider, subject: subject);
              },
            ),
            ListTile(
              leading: Icon(Icons.note_add_outlined,
                  color: isDark ? Colors.blue[300] : Colors.blue),
              title: Text(
                'Add Content to Section (إضافة محتوى)',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black),
              ),
              onTap: () {
                Navigator.pop(context);
                showGeneralAddDialog(context, provider, subject: subject);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      );
    },
  );
}

InputDecoration _buildInputDecoration(String hintText, {bool isDark = false}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(
        color: isDark ? AppColors.textMuted : const Color(0xFF94A3B8),
        fontSize: 14),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    filled: true,
    fillColor: isDark ? AppColors.surface2 : const Color(0xFFF8FAFC),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
          color: isDark ? AppColors.border : const Color(0xFFE2E8F0),
          width: 1.5),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
          color: isDark ? AppColors.border : const Color(0xFFE2E8F0),
          width: 1.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
          color: isDark ? const Color(0xFF8B75FF) : const Color(0xFF6B4EFF),
          width: 2),
    ),
  );
}

// --- Main Unified ClinicalSubjectScreen ---

class ClinicalSubjectScreen extends StatefulWidget {
  final String subject;
  const ClinicalSubjectScreen({super.key, required this.subject});

  @override
  State<ClinicalSubjectScreen> createState() => _ClinicalSubjectScreenState();
}

class _ClinicalSubjectScreenState extends State<ClinicalSubjectScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<AppProvider>(context, listen: false);
      final isLocked = !provider.isClinicalSubjectUnlockedByName(widget.subject);
      if (isLocked) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'عذراً، هذه المادة العملية تتطلب اشتراكاً نشطاً.',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      provider.loadClinicalData(widget.subject);
      provider.subscribeToClinicalRealtime(widget.subject);
    });
  }

  @override
  void dispose() {
    Provider.of<AppProvider>(context, listen: false)
        .unsubscribeFromClinicalRealtime();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final isTablet = MediaQuery.of(context).size.width > 600;
    final isLocked = !provider.isClinicalSubjectUnlockedByName(widget.subject);
    if (isLocked) {
      return const Scaffold(
        body: Center(child: LogoSpinner()),
      );
    }

    final double statusBarHeight = MediaQuery.of(context).padding.top;
    const Color brandColor = Color(0xFF6B4EFF);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        backgroundColor:
            provider.isDarkTheme ? AppColors.bg : const Color(0xFFF8F9FE),
        floatingActionButton:
            (!provider.isAdminOrOwner || provider.isClinicalLoading)
                ? null
                : Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FloatingActionButton(
                      onPressed: () => showAddOptionsSheet(context, provider,
                          subject: widget.subject),
                      backgroundColor: brandColor,
                      elevation: 6,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child:
                          const Icon(Icons.add, color: Colors.white, size: 26),
                    ),
                  ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        body: Column(
          children: [
            // Compaot Header
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                top: statusBarHeight + 8,
                bottom: 12,
                left: 16,
                right: 16,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: provider.isDarkTheme
                      ? const [Color(0xFF6047D6), Color(0xFF4930B6)]
                      : const [Color(0xFF7B5EFF), Color(0xFF5B3EEF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(_getSubjectIcon(widget.subject),
                                color: Colors.white, size: 14),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.subject,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.help_outline,
                            color: Colors.transparent),
                        onPressed: () {},
                      ), // Balancing spacer matching back button
                    ],
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Column(
                      children: [
                        if (provider.isClinicalLoading)
                          Padding(
                            padding: const EdgeInsets.only(top: 120.0),
                            child: const Center(
                                child: LogoSpinner(size: 80, logoSize: 50)),
                          )
                        else ...[
                          const SizedBox(height: 16),

                          // Voice and Video sections rendered in a 2-column Grid
                          (() {
                            final voiceAndVideoSeos = provider.clinicalSections
                                .where((s) =>
                                    s.contentType == 'voice' ||
                                    s.contentType == 'video')
                                .toList();

                            if (voiceAndVideoSeos.isEmpty)
                              return const SizedBox.shrink();

                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16.0),
                              child: GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: EdgeInsets.zero,
                                gridDelegate:
                                    SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 260,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: isTablet ? 1.35 : 0.88,
                                ),
                                itemCount: voiceAndVideoSeos.length,
                                itemBuilder: (context, index) {
                                  final section = voiceAndVideoSeos[index];
                                  if (section.contentType == 'voice') {
                                    final voiceCount = provider
                                        .getClinicalVoiceNotes(widget.subject)
                                        .where(
                                            (vn) => vn.sectionId == section.id)
                                        .length;
                                    return GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => VoiceScreen(
                                              subject: widget.subject,
                                              sectionId: section.id,
                                              sectionTitle: section.title,
                                            ),
                                          ),
                                        );
                                      },
                                      child: _buildBottomFeatureCard(
                                        title: section.title,
                                        subtitle:
                                            'Listen to ${section.title.toLowerCase()} recordings',
                                        badgeText: '$voiceCount Voice Notes',
                                        badgeIcon: Icons.mic_none_outlined,
                                        headerIcon: Icons.volume_up_outlined,
                                        progress: 1.0,
                                        brandColor: brandColor,
                                      ),
                                    );
                                  } else {
                                    final videoCount = provider
                                        .getClinicalVideos(widget.subject)
                                        .where((v) => v.sectionId == section.id)
                                        .length;
                                    return GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => VideoScreen(
                                              subject: widget.subject,
                                              sectionId: section.id,
                                              sectionTitle: section.title,
                                            ),
                                          ),
                                        );
                                      },
                                      child: _buildBottomFeatureCard(
                                        title: section.title,
                                        subtitle:
                                            'Watch and learn from ${section.title.toLowerCase()} videos',
                                        badgeText: '$videoCount Videos',
                                        badgeIcon: Icons.play_circle_outline,
                                        headerIcon: Icons.videocam_outlined,
                                        progress: 1.0,
                                        brandColor: brandColor,
                                      ),
                                    );
                                  }
                                },
                              ),
                            );
                          })(),

                          const SizedBox(height: 16),

                          // Slide sections (rendered as full-width grid cards)
                          ...(() {
                            final stations = provider
                                .getClinicalSlideStations(widget.subject);
                            final slideSeos = provider.clinicalSections
                                .where((s) => s.contentType == 'slide')
                                .toList();

                            return slideSeos.map((section) {
                              final sectionStations = stations
                                  .where((s) => s.sectionId == section.id)
                                  .toList();

                              return Padding(
                                padding: const EdgeInsets.only(
                                    left: 16.0, right: 16.0, bottom: 16.0),
                                child: _buildDynamicSlideSectionCard(
                                  context,
                                  provider,
                                  section,
                                  sectionStations,
                                  brandColor,
                                  isTablet,
                                ),
                              );
                            }).toList();
                          })(),

                          if (provider.clinicalSections.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 48.0),
                              child: Center(
                                child: Text(
                                  'No sections created yet.\nTap the + button below to add your first section!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Color(0xFF9E9EBF),
                                      fontSize: 13,
                                      fontFamily: 'Cairo'),
                                ),
                              ),
                            ),
                        ],
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicSlideSectionCard(
    BuildContext context,
    AppProvider provider,
    ClinicalSection section,
    List<ClinicalSlideStation> sectionStations,
    Color brandColor,
    bool isTablet,
  ) {
    int totalSlides = sectionStations.map((s) {
      final parts = s.progressText.split('/');
      if (parts.length > 1) {
        final numberPart = parts[1].trim().split(' ').first;
        return int.tryParse(numberPart) ?? 0;
      }
      return 0;
    }).fold(0, (a, b) => a + b);

    int totalStations = sectionStations.length;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: provider.isDarkTheme ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: provider.isDarkTheme
                ? Colors.black.withValues(alpha: 0.2)
                : brandColor.withValues(alpha: 0.02),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: brandColor,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.description_outlined,
                        color: Colors.white, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      section.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    _buildPillStat(
                        Icons.slideshow_rounded, '$totalSlides', 'Slides'),
                    _buildPillDivider(),
                    _buildPillStat(Icons.location_on_outlined, '$totalStations',
                        'Stations'),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // Grid of 3 columns
          Padding(
            padding:
                const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16.0),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: isTablet ? 260 : 210,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.86,
              ),
              itemCount: provider.isAdminOrOwner
                  ? sectionStations.length + 1
                  : sectionStations.length,
              itemBuilder: (context, index) {
                if (index < sectionStations.length) {
                  return _buildStationCard(
                      context, sectionStations[index], brandColor, isTablet);
                } else {
                  return _buildAddStationCard(brandColor, provider, section.id, isTablet);
                }
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // Header Stat Item helper
  Widget _buildPillStat(IconData icon, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 12),
        const SizedBox(width: 3),
        Text(
          value,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 9),
        ),
      ],
    );
  }

  Widget _buildPillDivider() {
    return Container(
      height: 12,
      width: 1,
      color: Colors.white.withValues(alpha: 0.3),
      margin: const EdgeInsets.symmetric(horizontal: 6),
    );
  }

  // Grid Station Card
  Widget _buildStationCard(
      BuildContext context, ClinicalSlideStation station, Color brandColor, bool isTablet) {
    final provider = Provider.of<AppProvider>(context);
    final isDark = provider.isDarkTheme;
    final isBookmarked = provider.isClinicalBookmarked('station', station.dbId);
    final isDone = provider.isStationCompleted(station.dbId);

    final double circleSize = isTablet ? 72 : 52;
    final double iconSize = isTablet ? 28 : 20;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => StationSubtitlesScreen(
              stationName: station.title,
              stationDbId: station.dbId,
              stationType: station.stationType,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surface : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDone
                ? const Color(0xFF10B981).withValues(alpha: 0.45)
                : (isDark ? AppColors.border : brandColor.withValues(alpha: 0.12)),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.25)
                  : brandColor.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: isTablet
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 14)
              : const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top Row: Station ID badge
              Align(
                alignment: Alignment.topRight,
                child: Container(
                  padding: isTablet
                      ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4)
                      : const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: brandColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${station.id}',
                    style: TextStyle(
                      color: brandColor,
                      fontSize: isTablet ? 12 : 9,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ),

              // Prominent Circular Icon in Center
              Container(
                width: circleSize,
                height: circleSize,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      brandColor.withValues(alpha: 0.16),
                      brandColor.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: brandColor.withValues(alpha: 0.15),
                    width: 1.2,
                  ),
                ),
                alignment: Alignment.center,
                child: _buildStationIcon(
                    _parseIconType(station.iconType), brandColor, iconSize),
              ),

              // Title underneath the circle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  station.title,
                  style: TextStyle(
                    color: isDark ? AppColors.text : const Color(0xFF1E1E50),
                    fontWeight: FontWeight.w700,
                    fontSize: isTablet ? 14 : 11,
                    fontFamily: 'Cairo',
                    height: 1.2,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Bottom Row with Save (Bookmark) & Marker (Completion) Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Bookmark / Save button
                  InkWell(
                    onTap: () => provider.toggleClinicalBookmark(
                        'station', station.dbId),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        isBookmarked
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        color: isBookmarked
                            ? AppColors.amber
                            : (isDark
                                ? AppColors.textMuted
                                : const Color(0xFF9E9EBF)),
                        size: isTablet ? 20 : 15,
                      ),
                    ),
                  ),

                  // Completion indicator / button
                  GestureDetector(
                    onTap: () {
                      provider.toggleStationCompletion(station.dbId);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isDone
                            ? const Color(0xFF10B981).withValues(alpha: 0.12)
                            : (isDark ? AppColors.surface2 : Colors.grey.shade50),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDone
                              ? const Color(0xFF10B981).withValues(alpha: 0.3)
                              : (isDark ? AppColors.border : Colors.grey.shade300),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        color: isDone
                            ? const Color(0xFF10B981)
                            : (isDark ? AppColors.textMuted : Colors.grey.shade400),
                        size: isTablet ? 15 : 11,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Add New Station Card
  Widget _buildAddStationCard(
      Color brandColor, AppProvider provider, String sectionId, bool isTablet) {
    final double circleSize = isTablet ? 48 : 32;
    final double iconSize = isTablet ? 24 : 16;
    final double fontSize = isTablet ? 12 : 8;

    return CustomPaint(
      painter: DashedBorderPainter(color: brandColor.withValues(alpha: 0.3)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Material(
          color: provider.isDarkTheme
              ? AppColors.surface
              : brandColor.withValues(alpha: 0.02),
          child: InkWell(
            onTap: () => showAddStationDialog(context, provider,
                subject: widget.subject, sectionId: sectionId),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: circleSize,
                  height: circleSize,
                  decoration: BoxDecoration(
                    color: brandColor.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.add,
                    color: brandColor,
                    size: iconSize,
                  ),
                ),
                SizedBox(height: isTablet ? 10 : 6),
                Text(
                  'Add New Station',
                  style: TextStyle(
                    color: brandColor,
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Draw appropriate icon / CustomPainter based on type
  Widget _buildStationIcon(IconType type, Color color, double size) {
    switch (type) {
      case IconType.scalpel:
        return CustomPaint(
            size: Size(size * 1.375, size * 1.375), painter: ScalpelPainter(color: color));
      case IconType.kidneys:
        return CustomPaint(
            size: Size(size * 1.375, size * 1.375), painter: KidneysPainter(color: color));
      case IconType.stomach:
        return CustomPaint(
            size: Size(size * 1.375, size * 1.375), painter: StomachPainter(color: color));
      case IconType.liver:
        return CustomPaint(
            size: Size(size * 1.375, size * 1.375), painter: LiverPainter(color: color));
      case IconType.vascular:
        return CustomPaint(
            size: Size(size * 1.375, size * 1.375), painter: VascularPainter(color: color));
      case IconType.brain:
        return FaIcon(FontAwesomeIcons.brain, color: color, size: size);
      case IconType.ribcage:
        return CustomPaint(
            size: Size(size * 1.375, size * 1.375), painter: RibcagePainter(color: color));
      case IconType.baby:
        return FaIcon(FontAwesomeIcons.baby, color: color, size: size);
      case IconType.siren:
        return Icon(Icons.notifications_active_outlined,
            color: color, size: size);
    }
  }

  // Bottom Cards Helper
  Widget _buildBottomFeatureCard({
    required String title,
    required String subtitle,
    required String badgeText,
    required IconData badgeIcon,
    required IconData headerIcon,
    required double progress,
    required Color brandColor,
  }) {
    final provider = Provider.of<AppProvider>(context);
    final isDark = provider.isDarkTheme;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color:
                isDark ? AppColors.border : brandColor.withValues(alpha: 0.08),
            width: 1),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : brandColor.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [brandColor, brandColor.withValues(alpha: 0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 150;
                final tight = constraints.maxWidth < 125;
                final titleSize = tight ? 11.5 : (compact ? 12.5 : 15.0);
                final iconSize = tight ? 13.0 : (compact ? 14.0 : 16.0);
                final iconPadding = tight ? 4.0 : 6.0;
                return Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(iconPadding),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child:
                          Icon(headerIcon, color: Colors.white, size: iconSize),
                    ),
                    SizedBox(width: tight ? 5 : 8),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: titleSize,
                          fontFamily: 'Cairo',
                          height: 1.1,
                        ),
                        maxLines: compact ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Subtitle
                Text(
                  subtitle,
                  style: TextStyle(
                    color: isDark ? AppColors.textDim : const Color(0xFF9E9EBF),
                    fontSize: 11,
                    fontFamily: 'Cairo',
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 12),

                // Badge/Counter Row
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: brandColor.withValues(alpha: isDark ? 0.2 : 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(badgeIcon, color: brandColor, size: 13),
                      const SizedBox(width: 5),
                      Text(
                        badgeText,
                        style: TextStyle(
                          color: brandColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Progress Row
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: isDark
                              ? AppColors.surface2
                              : const Color(0xFFF1F5F9),
                          valueColor: AlwaysStoppedAnimation<Color>(brandColor),
                          minHeight: 5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(progress * 100).round()}%',
                      style: TextStyle(
                        color: brandColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
