// ignore_for_file: invalid_use_of_protected_member
part of '../../studio.dart';

extension _StudioRightDock on _StudioState {
  Widget rightDock() => Material(
    color: paper.withValues(alpha: .65),
    child: Column(
      children: [
        Container(
          height: 45,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: line)),
          ),
          child: Row(
            children: [
              for (final name in [
                'AI',
                'Inspector',
                'Assets',
                'Focus',
                'Progress',
              ])
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() => dock = name);
                      saveLayout();
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: dock == name ? sage : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        {
                              'AI': 'Tutor',
                              'Inspector': 'Details',
                              'Assets': 'Resources',
                              'Focus': 'Focus',
                              'Progress': 'Progress',
                            }[name] ??
                            name,
                        style: TextStyle(
                          fontSize: 10,
                          color: dock == name ? ink : muted,
                          fontWeight: dock == name
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: [
              'AI',
              'Inspector',
              'Assets',
              'Focus',
              'Progress',
            ].indexOf(dock).clamp(0, 4),
            children: [
              AiPanel(
                key: ValueKey('ai-${project.id}'),
                store: store,
                session: ai,
                selected: selected,
                onInsert: (text) {
                  if (selected == null) return;
                  store.snapshot(selected!);
                  appendText(selected!, text);
                  store.changed();
                  toast('Response appended to ${selected!.title}');
                },
                onReplace: applySelectionReplace,
                onNavigateStudio:
                    (destination, objectId, dockName, trayVisible) {
                      navigate(destination);
                      setState(() {
                        if (objectId != null) selectedId = objectId;
                        if (dockName != null) {
                          dock = dockName;
                          showDock = true;
                        }
                        if (trayVisible != null) showTray = trayVisible;
                      });
                      saveLayout();
                    },
                onOpenObject: open,
                onProjectCreated: (created) {
                  setState(() {
                    mode = 'Overview';
                    dock = 'AI';
                    selectedId = null;
                    showTray = false;
                  });
                  saveLayout();
                  toast('Opened new project: ${created.title}');
                },
              ),
              inspector(),
              dockAssets(),
              FocusModeDock(store: store, onToast: toast),
              versions(),
            ],
          ),
        ),
      ],
    ),
  );
  Widget inspector() {
    final o = selected;
    if (o == null) {
      return const EmptyState(
        Icons.touch_app_outlined,
        'A closer look',
        'Select a note, flashcard, or lesson segment to explore its learning connections.',
      );
    }
    return DragTarget<CreativeObject>(
      onWillAcceptWithDetails: (d) => d.data.id != o.id,
      onAcceptWithDetails: (d) {
        if (!o.links.contains(d.data.id)) o.links.add(d.data.id);
        store.changed();
      },
      builder: (context, candidates, rejected) => Container(
        color: candidates.isNotEmpty
            ? paleSage.withValues(alpha: .5)
            : Colors.transparent,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Tag(studyKindLabel(o.kind).toUpperCase()),
                const Spacer(),
                IconButton(
                  tooltip: 'Edit details',
                  onPressed: () => edit(o),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              o.title,
              style: const TextStyle(
                fontFamily: 'Segoe UI',
                fontSize: 23,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 18),
            TextFormField(
              key: ValueKey('${o.id}-status'),
              initialValue: o.meta['status'] as String? ?? 'Draft',
              decoration: const InputDecoration(labelText: 'Status'),
              onChanged: (v) {
                o.meta['status'] = v;
                store.changed();
              },
            ),
            const SizedBox(height: 15),
            if (['script', 'manuscript'].contains(o.kind)) ...[
              TextFormField(
                key: ValueKey('${o.id}-act'),
                initialValue: o.meta['act'] as String? ?? '',
                decoration: const InputDecoration(
                  labelText: 'Topic / Unit / Section',
                ),
                onChanged: (v) {
                  o.meta['act'] = v;
                  store.changed();
                },
              ),
              const SizedBox(height: 15),
              TextFormField(
                key: ValueKey('${o.id}-synopsis'),
                initialValue: o.meta['synopsis'] as String? ?? '',
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Summary / Key Objectives',
                  alignLabelWithHint: true,
                ),
                onChanged: (v) {
                  o.meta['synopsis'] = v;
                  store.changed();
                },
              ),
              const SizedBox(height: 18),
            ],
            if (o.kind == 'shot') ...[
              TextFormField(
                key: ValueKey('${o.id}-camera'),
                initialValue: o.meta['camera'] as String? ?? '',
                decoration: const InputDecoration(
                  labelText: 'Teaching approach / visual cues',
                ),
                onChanged: (v) {
                  o.meta['camera'] = v;
                  store.changed();
                },
              ),
              const SizedBox(height: 15),
              TextFormField(
                key: ValueKey('${o.id}-duration'),
                initialValue: '${o.meta['duration'] ?? 5}',
                decoration: const InputDecoration(
                  labelText: 'Duration in seconds',
                ),
                keyboardType: TextInputType.number,
                onChanged: (v) {
                  final value = double.tryParse(v);
                  if (value != null && value > 0 && value <= 3600) {
                    o.meta['duration'] = value;
                    store.changed();
                  }
                },
              ),
              const SizedBox(height: 18),
            ],
            const Divider(),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'CONNECTIONS',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.5,
                    color: muted,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Link an object',
                  onPressed: () => linkObject(o),
                  icon: const Icon(Icons.add, size: 17),
                ),
              ],
            ),
            Text(
              'Drop an object here to connect it.',
              style: TextStyle(fontSize: 10, color: muted),
            ),
            const SizedBox(height: 12),
            for (final id in o.links)
              if (project.object(id) != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: line),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.only(left: 10),
                        title: Text(
                          project.object(id)!.title,
                          maxLines: 2,
                          style: const TextStyle(fontSize: 11),
                        ),
                        subtitle: Text(
                          project.object(id)!.kind,
                          style: TextStyle(fontSize: 9, color: muted),
                        ),
                        onTap: () => open(project.object(id)!),
                        trailing: IconButton(
                          tooltip: 'Unlink',
                          onPressed: () {
                            o.links.remove(id);
                            store.changed();
                          },
                          icon: const Icon(Icons.close, size: 12),
                        ),
                      ),
                    ),
                  ),
                ),
            const SizedBox(height: 25),
            OutlinedButton.icon(
              onPressed: () {
                o.meta['tray'] = !(o.meta['tray'] as bool? ?? false);
                store.changed();
              },
              icon: const Icon(Icons.inventory_2_outlined, size: 16),
              label: Text(
                o.meta['tray'] == true
                    ? 'Remove from tray'
                    : 'Keep in temporary tray',
                style: const TextStyle(fontSize: 11),
              ),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () => remove(o),
              icon: const Icon(Icons.delete_outline, size: 15),
              label: const Text(
                'Remove object',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> linkObject(CreativeObject target) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Connect to ${target.title}'),
        content: SizedBox(
          width: 450,
          height: 400,
          child: ListView(
            children: [
              for (final o in project.objects.where(
                (o) =>
                    o.id != target.id &&
                    !target.links.contains(o.id) &&
                    o.kind != 'generation',
              ))
                Material(
                  color: Colors.transparent,
                  child: ListTile(
                    title: Text(o.title),
                    subtitle: Text(studyKindLabel(o.kind)),
                    trailing: const Icon(Icons.add_link, size: 18),
                    onTap: () {
                      target.links.add(o.id);
                      store.changed();
                      Navigator.pop(context);
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget dockAssets() {
    final currentFolder = dockResourceFolderId == null
        ? null
        : resourceFolders
            .where((f) => f['id'] == dockResourceFolderId)
            .firstOrNull;
    final folders = _foldersIn(dockResourceFolderId);
    final visibleAssets = project
        .of('asset')
        .where((asset) => asset.meta['folderId'] == dockResourceFolderId)
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              if (currentFolder != null) ...[
                IconButton(
                  tooltip: 'Back to parent folder',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  icon: const Icon(Icons.arrow_back, size: 16),
                  onPressed: () {
                    setState(() {
                      final parentId = currentFolder['parentId'];
                      dockResourceFolderId =
                          (parentId == null || parentId.isEmpty) ? null : parentId;
                    });
                  },
                ),
                const SizedBox(width: 4),
                Icon(Icons.folder_open, size: 16, color: gold),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    currentFolder['name'] ?? 'Folder',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ] else
                const Expanded(
                  child: Text(
                    'Project assets',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              IconButton(
                tooltip: 'Import files',
                onPressed: () => run(importFiles),
                icon: const Icon(Icons.add, size: 17),
              ),
            ],
          ),
        ),
        Expanded(
          child: visibleAssets.isEmpty && folders.isEmpty
              ? (currentFolder != null
                  ? EmptyState(
                      Icons.folder_open_outlined,
                      'Folder is empty',
                      'Import files or drag resources here to organize into "${currentFolder['name']}".',
                    )
                  : const EmptyState(
                      Icons.photo_outlined,
                      'Gather your references',
                      'Import diagrams, lectures, or audio. Connect them to lesson segments, concept maps, or notes.',
                    ))
              : GridView.count(
                  crossAxisCount: 2,
                  childAspectRatio: 0.88,
                  padding: const EdgeInsets.all(12),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  children: [
                    for (final folder in folders)
                      _resourceFolderCard(
                        folder,
                        project.of('asset').toList(),
                        grid: true,
                        onTap: () => setState(() => dockResourceFolderId = folder['id']),
                      ),
                    for (final o in visibleAssets)
                      drag(
                        o,
                        InkWell(
                          onTap: () => preview(o),
                          child: Stack(
                            children: [
                              Column(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: AssetThumbnail(store: store, asset: o),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    o.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 9),
                                  ),
                                ],
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: PopupMenuButton<String>(
                                  tooltip: 'Asset options',
                                  iconSize: 13,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                  onSelected: (action) async {
                                    if (action == 'delete') {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: Text('Delete “${o.title}”?'),
                                          content: const Text(
                                            'Are you sure you want to delete this resource? This cannot be undone.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text('Cancel'),
                                            ),
                                            FilledButton(
                                              style: FilledButton.styleFrom(
                                                backgroundColor:
                                                    const Color(0xFFA54141),
                                              ),
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: const Text('Delete'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        remove(o);
                                        toast('Deleted "${o.title}"');
                                      }
                                    } else if (action == 'preview') {
                                      preview(o);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'preview',
                                      child: Text('Preview'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.delete_outline,
                                            size: 16,
                                            color: Color(0xFFA54141),
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'Delete',
                                            style: TextStyle(
                                              color: Color(0xFFA54141),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  icon: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: paper.withValues(alpha: .85),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.more_vert,
                                      size: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget versions() {
    final o = selected;
    final versions = List<dynamic>.from(o?.meta['versions'] ?? []);
    return Column(
      children: [
        if (o != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  o.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Self-assessment: ${o.meta['studyConfidence'] ?? 'Not checked yet'}',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                for (final checkpoint in List<dynamic>.from(
                  o.meta['studyCheckpoints'] ?? [],
                ).take(3))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${checkpoint['confidence']} · ${checkpoint['at'].toString().split('T').first}',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Learning checkpoints',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Save note snapshot',
                onPressed: o == null
                    ? null
                    : () {
                        store.snapshot(o);
                        toast('Note snapshot saved');
                      },
                icon: const Icon(Icons.add, size: 17),
              ),
            ],
          ),
        ),
        Expanded(
          child: versions.isEmpty
              ? const EmptyState(
                  Icons.history,
                  'See how your understanding develops',
                  'Save a note snapshot or record your confidence after studying. Earlier notes remain available to restore.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: versions.length,
                  itemBuilder: (context, index) {
                    final revision = versions[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(color: line),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${revision['at']}'
                                .replaceFirst('T', ' ')
                                .split('.')
                                .first,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '${revision['body']}',
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.6,
                              color: muted,
                            ),
                          ),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () {
                                  store.snapshot(o!);
                                  o.body = revision['body'] as String;
                                  o.title = revision['title'] as String;
                                  store.changed();
                                  toast(
                                    'Notes restored; previous content kept in checkpoints',
                                  );
                                },
                                child: const Text(
                                  'Restore these notes',
                                  style: TextStyle(fontSize: 10),
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: 'Delete this snapshot',
                                iconSize: 15,
                                color: muted,
                                onPressed: () {
                                  final removed = versions.removeAt(index);
                                  o!.meta['versions'] = versions;
                                  store.changed();
                                  setState(() {});
                                  TopNotification.show(
                                    context,
                                    'Note snapshot deleted',
                                    icon: Icons.delete_outline,
                                    actionLabel: 'Undo',
                                    onAction: () {
                                      versions.insert(index, removed);
                                      o.meta['versions'] = versions;
                                      store.changed();
                                      setState(() {});
                                    },
                                  );
                                },
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
