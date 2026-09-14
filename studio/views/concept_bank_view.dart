// ignore_for_file: invalid_use_of_protected_member
part of '../../studio.dart';

extension _StudioConceptBankView on _StudioState {
  IconData _conceptKindIcon(String kind) => switch (kind) {
        'definition' => Icons.menu_book_outlined,
        'formula' => Icons.functions_rounded,
        'concept' => Icons.bubble_chart_outlined,
        'rule' => Icons.verified_outlined,
        'note' => Icons.lightbulb_outline,
        'character' => Icons.person_outline,
        _ => Icons.bookmark_outline,
      };

  Color _conceptKindColor(String kind) => switch (kind) {
        'definition' => const Color(0xFF2E7D32),
        'formula' => const Color(0xFFB25E00),
        'concept' => const Color(0xFF1565C0),
        'rule' => const Color(0xFF6A1B9A),
        'note' => const Color(0xFFD84315),
        _ => const Color(0xFF4A6B5B),
      };

  void _createConceptObject(String kind) {
    final titlePrefix = switch (kind) {
      'definition' => 'New Definition',
      'formula' => 'New Formula',
      'concept' => 'New Concept',
      'rule' => 'New Core Rule',
      'character' => 'New Key Figure',
      _ => 'New Note',
    };
    final newObj = CreativeObject(
      kind: kind,
      title: titlePrefix,
      body: '',
      meta: {
        'status': 'Idea',
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
    store.add(newObj);
    setState(() {
      selectedId = newObj.id;
      expandedScratchpadId = newObj.id;
    });
    toast('Created ${studyKindLabel(kind).toLowerCase()}');
  }

  Widget conceptBankWorkspace() {
    final items = collectionObjects('Concept Bank / Glossary');

    return Column(
      children: [
        SectionHeading(
          'CORE CONCEPTS & TERMS',
          'Concept Bank & Glossary',
          subtitle:
              'Definitions, formulas, recurring concepts, and key notes. Click any concept to expand and edit.',
          actions: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.view_agenda_outlined, size: 15),
                  tooltip: 'List view',
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.grid_view_rounded, size: 15),
                  tooltip: 'Grid view',
                ),
              ],
              selected: {scratchpadGridView},
              onSelectionChanged: (selection) {
                setState(() {
                  scratchpadGridView = selection.first;
                  if (scratchpadGridView) expandedScratchpadId = null;
                });
                saveLayout();
              },
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 170,
              height: 32,
              child: TextField(
                style: const TextStyle(fontSize: 11),
                decoration: InputDecoration(
                  hintText: 'Filter concepts & terms...',
                  hintStyle: TextStyle(fontSize: 11, color: muted),
                  prefixIcon: const Icon(Icons.search, size: 15),
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                onChanged: (v) => setState(() => filter = v.trim()),
              ),
            ),
            const SizedBox(width: 10),
            PopupMenuButton<String>(
              tooltip: 'Add new concept, definition, or note',
              onSelected: _createConceptObject,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'definition',
                  child: Row(
                    children: [
                      Icon(Icons.menu_book_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Definition / Term'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'formula',
                  child: Row(
                    children: [
                      Icon(Icons.functions_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Formula / Equation'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'concept',
                  child: Row(
                    children: [
                      Icon(Icons.bubble_chart_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Concept'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'rule',
                  child: Row(
                    children: [
                      Icon(Icons.verified_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Core Rule / Fact'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'note',
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb_outline, size: 18),
                      SizedBox(width: 8),
                      Text('Quick Note'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'character',
                  child: Row(
                    children: [
                      Icon(Icons.person_outline, size: 18),
                      SizedBox(width: 8),
                      Text('Person / Thinker'),
                    ],
                  ),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: sage,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 16, color: Colors.white),
                    SizedBox(width: 5),
                    Text(
                      'New concept',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 3),
                    Icon(Icons.arrow_drop_down, size: 16, color: Colors.white),
                  ],
                ),
              ),
            ),
          ],
        ),
        Expanded(
          child: items.isEmpty
              ? const EmptyState(
                  Icons.menu_book_outlined,
                  'Your concept bank is empty',
                  'Capture definitions, formulas, rules, and notes to anchor your knowledge. Click "New concept" above.',
                )
              : scratchpadGridView
              ? GridView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 16,
                  ),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 340,
                    mainAxisExtent: 195,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) =>
                      conceptBankGridCard(items[index]),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 16,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isExpanded = expandedScratchpadId == item.id;
                    final kindColor = _conceptKindColor(item.kind);
                    final kindIcon = _conceptKindIcon(item.kind);

                    return drag(
                      item,
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: isExpanded ? paper : cream,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isExpanded ? sage : line,
                            width: isExpanded ? 2 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isExpanded ? 0.08 : 0.03,
                              ),
                              blurRadius: isExpanded ? 12 : 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: isExpanded
                            ? Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: kindColor.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(kindIcon, size: 12, color: kindColor),
                                              const SizedBox(width: 5),
                                              Text(
                                                studyKindLabel(item.kind).toUpperCase(),
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.8,
                                                  color: kindColor,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Spacer(),
                                        IconButton(
                                          tooltip: item.meta['tray'] == true
                                              ? 'Remove from quick tray'
                                              : 'Pin to quick tray',
                                          iconSize: 17,
                                          icon: Icon(
                                            item.meta['tray'] == true
                                                ? Icons.push_pin
                                                : Icons.push_pin_outlined,
                                            color: item.meta['tray'] == true ? sage : null,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              item.meta['tray'] =
                                                  !(item.meta['tray'] as bool? ?? false);
                                            });
                                            store.changed();
                                            toast(item.meta['tray'] == true
                                                ? 'Pinned "${item.title}" to quick tray'
                                                : 'Removed "${item.title}" from quick tray');
                                          },
                                        ),
                                        IconButton(
                                          tooltip: 'Pop out in floating window',
                                          iconSize: 17,
                                          icon: const Icon(
                                            Icons.picture_in_picture_alt,
                                          ),
                                          onPressed: () =>
                                              openFloatingVideo(item),
                                        ),
                                      IconButton(
                                        tooltip: 'Edit details in dialog',
                                        iconSize: 17,
                                        icon: const Icon(Icons.edit_note),
                                        onPressed: () => edit(item),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete concept',
                                        iconSize: 17,
                                        color: const Color(0xFFA54141),
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () {
                                          remove(item);
                                          if (expandedScratchpadId == item.id) {
                                            setState(
                                              () => expandedScratchpadId = null,
                                            );
                                          }
                                        },
                                      ),
                                      const SizedBox(width: 4),
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                        ),
                                        onPressed: () => setState(
                                          () => expandedScratchpadId = null,
                                        ),
                                        icon: const Icon(
                                          Icons.unfold_less,
                                          size: 14,
                                        ),
                                        label: const Text(
                                          'Collapse',
                                          style: TextStyle(fontSize: 11),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    key: ValueKey('${item.id}-concept-title'),
                                    initialValue: item.title,
                                    style: const TextStyle(
                                      fontFamily: 'Segoe UI',
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: 'Concept Title / Term…',
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: UnderlineInputBorder(
                                        borderSide: BorderSide(
                                          color: Color(0xFF6E8B76),
                                          width: 1.5,
                                        ),
                                      ),
                                      contentPadding: EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                    ),
                                    onChanged: (v) {
                                      item.title = v;
                                      store.changed();
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  TextFormField(
                                    key: ValueKey('${item.id}-concept-body'),
                                    initialValue: item.body,
                                    maxLines: null,
                                    minLines: 6,
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.65,
                                      color: ink,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: switch (item.kind) {
                                        'definition' =>
                                          'Type definition, etymology, and key explanation here…',
                                        'formula' =>
                                          'Type formula equation, variables, units, and derivation…',
                                        'rule' =>
                                          'Type core rule, conditions, application, and facts…',
                                        'note' =>
                                          'Type quick thoughts, reminders, or revision cues…',
                                        _ =>
                                          'Type concept details, examples, and study notes here…',
                                      },
                                      hintStyle: TextStyle(
                                        fontSize: 12,
                                        color: muted,
                                      ),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: const UnderlineInputBorder(
                                        borderSide: BorderSide(
                                          color: Color(0xFF6E8B76),
                                          width: 1.2,
                                        ),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            vertical: 6,
                                          ),
                                    ),
                                    onChanged: (v) {
                                      item.body = v;
                                      store.changed();
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  const Divider(height: 1),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Text(
                                        '${item.body.trim().isEmpty ? 0 : item.body.trim().split(RegExp(r'\s+')).length} words · ${item.body.length} chars',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: muted,
                                        ),
                                      ),
                                      const Spacer(),
                                      Icon(
                                        Icons.check_circle_outline,
                                        size: 12,
                                        color: sage,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Auto-saved',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: sage,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            )
                          : InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () {
                                setState(() {
                                  selectedId = item.id;
                                  expandedScratchpadId = item.id;
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: kindColor.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(kindIcon, size: 11, color: kindColor),
                                              const SizedBox(width: 4),
                                              Text(
                                                studyKindLabel(item.kind).toUpperCase(),
                                                style: TextStyle(
                                                  fontSize: 8.5,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.7,
                                                  color: kindColor,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            item.title,
                                            style: const TextStyle(
                                              fontFamily: 'Segoe UI',
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: item.meta['tray'] == true
                                              ? 'Remove from quick tray'
                                              : 'Pin to quick tray',
                                          iconSize: 16,
                                          visualDensity: VisualDensity.compact,
                                          icon: Icon(
                                            item.meta['tray'] == true
                                                ? Icons.push_pin
                                                : Icons.push_pin_outlined,
                                            color: item.meta['tray'] == true ? sage : muted,
                                            size: 15,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              item.meta['tray'] =
                                                  !(item.meta['tray'] as bool? ?? false);
                                            });
                                            store.changed();
                                            toast(item.meta['tray'] == true
                                                ? 'Pinned "${item.title}" to quick tray'
                                                : 'Removed "${item.title}" from quick tray');
                                          },
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.unfold_more,
                                          size: 16,
                                          color: muted,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      item.body.isEmpty
                                          ? 'Empty ${studyKindLabel(item.kind).toLowerCase()} — click to expand and write…'
                                          : item.body,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.5,
                                        color: item.body.isEmpty
                                            ? muted.withValues(alpha: 0.6)
                                            : muted,
                                        fontStyle: item.body.isEmpty
                                            ? FontStyle.italic
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ));
                  },
                ),
        ),
      ],
    );
  }

  Widget conceptBankGridCard(CreativeObject item) {
    final kindColor = _conceptKindColor(item.kind);
    final kindIcon = _conceptKindIcon(item.kind);

    return drag(
      item,
      Material(
        color: paper,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            setState(() => selectedId = item.id);
            openFloatingVideo(item);
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selectedId == item.id ? sage : line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: kindColor.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Icon(kindIcon, size: 15, color: kindColor),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: kindColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        studyKindLabel(item.kind),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: kindColor,
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: item.meta['tray'] == true
                          ? 'Remove from quick tray'
                          : 'Pin to quick tray',
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        setState(() {
                          item.meta['tray'] =
                              !(item.meta['tray'] as bool? ?? false);
                        });
                        store.changed();
                        toast(item.meta['tray'] == true
                            ? 'Pinned "${item.title}" to quick tray'
                            : 'Removed "${item.title}" from quick tray');
                      },
                      icon: Icon(
                        item.meta['tray'] == true
                            ? Icons.push_pin
                            : Icons.push_pin_outlined,
                        color: item.meta['tray'] == true ? sage : null,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Open floating concept',
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => openFloatingVideo(item),
                      icon: const Icon(Icons.picture_in_picture_alt_outlined),
                    ),
                    IconButton(
                      tooltip: 'Edit details in dialog',
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => edit(item),
                      icon: const Icon(Icons.edit_note),
                    ),
                    IconButton(
                      tooltip: 'Delete concept',
                      iconSize: 16,
                      color: const Color(0xFFA54141),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => remove(item),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Segoe UI',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Text(
                    item.body.isEmpty
                        ? 'Empty ${studyKindLabel(item.kind).toLowerCase()} — click to write.'
                        : item.body,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: muted,
                      fontStyle: item.body.isEmpty ? FontStyle.italic : null,
                    ),
                  ),
                ),
                Text(
                  '${item.body.trim().isEmpty ? 0 : item.body.trim().split(RegExp(r'\s+')).length} words',
                  style: TextStyle(fontSize: 9, color: muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
