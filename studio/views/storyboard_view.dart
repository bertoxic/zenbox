// ignore_for_file: invalid_use_of_protected_member
part of '../../studio.dart';

extension _StudioStoryboardView on _StudioState {
  List<CreativeObject> get shots => project.of('shot').toList();
  CreativeObject? shotAsset(CreativeObject shot) {
    final assets = shot.links
        .map(project.object)
        .whereType<CreativeObject>()
        .where((o) => o.kind == 'asset')
        .toList();
    return assets.where((o) => o.meta['mediaType'] == 'video').firstOrNull ??
        assets.where((o) => o.meta['mediaType'] == 'image').firstOrNull;
  }

  void playSequence([int index = 0]) {
    sequenceTimer?.cancel();
    if (index >= shots.length) {
      setState(() => playingShot = -1);
      return;
    }
    final shot = shots[index];
    setState(() {
      playingShot = index;
      selectedId = shot.id;
    });
    final duration = (shot.meta['duration'] as num? ?? 5).toDouble().clamp(
      .1,
      3600,
    );
    sequenceTimer = Timer(
      Duration(milliseconds: (duration * 1000).round()),
      () => playSequence(index + 1),
    );
  }

  Widget production([String? requestedMode]) {
    final items = shots;
    final current = selected?.kind == 'shot' ? selected : items.firstOrNull;
    final asset = current == null ? null : shotAsset(current);
    return ValueListenableBuilder<StudioSettings>(
      valueListenable: studioSettingsNotifier,
      builder: (context, settings, _) {
        final isDark = settings.themePreset == StudioThemePreset.obsidian;
        final themePreset = settings.themePreset;
        final timelineBg =
            isDark ? const Color(0xFF161B22) : const Color(0xFFEAECE1);
        final timelineBorder = isDark ? const Color(0xFF2E3846) : line;

        return Column(
          children: [
            SectionHeading(
              'Present what you understand',
              'Plan a lesson, topic by topic',
              subtitle:
                  '${items.length} segments · ${items.fold<double>(0, (n, o) => n + (o.meta['duration'] as num? ?? 5).toDouble()).toStringAsFixed(1)} seconds · Rehearse and edit your lesson presentation step by step.',
              actions: [
                if (items.isNotEmpty)
                  IconButton(
                    tooltip:
                        playingShot >= 0 ? 'Stop sequence' : 'Play sequence',
                    onPressed: () {
                      if (playingShot >= 0) {
                        sequenceTimer?.cancel();
                        setState(() => playingShot = -1);
                      } else {
                        playSequence();
                      }
                    },
                    icon: Icon(
                      playingShot >= 0
                          ? Icons.stop_circle_outlined
                          : Icons.play_circle_outline,
                      size: 20,
                      color: ink,
                    ),
                  ),
                IconButton(
                  tooltip: 'Export lesson plan as CSV',
                  onPressed: () => run(exportShots),
                  icon: const Icon(Icons.download_outlined, size: 18),
                ),
                FilledButton.icon(
                  onPressed: () => create('shot'),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('New segment'),
                ),
              ],
            ),
            Expanded(
              child: items.isEmpty
                  ? EmptyState(
                      Icons.movie_creation_outlined,
                      'Plan your first lesson segment.',
                      'Break a topic into steps. Write talking points, rehearse your explanation, and attach visual slides.',
                      action: FilledButton(
                        onPressed: () => create('shot'),
                        child: const Text('Add segment'),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(30, 0, 30, 14),
                      child: Column(
                        children: [
                          Expanded(
                            child: Container(
                              width: double.infinity,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color: ink,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: asset != null
                                  ? MediaPreview(
                                      key: ValueKey('${asset.id}-$playingShot'),
                                      store: store,
                                      asset: asset,
                                      autoplay: playingShot >= 0,
                                    )
                                  : Center(
                                      child: SingleChildScrollView(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 40,
                                          vertical: 24,
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: sage.withValues(
                                                  alpha: 0.25,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                current?.meta['camera']
                                                        as String? ??
                                                    'Explanation segment',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 1,
                                                  color: paleSage,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              current?.title ??
                                                  'Select a segment',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontFamily: 'Segoe UI',
                                                fontSize: 26,
                                                fontWeight: FontWeight.w700,
                                                color: cream,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            if (current?.body.trim().isEmpty ?? true)
                                              Text(
                                                'No talking points yet. Click "Edit segment" below to write notes.',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: paleSage,
                                                  fontSize: 13,
                                                  height: 1.7,
                                                ),
                                              )
                                            else
                                              Container(
                                                constraints: const BoxConstraints(maxWidth: 720),
                                                child: MarkdownView(
                                                  data: current!.body,
                                                  textColor: cream,
                                                  selectable: true,
                                                ),
                                              ),
                                            const SizedBox(height: 20),
                                            Wrap(
                                              spacing: 10,
                                              runSpacing: 10,
                                              alignment: WrapAlignment.center,
                                              children: [
                                                if (current != null)
                                                  FilledButton.tonalIcon(
                                                    style:
                                                        FilledButton.styleFrom(
                                                          visualDensity:
                                                              VisualDensity
                                                                  .compact,
                                                        ),
                                                    onPressed:
                                                        () => edit(current),
                                                    icon: const Icon(
                                                      Icons.edit_outlined,
                                                      size: 15,
                                                    ),
                                                    label: const Text(
                                                      'Edit segment & talking points',
                                                    ),
                                                  ),
                                                if (current != null)
                                                  OutlinedButton.icon(
                                                    style:
                                                        OutlinedButton.styleFrom(
                                                          foregroundColor:
                                                              cream,
                                                          side: BorderSide(
                                                            color: paleSage
                                                                .withValues(
                                                                  alpha: 0.4,
                                                                ),
                                                          ),
                                                          visualDensity:
                                                              VisualDensity
                                                                  .compact,
                                                        ),
                                                    onPressed: () {
                                                      setState(() {
                                                        selectedId = current.id;
                                                        dock = 'Inspector';
                                                        showDock = true;
                                                      });
                                                    },
                                                    icon: const Icon(
                                                      Icons.attachment,
                                                      size: 15,
                                                    ),
                                                    label: Text(
                                                      asset != null
                                                          ? 'Change visual'
                                                          : 'Link visual / slide',
                                                    ),
                                                  ),
                                                if (current != null)
                                                  IconButton(
                                                    tooltip:
                                                        'Open floating preview',
                                                    iconSize: 18,
                                                    color: cream,
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    icon: const Icon(
                                                      Icons
                                                          .picture_in_picture_alt,
                                                    ),
                                                    onPressed:
                                                        () =>
                                                            openFloatingVideo(
                                                              current,
                                                            ),
                                                  ),
                                                if (current != null)
                                                  IconButton(
                                                    tooltip: 'Delete segment',
                                                    iconSize: 18,
                                                    color: const Color(
                                                      0xFFA54141,
                                                    ),
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    icon: const Icon(
                                                      Icons.delete_outline,
                                                    ),
                                                    onPressed:
                                                        () => remove(current),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              IconButton(
                                tooltip:
                                    playingShot >= 0
                                        ? 'Stop sequence'
                                        : 'Play sequence',
                                onPressed: () {
                                  if (playingShot >= 0) {
                                    sequenceTimer?.cancel();
                                    setState(() => playingShot = -1);
                                  } else {
                                    playSequence();
                                  }
                                },
                                icon: Icon(
                                  playingShot >= 0
                                      ? Icons.stop_circle_outlined
                                      : Icons.play_circle_outline,
                                  size: 28,
                                  color: ink,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  current?.title ?? '',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (current != null) ...[
                                Tag(
                                  current.meta['camera'] as String? ??
                                      'Explanation',
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${current.meta['duration'] ?? 5}s',
                                  style: TextStyle(fontSize: 11, color: muted),
                                ),
                                const SizedBox(width: 12),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                  ),
                                  onPressed: () => edit(current),
                                  icon: const Icon(Icons.edit, size: 14),
                                  label: const Text(
                                    'Edit',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
            if (items.isNotEmpty)
              Container(
                height: 112,
                decoration: BoxDecoration(
                  color: timelineBg,
                  border: Border(top: BorderSide(color: timelineBorder)),
                ),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton.filledTonal(
                            tooltip: 'Add segment',
                            iconSize: 18,
                            onPressed: () => create('shot'),
                            icon: const Icon(Icons.add),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Add',
                            style: TextStyle(fontSize: 9, color: muted),
                          ),
                        ],
                      ),
                    ),
                    VerticalDivider(width: 1, color: timelineBorder),
                    Expanded(
                      child: ReorderableListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        itemCount: items.length,
                        buildDefaultDragHandles: false,
                        onReorderItem: reorderShots,
                        itemBuilder: (context, index) {
                          final shot = items[index];
                          final isSelected = current?.id == shot.id;
                          return ReorderableDragStartListener(
                            key: ValueKey(shot.id),
                            index: index,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  sequenceTimer?.cancel();
                                  setState(() {
                                    playingShot = -1;
                                    selectedId = shot.id;
                                  });
                                },
                                child: Container(
                                  width: 160,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color:
                                        isSelected
                                            ? (isDark
                                                ? themePreset.primary
                                                    .withValues(alpha: 0.3)
                                                : paleSage)
                                            : (isDark
                                                ? themePreset.paper
                                                : paper),
                                    border: Border.all(
                                      color:
                                          isSelected
                                              ? (isDark
                                                  ? themePreset.primary
                                                  : sage)
                                              : (isDark
                                                  ? const Color(0xFF2E3846)
                                                  : line),
                                      width: isSelected ? 1.8 : 1.0,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            '#${index + 1}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: isSelected ? sage : muted,
                                            ),
                                          ),
                                          const Spacer(),
                                          IconButton(
                                            tooltip: 'Edit segment',
                                            iconSize: 13,
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 20,
                                              minHeight: 20,
                                            ),
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                            ),
                                            onPressed: () => edit(shot),
                                          ),
                                          IconButton(
                                            tooltip: 'Delete segment',
                                            iconSize: 13,
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 20,
                                              minHeight: 20,
                                            ),
                                            color: const Color(0xFFA54141),
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
                                            onPressed: () => remove(shot),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        shot.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const Spacer(),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.slideshow_outlined,
                                            size: 12,
                                            color: muted,
                                          ),
                                          const Spacer(),
                                          Text(
                                            '${shot.meta['duration'] ?? 5}s',
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  void reorderShots(int oldIndex, int newIndex) {
    sequenceTimer?.cancel();
    playingShot = -1;
    final ordered = shots;

    ordered.insert(newIndex, ordered.removeAt(oldIndex));
    var n = 0;
    for (var i = 0; i < project.objects.length; i++) {
      if (project.objects[i].kind == 'shot') project.objects[i] = ordered[n++];
    }
    store.changed();
  }

  Future<void> exportShots() async {
    String escape(Object? v) => '"${'$v'.replaceAll('"', '""')}"';
    final csv = [
      [
        'Segment',
        'Explanation',
        'Teaching approach',
        'Duration (s)',
        'Linked topic',
      ],
      ...shots.map(
        (o) => [
          o.title,
          o.body,
          o.meta['camera'] ?? '',
          o.meta['duration'] ?? 5,
          o.links
              .map(project.object)
              .whereType<CreativeObject>()
              .where((e) => e.kind == 'script')
              .map((e) => e.title)
              .join('; '),
        ],
      ),
    ].map((r) => r.map(escape).join(',')).join('\r\n');
    final result = await FilePicker.saveFile(
      fileName: '${safeName(project.title)}-lesson-plan.csv',
      bytes: Uint8List.fromList(utf8.encode(csv)),
    );
    if (result != null) toast('Lesson plan exported');
  }

}
