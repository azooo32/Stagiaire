import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/models/question.dart';
import '../../../../core/models/question_report.dart';
import '../../../../core/providers/app_provider.dart';
import '../../../../core/services/report_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../practice/presentation/screens/question_viewer_screen.dart';

class AdminReportsCard extends StatefulWidget {
  const AdminReportsCard({super.key});

  @override
  State<AdminReportsCard> createState() => _AdminReportsCardState();
}

class _AdminReportsCardState extends State<AdminReportsCard> {
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

    for (final q in [...provider.practiceQuestions, ...provider.questions]) {
      if (q.id == questionId) {
        targetQ = q;
        break;
      }
    }

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
      provider.startPracticeSession([targetQ]);
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
    final cardBg = isDark ? const Color(0xFF18162B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E1E50);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? const Color(0xFF3B365C)
                : const Color(0xFFE2E2E9),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.report_problem_outlined,
                          color: Colors.red,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'بلاغات الأسئلة (للأدمن والمشرفين)',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'Cairo',
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: _refresh,
                    tooltip: 'تحديث البلاغات',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Scrollable Content Box
            FutureBuilder<List<QuestionReport>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    height: 120,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(color: Color(0xFF5B3EEF)),
                  );
                }

                final reports = snapshot.data ?? [];
                if (reports.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Center(
                      child: Text(
                        '🎉 لا توجد أي بلاغات معلقة حالياً.',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          color: isDark
                              ? const Color(0xFF918BAC)
                              : Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                }

                return SizedBox(
                  height: 230,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: reports.length,
                    itemBuilder: (context, index) {
                      final r = reports[index];
                      final hasReply = r.reply != null && r.reply!.isNotEmpty;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF211E38)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF3B365C)
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'بلاغ #${r.id} | سؤال #${r.questionId}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: hasReply
                                        ? Colors.green.withValues(alpha: 0.12)
                                        : Colors.orange.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    hasReply ? 'تم الرد' : 'معلق',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                      color: hasReply
                                          ? Colors.green
                                          : Colors.orange,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '💬 ${r.feedback}',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                color: textColor,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (hasReply) ...[
                              const SizedBox(height: 2),
                              Text(
                                '🟢 الرد: ${r.reply}',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 8),
                            // 3 Action Buttons: الذهاب للسؤال | الرد | تم الحل
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                InkWell(
                                  onTap: () =>
                                      _navigateToQuestion(context, r.questionId),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF5B3EEF),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.open_in_new,
                                            size: 12, color: Colors.white),
                                        SizedBox(width: 4),
                                        Text(
                                          'الذهاب للسؤال',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontFamily: 'Cairo',
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => _openReplyDialog(r),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF8B5CF6),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.reply,
                                            size: 12, color: Colors.white),
                                        const SizedBox(width: 4),
                                        Text(
                                          hasReply ? 'تعديل الرد' : 'الرد',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontFamily: 'Cairo',
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () async {
                                    await _service.resolveReport(r.id);
                                    _refresh();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.green),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.check_circle_outline,
                                            size: 12, color: Colors.green),
                                        SizedBox(width: 4),
                                        Text(
                                          'تم الحل',
                                          style: TextStyle(
                                            color: Colors.green,
                                            fontSize: 11,
                                            fontFamily: 'Cairo',
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
