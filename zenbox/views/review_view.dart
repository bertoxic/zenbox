import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zenbox/models/zenbox_model.dart';
import 'package:zenbox/theme/zenbox_theme.dart';
import 'package:zenbox/services/notification_service.dart';
import 'practice_exam_view.dart';

class ReviewView extends StatefulWidget {
  const ReviewView({super.key, required this.store});
  final ZenboxStore store;
  @override
  State<ReviewView> createState() => _ReviewViewState();
}

class _ReviewViewState extends State<ReviewView> {
  bool revealed = false;
  int reviewed = 0;
  bool practice = false;
  int practiceIndex = 0;
  final started = DateTime.now();
  List<Flashcard> get cards =>
      (practice ? widget.store.flashcards : widget.store.dueCards)
          .where(
            (c) =>
                widget.store.activeCourseId == null ||
                c.courseId == widget.store.activeCourseId,
          )
          .toList();
  void rate(ReviewRating rating) {
    final queue = cards;
    if (queue.isEmpty) return;
    widget.store.reviewCard(
      queue[practice ? practiceIndex % queue.length : 0],
      rating,
    );
    setState(() {
      reviewed++;
      revealed = false;
      if (practice) practiceIndex++;
    });
  }

  Future<void> add() async {
    final question = TextEditingController(), answer = TextEditingController();
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create a recall card'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: question,
                decoration: const InputDecoration(labelText: 'Question'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: answer,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Answer'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create card'),
          ),
        ],
      ),
    );
    if (yes == true &&
        question.text.trim().isNotEmpty &&
        answer.text.trim().isNotEmpty) {
      widget.store.addFlashcard(
        Flashcard(
          courseId: widget.store.activeCourseId ?? '',
          question: question.text.trim(),
          answer: answer.text.trim(),
        ),
      );
      setState(() => revealed = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final queue = cards;
      final card = queue.isEmpty
          ? null
          : queue[practice ? practiceIndex % queue.length : 0];
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): () =>
              setState(() => revealed = !revealed),
          for (var i = 0; i < 4; i++)
            SingleActivator(
              [
                LogicalKeyboardKey.digit1,
                LogicalKeyboardKey.digit2,
                LogicalKeyboardKey.digit3,
                LogicalKeyboardKey.digit4,
              ][i],
            ): () {
              if (revealed) rate(ReviewRating.values[i]);
            },
        },
        child: Focus(
          autofocus: true,
          child: ListView(
            padding: const EdgeInsets.all(28),
            children: [
              zenHeading(
                'Active Recall & Spaced Review',
                'Recall, compare, and rate your understanding honestly.',
                action: IconButton(
                  tooltip: 'Create card',
                  onPressed: add,
                  icon: const Icon(Icons.add),
                ),
              ),
              Wrap(
                spacing: 12,
                children: [
                  ActionChip(label:const Text('Practice exam'),avatar:const Icon(Icons.quiz_outlined,size:16),onPressed:()=>showDialog<void>(context:context,builder:(context)=>Dialog(insetPadding:const EdgeInsets.all(32),child:SizedBox(width:850,height:800,child:Column(children:[Align(alignment:Alignment.centerRight,child:IconButton(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.close))),Expanded(child:PracticeExamView(store:widget.store))]))))),
                  FilterChip(
                    label: const Text('Due today'),
                    selected: !practice,
                    onSelected: (_) => setState(() {
                      practice = false;
                      revealed = false;
                    }),
                  ),
                  FilterChip(
                    label: const Text('Practice all'),
                    selected: practice,
                    onSelected: (_) => setState(() {
                      practice = true;
                      revealed = false;
                    }),
                  ),
                  Chip(
                    label: Text(
                      '$reviewed reviewed · ${queue.length} ${practice ? 'cards' : 'remaining'}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              if (card == null)
                zenPanel(
                  const Column(
                    children: [
                      Icon(Icons.check_circle_outline, size: 48, color: moss),
                      SizedBox(height: 16),
                      Text('You’re caught up.', style: TextStyle(fontSize: 24)),
                      Text(
                        'Create a card or practice your full deck. Your next review dates are saved.',
                      ),
                    ],
                  ),
                )
              else
                zenPanel(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${widget.store.getCourse(card.courseId)?.code ?? 'PERSONAL'} · ${card.masteryLevel.toUpperCase()}',
                        style: const TextStyle(
                          color: secondaryInk,
                          fontSize: 11,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 28),
                      SelectableText(
                        card.question,
                        style: const TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 26,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 28),
                      if (revealed) ...[
                        const Divider(),
                        const SizedBox(height: 20),
                        SelectableText(
                          card.answer,
                          style: const TextStyle(fontSize: 18, height: 1.6),
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final rating in ReviewRating.values)
                              OutlinedButton(
                                onPressed: () => rate(rating),
                                child: Text(
                                  rating.name[0].toUpperCase() +
                                      rating.name.substring(1),
                                ),
                              ),
                          ],
                        ),
                      ] else
                        FilledButton(
                          onPressed: () => setState(() => revealed = true),
                          child: const Text('Reveal Answer (Space)'),
                        ),
                      if (card.links.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          'Source: ${card.links.map((id) => widget.store.project.object(id)?.title ?? id).join(', ')}',
                          style: const TextStyle(
                            color: secondaryInk,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                  padding: const EdgeInsets.all(30),
                ),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: () {
                  widget.store.logStudySession(
                    StudySession(
                      courseId: widget.store.activeCourseId ?? '',
                      durationMinutes: DateTime.now()
                          .difference(started)
                          .inMinutes,
                      cardsReviewed: reviewed,
                    ),
                  );
                  TopNotification.show(
                    context,
                    'Study session saved',
                    icon: Icons.check_circle_outline,
                  );
                  setState(() => reviewed = 0);
                },
                icon: const Icon(Icons.done_all),
                label: const Text('Save study session'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
