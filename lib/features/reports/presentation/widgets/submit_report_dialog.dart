import 'package:flutter/material.dart';
import '../../../../core/services/report_service.dart';

class SubmitReportDialog extends StatefulWidget {
  final int questionId;
  const SubmitReportDialog({super.key, required this.questionId});

  @override
  State<SubmitReportDialog> createState() => _SubmitReportDialogState();
}

class _SubmitReportDialogState extends State<SubmitReportDialog> {
  final TextEditingController _controller = TextEditingController();
  final ReportService _service = ReportService();
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF18162B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E1E50);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF5B3EEF).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.report_problem_outlined, color: Color(0xFF5B3EEF), size: 22),
            ),
            const SizedBox(width: 10),
            Text(
              'إرسال ملاحظة / إبلاغ',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
                color: textColor,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ساعدنا في تحسين المحتوى عبر كتابة ملاحظتك حول هذا السؤال:',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? const Color(0xFF918BAC) : Colors.grey.shade600,
                fontFamily: 'Cairo',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              maxLines: 4,
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'Cairo',
                color: textColor,
              ),
              decoration: InputDecoration(
                hintText: 'اكتب ملاحظتك هنا بالتفصيل...',
                hintStyle: TextStyle(
                  fontFamily: 'Cairo',
                  color: isDark ? const Color(0xFF918BAC) : Colors.grey.shade400,
                  fontSize: 13,
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF211E38) : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF3B365C) : Colors.grey.shade300,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF3B365C) : Colors.grey.shade300,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF5B3EEF), width: 1.5),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'إلغاء',
              style: TextStyle(
                color: isDark ? const Color(0xFF918BAC) : Colors.grey,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5B3EEF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              elevation: 0,
            ),
            onPressed: _isLoading
                ? null
                : () async {
                    final text = _controller.text.trim();
                    if (text.isEmpty) return;
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    setState(() => _isLoading = true);
                    try {
                      await _service.submitReport(
                        questionId: widget.questionId,
                        feedback: text,
                      );
                      if (mounted) {
                        navigator.pop();
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              '✅ تم إرسال البلاغ بنجاح!',
                              style: TextStyle(fontFamily: 'Cairo'),
                            ),
                            backgroundColor: Color(0xFF10B981),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('خطأ: $e', style: const TextStyle(fontFamily: 'Cairo')),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _isLoading = false);
                    }
                  },
            child: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text(
                    'إرسال',
                    style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }
}
