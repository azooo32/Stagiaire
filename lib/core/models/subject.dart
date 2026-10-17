class Subject {
  final int id;
  final String name;
  final String description;
  final int totalQuestions;
  final String? stage;
  final String? university;

  /// Per-(university|stage) question counts from the DB-maintained JSONB column.
  /// Key format: "<university>|<stage>" — empty string for "any".
  /// Example: "كلية طب نينوى|المرحلة الخامسة" → 120
  final Map<String, int> stageQuestionCounts;

  Subject({
    required this.id,
    required this.name,
    required this.description,
    required this.totalQuestions,
    this.stage,
    this.university,
    this.stageQuestionCounts = const {},
  });

  factory Subject.fromJson(Map<String, dynamic> json) {
    Map<String, int> stageCounts = {};
    final raw = json['stage_question_counts'];
    if (raw is Map) {
      raw.forEach((k, v) {
        final count = v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;
        stageCounts[k.toString()] = count;
      });
    }
    return Subject(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      totalQuestions: json['total_questions'] ?? 0,
      stage: json['stage'] as String?,
      university: json['university'] as String?,
      stageQuestionCounts: stageCounts,
    );
  }

  /// Returns the question count for a specific university+stage pair.
  /// Falls back in priority order:
  ///   1. exact match   "univ|stage"
  ///   2. stage only    "|stage"
  ///   3. univ only     "univ|"
  ///   4. global        "|"
  ///   5. totalQuestions
  int questionCountForStageAndUniv(String? userUniv, String? userStage) {
    if (stageQuestionCounts.isEmpty) return totalQuestions;
    final u = (userUniv ?? '').trim();
    final s = (userStage ?? '').trim();

    // 1. exact
    final exact = stageQuestionCounts['$u|$s'];
    if (exact != null) return exact;

    // 2. stage only (univ-agnostic questions)
    if (s.isNotEmpty) {
      final stageOnly = stageQuestionCounts['|$s'];
      if (stageOnly != null) return stageOnly;
    }

    // 3. univ only (stage-agnostic questions)
    if (u.isNotEmpty) {
      final univOnly = stageQuestionCounts['$u|'];
      if (univOnly != null) return univOnly;
    }

    // 4. global
    final global = stageQuestionCounts['|'];
    if (global != null) return global;

    return totalQuestions;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'total_questions': totalQuestions,
        'stage': stage,
        'university': university,
        'stage_question_counts': stageQuestionCounts,
      };
}
