import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdfrx/pdfrx.dart';
import 'package:zenbox/services/ai.dart';
import 'package:zenbox/models/model.dart';
import 'package:zenbox/models/quiz_model.dart';
import 'package:zenbox/zenbox/reader.dart';

Set<int>? parsePageRange(String? input, int maxPages) {
  if (input == null ||
      input.trim().isEmpty ||
      input.trim().toLowerCase() == 'all') {
    return null;
  }
  final pages = <int>{};
  final parts = input.split(RegExp(r'[,;]'));
  for (final part in parts) {
    final clean = part.trim();
    if (clean.isEmpty) continue;
    if (clean.contains('-')) {
      final sub = clean.split('-');
      if (sub.length == 2) {
        final start = int.tryParse(sub[0].trim());
        final end = int.tryParse(sub[1].trim());
        if (start != null && end != null) {
          final s = math.max(1, math.min(start, end));
          final e = math.min(maxPages, math.max(start, end));
          for (var i = s; i <= e; i++) {
            pages.add(i);
          }
        }
      }
    } else {
      final p = int.tryParse(clean);
      if (p != null && p >= 1 && p <= maxPages) {
        pages.add(p);
      }
    }
  }
  return pages.isEmpty ? null : pages;
}

Future<String> extractQuizSourceText({
  required StudioStore store,
  required CreativeObject object,
  String? pageRange,
}) async {
  final ext =
      object.meta['file']?.toString().split('.').last.toLowerCase() ?? '';
  final filePath = store.mediaPath(object);

  if (ext == 'pdf' && File(filePath).existsSync()) {
    final doc = await PdfDocument.openFile(filePath);
    try {
      final total = doc.pages.length;
      final selectedPages =
          parsePageRange(pageRange, total) ??
          List.generate(math.min(total, 25), (i) => i + 1).toSet();
      final buffer = StringBuffer();
      for (final pNum in (selectedPages.toList()..sort())) {
        if (pNum >= 1 && pNum <= total) {
          final page = doc.pages[pNum - 1];
          final text = await page.loadText();
          final pageText = text?.fullText.trim() ?? '';
          if (pageText.isNotEmpty) {
            buffer.writeln('[Page $pNum]');
            buffer.writeln(pageText);
            buffer.writeln();
          }
        }
      }
      return buffer.toString().trim();
    } finally {
      await doc.dispose();
    }
  }

  if (ext == 'docx' && File(filePath).existsSync()) {
    final blocks = readDocx(await File(filePath).readAsBytes());
    return blocks
        .map((b) => b.text)
        .where((t) => t.trim().isNotEmpty)
        .join('\n\n');
  }

  if (['txt', 'md', 'csv', 'json'].contains(ext) &&
      File(filePath).existsSync()) {
    return await File(filePath).readAsString();
  }

  return object.body.trim();
}

String cleanQuizJsonResponse(String raw) {
  var text = raw.trim();
  final codeBlockRegex = RegExp(
    r'```(?:json)?\s*([\s\S]*?)\s*```',
    caseSensitive: false,
  );
  final match = codeBlockRegex.firstMatch(text);
  if (match != null) {
    text = match.group(1)?.trim() ?? text;
  }
  final firstBrace = text.indexOf('{');
  final lastBrace = text.lastIndexOf('}');
  if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
    text = text.substring(firstBrace, lastBrace + 1).trim();
  }
  return text;
}

QuizData parseAndValidateQuizJson(
  String jsonStr,
  String fallbackTitle,
  String source,
) {
  final cleaned = cleanQuizJsonResponse(jsonStr);
  final decoded = jsonDecode(cleaned);
  if (decoded is! Map) {
    throw const FormatException('Expected JSON object at root.');
  }
  final map = Map<String, dynamic>.from(decoded);
  if (map['quiz_title'] == null ||
      map['quiz_title'].toString().trim().isEmpty) {
    map['quiz_title'] = fallbackTitle;
  }
  map['source'] = source;

  final questions = map['questions'];
  if (questions is! List || questions.isEmpty) {
    throw const FormatException(
      'Quiz must contain at least one question in questions array.',
    );
  }

  final parsedQuestions = <QuizQuestion>[];
  var idCounter = 1;
  for (final item in questions) {
    if (item is! Map) continue;
    final qMap = Map<String, dynamic>.from(item);
    final question = (qMap['question'] as String? ?? '').trim();
    if (question.isEmpty) continue;
    qMap['id'] ??= idCounter++;
    final q = QuizQuestion.fromJson(qMap);
    parsedQuestions.add(q);
  }

  if (parsedQuestions.isEmpty) {
    throw const FormatException('No valid questions found in quiz data.');
  }

  return QuizData(
    quizTitle: map['quiz_title'] as String,
    source: source,
    questions: parsedQuestions,
  );
}

Future<QuizData> generateQuiz({
  required StudioStore store,
  required AiSession session,
  required String sourceTitle,
  required String sourceContent,
  int questionCount = 5,
  String questionType = 'mixed',
  String difficulty = 'medium',
  String? customInstructions,
  void Function(String delta)? onProgress,
}) async {
  if (sourceContent.trim().isEmpty) {
    throw const FormatException(
      'The selected source has no readable content to generate a quiz from.',
    );
  }

  final truncatedContent = sourceContent.length > 18000
      ? '${sourceContent.substring(0, 18000)}\n\n[Content truncated for length]'
      : sourceContent;

  final typeDescription = switch (questionType) {
    'multiple_choice' =>
      'All multiple choice questions (4 distinct options with one correct answer).',
    'true_false' => 'All True/False questions (options: ["True", "False"]).',
    'fill_in_blank' =>
      'All fill-in-the-blank questions (clear question with target term/answer).',
    _ =>
      'A balanced mix of multiple choice, True/False, and fill-in-the-blank questions.',
  };

  final systemPrompt =
      '''You are an expert academic tutor and exam designer.
Your task is to generate a high-quality, comprehensive study quiz strictly based on the provided text.

Return ONLY a valid JSON object matching this schema exactly. Do NOT include markdown code fences, commentary, or text before or after the JSON:
{
  "quiz_title": "Descriptive Quiz Title",
  "source": "$sourceTitle",
  "questions": [
    {
      "id": 1,
      "type": "multiple_choice",
      "question": "Question text here?",
      "options": ["Option A", "Option B", "Option C", "Option D"],
      "correct_answer": "Option A",
      "explanation": "Clear explanation citing facts from the source text."
    }
  ]
}

Specifications:
- Number of questions: exactly $questionCount.
- Format requirement: $typeDescription.
- Difficulty: $difficulty.
- For multiple_choice: include 4 options. correct_answer must match one option exactly.
- For true_false: options must be ["True", "False"], correct_answer must be "True" or "False".
- For fill_in_blank: omit options or provide empty list.
- Provide a helpful, clear explanation for every single question explaining why the correct answer is right.
${customInstructions != null && customInstructions.trim().isNotEmpty ? '- Special instruction: $customInstructions' : ''}''';

  final userPrompt =
      'Generate the quiz for "$sourceTitle" based on the following study text:\n\n$truncatedContent';

  final client = http.Client();
  try {
    final requestBody = {
      'model': store.settings['model'] ?? 'default',
      'stream': false,
      'temperature': 0.3,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
    };

    final request = http.Request('POST', endpoint(store, 'chat/completions'))
      ..headers.addAll(aiHeaders(session))
      ..body = jsonEncode(requestBody);

    final response = await client
        .send(request)
        .timeout(const Duration(minutes: 3));
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode >= 300) {
      throw AiProviderHttpException(response.statusCode, responseBody);
    }

    final decodedResponse = jsonDecode(responseBody);
    final rawText =
        (decodedResponse['choices']?[0]?['message']?['content'] as String? ??
                '')
            .trim();

    try {
      return parseAndValidateQuizJson(
        rawText,
        'Quiz: $sourceTitle',
        sourceTitle,
      );
    } catch (parseError) {
      final repairBody = {
        'model': store.settings['model'] ?? 'default',
        'stream': false,
        'temperature': 0.1,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
          {'role': 'assistant', 'content': rawText},
          {
            'role': 'user',
            'content':
                'Your output was not valid JSON ($parseError). Please return the corrected JSON object now with NO formatting, NO markdown fences, and NO extra words.',
          },
        ],
      };

      final retryRequest =
          http.Request('POST', endpoint(store, 'chat/completions'))
            ..headers.addAll(aiHeaders(session))
            ..body = jsonEncode(repairBody);

      final retryResponse = await client
          .send(retryRequest)
          .timeout(const Duration(minutes: 2));
      final retryResponseBody = await retryResponse.stream.bytesToString();
      final retryDecoded = jsonDecode(retryResponseBody);
      final retryText =
          (retryDecoded['choices']?[0]?['message']?['content'] as String? ?? '')
              .trim();

      return parseAndValidateQuizJson(
        retryText,
        'Quiz: $sourceTitle',
        sourceTitle,
      );
    }
  } finally {
    client.close();
  }
}

CreativeObject saveQuizToProject(
  StudioStore store,
  QuizData quiz, {
  Project? project,
}) {
  final object = CreativeObject(
    kind: 'quiz',
    title: quiz.quizTitle,
    body: quiz.toJsonString(),
    links: [if (quiz.sourceObjectId != null) quiz.sourceObjectId!],
    meta: {
      'source': quiz.source,
      if (quiz.sourceObjectId != null) 'sourceObjectId': quiz.sourceObjectId,
      'questionCount': quiz.questions.length,
      'created': DateTime.now().toIso8601String(),
    },
  );
  (project ?? store.project).objects.add(object);
  store.changed();
  return object;
}

List<CreativeObject> convertQuizToFlashcards(
  StudioStore store,
  QuizData quiz, {
  Project? project,
}) {
  final cards = <CreativeObject>[];
  final deckId = newId();
  final deckTitle = quiz.quizTitle.trim().isEmpty
      ? 'Generated flashcards'
      : quiz.quizTitle.trim();
  final deckDescription = quiz.source.trim().isEmpty
      ? '${quiz.questions.length} cards generated together'
      : '${quiz.questions.length} cards generated from ${quiz.source.trim()}';
  for (final q in quiz.questions) {
    final body = StringBuffer();
    if (q.type == 'multiple_choice' && q.options.isNotEmpty) {
      body.writeln('Options:');
      for (final opt in q.options) {
        body.writeln('- $opt');
      }
      body.writeln();
    }
    body.writeln('Answer: ${q.correctAnswer}');
    if (q.explanation.isNotEmpty) {
      body.writeln('\nExplanation: ${q.explanation}');
    }
    final card = CreativeObject(
      kind: 'card',
      title: q.question,
      links: [if (quiz.sourceObjectId != null) quiz.sourceObjectId!],
      body: body.toString().trim(),
      meta: {
        'source': quiz.quizTitle,
        if (quiz.sourceObjectId != null) 'sourceObjectId': quiz.sourceObjectId,
        'type': q.type,
        'deckId': deckId,
        'deckTitle': deckTitle,
        'deckDescription': deckDescription,
        'generatedAt': DateTime.now().toIso8601String(),
      },
    );
    (project ?? store.project).objects.add(card);
    cards.add(card);
  }
  store.changed();
  return cards;
}

List<CreativeObject> getProjectDocuments(StudioStore store) {
  final docKinds = {
    'scene',
    'beat',
    'chapter',
    'note',
    'script',
    'manuscript',
    'guide',
    'summary',
    'concept',
    'glossary',
    'definition',
    'formula',
    'rule',
    'topic',
    'source',
  };
  const docExtensions = {'pdf', 'docx', 'doc', 'txt', 'md', 'csv', 'json'};

  return store.project.objects.where((o) {
    if (o.kind == 'quiz' ||
        o.kind == 'card' ||
        o.kind == 'board' ||
        o.kind == 'shot') {
      return false;
    }
    if (docKinds.contains(o.kind)) {
      return true;
    }
    if (o.kind == 'asset') {
      final ext =
          o.meta['file']?.toString().split('.').last.toLowerCase() ?? '';
      final mediaType = o.meta['mediaType']?.toString().toLowerCase();
      if (docExtensions.contains(ext) || mediaType == 'document') {
        return true;
      }
    }
    return false;
  }).toList();
}

enum BackgroundQuizStatus { pending, running, completed, failed }

enum StudyToolOutput { quiz, flashcards }

class BackgroundQuizTask {
  BackgroundQuizTask({
    required this.id,
    required this.sourceTitle,
    this.status = BackgroundQuizStatus.pending,
    this.progress = 0.0,
    this.error,
    this.resultQuiz,
    this.savedObject,
    this.savedObjects = const [],
    this.output = StudyToolOutput.quiz,
  });

  final String id;
  final String sourceTitle;
  BackgroundQuizStatus status;
  double progress;
  String? error;
  QuizData? resultQuiz;
  CreativeObject? savedObject;
  List<CreativeObject> savedObjects;
  final StudyToolOutput output;
}

class BackgroundQuizManager {
  BackgroundQuizManager._();
  static final BackgroundQuizManager instance = BackgroundQuizManager._();

  final ValueNotifier<List<BackgroundQuizTask>> tasksNotifier = ValueNotifier(
    [],
  );
  final List<void Function(BackgroundQuizTask)> _completionListeners = [];

  void addCompletionListener(void Function(BackgroundQuizTask) callback) {
    _completionListeners.add(callback);
  }

  void removeCompletionListener(void Function(BackgroundQuizTask) callback) {
    _completionListeners.remove(callback);
  }

  Future<BackgroundQuizTask> startBackgroundGeneration({
    required StudioStore store,
    required AiSession session,
    required CreativeObject sourceObject,
    String? pageRange,
    int questionCount = 5,
    String questionType = 'mixed',
    String difficulty = 'medium',
    String? customInstructions,
    StudyToolOutput output = StudyToolOutput.quiz,
  }) async {
    final task = BackgroundQuizTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      sourceTitle: sourceObject.title.trim().isEmpty
          ? 'Untitled Document'
          : sourceObject.title.trim(),
      status: BackgroundQuizStatus.running,
      output: output,
    );
    tasksNotifier.value = [...tasksNotifier.value, task];

    // Run in background asynchronously without blocking caller
    _executeTask(
      task: task,
      store: store,
      session: session,
      sourceObject: sourceObject,
      pageRange: pageRange,
      questionCount: questionCount,
      questionType: questionType,
      difficulty: difficulty,
      customInstructions: customInstructions,
      output: output,
    );

    return task;
  }

  Future<void> _executeTask({
    required BackgroundQuizTask task,
    required StudioStore store,
    required AiSession session,
    required CreativeObject sourceObject,
    String? pageRange,
    int questionCount = 5,
    String questionType = 'mixed',
    String difficulty = 'medium',
    String? customInstructions,
    StudyToolOutput output = StudyToolOutput.quiz,
  }) async {
    final targetProject = store.project;
    try {
      final sourceText = await extractQuizSourceText(
        store: store,
        object: sourceObject,
        pageRange: pageRange,
      );

      final quiz = await generateQuiz(
        store: store,
        session: session,
        sourceTitle: task.sourceTitle,
        sourceContent: sourceText,
        questionCount: questionCount,
        questionType: questionType,
        difficulty: difficulty,
        customInstructions: customInstructions,
      );

      quiz.sourceObjectId = sourceObject.id;
      final savedObjects = output == StudyToolOutput.flashcards
          ? convertQuizToFlashcards(store, quiz, project: targetProject)
          : [saveQuizToProject(store, quiz, project: targetProject)];
      task.status = BackgroundQuizStatus.completed;
      task.resultQuiz = quiz;
      task.savedObjects = savedObjects;
      task.savedObject = savedObjects.firstOrNull;
      tasksNotifier.value = List.from(tasksNotifier.value);

      for (final listener in List.from(_completionListeners)) {
        try {
          listener(task);
        } catch (_) {}
      }
    } catch (e) {
      task.status = BackgroundQuizStatus.failed;
      task.error = e.toString();
      tasksNotifier.value = List.from(tasksNotifier.value);
    }
  }
}
