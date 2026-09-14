import 'package:flutter/material.dart';
import 'package:zenbox/services/ai.dart';
import 'package:zenbox/models/model.dart';
import 'package:zenbox/models/quiz_model.dart';
import 'package:zenbox/services/quiz_service.dart';
import 'package:zenbox/services/notification_service.dart';
import 'package:zenbox/theme/theme.dart';
import 'package:zenbox/widgets/notes_grid_picker.dart';

enum QuizViewStep { configure, generating, playing, summary }

class QuizPlayerWidget extends StatefulWidget {
  const QuizPlayerWidget({
    super.key,
    required this.quiz,
    this.store,
    this.onFinished,
    this.onQuizUpdated,
    this.onClose,
    this.compact = false,
  });

  final QuizData quiz;
  final StudioStore? store;
  final VoidCallback? onFinished;
  final void Function(QuizData updatedQuiz)? onQuizUpdated;
  final VoidCallback? onClose;
  final bool compact;

  @override
  State<QuizPlayerWidget> createState() => _QuizPlayerWidgetState();
}

class _QuizPlayerWidgetState extends State<QuizPlayerWidget> {
  late QuizData quizData;
  int currentQuestionIndex = 0;
  Map<int, String> userAnswers = {};
  Map<int, bool> questionRevealed = {};
  int score = 0;
  bool isCompleted = false;
  final fillBlankController = TextEditingController();
  bool isSaved = false;
  bool isSavedToCards = false;

  @override
  void initState() {
    super.initState();
    quizData = widget.quiz;
  }

  @override
  void didUpdateWidget(covariant QuizPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quiz != widget.quiz) {
      setState(() {
        quizData = widget.quiz;
      });
    }
  }

  @override
  void dispose() {
    fillBlankController.dispose();
    super.dispose();
  }

  void _answerQuestion(String answer) {
    if (quizData.questions.isEmpty) return;
    final q = quizData.questions[currentQuestionIndex];
    if (questionRevealed[q.id] == true) return;

    final isCorrect = _checkAnswer(answer, q);
    setState(() {
      userAnswers[q.id] = answer;
      questionRevealed[q.id] = true;
      if (isCorrect) score++;
    });
  }

  bool _checkAnswer(String answer, QuizQuestion q) {
    final cleanAns = answer.trim().toLowerCase();
    final cleanCorrect = q.correctAnswer.trim().toLowerCase();
    if (cleanAns == cleanCorrect) return true;
    if (q.type == 'multiple_choice') {
      if (cleanAns.length == 1 &&
          cleanAns.codeUnitAt(0) >= 97 &&
          cleanAns.codeUnitAt(0) <= 122) {
        final idx = cleanAns.codeUnitAt(0) - 97;
        if (idx >= 0 && idx < q.options.length) {
          return q.options[idx].trim().toLowerCase() == cleanCorrect;
        }
      }
    }
    return false;
  }

  void _nextQuestion() {
    fillBlankController.clear();
    if (currentQuestionIndex < quizData.questions.length - 1) {
      setState(() => currentQuestionIndex++);
    } else {
      setState(() => isCompleted = true);
      widget.onFinished?.call();
    }
  }

  void _prevQuestion() {
    fillBlankController.clear();
    if (currentQuestionIndex > 0) {
      setState(() => currentQuestionIndex--);
    }
  }

  void _retakeQuiz() {
    setState(() {
      currentQuestionIndex = 0;
      userAnswers = {};
      questionRevealed = {};
      score = 0;
      isCompleted = false;
      fillBlankController.clear();
    });
  }

  void _saveQuiz() {
    if (widget.store == null) return;
    saveQuizToProject(widget.store!, quizData);
    setState(() => isSaved = true);
  }

  void _convertToCards() {
    if (widget.store == null) return;
    convertQuizToFlashcards(widget.store!, quizData);
    setState(() => isSavedToCards = true);
  }

  @override
  Widget build(BuildContext context) {
    if (quizData.questions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.quiz_outlined, size: 36, color: muted),
              const SizedBox(height: 8),
              Text(
                'No questions in this quiz.',
                style: TextStyle(color: muted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (isCompleted) {
      return _buildSummaryView();
    }

    return _buildPlayingView();
  }

  Widget _buildPlayingView() {
    final q = quizData.questions[currentQuestionIndex];
    final answered = questionRevealed[q.id] == true;
    final userAnswer = userAnswers[q.id];
    final isCorrect = userAnswer != null && _checkAnswer(userAnswer, q);
    final progress = (currentQuestionIndex + 1) / quizData.questions.length;
    final isCompact = widget.compact;

    return Column(
      children: [
        LinearProgressIndicator(
          value: progress,
          backgroundColor: paleSage.withValues(alpha: 0.3),
          color: sage,
          minHeight: isCompact ? 3 : 4,
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.all(isCompact ? 14 : 24),
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: paleSage.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      q.type.replaceAll('_', ' ').toUpperCase(),
                      style: TextStyle(
                        fontSize: isCompact ? 9 : 10,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${currentQuestionIndex + 1} / ${quizData.questions.length}',
                    style: TextStyle(
                      fontSize: isCompact ? 11 : 12,
                      color: muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              SizedBox(height: isCompact ? 10 : 16),
              Text(
                q.question,
                style: TextStyle(
                  fontSize: isCompact ? 14 : 17,
                  fontWeight: FontWeight.w700,
                  color: ink,
                  height: 1.35,
                ),
              ),
              SizedBox(height: isCompact ? 14 : 20),

              // Options Area
              if (q.type == 'multiple_choice' || q.type == 'true_false') ...[
                ...q.options.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final opt = entry.value;
                  final isChosen = userAnswer == opt;
                  final isThisOptionCorrect =
                      opt.trim().toLowerCase() ==
                      q.correctAnswer.trim().toLowerCase();

                  Color btnBorder = line;
                  Color btnBg = cream;
                  Widget? trailingIcon;

                  if (answered) {
                    if (isThisOptionCorrect) {
                      btnBg = Colors.green.withValues(alpha: 0.15);
                      btnBorder = Colors.green;
                      trailingIcon = const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 18,
                      );
                    } else if (isChosen) {
                      btnBg = Colors.red.withValues(alpha: 0.15);
                      btnBorder = Colors.red;
                      trailingIcon = const Icon(
                        Icons.cancel,
                        color: Colors.red,
                        size: 18,
                      );
                    }
                  } else if (isChosen) {
                    btnBg = paleSage;
                    btnBorder = sage;
                  }

                  final letter = String.fromCharCode(65 + idx);

                  return Padding(
                    padding: EdgeInsets.only(bottom: isCompact ? 8 : 10),
                    child: InkWell(
                      onTap: answered ? null : () => _answerQuestion(opt),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompact ? 10 : 14,
                          vertical: isCompact ? 10 : 12,
                        ),
                        decoration: BoxDecoration(
                          color: btnBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: btnBorder, width: 1.2),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: isCompact ? 22 : 26,
                              height: isCompact ? 22 : 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: paleSage.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                letter,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: isCompact ? 11 : 12,
                                  color: ink,
                                ),
                              ),
                            ),
                            SizedBox(width: isCompact ? 10 : 12),
                            Expanded(
                              child: Text(
                                opt,
                                style: TextStyle(
                                  fontSize: isCompact ? 12 : 14,
                                  color: ink,
                                  height: 1.3,
                                ),
                              ),
                            ),
                            ?trailingIcon,
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ] else ...[
                // Fill in the blank
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: fillBlankController,
                        enabled: !answered,
                        style: TextStyle(fontSize: isCompact ? 12 : 14),
                        decoration: InputDecoration(
                          hintText: 'Type your answer...',
                          isDense: isCompact,
                          contentPadding: isCompact
                              ? const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onSubmitted: answered
                            ? null
                            : (val) {
                                if (val.trim().isNotEmpty)
                                  _answerQuestion(val.trim());
                              },
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: sage,
                        foregroundColor: cream,
                        visualDensity: isCompact ? VisualDensity.compact : null,
                      ),
                      onPressed: answered
                          ? null
                          : () {
                              if (fillBlankController.text.trim().isNotEmpty) {
                                _answerQuestion(
                                  fillBlankController.text.trim(),
                                );
                              }
                            },
                      child: const Text('Submit'),
                    ),
                  ],
                ),
              ],

              if (answered) ...[
                SizedBox(height: isCompact ? 12 : 18),
                Container(
                  padding: EdgeInsets.all(isCompact ? 10 : 14),
                  decoration: BoxDecoration(
                    color: isCorrect
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isCorrect
                          ? Colors.green.withValues(alpha: 0.4)
                          : Colors.orange.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isCorrect
                                ? Icons.check_circle_outline
                                : Icons.info_outline,
                            color: isCorrect ? Colors.green : Colors.orange,
                            size: isCompact ? 16 : 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              isCorrect
                                  ? 'Correct!'
                                  : 'Answer: ${q.correctAnswer}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: isCorrect
                                    ? Colors.green[800]
                                    : Colors.orange[900],
                                fontSize: isCompact ? 12 : 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (q.explanation.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          q.explanation,
                          style: TextStyle(
                            fontSize: isCompact ? 11 : 12,
                            color: ink,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: isCompact ? 14 : 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (currentQuestionIndex > 0)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: isCompact
                              ? VisualDensity.compact
                              : null,
                        ),
                        onPressed: _prevQuestion,
                        icon: const Icon(Icons.arrow_back, size: 14),
                        label: const Text('Previous'),
                      )
                    else
                      const SizedBox.shrink(),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: sage,
                        foregroundColor: cream,
                        visualDensity: isCompact ? VisualDensity.compact : null,
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompact ? 14 : 20,
                          vertical: isCompact ? 8 : 12,
                        ),
                      ),
                      onPressed: _nextQuestion,
                      icon: Icon(
                        currentQuestionIndex < quizData.questions.length - 1
                            ? Icons.arrow_forward
                            : Icons.flag_outlined,
                        size: 16,
                      ),
                      label: Text(
                        currentQuestionIndex < quizData.questions.length - 1
                            ? 'Next'
                            : 'Results',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryView() {
    final total = quizData.questions.length;
    final percentage = total > 0 ? ((score / total) * 100).round() : 0;
    final isCompact = widget.compact;

    return ListView(
      padding: EdgeInsets.all(isCompact ? 16 : 28),
      children: [
        Center(
          child: Column(
            children: [
              Container(
                width: isCompact ? 60 : 76,
                height: isCompact ? 60 : 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: percentage >= 70
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.orange.withValues(alpha: 0.15),
                  border: Border.all(
                    color: percentage >= 70 ? Colors.green : Colors.orange,
                    width: 2.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$percentage%',
                  style: TextStyle(
                    fontSize: isCompact ? 16 : 20,
                    fontWeight: FontWeight.w800,
                    color: percentage >= 70
                        ? Colors.green[800]
                        : Colors.orange[900],
                  ),
                ),
              ),
              SizedBox(height: isCompact ? 10 : 16),
              Text(
                percentage >= 80
                    ? 'Excellent Work!'
                    : percentage >= 60
                    ? 'Good Effort!'
                    : 'Keep Reviewing!',
                style: TextStyle(
                  fontSize: isCompact ? 16 : 20,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'You scored $score out of $total questions',
                style: TextStyle(fontSize: isCompact ? 12 : 14, color: muted),
              ),
            ],
          ),
        ),
        SizedBox(height: isCompact ? 16 : 24),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                visualDensity: isCompact ? VisualDensity.compact : null,
              ),
              onPressed: _retakeQuiz,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retake Quiz'),
            ),
            if (widget.store != null) ...[
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: isSaved ? Colors.grey : sage,
                  foregroundColor: cream,
                  visualDensity: isCompact ? VisualDensity.compact : null,
                ),
                onPressed: isSaved ? null : _saveQuiz,
                icon: Icon(isSaved ? Icons.check : Icons.save_alt, size: 16),
                label: Text(isSaved ? 'Saved to Project' : 'Save Quiz'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: isCompact ? VisualDensity.compact : null,
                ),
                onPressed: isSavedToCards ? null : _convertToCards,
                icon: Icon(
                  isSavedToCards ? Icons.check : Icons.style_outlined,
                  size: 16,
                ),
                label: Text(
                  isSavedToCards ? 'Created Cards' : 'Convert to Flashcards',
                ),
              ),
            ],
            if (widget.onClose != null)
              TextButton(onPressed: widget.onClose, child: const Text('Close')),
          ],
        ),
        SizedBox(height: isCompact ? 16 : 24),
        Text(
          'Question Breakdown',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: isCompact ? 13 : 15,
            color: ink,
          ),
        ),
        const SizedBox(height: 8),
        ...quizData.questions.asMap().entries.map((entry) {
          final idx = entry.key;
          final q = entry.value;
          final userAns = userAnswers[q.id];
          final correct = userAns != null && _checkAnswer(userAns, q);

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: cream,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: line),
            ),
            child: Padding(
              padding: EdgeInsets.all(isCompact ? 8 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        correct ? Icons.check_circle : Icons.cancel,
                        color: correct ? Colors.green : Colors.red,
                        size: isCompact ? 16 : 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Q${idx + 1}: ${q.question}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: isCompact ? 11 : 13,
                            color: ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!correct) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Your answer: ${userAns ?? "None"} · Correct: ${q.correctAnswer}',
                      style: TextStyle(
                        fontSize: isCompact ? 10 : 11,
                        color: Colors.red[800],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  if (q.explanation.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      q.explanation,
                      style: TextStyle(
                        fontSize: isCompact ? 10 : 11,
                        color: muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

class QuizEditDialog extends StatefulWidget {
  const QuizEditDialog({super.key, required this.quiz});

  final QuizData quiz;

  static Future<QuizData?> show(BuildContext context, QuizData quiz) {
    return showDialog<QuizData>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
          child: QuizEditDialog(quiz: quiz),
        ),
      ),
    );
  }

  @override
  State<QuizEditDialog> createState() => _QuizEditDialogState();
}

class _EditableQuestion {
  int id;
  TextEditingController questionCtrl;
  String type;
  List<TextEditingController> optionCtrls;
  TextEditingController correctAnswerCtrl;
  TextEditingController explanationCtrl;

  _EditableQuestion({
    required this.id,
    required this.questionCtrl,
    required this.type,
    required this.optionCtrls,
    required this.correctAnswerCtrl,
    required this.explanationCtrl,
  });

  void dispose() {
    questionCtrl.dispose();
    for (final c in optionCtrls) {
      c.dispose();
    }
    correctAnswerCtrl.dispose();
    explanationCtrl.dispose();
  }
}

class _QuizEditDialogState extends State<QuizEditDialog> {
  late TextEditingController titleCtrl;
  final List<_EditableQuestion> questions = [];
  int nextId = 100;

  @override
  void initState() {
    super.initState();
    titleCtrl = TextEditingController(text: widget.quiz.quizTitle);
    for (final q in widget.quiz.questions) {
      questions.add(
        _EditableQuestion(
          id: q.id,
          questionCtrl: TextEditingController(text: q.question),
          type: q.type,
          optionCtrls: q.options
              .map((o) => TextEditingController(text: o))
              .toList(),
          correctAnswerCtrl: TextEditingController(text: q.correctAnswer),
          explanationCtrl: TextEditingController(text: q.explanation),
        ),
      );
      if (q.id >= nextId) nextId = q.id + 1;
    }
  }

  @override
  void dispose() {
    titleCtrl.dispose();
    for (final q in questions) {
      q.dispose();
    }
    super.dispose();
  }

  void _addQuestion() {
    setState(() {
      questions.add(
        _EditableQuestion(
          id: nextId++,
          questionCtrl: TextEditingController(text: 'New Question'),
          type: 'multiple_choice',
          optionCtrls: [
            TextEditingController(text: 'Option A'),
            TextEditingController(text: 'Option B'),
            TextEditingController(text: 'Option C'),
            TextEditingController(text: 'Option D'),
          ],
          correctAnswerCtrl: TextEditingController(text: 'Option A'),
          explanationCtrl: TextEditingController(text: 'Explanation here.'),
        ),
      );
    });
  }

  void _removeQuestion(int index) {
    if (questions.length <= 1) return;
    setState(() {
      final removed = questions.removeAt(index);
      removed.dispose();
    });
  }

  void _save() {
    final updatedQuestions = <QuizQuestion>[];
    for (final eq in questions) {
      final qText = eq.questionCtrl.text.trim();
      if (qText.isEmpty) continue;
      final opts = eq.type == 'multiple_choice' || eq.type == 'true_false'
          ? eq.optionCtrls
                .map((c) => c.text.trim())
                .where((t) => t.isNotEmpty)
                .toList()
          : <String>[];
      final corr = eq.correctAnswerCtrl.text.trim();
      final expl = eq.explanationCtrl.text.trim();

      updatedQuestions.add(
        QuizQuestion(
          id: eq.id,
          type: eq.type,
          question: qText,
          options: opts,
          correctAnswer: corr.isEmpty && opts.isNotEmpty ? opts.first : corr,
          explanation: expl,
        ),
      );
    }

    final newTitle = titleCtrl.text.trim().isEmpty
        ? widget.quiz.quizTitle
        : titleCtrl.text.trim();
    final updatedQuiz = widget.quiz.copyWith(
      quizTitle: newTitle,
      questions: updatedQuestions.isEmpty
          ? widget.quiz.questions
          : updatedQuestions,
    );

    Navigator.of(context).pop(updatedQuiz);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: line, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: cream,
              border: Border(bottom: BorderSide(color: line)),
            ),
            child: Row(
              children: [
                Icon(Icons.edit_note, size: 20, color: sage),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Edit Quiz Questions & Options',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: ink,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Quiz Title',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text(
                      'Questions (${questions.length})',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: ink,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: paleSage,
                        foregroundColor: ink,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _addQuestion,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Question'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...questions.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final q = entry.value;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cream,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: paleSage,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Question ${idx + 1}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                  color: ink,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            DropdownButton<String>(
                              value: q.type,
                              isDense: true,
                              items: const [
                                DropdownMenuItem(
                                  value: 'multiple_choice',
                                  child: Text('Multiple Choice'),
                                ),
                                DropdownMenuItem(
                                  value: 'true_false',
                                  child: Text('True / False'),
                                ),
                                DropdownMenuItem(
                                  value: 'fill_in_blank',
                                  child: Text('Fill in Blank'),
                                ),
                              ],
                              onChanged: (val) {
                                if (val == null) return;
                                setState(() {
                                  q.type = val;
                                  if (val == 'true_false') {
                                    q.optionCtrls.clear();
                                    q.optionCtrls.add(
                                      TextEditingController(text: 'True'),
                                    );
                                    q.optionCtrls.add(
                                      TextEditingController(text: 'False'),
                                    );
                                    q.correctAnswerCtrl.text = 'True';
                                  } else if (val == 'multiple_choice' &&
                                      q.optionCtrls.length < 2) {
                                    q.optionCtrls.clear();
                                    q.optionCtrls.add(
                                      TextEditingController(text: 'Option A'),
                                    );
                                    q.optionCtrls.add(
                                      TextEditingController(text: 'Option B'),
                                    );
                                    q.optionCtrls.add(
                                      TextEditingController(text: 'Option C'),
                                    );
                                    q.optionCtrls.add(
                                      TextEditingController(text: 'Option D'),
                                    );
                                    q.correctAnswerCtrl.text = 'Option A';
                                  }
                                });
                              },
                            ),
                            const Spacer(),
                            if (questions.length > 1)
                              IconButton(
                                tooltip: 'Delete question',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () => _removeQuestion(idx),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: q.questionCtrl,
                          decoration: InputDecoration(
                            labelText: 'Question Text',
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Options if multiple choice
                        if (q.type == 'multiple_choice') ...[
                          Text(
                            'Options:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...q.optionCtrls.asMap().entries.map((optEntry) {
                            final oIdx = optEntry.key;
                            final optCtrl = optEntry.value;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Text(
                                    '${String.fromCharCode(65 + oIdx)}.',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: ink,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: optCtrl,
                                      decoration: InputDecoration(
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 8,
                                            ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        q.correctAnswerCtrl.text = optCtrl.text;
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(16),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(
                                        q.correctAnswerCtrl.text == optCtrl.text
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        size: 20,
                                        color:
                                            q.correctAnswerCtrl.text ==
                                                optCtrl.text
                                            ? Colors.green
                                            : muted,
                                      ),
                                    ),
                                  ),
                                  if (q.optionCtrls.length > 2)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                        size: 16,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          q.optionCtrls
                                              .removeAt(oIdx)
                                              .dispose();
                                        });
                                      },
                                    ),
                                ],
                              ),
                            );
                          }),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () {
                              setState(() {
                                q.optionCtrls.add(
                                  TextEditingController(
                                    text:
                                        'Option ${String.fromCharCode(65 + q.optionCtrls.length)}',
                                  ),
                                );
                              });
                            },
                            icon: const Icon(Icons.add, size: 14),
                            label: const Text(
                              'Add Option',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],

                        // True False
                        if (q.type == 'true_false') ...[
                          Row(
                            children: [
                              const Text(
                                'Correct Answer: ',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              ChoiceChip(
                                label: const Text('True'),
                                selected:
                                    q.correctAnswerCtrl.text.toLowerCase() ==
                                    'true',
                                onSelected: (_) => setState(
                                  () => q.correctAnswerCtrl.text = 'True',
                                ),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('False'),
                                selected:
                                    q.correctAnswerCtrl.text.toLowerCase() ==
                                    'false',
                                onSelected: (_) => setState(
                                  () => q.correctAnswerCtrl.text = 'False',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],

                        // Fill in Blank
                        if (q.type == 'fill_in_blank') ...[
                          TextField(
                            controller: q.correctAnswerCtrl,
                            decoration: InputDecoration(
                              labelText: 'Target Correct Answer',
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],

                        TextField(
                          controller: q.explanationCtrl,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'Explanation (Optional)',
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: cream,
              border: Border(top: BorderSide(color: line)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: sage,
                    foregroundColor: cream,
                  ),
                  onPressed: _save,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Save Changes'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FlashcardFlipWidget extends StatefulWidget {
  const FlashcardFlipWidget({
    super.key,
    required this.card,
    this.compact = false,
    this.currentIndex,
    this.totalCount,
    this.onPrevious,
    this.onNext,
  });

  final CreativeObject card;
  final bool compact;
  final int? currentIndex;
  final int? totalCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  State<FlashcardFlipWidget> createState() => _FlashcardFlipWidgetState();
}

class _FlashcardFlipWidgetState extends State<FlashcardFlipWidget> {
  bool isFlipped = false;

  @override
  void didUpdateWidget(covariant FlashcardFlipWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.id != widget.card.id) {
      setState(() => isFlipped = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = widget.compact;
    return InkWell(
      onTap: () => setState(() => isFlipped = !isFlipped),
      child: Container(
        color: cream,
        padding: EdgeInsets.all(isCompact ? 14 : 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isFlipped ? paleSage : sage.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isFlipped ? 'ANSWER / BACK' : 'QUESTION / FRONT',
                    style: TextStyle(
                      fontSize: isCompact ? 9 : 10,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ),
                if (widget.currentIndex != null && widget.totalCount != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: paper,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: line),
                    ),
                    child: Text(
                      '${widget.currentIndex! + 1} / ${widget.totalCount}',
                      style: TextStyle(
                        fontSize: isCompact ? 9 : 10,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(Icons.flip, size: isCompact ? 14 : 18, color: muted),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          isFlipped ? 'Tap to see question' : 'Tap to reveal answer',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: isCompact ? 9 : 11, color: muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: (widget.onPrevious != null || widget.onNext != null) ? 36 : 12,
                      ),
                      child: isFlipped
                          ? Text(
                              widget.card.body.trim().isEmpty
                                  ? 'No answer provided.'
                                  : widget.card.body,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: isCompact ? 13 : 16,
                                color: ink,
                                height: 1.4,
                              ),
                            )
                          : Text(
                              widget.card.title.trim().isEmpty
                                  ? 'Untitled Card'
                                  : widget.card.title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: isCompact ? 15 : 18,
                                fontWeight: FontWeight.w700,
                                color: ink,
                                height: 1.35,
                              ),
                            ),
                    ),
                  ),
                  if (widget.onPrevious != null)
                    Positioned(
                      left: 0,
                      child: IconButton(
                        tooltip: 'Previous card',
                        icon: const Icon(Icons.chevron_left),
                        onPressed: widget.onPrevious,
                      ),
                    ),
                  if (widget.onNext != null)
                    Positioned(
                      right: 0,
                      child: IconButton(
                        tooltip: 'Next card',
                        icon: const Icon(Icons.chevron_right),
                        onPressed: widget.onNext,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                isFlipped
                    ? '↻ Click anywhere to flip back'
                    : '↷ Click anywhere to flip',
                style: TextStyle(fontSize: isCompact ? 9 : 10, color: muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FlashcardDeckModal extends StatefulWidget {
  const FlashcardDeckModal({
    super.key,
    required this.cards,
    required this.store,
    this.initialIndex = 0,
    this.onPopOut,
  });

  final List<CreativeObject> cards;
  final StudioStore store;
  final int initialIndex;
  final VoidCallback? onPopOut;

  static Future<void> show(
    BuildContext context, {
    required List<CreativeObject> cards,
    required StudioStore store,
    int initialIndex = 0,
    VoidCallback? onPopOut,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: Colors.transparent,
        child: FlashcardDeckModal(
          cards: cards,
          store: store,
          initialIndex: initialIndex,
          onPopOut: onPopOut,
        ),
      ),
    );
  }

  @override
  State<FlashcardDeckModal> createState() => _FlashcardDeckModalState();
}

class _FlashcardDeckModalState extends State<FlashcardDeckModal> {
  late int currentIndex;
  late List<CreativeObject> cardList;
  bool isFlipped = false;

  @override
  void initState() {
    super.initState();
    cardList = List.from(widget.cards);
    currentIndex = widget.initialIndex.clamp(0, cardList.isEmpty ? 0 : cardList.length - 1);
  }

  void nextCard() {
    if (currentIndex < cardList.length - 1) {
      setState(() {
        currentIndex++;
        isFlipped = false;
      });
    }
  }

  void previousCard() {
    if (currentIndex > 0) {
      setState(() {
        currentIndex--;
        isFlipped = false;
      });
    }
  }

  void shuffleCards() {
    setState(() {
      cardList.shuffle();
      currentIndex = 0;
      isFlipped = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (cardList.isEmpty) {
      return Container(
        width: 420,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: paper,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: line),
        ),
        child: const Center(child: Text('No flashcards in this deck.')),
      );
    }

    final card = cardList[currentIndex];
    final deckTitle = card.meta['deckTitle']?.toString().isNotEmpty == true
        ? card.meta['deckTitle'].toString()
        : card.meta['source']?.toString().isNotEmpty == true
        ? card.meta['source'].toString()
        : card.meta['deck']?.toString().isNotEmpty == true
        ? card.meta['deck'].toString()
        : 'Flashcard Deck';

    return Container(
      width: 640,
      height: 480,
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: cream,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
              border: Border(bottom: BorderSide(color: line)),
            ),
            child: Row(
              children: [
                Icon(Icons.style_outlined, size: 18, color: gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    deckTitle,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: paper,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: line),
                  ),
                  child: Text(
                    '${currentIndex + 1} of ${cardList.length}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.onPopOut != null)
                  IconButton(
                    tooltip: 'Pop out in floating window',
                    icon: const Icon(Icons.picture_in_picture_alt, size: 18),
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onPopOut!();
                    },
                  ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Progress Bar
          LinearProgressIndicator(
            value: (currentIndex + 1) / cardList.length,
            backgroundColor: cream,
            valueColor: AlwaysStoppedAnimation<Color>(gold),
            minHeight: 3,
          ),
          // Body Flip Card
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => isFlipped = !isFlipped),
                child: Container(
                  decoration: BoxDecoration(
                    color: cream.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: line),
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: isFlipped ? paleSage : gold.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isFlipped ? 'ANSWER / BACK' : 'QUESTION / FRONT',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: ink,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Icon(Icons.flip, size: 16, color: muted),
                          const SizedBox(width: 4),
                          Text(
                            isFlipped ? 'Click to show question' : 'Click to reveal answer',
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Center(
                          child: SingleChildScrollView(
                            child: Text(
                              isFlipped
                                  ? (card.body.trim().isEmpty ? 'No answer provided.' : card.body)
                                  : (card.title.trim().isEmpty ? 'Untitled Question' : card.title),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: isFlipped ? 15 : 17,
                                fontWeight: isFlipped ? FontWeight.normal : FontWeight.w700,
                                color: ink,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: Text(
                          isFlipped ? '↻ Tap card to flip back' : '↷ Tap card to flip',
                          style: TextStyle(fontSize: 10, color: muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Footer Navigation Controls
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: cream.withValues(alpha: 0.5),
              border: Border(top: BorderSide(color: line)),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: shuffleCards,
                  icon: const Icon(Icons.shuffle, size: 15),
                  label: const Text('Shuffle', style: TextStyle(fontSize: 11)),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: currentIndex > 0 ? previousCard : null,
                  icon: const Icon(Icons.arrow_back, size: 15),
                  label: const Text('Previous', style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: ink),
                  onPressed: currentIndex < cardList.length - 1 ? nextCard : null,
                  icon: const Icon(Icons.arrow_forward, size: 15),
                  label: Text(
                    currentIndex == cardList.length - 1 ? 'Finished' : 'Next',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class QuizModal extends StatefulWidget {
  const QuizModal({
    super.key,
    required this.store,
    required this.session,
    this.initialSource,
    this.initialOutput = StudyToolOutput.quiz,
    this.existingQuiz,
  });

  final StudioStore store;
  final AiSession session;
  final CreativeObject? initialSource;
  final StudyToolOutput initialOutput;
  final QuizData? existingQuiz;

  static Future<void> show(
    BuildContext context, {
    required StudioStore store,
    required AiSession session,
    CreativeObject? initialSource,
    StudyToolOutput initialOutput = StudyToolOutput.quiz,
    QuizData? existingQuiz,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860, maxHeight: 780),
          child: QuizModal(
            store: store,
            session: session,
            initialSource: initialSource,
            initialOutput: initialOutput,
            existingQuiz: existingQuiz,
          ),
        ),
      ),
    );
  }

  @override
  State<QuizModal> createState() => _QuizModalState();
}

class _QuizModalState extends State<QuizModal> {
  late QuizViewStep step;
  CreativeObject? selectedSource;
  final pageRangeController = TextEditingController();
  final customInstructionController = TextEditingController();

  int questionCount = 5;
  String questionType = 'mixed';
  String difficulty = 'medium';
  StudyToolOutput output = StudyToolOutput.quiz;

  QuizData? quizData;
  String? generationError;
  String generationProgress = 'Connecting to local AI...';

  @override
  void initState() {
    super.initState();
    output = widget.initialOutput;
    if (widget.existingQuiz != null) {
      quizData = widget.existingQuiz;
      step = QuizViewStep.playing;
    } else {
      step = QuizViewStep.configure;
      selectedSource = widget.initialSource ?? _findDefaultSource();
    }
  }

  @override
  void dispose() {
    pageRangeController.dispose();
    customInstructionController.dispose();
    super.dispose();
  }

  CreativeObject? _findDefaultSource() {
    final candidates = getProjectDocuments(widget.store);
    return candidates.isNotEmpty ? candidates.first : null;
  }

  bool _isPdf(CreativeObject? o) {
    if (o == null) return false;
    final ext = o.meta['file']?.toString().split('.').last.toLowerCase() ?? '';
    return ext == 'pdf';
  }

  Future<void> _openNotesGridDialog(List<CreativeObject> sources) async {
    final picked = await showDialog<CreativeObject>(
      context: context,
      builder: (context) => NotesGridPickerModal(
        sources: sources,
        initialSelection: selectedSource,
        isPdf: _isPdf,
      ),
    );
    if (picked != null && mounted) {
      setState(() => selectedSource = picked);
    }
  }

  void _startBackgroundGeneration() {
    if (selectedSource == null) return;
    BackgroundQuizManager.instance.startBackgroundGeneration(
      store: widget.store,
      session: widget.session,
      sourceObject: selectedSource!,
      pageRange: pageRangeController.text.trim(),
      questionCount: questionCount,
      questionType: questionType,
      difficulty: difficulty,
      customInstructions: customInstructionController.text.trim(),
      output: output,
    );
    Navigator.of(context).pop();
    TopNotification.show(
      context,
      'Generating ${output == StudyToolOutput.quiz ? 'a quiz' : 'flashcards'} from "${selectedSource!.title}" in the background…',
      icon: output == StudyToolOutput.quiz
          ? Icons.quiz_outlined
          : Icons.style_outlined,
      duration: const Duration(seconds: 4),
    );
  }

  Future<void> _startGeneration() async {
    if (selectedSource == null) return;
    setState(() {
      step = QuizViewStep.generating;
      generationError = null;
      generationProgress = 'Extracting source text...';
    });

    try {
      final text = await extractQuizSourceText(
        store: widget.store,
        object: selectedSource!,
        pageRange: pageRangeController.text.trim(),
      );

      if (text.trim().isEmpty) {
        throw const FormatException(
          'The selected source contains no readable text.',
        );
      }

      setState(() {
        generationProgress = 'Generating quiz with local AI...';
      });

      final generated = await generateQuiz(
        store: widget.store,
        session: widget.session,
        sourceTitle: selectedSource!.title,
        sourceContent: text,
        questionCount: questionCount,
        questionType: questionType,
        difficulty: difficulty,
        customInstructions: customInstructionController.text.trim(),
      );

      if (!mounted) return;
      if (output == StudyToolOutput.flashcards) {
        final cards = convertQuizToFlashcards(widget.store, generated);
        Navigator.of(context).pop();
        TopNotification.show(
          context,
          '${cards.length} flashcards generated in “${generated.quizTitle}”.',
          icon: Icons.check_circle_outline,
        );
        return;
      }
      setState(() {
        quizData = generated;
        step = QuizViewStep.playing;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        generationError = e.toString();
        step = QuizViewStep.configure;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: line, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: ink.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: switch (step) {
              QuizViewStep.configure => _buildConfigureView(),
              QuizViewStep.generating => _buildGeneratingView(),
              QuizViewStep.playing || QuizViewStep.summary => QuizPlayerWidget(
                quiz: quizData!,
                store: widget.store,
                onClose: () => Navigator.of(context).pop(),
              ),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: cream,
        border: Border(bottom: BorderSide(color: line)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: paleSage.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.quiz_outlined, size: 20, color: sage),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quizData?.quizTitle ?? 'Quiz & Flashcard Generator',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  step == QuizViewStep.playing
                      ? 'Study & Practice · Local AI'
                      : 'Create a quiz or a grouped flashcard deck from your notes and PDFs',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigureView() {
    // Keep source selection focused: learners choose their notes or an
    // existing flashcard deck instead of navigating every project object.
    final availableSources = widget.store.project.objects
        .where((o) => {'note', 'script', 'manuscript', 'card'}.contains(o.kind))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (generationError != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    generationError!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

        Text(
          '1. Choose Output',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: ink,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<StudyToolOutput>(
          segments: const [
            ButtonSegment(
              value: StudyToolOutput.quiz,
              icon: Icon(Icons.quiz_outlined, size: 17),
              label: Text('Interactive Quiz'),
            ),
            ButtonSegment(
              value: StudyToolOutput.flashcards,
              icon: Icon(Icons.style_outlined, size: 17),
              label: Text('Flashcard Deck'),
            ),
          ],
          selected: {output},
          onSelectionChanged: (value) => setState(() => output = value.first),
        ),
        const SizedBox(height: 22),
        Text(
          '2. Choose Study Source (Current Project)',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: ink,
          ),
        ),
        const SizedBox(height: 8),
        Builder(
          builder: (context) {
            final hasMore = availableSources.length > 10;
            final displayedSources = <CreativeObject>[];
            if (selectedSource != null && !availableSources.take(10).contains(selectedSource)) {
              displayedSources.add(selectedSource!);
              displayedSources.addAll(
                availableSources.where((s) => s.id != selectedSource!.id).take(9),
              );
            } else {
              displayedSources.addAll(availableSources.take(10));
            }

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: cream,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: line),
              ),
              child: availableSources.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No notes or documents in this project yet.',
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<CreativeObject?>(
                              isExpanded: true,
                              value: displayedSources.contains(selectedSource)
                                  ? selectedSource
                                  : null,
                              hint: const Text('Select a note or flashcard…'),
                              items: [
                                ...displayedSources.map((o) {
                                  final isPdf = _isPdf(o);
                                  final icon = isPdf
                                      ? Icons.picture_as_pdf_outlined
                                      : [
                                          'concept',
                                          'definition',
                                          'formula',
                                        ].contains(o.kind)
                                      ? Icons.lightbulb_outline
                                      : Icons.description_outlined;
                                  return DropdownMenuItem<CreativeObject?>(
                                    value: o,
                                    child: Row(
                                      children: [
                                        Icon(icon, size: 16, color: sage),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            o.title.isEmpty
                                                ? 'Untitled ${o.kind}'
                                                : o.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          ' (${o.kind})',
                                          style: TextStyle(fontSize: 11, color: muted),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                                if (hasMore)
                                  DropdownMenuItem<CreativeObject?>(
                                    value: null,
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.grid_view_rounded,
                                          size: 16,
                                          color: gold,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          'See more… (${availableSources.length} in grid)',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: gold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                              onChanged: (o) {
                                if (o == null) {
                                  _openNotesGridDialog(availableSources);
                                } else {
                                  setState(() => selectedSource = o);
                                }
                              },
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Browse all in grid view',
                          icon: const Icon(Icons.grid_view_rounded, size: 18),
                          onPressed: () => _openNotesGridDialog(availableSources),
                        ),
                      ],
                    ),
            );
          },
        ),

        if (_isPdf(selectedSource)) ...[
          const SizedBox(height: 14),
          TextField(
            controller: pageRangeController,
            decoration: InputDecoration(
              labelText: 'PDF Page Range (Optional)',
              hintText: 'e.g. 4-9 or 1, 3, 5-7 (Leave blank for whole file)',
              prefixIcon: const Icon(Icons.auto_stories_outlined, size: 18),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],

        const SizedBox(height: 22),
        Text(
          '3. Number of ${output == StudyToolOutput.quiz ? 'Questions' : 'Cards'}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: ink,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          children: [3, 5, 10, 15].map((count) {
            final isSelected = questionCount == count;
            return ChoiceChip(
              label: Text(
                '$count ${output == StudyToolOutput.quiz ? 'Questions' : 'Cards'}',
              ),
              selected: isSelected,
              selectedColor: paleSage,
              onSelected: (_) => setState(() => questionCount = count),
            );
          }).toList(),
        ),

        const SizedBox(height: 22),
        Text(
          '4. Question Format',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: ink,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          children:
              [
                ('mixed', 'Mixed Format'),
                ('multiple_choice', 'Multiple Choice (MCQ)'),
                ('true_false', 'True / False'),
                ('fill_in_blank', 'Fill in the Blank'),
              ].map((item) {
                final isSelected = questionType == item.$1;
                return ChoiceChip(
                  label: Text(item.$2),
                  selected: isSelected,
                  selectedColor: paleSage,
                  onSelected: (_) => setState(() => questionType = item.$1),
                );
              }).toList(),
        ),

        const SizedBox(height: 22),
        Text(
          '5. Difficulty Level',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: ink,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          children: ['easy', 'medium', 'hard'].map((diff) {
            final isSelected = difficulty == diff;
            return ChoiceChip(
              label: Text(diff[0].toUpperCase() + diff.substring(1)),
              selected: isSelected,
              selectedColor: paleSage,
              onSelected: (_) => setState(() => difficulty = diff),
            );
          }).toList(),
        ),

        const SizedBox(height: 22),
        Text(
          '6. Custom Focus & Instructions (Optional)',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: ink,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: customInstructionController,
          maxLines: 2,
          decoration: InputDecoration(
            hintText:
                'e.g. "Focus on definitions and formulas only", "Make it exam-style", "Include tricky questions"',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),

        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: ink,
                side: BorderSide(color: sage),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              onPressed: selectedSource != null
                  ? _startBackgroundGeneration
                  : null,
              icon: const Icon(Icons.schedule, size: 18),
              label: Text(
                output == StudyToolOutput.quiz
                    ? 'Quiz in Background'
                    : 'Cards in Background',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: sage,
                foregroundColor: cream,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
              ),
              onPressed: selectedSource != null ? _startGeneration : null,
              icon: Icon(
                output == StudyToolOutput.quiz
                    ? Icons.play_arrow
                    : Icons.style_outlined,
                size: 18,
              ),
              label: Text(
                output == StudyToolOutput.quiz
                    ? 'Generate & Play Now'
                    : 'Generate Cards Now',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGeneratingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 54,
              height: 54,
              child: CircularProgressIndicator(strokeWidth: 3.5, color: sage),
            ),
            const SizedBox(height: 24),
            Text(
              generationProgress,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Synthesizing key concepts from ${selectedSource?.title ?? "source"}...',
              style: TextStyle(color: muted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
