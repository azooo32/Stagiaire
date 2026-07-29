import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/providers/app_provider.dart';
import '../../../../core/theme/colors.dart';

// --- Urinary System Vector Graphic Painter ---

class UrinarySystemPainter extends CustomPainter {
  final Color outlineColor;
  final Color fillColor;

  UrinarySystemPainter({
    required this.outlineColor,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Outer anatomical outline path
    final mainPaint = Paint()
      ..color = outlineColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    // Draw kidneys
    final leftKidney = Path()
      ..moveTo(w * 0.46, h * 0.28)
      ..cubicTo(w * 0.38, h * 0.28, w * 0.38, h * 0.42, w * 0.46, h * 0.42)
      ..cubicTo(w * 0.49, h * 0.38, w * 0.49, h * 0.32, w * 0.46, h * 0.28)
      ..close();

    final rightKidney = Path()
      ..moveTo(w * 0.54, h * 0.28)
      ..cubicTo(w * 0.62, h * 0.28, w * 0.62, h * 0.42, w * 0.54, h * 0.42)
      ..cubicTo(w * 0.51, h * 0.38, w * 0.51, h * 0.32, w * 0.54, h * 0.28)
      ..close();

    canvas.drawPath(leftKidney, fillPaint);
    canvas.drawPath(leftKidney, mainPaint);
    canvas.drawPath(rightKidney, fillPaint);
    canvas.drawPath(rightKidney, mainPaint);

    // Draw bladder (urinary bladder pouoh)
    final bladderPath = Path()
      ..moveTo(w * 0.46, h * 0.72)
      ..cubicTo(w * 0.42, h * 0.72, w * 0.42, h * 0.82, w * 0.5, h * 0.82)
      ..cubicTo(w * 0.58, h * 0.82, w * 0.58, h * 0.72, w * 0.54, h * 0.72)
      ..close();

    canvas.drawPath(bladderPath, fillPaint);
    canvas.drawPath(bladderPath, mainPaint);

    // Draw ureter tubes connecting kidney to bladder
    final leftUreter = Path()
      ..moveTo(w * 0.47, h * 0.35)
      ..quadraticBezierTo(w * 0.46, h * 0.55, w * 0.47, h * 0.73);

    final rightUreter = Path()
      ..moveTo(w * 0.53, h * 0.35)
      ..quadraticBezierTo(w * 0.54, h * 0.55, w * 0.53, h * 0.73);

    canvas.drawPath(leftUreter, mainPaint);
    canvas.drawPath(rightUreter, mainPaint);

    // Draw urethra tube extending downwards
    canvas.drawLine(
      Offset(w * 0.5, h * 0.82),
      Offset(w * 0.5, h * 0.90),
      mainPaint,
    );

    // Draw vena cava & aorta vascular trunks (center background anatomy)
    final vesselPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.5)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final veinPaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.5)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    // Vena cava (Blue)
    canvas.drawLine(
        Offset(w * 0.49, h * 0.22), Offset(w * 0.49, h * 0.65), veinPaint);
    // Aorta (Red)
    canvas.drawLine(
        Offset(w * 0.51, h * 0.22), Offset(w * 0.51, h * 0.65), vesselPaint);

    // Branohing renal vessels
    canvas.drawLine(
        Offset(w * 0.49, h * 0.34), Offset(w * 0.46, h * 0.34), veinPaint);
    canvas.drawLine(
        Offset(w * 0.51, h * 0.34), Offset(w * 0.54, h * 0.34), vesselPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// --- Dynamic Diagram Widget with Pointer Lines and Overlay Labels ---

class UrinarySystemDiagram extends StatelessWidget {
  const UrinarySystemDiagram({super.key});

  @override
  Widget build(BuildContext context) {
    const Color brandColor = Color(0xFF6B4EFF);

    return Container(
      width: double.infinity,
      height: 240,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Centered Anatomical Drawing
          Center(
            child: CustomPaint(
              size: const Size(200, 200),
              painter: UrinarySystemPainter(
                outlineColor: brandColor.withValues(alpha: 0.8),
                fillColor: brandColor.withValues(alpha: 0.15),
              ),
            ),
          ),

          // Top Left Title
          const Positioned(
            top: 16,
            left: 20,
            child: Text(
              'The Urinary System',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                fontFamily: 'Cairo',
              ),
            ),
          ),

          // Labels and Pointer Lines
          // 1. Kidney Label (Top Left)
          Positioned(
            top: 55,
            left: 20,
            child: _buildPointerLabel('Kidney'),
          ),
          // Pointer Line: Kidney
          CustomPaint(
            painter: _PointerLinePainter(
              start: const Offset(90, 63),
              end: const Offset(142, 63),
            ),
          ),

          // 2. Ureter Label (Middle Left)
          Positioned(
            top: 100,
            left: 20,
            child: _buildPointerLabel('Ureter'),
          ),
          // Pointer Line: Ureter
          CustomPaint(
            painter: _PointerLinePainter(
              start: const Offset(90, 108),
              end: const Offset(182, 108),
            ),
          ),

          // 3. Urinary Bladder Label (Lower Left)
          Positioned(
            top: 145,
            left: 20,
            child: _buildPointerLabel('Urinary Bladder'),
          ),
          // Pointer Line: Bladder
          CustomPaint(
            painter: _PointerLinePainter(
              start: const Offset(145, 153),
              end: const Offset(195, 153),
            ),
          ),

          // 4. Urethra Label (Bottom Left)
          Positioned(
            top: 190,
            left: 20,
            child: _buildPointerLabel('Urethra'),
          ),
          // Pointer Line: Urethra
          CustomPaint(
            painter: _PointerLinePainter(
              start: const Offset(95, 198),
              end: const Offset(198, 198),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPointerLabel(String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFamily: 'Cairo',
          ),
        ),
        const SizedBox(width: 4),
        Container(
          width: 4,
          height: 4,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

// Simple Pointer Line drawing
class _PointerLinePainter extends CustomPainter {
  final Offset start;
  final Offset end;

  _PointerLinePainter({required this.start, required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white30
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(start, end, paint);
    // Draw tiny circle indicator at the end point
    final dotPaint = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.fill;
    canvas.drawCircle(end, 2.0, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// --- Main SlidePracticeScreen Stateful Widget ---

class SlidePracticeScreen extends StatefulWidget {
  final String stationName;
  final String? stationDbId;
  const SlidePracticeScreen({
    super.key,
    required this.stationName,
    this.stationDbId,
  });

  @override
  State<SlidePracticeScreen> createState() => _SlidePracticeScreenState();
}

class _SlidePracticeScreenState extends State<SlidePracticeScreen> {
  bool _showAnswers = false;
  final TextEditingController _notesController = TextEditingController();

  // Track selected active slide index (0-indexed, represents 3/12 initially)
  int _currentSlideIndex = 2;
  final int _totalSlidesCount = 12;

  // Mocked questions & answers
  final List<Map<String, dynamic>> _slidesData = [
    {
      'question': 'What are the main functions of the kidneys?',
      'subtext': 'Recall all primary functions in filtration.',
      'answers': [
        'Filtering waste produots',
        'Regulating blood pressure',
        'Maintaining fluid balanoe'
      ],
    },
    {
      'question': 'Describe the ureters pathway.',
      'subtext': 'Write down the connection routes.',
      'answers': [
        'Connects renal pelvis to bladder',
        'Runs retroperitoneally',
        'Uses peristalsis to move urine'
      ],
    },
    {
      'question': 'What are the parts of the urinary system?',
      'subtext': 'Write down everything you oan remember.',
      'answers': ['Kidneys', 'Ureters', 'Urinary bladder', 'Urethra'],
    },
    {
      'question': 'What triggers micturition?',
      'subtext': 'Explain the nerve pathways involved.',
      'answers': [
        'Stretch receptors in bladder wall',
        'Parasympathetic signals',
        'Relaxation of internal sphincter'
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadNoteForSlide();
  }

  void _loadNoteForSlide() async {
    if (widget.stationDbId == null) return;
    final provider = Provider.of<AppProvider>(context, listen: false);
    final note = await provider.getUserNote(
        'slide', '${widget.stationDbId}_$_currentSlideIndex');
    if (mounted) {
      setState(() {
        _notesController.text = note ?? '';
      });
    }
  }

  void _saveNoteForSlide() {
    if (widget.stationDbId == null) return;
    final provider = Provider.of<AppProvider>(context, listen: false);
    provider.saveUserNote('slide', '${widget.stationDbId}_$_currentSlideIndex',
        _notesController.text.trim());
  }

  void _evaluateSlide(String evaluation) {
    if (widget.stationDbId == null) return;
    final provider = Provider.of<AppProvider>(context, listen: false);
    _saveNoteForSlide();
    provider.updateStationProgress(
        widget.stationDbId!, _currentSlideIndex + 1, evaluation);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          evaluation == 'Good'
              ? 'تم الحفظ: ممتاز! استمر.'
              : evaluation == 'Average'
                  ? 'تم الحفظ: متوسط، راجع لاحقاً.'
                  : 'تم الحفظ: يحتاج مراجعة.',
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  void dispose() {
    _saveNoteForSlide();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    const Color brandColor = Color(0xFF6B4EFF);
    final provider = Provider.of<AppProvider>(context);
    final isDark = provider.isDarkTheme;

    // Fetch question data safely
    final currentDataIndex = _currentSlideIndex % _slidesData.length;
    final slide = _slidesData[currentDataIndex];
    final String currentQuestion = slide['question'];
    final String currentSubtext = slide['subtext'];
    final List<String> currentAnswers = slide['answers'];

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        backgroundColor: isDark ? AppColors.bg : const Color(0xFFF8F9FE),
        body: Column(
          children: [
            // Custom Navigation Header
            Container(
              padding: EdgeInsets.only(
                top: statusBarHeight + 8,
                bottom: 12,
                left: 12,
                right: 12,
              ),
              color: isDark ? AppColors.surface : Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back,
                        color:
                            isDark ? AppColors.text : const Color(0xFF1E1E50)),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.stationName,
                        style: TextStyle(
                          color:
                              isDark ? AppColors.text : const Color(0xFF1E1E50),
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.visibility_outlined,
                          color: brandColor, size: 18),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.help_outline,
                        color: Colors.transparent),
                    onPressed: () {},
                  ), // Balanced spacer matching back button
                ],
              ),
            ),

            // Horizontal Linear Progress Bar below header
            LinearProgressIndicator(
              value: (_currentSlideIndex + 1) / _totalSlidesCount,
              backgroundColor:
                  isDark ? AppColors.surface3 : const Color(0xFFE2E8F0),
              valueColor: const AlwaysStoppedAnimation<Color>(brandColor),
              minHeight: 3,
            ),

            // Main scrollable content
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    const SizedBox(height: 16),

                    // Anatomy Slide Diagram Card (Dark Blue container with Question text built in at the bottom)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: brandColor.withValues(alpha: 0.08),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            const UrinarySystemDiagram(),
                            // Question Section built inside the dark card (No "Question" label as requested)
                            Container(
                              padding: const EdgeInsets.all(20),
                              color: const Color(0xFF0B1120),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          currentQuestion,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          currentSubtext,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.volume_up_outlined,
                                      color: brandColor,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Dot indicators below card
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(6, (index) {
                        final bool isActive = index == (_currentSlideIndex % 6);
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: isActive ? 8 : 6,
                          height: isActive ? 8 : 6,
                          decoration: BoxDecoration(
                            color:
                                isActive ? brandColor : const Color(0xFFE2E8F0),
                            shape: BoxShape.circle,
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 16),

                    // Your Answer Section & Correct Answer Flow
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.surface : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Your Answer',
                              style: TextStyle(
                                color: brandColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            const SizedBox(height: 10),

                            // TextField Container with edit icon on the right
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.surface2
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: isDark
                                        ? AppColors.border
                                        : const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _notesController,
                                      maxLines: 4,
                                      style: TextStyle(
                                          color: isDark
                                              ? AppColors.text
                                              : const Color(0xFF1E1E50),
                                          fontSize: 13),
                                      decoration: InputDecoration(
                                        hintText: 'Write your answer here...',
                                        hintStyle: TextStyle(
                                            color: isDark
                                                ? AppColors.textMuted
                                                : const Color(0xFF9E9EBF),
                                            fontSize: 12),
                                        border: InputBorder.none,
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.edit_outlined,
                                      color: brandColor, size: 18),
                                ],
                              ),
                            ),

                            // DYNAMIC LAYOUT FLOW:
                            // If Answers NOT revealed:
                            if (!_showAnswers) ...[
                              const SizedBox(height: 16),
                              // 1. Show Answer Button
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: brandColor,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    elevation: 0,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _showAnswers = true;
                                    });
                                  },
                                  icon: const Icon(Icons.visibility_outlined,
                                      color: Colors.white, size: 18),
                                  label: const Text(
                                    'Show Answer',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // 2. Look info below button
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.lock_outline,
                                      color: Color(0xFF9E9EBF), size: 12),
                                  SizedBox(width: 4),
                                  Text(
                                    'Answer will be revealed after you click "Show Answer".',
                                    style: TextStyle(
                                      color: Color(0xFF9E9EBF),
                                      fontSize: 10,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            // If Answers ARE revealed (Correct Answer appears ABOVE the button as requested):
                            if (_showAnswers) ...[
                              const SizedBox(height: 20),
                              // 1. Correct Answer Card
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.surface2
                                      : const Color(0xFFF5F3FF),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color:
                                          brandColor.withValues(alpha: 0.15)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: const [
                                        Text(
                                          'Correct Answer',
                                          style: TextStyle(
                                            color: brandColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                        Icon(Icons.visibility_off_outlined,
                                            color: brandColor, size: 16),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    // Bullet points
                                    ...currentAnswers.map((answer) {
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 6.0),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              margin: const EdgeInsets.only(
                                                  top: 6, right: 8),
                                              width: 5,
                                              height: 5,
                                              decoration: const BoxDecoration(
                                                color: brandColor,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                answer,
                                                style: TextStyle(
                                                  color: isDark
                                                      ? AppColors.text
                                                      : const Color(0xFF1E1E50),
                                                  fontSize: 13,
                                                  fontFamily: 'Cairo',
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 16),

                              // 2. Show Answer Button (now below the Correct Answer section)
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                        color: brandColor, width: 1.5),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _showAnswers = false;
                                    });
                                  },
                                  icon: const Icon(
                                      Icons.visibility_off_outlined,
                                      color: brandColor,
                                      size: 18),
                                  label: const Text(
                                    'Hide Answer',
                                    style: TextStyle(
                                      color: brandColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 20),

                              // 3. Self-Evaluation Row (Good, Average, Bad)
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildEvaluationButton(
                                      label: 'Good',
                                      sublabel: 'I knew it well',
                                      icon: Icons
                                          .sentiment_very_satisfied_outlined,
                                      activeColor: Colors.green,
                                      bgColor: const Color(0xFFECFDF5),
                                      onTap: () => _evaluateSlide('Good'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _buildEvaluationButton(
                                      label: 'Average',
                                      sublabel: 'It was okay',
                                      icon: Icons.sentiment_neutral_outlined,
                                      activeColor: Colors.amber.shade700,
                                      bgColor: const Color(0xFFFFFBEB),
                                      onTap: () => _evaluateSlide('Average'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _buildEvaluationButton(
                                      label: 'Bad',
                                      sublabel: "I didn't know it",
                                      icon: Icons
                                          .sentiment_very_dissatisfied_outlined,
                                      activeColor: Colors.red,
                                      bgColor: const Color(0xFFFFF1F2),
                                      onTap: () => _evaluateSlide('Bad'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // Bottom Navigation Row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surface : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 1. Back button card
                  InkWell(
                    onTap: () {
                      if (_currentSlideIndex > 0) {
                        _saveNoteForSlide();
                        setState(() {
                          _currentSlideIndex--;
                          _showAnswers = false; // Reset answer visibility
                        });
                        _loadNoteForSlide();
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.surface2
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.arrow_back,
                          color: isDark
                              ? AppColors.textDim
                              : const Color(0xFF64748B),
                          size: 20),
                    ),
                  ),

                  // 2. Middle Slide Progress Counter (replaces the bookmark icon)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: brandColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_currentSlideIndex + 1} / $_totalSlidesCount',
                      style: const TextStyle(
                        color: brandColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),

                  // 3. Next Button Card with ENLARGED text
                  InkWell(
                    onTap: () {
                      if (_currentSlideIndex < _totalSlidesCount - 1) {
                        _saveNoteForSlide();
                        setState(() {
                          _currentSlideIndex++;
                          _showAnswers = false; // Reset answer visibility
                        });
                        _loadNoteForSlide();
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.surface2
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Next',
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.textDim
                                  : const Color(0xFF64748B),
                              fontWeight: FontWeight.bold,
                              fontSize: 16, // Enlarged font size as requested
                              fontFamily: 'Cairo',
                            ),
                          ),
                          SizedBox(width: 6),
                          Icon(Icons.arrow_forward,
                              color: isDark
                                  ? AppColors.textDim
                                  : const Color(0xFF64748B),
                              size: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper for Self-Evaluation buttons
  Widget _buildEvaluationButton({
    required String label,
    required String sublabel,
    required IconData icon,
    required Color activeColor,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: activeColor.withValues(alpha: 0.3), width: 1.0),
          ),
          child: Column(
            children: [
              Icon(icon, color: activeColor, size: 20),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: activeColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  fontFamily: 'Cairo',
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sublabel,
                style: const TextStyle(
                  color: Color(0xFF9E9EBF),
                  fontSize: 8,
                  fontFamily: 'Cairo',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}









