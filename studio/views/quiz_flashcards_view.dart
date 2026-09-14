// ignore_for_file: invalid_use_of_protected_member
part of '../../studio.dart';

extension _StudioQuizFlashcardsView on _StudioState {
  Widget quizAndFlashcardsWorkspace() {
    if (activePlayingQuiz != null) {
      return Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: paper,
              border: Border(bottom: BorderSide(color: line)),
            ),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() => activePlayingQuiz = null),
                  icon: const Icon(Icons.arrow_back, size: 15),
                  label: const Text(
                    'Back to Quizzes & Flashcards',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  activePlayingQuiz!.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (project.object(activePlayingQuiz!.sourceObjectId)
              case final source?)
            TextButton.icon(
              onPressed: () {
                setState(() => activePlayingQuiz = null);
                open(source);
              },
              icon: const Icon(Icons.menu_book_outlined, size: 16),
              label: Text('Return to ${source.title}'),
            ),
          Expanded(
            child: QuizPlayerWidget(
              quiz: activePlayingQuiz!,
              store: store,
              onFinished: () {},
              onQuizUpdated: (updated) {
                for (final o in project.objects.where(
                  (o) => o.kind == 'quiz',
                )) {
                  try {
                    final d = QuizData.fromJson(jsonDecode(o.body));
                    if (d.title == updated.title || o.title == updated.title) {
                      o.body = jsonEncode(updated.toJson());
                      store.changed();
                      break;
                    }
                  } catch (_) {}
                }
              },
              onClose: () => setState(() => activePlayingQuiz = null),
            ),
          ),
        ],
      );
    }

    final allItems = project.objects
        .where((o) => o.kind == 'quiz' || o.kind == 'card')
        .toList();
    final quizzes = allItems.where((o) => o.kind == 'quiz').toList();
    final flashcards = allItems.where((o) => o.kind == 'card').toList();
    final flashcardGroups = <String, List<CreativeObject>>{};
    for (final card in flashcards) {
      final groupId =
          card.meta['deckId']?.toString() ??
          card.meta['source']?.toString() ??
          card.meta['deck']?.toString() ??
          'ungrouped';
      flashcardGroups.putIfAbsent(groupId, () => []).add(card);
    }

    return Column(
      children: [
        if (selected != null &&
            ['script', 'manuscript', 'note'].contains(selected!.kind))
          studyActions(selected!),
        SectionHeading(
          'Active study tools',
          'Quizzes & Flashcards',
          subtitle:
              'Interactive self-testing tools generated from your study notes and PDFs',
          actions: [
            FilledButton.icon(
              onPressed: () => openQuizGenerator(),
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('Generate study tool'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () {
                final card = CreativeObject(
                  kind: 'card',
                  title: 'New Flashcard Question',
                  body: 'Flashcard Answer / Explanation',
                  meta: {
                    'question': 'New Flashcard Question',
                    'answer': 'Flashcard Answer / Explanation',
                    'deck': 'General',
                    'deckId': 'manual-general',
                    'deckTitle': 'General flashcards',
                    'deckDescription': 'Flashcards created manually',
                  },
                );
                store.add(card);
                edit(card);
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New Flashcard'),
            ),
          ],
        ),
        Expanded(
          child: allItems.isEmpty
              ? const EmptyState(
                  Icons.school_outlined,
                  'No quizzes or flashcards yet',
                  'Generate interactive quizzes from any note or PDF document, or create flashcards manually.',
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 16,
                  ),
                  children: [
                    if (quizzes.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(Icons.quiz_outlined, size: 18, color: sage),
                          const SizedBox(width: 8),
                          Text(
                            'GENERATED QUIZZES (${quizzes.length})',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      for (final q in quizzes) _buildQuizWorkspaceItem(q),
                      const SizedBox(height: 24),
                    ],
                    if (flashcards.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.flip_to_back_outlined,
                            size: 18,
                            color: gold,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'FLASHCARD DECKS (${flashcardGroups.length})',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      for (final cards in flashcardGroups.values)
                        _buildFlashcardDeckWorkspaceItem(cards),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildQuizWorkspaceItem(CreativeObject q) {
    QuizData? quizData;
    try {
      quizData = QuizData.fromJson(jsonDecode(q.body));
    } catch (_) {}

    final qCount = quizData?.questions.length ?? 0;
    final diff = quizData?.difficulty ?? 'medium';
    final sourceTitle = quizData?.sourceTitle ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: sage.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.quiz_outlined, color: sage, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  q.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: cream,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: line),
                      ),
                      child: Text(
                        '$qCount questions',
                        style: TextStyle(
                          fontSize: 10,
                          color: ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: paleSage.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        diff.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          color: sage,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (sourceTitle.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.source_outlined, size: 12, color: muted),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          sourceTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10, color: muted),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (quizData != null)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: sage,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
              ),
              onPressed: () => setState(() => activePlayingQuiz = quizData),
              icon: const Icon(Icons.play_arrow, size: 16),
              label: const Text('Take Quiz', style: TextStyle(fontSize: 12)),
            ),
          const SizedBox(width: 6),
          if (quizData != null)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              onPressed: () async {
                final updated = await QuizEditDialog.show(context, quizData!);
                if (updated != null) {
                  q.body = jsonEncode(updated.toJson());
                  q.title = updated.title;
                  store.changed();
                  setState(() {});
                  toast('Quiz updated');
                }
              },
              icon: const Icon(Icons.edit_outlined, size: 14),
              label: const Text('Edit', style: TextStyle(fontSize: 11)),
            ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Pop out in floating window',
            iconSize: 18,
            icon: const Icon(Icons.picture_in_picture_alt),
            onPressed: () => openFloatingVideo(q),
          ),
          IconButton(
            tooltip: 'Delete quiz',
            iconSize: 18,
            color: const Color(0xFFA54141),
            icon: const Icon(Icons.delete_outline),
            onPressed: () => remove(q),
          ),
        ],
      ),
    );
  }

  Widget _buildFlashcardDeckWorkspaceItem(List<CreativeObject> cards) {
    final first = cards.first;
    String metadataText(String key) => first.meta[key]?.toString().trim() ?? '';
    final title = metadataText('deckTitle').isNotEmpty
        ? metadataText('deckTitle')
        : metadataText('source').isNotEmpty
        ? metadataText('source')
        : metadataText('deck').isNotEmpty
        ? metadataText('deck')
        : (cards.length == 1 ? first.title : 'Flashcard Deck');
    final description = metadataText('deckDescription').isNotEmpty
        ? metadataText('deckDescription')
        : '${cards.length} ${cards.length == 1 ? 'card' : 'cards'} in this deck';
    final sourceTitle = metadataText('sourceTitle').isNotEmpty
        ? metadataText('sourceTitle')
        : metadataText('source');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => FlashcardDeckModal.show(
            context,
            cards: cards,
            store: store,
            onPopOut: () => openFloatingFlashcardDeck(cards),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.style_outlined, color: gold, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: cream,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: line),
                            ),
                            child: Text(
                              '${cards.length} ${cards.length == 1 ? 'card' : 'cards'}',
                              style: TextStyle(
                                fontSize: 10,
                                color: ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (sourceTitle.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.source_outlined, size: 12, color: muted),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                sourceTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 10, color: muted),
                              ),
                            ),
                          ],
                          if (description.isNotEmpty &&
                              description !=
                                  '${cards.length} ${cards.length == 1 ? 'card' : 'cards'} in this deck') ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 10, color: muted),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: gold,
                    foregroundColor: ink,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                  onPressed: () => FlashcardDeckModal.show(
                    context,
                    cards: cards,
                    store: store,
                    onPopOut: () => openFloatingFlashcardDeck(cards),
                  ),
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text(
                    'Study Deck',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Pop out in floating window',
                  iconSize: 18,
                  icon: const Icon(Icons.picture_in_picture_alt),
                  onPressed: () => openFloatingFlashcardDeck(cards),
                ),
                IconButton(
                  tooltip: 'Delete deck',
                  iconSize: 18,
                  color: const Color(0xFFA54141),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDeleteDeck(cards, title),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteDeck(List<CreativeObject> cards, String title) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “$title”?'),
        content: Text(
          'This will delete all ${cards.length} flashcards in this deck. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFA54141),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete Deck'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      for (final card in cards) {
        store.project.objects.removeWhere((o) => o.id == card.id);
      }
      store.changed();
      setState(() {});
      toast('Deleted flashcard deck “$title”');
    }
  }
}
