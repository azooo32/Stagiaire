class Subject {
  final int id;
  final String name;
  final String description;
  final int totalQuestions;
  final String? stage;
  final String? university;

  Subject({
    required this.id,
    required this.name,
    required this.description,
    required this.totalQuestions,
    this.stage,
    this.university,
  });

  factory Subject.fromJson(Map<String, dynamic> json) {
    return Subject(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      totalQuestions: json['total_questions'] ?? 0,
      stage: json['stage'] as String?,
      university: json['university'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'total_questions': totalQuestions,
        'stage': stage,
        'university': university,
      };
}
