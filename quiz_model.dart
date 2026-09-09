import 'dart:convert';

class QuizQuestion {
  QuizQuestion({
    required this.id,
    required this.type,
    required this.question,
    required this.options,
    required this.correctAnswer,
    required this.explanation,
  });

  final int id;

  /// 'multiple_choice', 'true_false', or 'fill_in_blank'
  final String type;
  final String question;
  final List<String> options;
  final String correctAnswer;
  final String explanation;

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    var rawType = (json['type'] as String? ?? 'multiple_choice')
        .trim()
        .toLowerCase();
    if (rawType == 'mcq' || rawType == 'multiple-choice')
      rawType = 'multiple_choice';
    if (rawType == 'tf' || rawType == 'true-false' || rawType == 'true/false')
      rawType = 'true_false';
    if (rawType == 'fill_in_the_blank' ||
        rawType == 'fill-in-the-blank' ||
        rawType == 'blank')
      rawType = 'fill_in_blank';

    final opts = <String>[];
    if (json['options'] is List) {
      for (final opt in json['options'] as List) {
        final s = opt?.toString().trim() ?? '';
        if (s.isNotEmpty) opts.add(s);
      }
    }
    if (rawType == 'true_false' && opts.isEmpty) {
      opts.addAll(['True', 'False']);
    }

    return QuizQuestion(
      id: (json['id'] as num?)?.toInt() ?? 1,
      type: rawType,
      question: (json['question'] as String? ?? '').trim(),
      options: opts,
      correctAnswer: (json['correct_answer'] ?? json['correctAnswer'] ?? '')
          .toString()
          .trim(),
      explanation: (json['explanation'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'question': question,
    if (options.isNotEmpty) 'options': options,
    'correct_answer': correctAnswer,
    'explanation': explanation,
  };

  QuizQuestion copyWith({
    int? id,
    String? type,
    String? question,
    List<String>? options,
    String? correctAnswer,
    String? explanation,
  }) {
    return QuizQuestion(
      id: id ?? this.id,
      type: type ?? this.type,
      question: question ?? this.question,
      options: options ?? List.from(this.options),
      correctAnswer: correctAnswer ?? this.correctAnswer,
      explanation: explanation ?? this.explanation,
    );
  }
}

class QuizData {
  QuizData({
    required this.quizTitle,
    required this.source,
    required this.questions,
    this.difficulty = 'medium',
    this.sourceObjectId,
  });

  String quizTitle;
  String source;
  String? sourceObjectId;
  List<QuizQuestion> questions;
  String difficulty;

  String get title => quizTitle;
  set title(String val) => quizTitle = val;

  String get sourceTitle => source;
  set sourceTitle(String val) => source = val;

  factory QuizData.fromJson(Map<String, dynamic> json) {
    final questionsList = <QuizQuestion>[];
    if (json['questions'] is List) {
      var counter = 1;
      for (final raw in json['questions'] as List) {
        if (raw is Map) {
          final qMap = Map<String, dynamic>.from(raw);
          if (qMap['id'] == null) qMap['id'] = counter++;
          questionsList.add(QuizQuestion.fromJson(qMap));
        }
      }
    }
    return QuizData(
      quizTitle: (json['quiz_title'] ?? json['title'] ?? 'Generated Quiz')
          .toString()
          .trim(),
      source:
          (json['source'] ?? json['source_title'] ?? json['sourceTitle'] ?? '')
              .toString()
              .trim(),
      sourceObjectId: json['sourceObjectId'] as String?,
      questions: questionsList,
      difficulty: (json['difficulty'] ?? 'medium').toString().trim(),
    );
  }

  Map<String, dynamic> toJson() => {
    'quiz_title': quizTitle,
    'source': source,
    if (sourceObjectId != null) 'sourceObjectId': sourceObjectId,
    'questions': questions.map((q) => q.toJson()).toList(),
    'difficulty': difficulty,
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  QuizData copyWith({
    String? quizTitle,
    String? source,
    String? sourceObjectId,
    List<QuizQuestion>? questions,
    String? difficulty,
  }) {
    return QuizData(
      quizTitle: quizTitle ?? this.quizTitle,
      source: source ?? this.source,
      sourceObjectId: sourceObjectId ?? this.sourceObjectId,
      questions: questions ?? List.from(this.questions),
      difficulty: difficulty ?? this.difficulty,
    );
  }
}
