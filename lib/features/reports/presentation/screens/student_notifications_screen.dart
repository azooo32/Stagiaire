import 'package:flutter/material.dart';
import '../../../../core/models/question_report.dart';
import '../../../../core/services/report_service.dart';

class StudentNotificationsScreen extends StatefulWidget {
  const StudentNotificationsScreen({super.key});

  @override
  State<StudentNotificationsScreen> createState() =>
      _StudentNotificationsScreenState();
}

class _StudentNotificationsScreenState
    extends State<StudentNotificationsScreen> {
  final ReportService _service = ReportService();
  late Future<List<QuestionReport>> _future;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    _future = _service.fetchStudentNotifications().then((list) async {
      final unreadIds =
          list.where((item) => !item.isRead).map((item) => item.id).toList();
      if (unreadIds.isNotEmpty) {
        await _service.markAsRead(unreadIds);
      }
      return list;
    });
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
            'الرسائل والإشعارات',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontFamily: 'Cairo',
              fontSize: 18,
            ),
          ),
          centerTitle: true,
          backgroundColor:
              isDark ? const Color(0xFF4930B6) : const Color(0xFF5B3EEF),
        ),
        body: FutureBuilder<List<QuestionReport>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF5B3EEF)),
              );
            }
            final list = snapshot.data ?? [];
            if (list.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.notifications_none_outlined,
                      size: 64,
                      color: isDark
                          ? const Color(0xFF918BAC)
                          : Colors.grey.shade400,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'لا توجد أي ردود أو إشعارات حالياً.',
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
              itemCount: list.length,
              itemBuilder: (context, index) {
                final item = list[index];

                return Card(
                  margin: const EdgeInsets.only(bottom: 14),
                  color: cardBg,
                  elevation: isDark ? 0 : 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: !item.isRead
                          ? const Color(0xFF8B5CF6)
                          : (isDark
                              ? const Color(0xFF3B365C)
                              : Colors.grey.shade200),
                      width: !item.isRead ? 1.5 : 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.quiz_outlined,
                                  size: 18,
                                  color: isDark
                                      ? const Color(0xFF918BAC)
                                      : const Color(0xFF6B4EFF),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'بلاغ حول سؤال #${item.questionId}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                    color: textColor,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: !item.isRead
                                    ? Colors.red.withValues(alpha: 0.12)
                                    : (isDark
                                        ? const Color(0xFF211E38)
                                        : Colors.grey.shade100),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                !item.isRead ? 'جديد 🔴' : 'تمت القراءة',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  color: !item.isRead
                                      ? Colors.red
                                      : (isDark
                                          ? const Color(0xFF918BAC)
                                          : Colors.grey.shade600),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Student's Feedback
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF211E38)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: const Border(
                              right: BorderSide(
                                  color: Color(0xFFEF4444), width: 3.5),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '💬 ملاحظتك:',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  color: Color(0xFFEF4444),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.feedback,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontFamily: 'Cairo',
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Platform's Reply
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: const Border(
                              right: BorderSide(
                                  color: Color(0xFF10B981), width: 3.5),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '🟢 رد منصة ستاجير:',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  color: Color(0xFF10B981),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.reply ?? '',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Cairo',
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
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
