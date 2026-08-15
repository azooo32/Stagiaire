import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/question_report.dart';

class ReportService {
  final SupabaseClient supabase = Supabase.instance.client;

  /// ① Submit a question report from a student
  Future<bool> submitReport({
    required int questionId,
    required String feedback,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('المستخدم غير مسجل الدخول');

    await supabase.from('question_reports').insert({
      'question_id': questionId,
      'user_id': user.id,
      'feedback': feedback.trim(),
      'created_at': DateTime.now().toIso8601String(),
      'status': 'pending',
      'is_read': false,
    });
    return true;
  }

  /// ② Fetch reports for admin / supervisor
  Future<List<QuestionReport>> fetchSupervisorReports() async {
    try {
      final response = await supabase
          .from('question_reports')
          .select('id, question_id, user_id, feedback, reply, replied_at, status, is_read, created_at, questions(id, question, subject, title, sub_title)')
          .order('created_at', ascending: false);

      final List list = response as List;
      return list.map((item) => QuestionReport.fromMap(item)).toList();
    } catch (e) {
      // Fallback query if join with questions fails or schema differs slightly
      final response = await supabase
          .from('question_reports')
          .select('*')
          .order('created_at', ascending: false);

      final List list = response as List;
      return list.map((item) => QuestionReport.fromMap(item)).toList();
    }
  }

  /// ③ Admin reply to a report
  Future<bool> sendAdminReply({
    required int reportId,
    required String replyText,
  }) async {
    final user = supabase.auth.currentUser;

    await supabase.from('question_reports').update({
      'reply': replyText.trim(),
      'status': 'replied',
      'replied_at': DateTime.now().toIso8601String(),
      'replied_by': user?.id,
      'is_read': false,
    }).eq('id', reportId);

    return true;
  }

  /// ④ Get count of unread admin replies for current student
  Future<int> getUnreadCount() async {
    final user = supabase.auth.currentUser;
    if (user == null) return 0;

    try {
      final response = await supabase
          .from('question_reports')
          .select('id')
          .eq('user_id', user.id)
          .not('reply', 'is', null)
          .or('is_read.is.null,is_read.eq.false');

      final List list = response as List;
      return list.length;
    } catch (_) {
      return 0;
    }
  }

  /// ⑤ Fetch student notifications (replies from platform)
  Future<List<QuestionReport>> fetchStudentNotifications() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    try {
      final response = await supabase
          .from('question_reports')
          .select('id, question_id, user_id, feedback, reply, replied_at, status, is_read, created_at, questions(id, question, subject, title, sub_title)')
          .eq('user_id', user.id)
          .not('reply', 'is', null)
          .order('replied_at', ascending: false);

      final List list = response as List;
      return list.map((item) => QuestionReport.fromMap(item)).toList();
    } catch (e) {
      final response = await supabase
          .from('question_reports')
          .select('*')
          .eq('user_id', user.id)
          .not('reply', 'is', null)
          .order('created_at', ascending: false);

      final List list = response as List;
      return list.map((item) => QuestionReport.fromMap(item)).toList();
    }
  }

  /// ⑥ Mark notification reports as read
  Future<void> markAsRead(List<int> reportIds) async {
    if (reportIds.isEmpty) return;
    try {
      await supabase
          .from('question_reports')
          .update({'is_read': true})
          .filter('id', 'in', reportIds);
    } catch (e) {
      // Ignore batch error or retry individually
      for (final id in reportIds) {
        try {
          await supabase.from('question_reports').update({'is_read': true}).eq('id', id);
        } catch (_) {}
      }
    }
  }

  /// ⑦ Resolve (delete) report
  Future<void> resolveReport(int reportId) async {
    await supabase.from('question_reports').delete().eq('id', reportId);
  }
}
