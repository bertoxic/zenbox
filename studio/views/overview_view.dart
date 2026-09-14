// ignore_for_file: invalid_use_of_protected_member
part of '../../studio.dart';

extension _StudioOverviewView on _StudioState {
  Widget overview() => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          'YOUR LEARNING WORKSPACE',
          'Build understanding, one topic at a time.',
          subtitle:
              'Capture ideas, connect concepts, and practise what you learn.',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 0, 30, 20),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ActionChip(
                avatar: const Icon(Icons.edit_note, size: 18),
                label: const Text('1  Capture notes'),
                onPressed: () => navigate('Notes'),
              ),
              ActionChip(
                avatar: const Icon(Icons.account_tree_outlined, size: 18),
                label: const Text('2  Connect concepts'),
                onPressed: () => navigate('Mind Map / Concept Board'),
              ),
              ActionChip(
                avatar: const Icon(Icons.school_outlined, size: 18),
                label: const Text('3  Practise recall'),
                onPressed: () => navigate('Quizzes & Flashcards'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: DragTarget<CreativeObject>(
            onAcceptWithDetails: (d) {
              d.data.meta['tray'] = true;
              store.changed();
              toast('Pinned "${d.data.title}" to quick tray');
            },
            builder: (context, candidates, rejected) {
              final isDark = Theme.of(context).brightness == Brightness.dark ||
                  studioSettingsNotifier.value.themePreset == StudioThemePreset.obsidian;
              final bannerBg = isDark ? paper : paleSage;
              final overlayColor = isDark ? paper : const Color(0xFFE4ECD9);
              return Container(
                height: 220,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: candidates.isNotEmpty
                      ? sage.withValues(alpha: .2)
                      : bannerBg,
                  borderRadius: BorderRadius.circular(10),
                  border: candidates.isNotEmpty
                      ? Border.all(color: sage, width: 2)
                      : null,
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: () {
                          final customPath =
                              project.layout['overviewWallpaper'] as String? ??
                              project.layout['dashboardWallpaper'] as String? ??
                              studioSettingsNotifier.value.dashboardWallpaper;
                          final illustration =
                              project.layout['overviewWallpaperAsset']
                                  as String? ??
                              project.layout['dashboardWallpaperAsset']
                                  as String? ??
                              studioSettingsNotifier.value.dashboardWallpaperAsset ??
                              dashboardWallpapers.first;
                          if (customPath != null && customPath.isNotEmpty) {
                            return Image.file(
                              File(customPath),
                              fit: BoxFit.cover,
                              alignment: Alignment.centerRight,
                              errorBuilder: (_, _, _) => Image.asset(
                                illustration,
                                fit: BoxFit.cover,
                                alignment: Alignment.centerRight,
                              ),
                            );
                          }
                          return Image.asset(
                            illustration,
                            fit: BoxFit.cover,
                            alignment: Alignment.centerRight,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          );
                        }(),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: IconButton(
                        icon: const Icon(Icons.wallpaper, size: 18),
                        tooltip: 'Change dashboard illustration',
                        onPressed: _chooseOverviewWallpaper,
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                overlayColor.withValues(alpha: .96),
                                overlayColor.withValues(alpha: .88),
                                overlayColor.withValues(alpha: .32),
                                overlayColor.withValues(alpha: .0),
                              ],
                              stops: const [0, .40, .70, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 27,
                      top: 26,
                      right: 27,
                      bottom: 22,
                      child: LayoutBuilder(
                        builder: (context, heroBox) {
                          return SingleChildScrollView(
                            physics: const NeverScrollableScrollPhysics(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: (heroBox.maxWidth - (heroBox.maxWidth < 600 ? 40 : 300)).clamp(150.0, 900.0),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Tag('CURRENT COURSE', color: isDark ? sage.withValues(alpha: .5) : paper),
                                  const SizedBox(height: 8),
                                  Text(
                                    project.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Segoe UI',
                                      fontSize: heroBox.maxWidth < 500 ? 22 : 31,
                                      height: 1.12,
                                      color: ink,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  if (project.description.isNotEmpty)
                                    Text(
                                      project.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        height: 1.4,
                                        color: ink,
                                      ),
                                    ),
                                  const SizedBox(height: 10),
                                  InkWell(
                                    onTap: () => navigate('Notes'),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Continue studying',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: ink,
                                          ),
                                        ),
                                        const SizedBox(width: 9),
                                        Icon(Icons.arrow_forward, size: 15, color: ink),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  Positioned(
                    right: 18,
                    top: 18,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: Image.asset(
                        'assets/illustrations/dashboard_courses.jpg',
                        width: 78,
                        height: 78,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 20, 30, 28),
          child: Row(
            children: [
              stat(
                '${project.of('script').length + project.of('manuscript').length}',
                'Notes & Guides',
                Icons.description_outlined,
              ),
              const SizedBox(width: 12),
              stat(
                '${project.objects.where((o) => ['definition', 'formula', 'concept', 'rule', 'character', 'location', 'lore'].contains(o.kind)).length}',
                'Concepts & Rules',
                Icons.library_books_outlined,
              ),
              const SizedBox(width: 12),
              stat(
                '${project.of('asset').length}',
                'Learning resources',
                Icons.photo_outlined,
              ),
              const SizedBox(width: 12),
              stat(
                '${project.objects.where((o) => o.meta['studyConfidence'] == 'Confident').length}',
                'Topics confident',
                Icons.check_circle_outline,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Continue learning',
                  style: TextStyle(fontFamily: 'Segoe UI', fontSize: 21),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => navigate('Notes'),
                child: const Text(
                  'All notes & guides  →',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 12, 30, 24),
          child: Column(
            children: [
              for (final o
                  in project.objects
                      .where((o) => ['script', 'manuscript'].contains(o.kind))
                      .take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Material(
                    color: paper,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap: () => open(o),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(17),
                        decoration: BoxDecoration(
                          border: Border.all(color: line),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 40,
                              decoration: BoxDecoration(
                                color: cream,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Icon(
                                o.kind == 'script'
                                    ? Icons.edit_note
                                    : Icons.auto_stories_outlined,
                                color: sage,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    o.title,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    o.kind == 'script'
                                        ? 'Note · ${o.meta['act'] ?? o.meta['topic'] ?? 'General topic'}'
                                        : 'Study Guide / Summary Doc',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Tag(o.meta['status'] as String? ?? 'Draft'),
                            const SizedBox(width: 13),
                            Icon(Icons.arrow_outward, size: 16, color: muted),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (project.objects
                  .where((o) => ['script', 'manuscript'].contains(o.kind))
                  .isEmpty)
                OutlinedButton.icon(
                  onPressed: () => create('script'),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Write your first note / topic'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Row(
            children: [
              const Text(
                'Room to explore',
                style: TextStyle(fontFamily: 'Segoe UI', fontSize: 21),
              ),
              const Spacer(),
              TextButton(
                onPressed: quickCapture,
                child: const Text(
                  '+ Capture a thought',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 15, 30, 30),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              exploreCard(
                'Concept Bank / Glossary',
                'Definitions, formulas & core rules.',
                Icons.library_books_outlined,
                paleSage,
              ),
              exploreCard(
                'Mind Map / Concept Board',
                'Connect ideas across topics visually.',
                Icons.account_tree_outlined,
                const Color(0xFFE2D5B6),
              ),
              exploreCard(
                'Quizzes & Flashcards',
                'Test knowledge with active recall.',
                Icons.school_outlined,
                const Color(0xFFD9DECE),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget stat(String value, String label, IconData icon) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
      decoration: BoxDecoration(
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(fontFamily: 'Segoe UI', fontSize: 23),
                ),
              ),
              Icon(icon, size: 16, color: sage),
            ],
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 10, color: muted)),
        ],
      ),
    ),
  );
  Widget exploreCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
  ) => SizedBox(
    width: 210,
    child: Material(
      color: color.withValues(alpha: .4),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => navigate(title),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: ink, size: 23),
              const SizedBox(height: 25),
              Text(
                studyModeLabel(title),
                style: const TextStyle(fontFamily: 'Segoe UI', fontSize: 18),
              ),
              const SizedBox(height: 7),
              Text(subtitle, style: TextStyle(fontSize: 10, color: muted)),
            ],
          ),
        ),
      ),
    ),
  );
  Future<void> reviewCard(CreativeObject card) async {
    var revealed = false;
    final source =
        project.object(card.meta['sourceObjectId'] as String?) ??
        card.links
            .map(project.object)
            .whereType<CreativeObject>()
            .where(
              (item) => [
                'script',
                'manuscript',
                'note',
                'research',
                'asset',
              ].contains(item.kind),
            )
            .firstOrNull;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Recall before you reveal'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 20),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    alignment: Alignment.topLeft,
                    child: revealed
                        ? Text(card.body)
                        : const Text(
                            'Try explaining the answer in your own words.',
                          ),
                  ),
                  if (source != null) ...[
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context, 'source'),
                      icon: const Icon(Icons.menu_book_outlined, size: 16),
                      label: Text('Return to ${source.title}'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            if (!revealed)
              FilledButton(
                onPressed: () => update(() => revealed = true),
                child: const Text('Reveal answer'),
              ),
            if (revealed) ...[
              OutlinedButton(
                onPressed: () => Navigator.pop(context, 'Needs practice'),
                child: const Text('Needs practice'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'Remembered'),
                child: const Text('Remembered'),
              ),
            ],
          ],
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result == 'source') {
      if (source != null) open(source);
      return;
    }
    final reviews = List<dynamic>.from(card.meta['recallReviews'] ?? []);
    reviews.insert(0, {
      'at': DateTime.now().toIso8601String(),
      'result': result,
    });
    card.meta['recallReviews'] = reviews;
    card.meta['lastRecall'] = result;
    store.changed();
    toast('Recall recorded: $result');
  }

  Future<void> createRecallCard(CreativeObject source) async {
    final question = await askText(
      context,
      'Test your understanding',
      hint: 'What question should you be able to answer?',
      multiline: true,
    );
    if (question == null || !mounted) return;
    final answer = await askText(
      context,
      'Add the answer',
      hint: 'Explain the answer in your own words',
      multiline: true,
    );
    if (answer == null || !mounted) return;
    store.project.objects.add(
      CreativeObject(
        kind: 'card',
        title: question,
        body: answer,
        links: [source.id],
        meta: {
          'sourceObjectId': source.id,
          'deckTitle': source.title,
          'deckId': 'source-${source.id}',
        },
      ),
    );
    store.changed();
    toast('Flashcard saved and linked to ${source.title}');
  }

  Widget studyActions(CreativeObject source) {
    final related = relatedStudyTools(project, source);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: paper,
        border: Border(bottom: BorderSide(color: line)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Icon(Icons.route_outlined, size: 17),
            const SizedBox(width: 10),
            Text(
              'Learn → Recall → Check',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(width: 16),
            TextButton.icon(
              onPressed: () => createRecallCard(source),
              icon: const Icon(Icons.add_card_outlined, size: 16),
              label: const Text('Make flashcard'),
            ),
            TextButton.icon(
              onPressed: () => openQuizGenerator(
                source: source,
                output: StudyToolOutput.flashcards,
              ),
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('Generate cards'),
            ),
            TextButton.icon(
              onPressed: () => openQuizGenerator(source: source),
              icon: const Icon(Icons.quiz_outlined, size: 16),
              label: const Text('Quiz this note'),
            ),
            TextButton.icon(
              onPressed: related.isEmpty
                  ? null
                  : () => showDialog<void>(
                      context: context,
                      builder: (context) => SimpleDialog(
                        title: Text('Practise: ${source.title}'),
                        children: related
                            .map(
                              (item) => SimpleDialogOption(
                                onPressed: () {
                                  Navigator.pop(context);
                                  open(item);
                                },
                                child: Text(
                                  '${studyKindLabel(item.kind)} · ${item.title}',
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
              icon: const Icon(Icons.school_outlined, size: 16),
              label: Text('Practice (${related.length})'),
            ),
            IconButton(
              tooltip: 'Learning checkpoints',
              icon: const Icon(Icons.history, size: 18),
              onPressed: () {
                setState(() => selectedId = source.id);
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => SizedBox(
                    height: MediaQuery.sizeOf(context).height * .75,
                    child: AnimatedBuilder(
                      animation: store,
                      builder: (_, _) => versions(),
                    ),
                  ),
                );
              },
            ),
            PopupMenuButton<String>(
              tooltip: 'Record understanding',
              onSelected: (confidence) {
                recordStudyCheckpoint(store, source, confidence);
                setState(() => selectedId = source.id);
                toast('Checkpoint saved: $confidence');
              },
              itemBuilder: (_) => ['Learning', 'Needs practice', 'Confident']
                  .map(
                    (value) => PopupMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: sage, size: 17),
                    const SizedBox(width: 6),
                    Text(
                      source.meta['studyConfidence'] as String? ??
                          'Check understanding',
                    ),
                    const Icon(Icons.expand_more, size: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
