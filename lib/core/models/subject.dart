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
  /// Returns the question count for a specific university+stage pair.
  /// Sums all entries whose university and stage match the user's profile.
  int questionCountForStageAndUniv(String? userUniv, String? userStage) {
    if (stageQuestionCounts.isEmpty) return totalQuestions;
    final u = (userUniv ?? '').trim().toLowerCase();
    final s = (userStage ?? '').trim().toLowerCase();

    // Direct single exact match fast-path
    if (stageQuestionCounts.containsKey('${userUniv?.trim()}|${userStage?.trim()}')) {
      final exact = stageQuestionCounts['${userUniv?.trim()}|${userStage?.trim()}'];
      // If there are no other multi-stage keys, return exact directly
      if (!stageQuestionCounts.keys.any((k) => k.contains(',') || k.contains('،'))) {
        return exact ?? totalQuestions;
      }
    }

    int matchedCount = 0;
    bool foundAnyMatch = false;

    for (final entry in stageQuestionCounts.entries) {
      final parts = entry.key.split('|');
      final entryUniv = parts.isNotEmpty ? parts[0].trim().toLowerCase() : '';
      final entryStage = parts.length > 1 ? parts[1].trim().toLowerCase() : '';

      final univMatches = _matchesTargetUniv(entryUniv, u);
      final stageMatches = _matchesTargetStage(entryStage, s);

      if (univMatches && stageMatches) {
        matchedCount += entry.value;
        foundAnyMatch = true;
      }
    }

    if (foundAnyMatch) return matchedCount;
    return totalQuestions;
  }

  static bool _matchesTargetUniv(String targetUniv, String userUniv) {
    if (targetUniv.isEmpty || userUniv.isEmpty) return true;
    if (targetUniv == userUniv || targetUniv.contains(userUniv) || userUniv.contains(targetUniv)) {
      return true;
    }
    final parts = targetUniv.split(RegExp(r'[,;/،]')).map((p) => p.trim());
    for (final part in parts) {
      if (part.isNotEmpty && (part == userUniv || part.contains(userUniv) || userUniv.contains(part))) {
        return true;
      }
    }
    return false;
  }

  static bool _matchesTargetStage(String targetStage, String userStage) {
    if (targetStage.isEmpty || userStage.isEmpty) return true;
    if (targetStage == userStage || targetStage.contains(userStage) || userStage.contains(targetStage)) {
      return true;
    }

    const stageKeywords = <int, List<String>>{
      1: ['1', '1st', 'الأولى', 'الاولى', 'first'],
      2: ['2', '2nd', 'الثانية', 'الثانيه', 'second'],
      3: ['3', '3rd', 'الثالثة', 'الثالثه', 'third'],
      4: ['4', '4th', 'الرابعة', 'الرابعه', 'fourth'],
      5: ['5', '5th', 'الخامسة', 'الخامسه', 'fifth'],
      6: ['6', '6th', 'السادسة', 'السادسه', 'sixth'],
    };

    int? userNum;
    for (final entry in stageKeywords.entries) {
      if (entry.value.any((k) => userStage.contains(k))) {
        userNum = entry.key;
        break;
      }
    }

    if (userNum != null) {
      final targetMatchesUserNum = stageKeywords[userNum]!.any((k) => targetStage.contains(k));
      if (targetMatchesUserNum) return true;
    }

    return false;
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
