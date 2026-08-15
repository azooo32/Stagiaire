class QuestionReport {
  final int id;
  final int questionId;
  final String userId;
  final String feedback;
  final String? reply;
  final DateTime createdAt;
  final DateTime? repliedAt;
  final bool isRead;
  final String status;
  final Map<String, dynamic>? questionData;

  QuestionReport({
    required this.id,
    required this.questionId,
    required this.userId,
    required this.feedback,
    this.reply,
    required this.createdAt,
    this.repliedAt,
    required this.isRead,
    required this.status,
    this.questionData,
  });

  factory QuestionReport.fromMap(Map<String, dynamic> map) {
    return QuestionReport(
      id: map['id'] is int ? map['id'] : int.parse(map['id'].toString()),
      questionId: map['question_id'] is int
          ? map['question_id']
          : int.parse(map['question_id'].toString()),
      userId: map['user_id']?.toString() ?? '',
      feedback: map['feedback']?.toString() ?? '',
      reply: map['reply']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      repliedAt: map['replied_at'] != null
          ? DateTime.tryParse(map['replied_at'].toString())
          : null,
      isRead: map['is_read'] == true,
      status: map['status']?.toString() ?? 'pending',
      questionData: map['questions'] != null
          ? Map<String, dynamic>.from(map['questions'])
          : null,
    );
  }
}
