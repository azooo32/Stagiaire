import 'package:flutter/material.dart';

class PdfLectureRecordingBar extends StatelessWidget {
  final Duration elapsed;
  final bool isPaused;
  final int pageNumber;
  final VoidCallback onPauseResume;
  final VoidCallback onFinish;
  final VoidCallback onCancel;
  final bool isSaving;

  const PdfLectureRecordingBar({
    super.key,
    required this.elapsed,
    required this.isPaused,
    required this.pageNumber,
    required this.onPauseResume,
    required this.onFinish,
    required this.onCancel,
    this.isSaving = false,
  });

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1B2E).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: const Color(0xFFFF3B30).withValues(alpha: 0.4),
            width: 1.5,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55FF3B30),
              blurRadius: 16,
              spreadRadius: 1,
              offset: Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black54,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Pulsing Red Recording Indicator
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isPaused ? Colors.amber : const Color(0xFFFF3B30),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: isPaused
                          ? const Color(0x88FFC107)
                          : const Color(0xAAFF3B30),
                      blurRadius: 6,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // 2. Status & Page Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'ص $pageNumber',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // 3. Timer (LTR for proper digits)
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  _formatDuration(elapsed),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                    letterSpacing: 1.0,
                  ),
                ),
              ),

              const SizedBox(width: 14),

              // 4. Pause / Resume Button
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(
                  isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                tooltip: isPaused ? 'استئناف' : 'إيقاف مؤقت',
                onPressed: isSaving ? null : onPauseResume,
              ),

              const SizedBox(width: 4),

              // 5. Finish & Save Button
              if (isSaving)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF34C759),
                    ),
                  ),
                )
              else
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF34C759),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: const Size(0, 30),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text(
                    'حفظ الشرح',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  onPressed: onFinish,
                ),

              const SizedBox(width: 6),

              // 6. Cancel / Discard Button
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white54,
                  size: 18,
                ),
                tooltip: 'إلغاء التسجيل',
                onPressed: isSaving ? null : onCancel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
