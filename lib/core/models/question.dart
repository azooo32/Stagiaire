int? _safeInt(dynamic val) {
  if (val == null) return null;
  if (val is int) return val;
  if (val is num) return val.toInt();
  return int.tryParse(val.toString());
}

double? _safeDouble(dynamic val) {
  if (val == null) return null;
  if (val is double) return val;
  if (val is num) return val.toDouble();
  return double.tryParse(val.toString());
}

class OptionStats {
  final int count;
  final double percent;

  OptionStats({required this.count, required this.percent});

  factory OptionStats.fromJson(Map<String, dynamic> json) {
    return OptionStats(
      count: _safeInt(json['count']) ?? 0,
      percent: _safeDouble(json['percent']) ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'count': count,
        'percent': percent,
      };
}

class TextFormatRange {
  final int start;
  final int end;
  final String text;

  const TextFormatRange({
    required this.start,
    required this.end,
    required this.text,
  });

  factory TextFormatRange.fromJson(Map<String, dynamic> json) {
    return TextFormatRange(
      start: _safeInt(json['start']) ?? 0,
      end: _safeInt(json['end']) ?? 0,
      text: json['text']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'start': start,
        'end': end,
        'text': text,
      };
}

class AudioHighlight {
  final String text;
  final int start;
  final int length;
  final double audioTime;
  final String elementType;
  final int? optionIndex;
  final String color;

  const AudioHighlight({
    required this.text,
    required this.start,
    required this.length,
    required this.audioTime,
    required this.elementType,
    this.optionIndex,
    required this.color,
  });

  factory AudioHighlight.fromJson(Map<String, dynamic> json) => AudioHighlight(
        text: json['text']?.toString() ?? '',
        start: _safeInt(json['start']) ?? 0,
        length: _safeInt(json['length']) ?? 0,
        audioTime: _safeDouble(json['audioTime']) ?? 0.0,
        elementType: json['elementType']?.toString() ?? 'question',
        optionIndex: _safeInt(json['optionIndex']),
        color: json['color']?.toString() ?? '#ffeb3b',
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'start': start,
        'length': length,
        'audioTime': audioTime,
        'elementType': elementType,
        'optionIndex': optionIndex,
        'color': color,
      };
}

class Question {
  final int id;
  final String text;
  final List<String> options;
  final int correct;
  final String explanation;
  final String subject;
  final String? topic;
  final String? subTopic;
  final String? ref;
  final String? audioUrl;
  final int? audioDurationSeconds;
  final List<AudioHighlight> audioHighlights;
  final List<TextFormatRange> explanationBoldRanges;
  final List<TextFormatRange> explanationUnderlineRanges;
  final String? updatedAt;

  // Local Solve states
  bool isSolved;
  int? userAnswer;

  final Map<int, OptionStats> answersDistribution;

  Question({
    required this.id,
    required this.text,
    required this.options,
    required this.correct,
    required this.explanation,
    required this.subject,
    this.topic,
    this.subTopic,
    this.ref,
    this.audioUrl,
    this.audioDurationSeconds,
    this.audioHighlights = const [],
    this.explanationBoldRanges = const [],
    this.explanationUnderlineRanges = const [],
    this.updatedAt,
    this.isSolved = false,
    this.userAnswer,
    Map<int, OptionStats>? answersDistribution,
  }) : this.answersDistribution = answersDistribution ?? {};

  factory Question.fromJson(Map<String, dynamic> json) {
    final List<String> parsedOptions = [];
    if (json['options'] != null) {
      if (json['options'] is List) {
        parsedOptions.addAll(
            (json['options'] as List).map((e) => e?.toString() ?? ''));
      }
    } else {
      // Read dynamic answer columns from answer_1 to answer_11
      for (int i = 1; i <= 11; i++) {
        final opt = json['answer_$i'];
        if (opt != null && opt.toString().trim().isNotEmpty) {
          parsedOptions.add(opt.toString().trim());
        }
      }
    }

    // correct_answer in DB is 1-based, convert to 0-based index for UI
    final int correctAnswerVal = (_safeInt(json['correct_answer']) ?? 1) - 1;

    // Parse answers distribution
    final Map<int, OptionStats> parsedDistribution = {};
    final rawDist = json['answers_distribution'];
    if (rawDist is Map) {
      rawDist.forEach((key, val) {
        final intIndex = int.tryParse(key.toString());
        if (intIndex != null) {
          if (val is Map<String, dynamic>) {
            parsedDistribution[intIndex] = OptionStats.fromJson(val);
          } else if (val is Map) {
            parsedDistribution[intIndex] =
                OptionStats.fromJson(Map<String, dynamic>.from(val));
          }
        }
      });
    }

    List<TextFormatRange> parseFormatRanges(dynamic raw) {
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((item) =>
                TextFormatRange.fromJson(Map<String, dynamic>.from(item)))
            .where((range) => range.end > range.start && range.text.isNotEmpty)
            .toList();
      }
      return const [];
    }

    List<AudioHighlight> parseAudioHighlights(dynamic raw) {
      if (raw is! List) return const [];
      final highlights = raw
          .whereType<Map>()
          .map((item) =>
              AudioHighlight.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.text.isNotEmpty)
          .toList();
      highlights.sort((a, b) => a.audioTime.compareTo(b.audioTime));
      return highlights;
    }

    return Question(
      id: _safeInt(json['id']) ?? 0,
      text: json['question']?.toString() ?? json['text']?.toString() ?? '',
      options: parsedOptions,
      correct: correctAnswerVal,
      explanation: json['explanation']?.toString() ?? '',
      subject: json['subject']?.toString() ?? '',
      topic: json['title']?.toString() ?? json['topic']?.toString() ?? 'غير محدد',
      subTopic: json['sub_title']?.toString() ?? json['subtopic']?.toString() ?? 'غير محدد',
      ref: json['ref']?.toString() ?? '',
      audioUrl: json['audio_url']?.toString(),
      audioDurationSeconds: _safeInt(json['audio_duration_seconds']),
      audioHighlights: parseAudioHighlights(json['audio_highlights']),
      explanationBoldRanges: parseFormatRanges(json['explanation_bold_ranges']),
      explanationUnderlineRanges:
          parseFormatRanges(json['explanation_underline_ranges']),
      updatedAt: json['updated_at']?.toString(),
      isSolved: json['isSolved'] == true,
      userAnswer: _safeInt(json['userAnswer']),
      answersDistribution: parsedDistribution,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'question': text,
        'options': options,
        'correct_answer': correct + 1,
        'explanation': explanation,
        'subject': subject,
        'title': topic,
        'sub_title': subTopic,
        'ref': ref,
        'audio_url': audioUrl,
        'audio_duration_seconds': audioDurationSeconds,
        'audio_highlights':
            audioHighlights.map((item) => item.toJson()).toList(),
        'explanation_bold_ranges':
            explanationBoldRanges.map((r) => r.toJson()).toList(),
        'explanation_underline_ranges':
            explanationUnderlineRanges.map((r) => r.toJson()).toList(),
        'updated_at': updatedAt,
        'answers_distribution': answersDistribution
            .map((k, v) => MapEntry(k.toString(), v.toJson())),
      };
}
