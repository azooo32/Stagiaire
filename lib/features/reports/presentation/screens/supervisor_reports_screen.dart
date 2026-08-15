import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/models/question.dart';
import '../../../../core/models/question_report.dart';
import '../../../../core/providers/app_provider.dart';
import '../../../../core/services/report_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../practice/presentation/screens/question_viewer_screen.dart';

class SupervisorReportsScreen extends StatefulWidget {
  const SupervisorReportsScreen({super.key});

  @override
  State<SupervisorReportsScreen> createState() =>
      _SupervisorReportsScreenState();
}

class _SupervisorReportsScreenState extends State<SupervisorReportsScreen> {
  final ReportService _service = ReportService();
  late Future<List<QuestionReport>> _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _future = _service.fetchSupervisorReports();
    });
  }

  Future<void> _navigateToQuestion(BuildContext context, int questionId) async {
    final provider = context.read<AppProvider>();
    Question? targetQ;

    // Search in current provider questions list
    for (final q in [...provider.practiceQuestions, ...provider.questions]) {
      if (q.id == questionId) {
        targetQ = q;
        break;
      }
    }

    // If not found, fetch directly from Supabase
    if (targetQ == null) {
      try {
        final res = await SupabaseService()
            .client
            .from('questions')
            .select()
            .eq('id', questionId)
            .maybeSingle();

        if (res != null) {
          targetQ = Question.fromJson(res);
        }
      } catch (_) {}
    }

    if (!context.mounted) return;

    if (targetQ != null) {
      if (targetQ.subject.isNotEmpty &&
          (provider.selectedSubject != targetQ.subject ||
              provider.questions.isEmpty)) {
        await provider.selectSubject(targetQ.subject);
      }
      provider.startPracticeSession([targetQ]);
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const QuestionViewerScreen(initialIndex: 0),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر العثور على السؤال رقم #$questionId',
              style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openReplyDialog(QuestionReport report) {
    final TextEditingController replyController =
        TextEditingController(text: report.reply ?? '');

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF18162B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E1E50);

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: dialogBg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.reply_rounded,
                    color: Color(0xFF8B5CF6), size: 22),
              ),
              const SizedBox(width: 10),
              Text(
                'الرد على ملاحظة الطالب',
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF211E38)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: const Border(
                    right: BorderSide(color: Color(0xFFEF4444), width: 3),
                  ),
                ),
                child: Text(
                  'ملاحظة الطالب: ${report.feedback}',
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'Cairo',
                    color: textColor,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: replyController,
                maxLines: 4,
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: 'Cairo',
                  color: textColor,
                ),
                decoration: InputDecoration(
                  hintText: 'اكتب رد المنصة الرسمية هنا...',
                  hintStyle: TextStyle(
                    fontFamily: 'Cairo',
                    color: isDark
                        ? const Color(0xFF918BAC)
                        : Colors.grey.shade400,
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF211E38)
                      : const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: isDark
                          ? const Color(0xFF3B365C)
                          : Colors.grey.shade300,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: Color(0xFF8B5CF6), width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
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
                backgroundColor: const Color(0xFF8B5CF6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                elevation: 0,
              ),
              onPressed: () async {
                final replyText = replyController.text.trim();
                if (replyText.isEmpty) return;
                Navigator.pop(ctx);
                await _service.sendAdminReply(
                  reportId: report.id,
                  replyText: replyText,
                );
                _refresh();
              },
              child: const Text(
                'إرسال الرد',
                style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF100F1F) : const Color(0xFFF8F9FE);
    final cardBg = isDark ? const Color(0xFF18162B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E1E50);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          elevation: 0,
          title: const Text(
            'لوحة البلاغات والملاحظات (للأدمن)',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontFamily: 'Cairo',
              fontSize: 18,
            ),
          ),
          centerTitle: true,
          backgroundColor:
              isDark ? const Color(0xFF4930B6) : const Color(0xFF5B3EEF),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refresh,
            ),
          ],
        ),
        body: FutureBuilder<List<QuestionReport>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF5B3EEF)),
              );
            }
            final reports = snapshot.data ?? [];
            if (reports.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 64,
                      color: isDark
                          ? const Color(0xFF918BAC)
                          : Colors.grey.shade400,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'لا توجد أي بلاغات حالياً.',
                      style: TextStyle(
                        color: isDark
                            ? const Color(0xFF918BAC)
                            : Colors.grey.shade600,
                        fontFamily: 'Cairo',
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: reports.length,
              itemBuilder: (context, index) {
                final r = reports[index];
                final hasReply = r.reply != null && r.reply!.isNotEmpty;

                return Card(
                  margin: const EdgeInsets.only(bottom: 14),
                  color: cardBg,
                  elevation: isDark ? 0 : 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isDark
                          ? const Color(0xFF3B365C)
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'بلاغ #${r.id} (سؤال #${r.questionId})',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFEF4444),
                                fontFamily: 'Cairo',
                                fontSize: 14,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: hasReply
                                    ? Colors.green.withValues(alpha: 0.12)
                                    : Colors.orange.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                hasReply ? 'تم الرد' : 'معلق',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  color:
                                      hasReply ? Colors.green : Colors.orange,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '💬 الملاحظة: ${r.feedback}',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            color: textColor,
                          ),
                        ),
                        if (hasReply) ...[
                          const SizedBox(height: 6),
                          Text(
                            '🟢 الرد الحالي: ${r.reply}',
                            style: const TextStyle(
                              color: Color(0xFF10B981),
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        // 3 Action Buttons as requested: (1) الذهاب للسؤال (2) الرد (3) تم الحل
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF5B3EEF),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: const Text(
                                'الذهاب للسؤال',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: () =>
                                  _navigateToQuestion(context, r.questionId),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF8B5CF6),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.reply, size: 16),
                              label: Text(
                                hasReply ? 'تعديل الرد' : 'الرد',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: () => _openReplyDialog(r),
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.green,
                                side: const BorderSide(color: Colors.green),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              icon: const Icon(Icons.check_circle, size: 16),
                              label: const Text(
                                'تم الحل',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: () async {
                                await _service.resolveReport(r.id);
                                _refresh();
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
