// ignore_for_file: invalid_use_of_protected_member
part of '../../studio.dart';

extension _StudioResourceLibraryView on _StudioState {
  List<CreativeObject> collectionObjects([String? requestedMode]) {
    final collectionMode = requestedMode ?? mode;
    final kinds = switch (collectionMode) {
      'Concept Bank / Glossary' ||
      'Concept Bank' ||
      'Story bible' ||
      'Scratchpad' => [
        'definition',
        'formula',
        'concept',
        'rule',
        'character',
        'location',
        'lore',
        'note',
      ],
      'Media library' => ['asset'],
      'Research' => ['research'],
      _ => ['note'],
    };
    return project.objects
        .where(
          (o) =>
              kinds.contains(o.kind) &&
              (filter.isEmpty ||
                  '${o.title} ${o.body} ${o.kind}'.toLowerCase().contains(
                    filter.toLowerCase(),
                  )),
        )
        .toList();
  }

  List<Map<String, String>> get resourceFolders =>
      (project.layout['resourceFolders'] as List? ?? [])
          .whereType<Map>()
          .map(
            (raw) => {
              'id': raw['id']?.toString() ?? '',
              'name': raw['name']?.toString() ?? 'Untitled folder',
              'parentId': raw['parentId']?.toString() ?? '',
            },
          )
          .where((folder) => folder['id']!.isNotEmpty)
          .toList();

  List<CreativeObject> _orderedResources(Iterable<CreativeObject> assets) {
    final order = List<String>.from(
      project.layout['resourceOrder'] as List? ?? [],
    );
    final index = <String, int>{
      for (var i = 0; i < order.length; i++) order[i]: i,
    };
    final result = assets.toList();
    result.sort(
      (a, b) => (index[a.id] ?? (1 << 30)).compareTo(index[b.id] ?? (1 << 30)),
    );
    return result;
  }

  Future<void> _createResourceFolder() async {
    final name = await askText(
      context,
      'New resource folder',
      hint: 'e.g. Week 3 lectures',
    );
    if (name == null || name.trim().isEmpty) return;
    final folders = List<Map<String, dynamic>>.from(
      project.layout['resourceFolders'] as List? ?? [],
    );
    final id = 'folder-${newId()}';
    folders.add({
      'id': id,
      'name': name.trim(),
      // Creating a folder while browsing one makes it a child of that folder.
      'parentId': selectedResourceFolder == 'all'
          ? null
          : selectedResourceFolder,
    });
    setState(() => selectedResourceFolder = id);
    project.layout['resourceFolders'] = folders;
    store.changed();
  }

  void _moveResourceToFolder(CreativeObject resource, String folderId) {
    resource.meta['folderId'] = folderId == 'root' ? null : folderId;
    store.changed();
    setState(() {});
  }

  List<Map<String, String>> _foldersIn(String? parentId) => resourceFolders
      .where((folder) => (folder['parentId'] ?? '') == (parentId ?? ''))
      .toList();

  bool _folderIsInside(String folderId, String possibleAncestorId) {
    var parentId = resourceFolders
        .where((folder) => folder['id'] == folderId)
        .map((folder) => folder['parentId'])
        .firstOrNull;
    final visited = <String>{};
    while (parentId != null && parentId.isNotEmpty && visited.add(parentId)) {
      if (parentId == possibleAncestorId) return true;
      parentId = resourceFolders
          .where((folder) => folder['id'] == parentId)
          .map((folder) => folder['parentId'])
          .firstOrNull;
    }
    return false;
  }

  void _moveFolderToFolder(Map<String, String> folder, String? parentId) {
    final folderId = folder['id']!;
    if (parentId == folderId ||
        (parentId != null && _folderIsInside(parentId, folderId))) {
      toast('A folder cannot be placed inside itself.');
      return;
    }
    final folders = List<Map<String, dynamic>>.from(
      project.layout['resourceFolders'] as List? ?? [],
    );
    final index = folders.indexWhere(
      (item) => item['id']?.toString() == folderId,
    );
    if (index < 0) return;
    folders[index] = {...folders[index], 'parentId': parentId};
    project.layout['resourceFolders'] = folders;
    store.changed();
    setState(() {});
  }

  Future<void> _batchDeleteResources() async {
    final count = markedResourceIds.length;
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $count resource${count == 1 ? '' : 's'}?'),
        content: const Text(
          'The selected resources will be permanently removed from your workspace. This cannot be undone.',
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
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final toDelete = project.objects
        .where((o) => markedResourceIds.contains(o.id))
        .toList();
    for (final resource in toDelete) {
      remove(resource);
    }
    setState(() {
      markedResourceIds.clear();
      resourceSelectionMode = false;
    });
    toast('Deleted $count resource${count == 1 ? '' : 's'}');
  }

  Future<void> _batchMoveResourcesDialog() async {
    final count = markedResourceIds.length;
    if (count == 0) return;
    final selectedFolder = await showDialog<String?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Move $count item${count == 1 ? '' : 's'} to…'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'root'),
            child: const Row(
              children: [
                Icon(Icons.folder_open_outlined, size: 18),
                SizedBox(width: 8),
                Text('Root (Learning Resources)'),
              ],
            ),
          ),
          for (final folder in resourceFolders)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, folder['id']),
              child: Row(
                children: [
                  Icon(Icons.folder_rounded, size: 18, color: gold),
                  const SizedBox(width: 8),
                  Text(folder['name']!),
                ],
              ),
            ),
        ],
      ),
    );
    if (selectedFolder == null) return;
    final targetFolderId = selectedFolder == 'root' ? null : selectedFolder;
    for (final id in markedResourceIds) {
      final res = project.object(id);
      if (res != null) {
        res.meta['folderId'] = targetFolderId;
      }
    }
    store.changed();
    setState(() {
      markedResourceIds.clear();
      resourceSelectionMode = false;
    });
    toast('Moved $count resource${count == 1 ? '' : 's'}');
  }

  Future<void> _deleteResourceFolder(Map<String, String> folder) async {
    final directFiles = project
        .of('asset')
        .where((asset) => asset.meta['folderId'] == folder['id'])
        .length;
    final childFolders = _foldersIn(folder['id']).length;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${folder['name']}”?'),
        content: Text(
          'The folder will be removed. Its $directFiles direct resource${directFiles == 1 ? '' : 's'} and $childFolders subfolder${childFolders == 1 ? '' : 's'} will move up one level; no files will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete folder'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final parentId = folder['parentId'];
    for (final asset in project.of('asset')) {
      if (asset.meta['folderId'] == folder['id']) {
        asset.meta['folderId'] = parentId?.isEmpty ?? true ? null : parentId;
      }
    }
    final folders = List<Map<String, dynamic>>.from(
      project.layout['resourceFolders'] as List? ?? [],
    );
    for (var index = 0; index < folders.length; index++) {
      if (folders[index]['parentId']?.toString() == folder['id']) {
        folders[index] = {
          ...folders[index],
          'parentId': parentId?.isEmpty ?? true ? null : parentId,
        };
      }
    }
    folders.removeWhere((item) => item['id']?.toString() == folder['id']);
    project.layout['resourceFolders'] = folders;
    if (selectedResourceFolder == folder['id']) {
      selectedResourceFolder = parentId?.isEmpty ?? true ? 'all' : parentId!;
    }
    store.changed();
    if (mounted) setState(() {});
    toast('Deleted folder “${folder['name']}”');
  }

  List<Map<String, String>> _folderPath(String folderId) {
    final path = <Map<String, String>>[];
    var currentId = folderId;
    final visited = <String>{};
    while (currentId.isNotEmpty && visited.add(currentId)) {
      final folder = resourceFolders
          .where((candidate) => candidate['id'] == currentId)
          .firstOrNull;
      if (folder == null) break;
      path.insert(0, folder);
      currentId = folder['parentId'] ?? '';
    }
    return path;
  }

  void _reorderResources(
    List<CreativeObject> visible,
    int oldIndex,
    int newIndex,
  ) {
    if (newIndex > oldIndex) newIndex--;
    final reordered = List<CreativeObject>.from(visible);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    final order = List<String>.from(
      project.layout['resourceOrder'] as List? ?? [],
    );
    order.removeWhere((id) => visible.any((asset) => asset.id == id));
    order.addAll(reordered.map((asset) => asset.id));
    project.layout['resourceOrder'] = order;
    store.changed();
    setState(() {});
  }

  Widget resourceLibrary(List<CreativeObject> assets) {
    if (selectedResourceFolder != 'all' &&
        !resourceFolders.any(
          (folder) => folder['id'] == selectedResourceFolder,
        )) {
      selectedResourceFolder = 'all';
    }
    final currentFolderId = selectedResourceFolder == 'all'
        ? null
        : selectedResourceFolder;
    final folders = _foldersIn(currentFolderId);
    final showFolderTiles = folders.isNotEmpty;
    final visible = _orderedResources(
      assets.where(
        (asset) => currentFolderId == null
            ? asset.meta['folderId'] == null
            : asset.meta['folderId'] == currentFolderId,
      ),
    );
    final path = currentFolderId == null
        ? const <Map<String, String>>[]
        : _folderPath(currentFolderId);
    return Column(
      children: [
        // ─── Breadcrumb address bar ──────────────────────────────────────────
        DragTarget<Object>(
          onWillAcceptWithDetails: (details) {
            final item = details.data;
            if (item is CreativeObject)
              return item.kind == 'asset' && item.meta['folderId'] != null;
            if (item is Map<String, String>)
              return (item['parentId'] ?? '').isNotEmpty;
            return false;
          },
          onAcceptWithDetails: (details) {
            final item = details.data;
            if (item is CreativeObject) {
              _moveResourceToFolder(item, 'root');
              toast('Moved "${item.title}" to Learning Resources');
            } else if (item is Map<String, String>) {
              _moveFolderToFolder(item, null);
              toast('Moved "${item['name']}" to Learning Resources');
            }
          },
          builder: (context, candidates, rejected) => Container(
            margin: const EdgeInsets.fromLTRB(30, 0, 30, 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: candidates.isEmpty ? paper : paleSage,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: candidates.isEmpty ? line : sage,
                width: candidates.isEmpty ? 1 : 2,
              ),
            ),
            child: Row(
              children: [
                // Back button (only inside a folder)
                if (path.isNotEmpty) ...[
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => setState(
                      () => selectedResourceFolder = path.length == 1
                          ? 'all'
                          : path[path.length - 2]['id']!,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.arrow_back_ios_rounded,
                        size: 13,
                        color: muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                // Root crumb — the root shows only items that actually live there.
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: path.isNotEmpty
                      ? () => setState(() => selectedResourceFolder = 'all')
                      : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.folder_open_outlined,
                        size: 14,
                        color: path.isNotEmpty ? muted : ink,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Learning Resources',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: path.isEmpty
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: path.isNotEmpty ? muted : ink,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final folder in path) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.chevron_right, size: 14, color: muted),
                  ),
                  InkWell(
                    onTap: () =>
                        setState(() => selectedResourceFolder = folder['id']!),
                    child: Text(
                      folder['name']!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: folder == path.last
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: folder == path.last ? ink : muted,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: paleSage,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${visible.length}',
                    style: TextStyle(
                      fontSize: 10,
                      color: ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
        // ─── Toolbar row (view toggle + new folder) ──────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 0, 30, 10),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    resourceSelectionMode = !resourceSelectionMode;
                    if (!resourceSelectionMode) markedResourceIds.clear();
                  });
                },
                icon: Icon(
                  resourceSelectionMode
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: 16,
                  color: resourceSelectionMode ? sage : null,
                ),
                label: Text(
                  resourceSelectionMode ? 'Done marking' : 'Mark items',
                ),
              ),
              if (resourceSelectionMode || markedResourceIds.isNotEmpty) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (markedResourceIds.length >= visible.length && visible.isNotEmpty) {
                        markedResourceIds.clear();
                      } else {
                        markedResourceIds.addAll(visible.map((r) => r.id));
                      }
                    });
                  },
                  child: Text(
                    markedResourceIds.length >= visible.length && visible.isNotEmpty
                        ? 'Deselect all'
                        : 'Select all (${visible.length})',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
              const Spacer(),
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
                selected: {resourceGridView},
                onSelectionChanged: (selection) {
                  setState(() => resourceGridView = selection.first);
                  saveLayout();
                },
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _createResourceFolder,
                icon: const Icon(Icons.create_new_folder_outlined, size: 16),
                label: const Text('Folder'),
              ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty && (!showFolderTiles || folders.isEmpty)
              ? EmptyState(
                  Icons.folder_open_outlined,
                  'This folder is ready.',
                  'Import a resource or move one here from the resource menu.',
                )
              : resourceGridView
              ? GridView.builder(
                  padding: const EdgeInsets.fromLTRB(30, 6, 30, 30),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 250,
                    mainAxisExtent: 216,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemCount:
                      visible.length + (showFolderTiles ? folders.length : 0),
                  itemBuilder: (context, index) {
                    if (showFolderTiles && index < folders.length) {
                      return _resourceFolderCard(
                        folders[index],
                        assets,
                        grid: true,
                      );
                    }
                    return _resourceCard(
                      visible[index - (showFolderTiles ? folders.length : 0)],
                      resourceFolders,
                      grid: true,
                    );
                  },
                )
              : showFolderTiles
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(30, 6, 30, 30),
                  children: [
                    for (final folder in folders)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _resourceFolderCard(folder, assets),
                      ),
                    for (final resource in visible)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _resourceCard(resource, resourceFolders),
                      ),
                  ],
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(30, 6, 30, 30),
                  buildDefaultDragHandles: false,
                  itemCount: visible.length,
                  onReorder: (oldIndex, newIndex) =>
                      _reorderResources(visible, oldIndex, newIndex),
                  itemBuilder: (context, index) => Padding(
                    key: ValueKey(visible[index].id),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _resourceCard(
                      visible[index],
                      resourceFolders,
                      dragIndex: index,
                    ),
                  ),
                ),
        ),
        if (markedResourceIds.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(30, 0, 30, 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: paper,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: sage, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, size: 18, color: sage),
                const SizedBox(width: 8),
                Text(
                  '${markedResourceIds.length} marked',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(width: 14),
                OutlinedButton.icon(
                  onPressed: _batchMoveResourcesDialog,
                  icon: const Icon(Icons.drive_file_move_outline, size: 16),
                  label: const Text('Move to…'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFA54141),
                  ),
                  onPressed: _batchDeleteResources,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Delete'),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Clear selection',
                  onPressed: () => setState(() {
                    markedResourceIds.clear();
                    resourceSelectionMode = false;
                  }),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _resourceFolderCard(
    Map<String, String> folder,
    List<CreativeObject> assets, {
    bool grid = false,
    VoidCallback? onTap,
  }) {
    final itemCount = assets
        .where((asset) => asset.meta['folderId'] == folder['id'])
        .length;
    final organizer = PopupMenuButton<String>(
      tooltip: 'Folder options',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      iconSize: 16,
      onSelected: (action) {
        if (action == 'delete') _deleteResourceFolder(folder);
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 17),
              SizedBox(width: 8),
              Text('Delete folder'),
            ],
          ),
        ),
      ],
      icon: const Icon(Icons.more_horiz, size: 16),
    );
    final card = DragTarget<Object>(
      onWillAcceptWithDetails: (d) {
        final item = d.data;
        if (item is CreativeObject) {
          return item.kind == 'asset' && item.meta['folderId'] != folder['id'];
        }
        if (item is Map<String, String>) {
          final folderId = item['id'];
          return folderId != null &&
              folderId != folder['id'] &&
              !_folderIsInside(folder['id']!, folderId);
        }
        return false;
      },
      onAcceptWithDetails: (d) {
        if (d.data is CreativeObject) {
          final resource = d.data as CreativeObject;
          _moveResourceToFolder(resource, folder['id']!);
          toast('Moved "${resource.title}" to ${folder['name']}');
        } else if (d.data is Map<String, String>) {
          final moving = d.data as Map<String, String>;
          _moveFolderToFolder(moving, folder['id']);
          toast('Moved "${moving['name']}" to ${folder['name']}');
        }
      },
      builder: (context, candidates, rejected) {
        final isHovered = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isHovered ? gold : Colors.transparent,
              width: 2,
            ),
          ),
          child: Material(
            color: isHovered ? gold.withValues(alpha: .08) : paper,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap ??
                  () {
                    navigate('Media library');
                    setState(() => selectedResourceFolder = folder['id']!);
                  },
              child: Container(
                padding: EdgeInsets.all(grid ? 10 : 14),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isHovered ? Colors.transparent : line,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: grid
                    ? SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.folder_rounded,
                              size: 42,
                              color: gold,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    folder['name']!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                organizer,
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$itemCount ${itemCount == 1 ? 'resource' : 'resources'}',
                              style: TextStyle(fontSize: 10, color: muted),
                            ),
                            if (isHovered)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Drop to add',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: gold,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )
                    : Row(
                        children: [
                          Container(
                            width: 64,
                            height: 58,
                            decoration: BoxDecoration(
                              color: gold.withValues(alpha: .14),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(
                              Icons.folder_rounded,
                              color: gold,
                              size: 34,
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  folder['name']!,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  isHovered
                                      ? 'Drop to add here'
                                      : '$itemCount ${itemCount == 1 ? 'resource' : 'resources'}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isHovered ? gold : muted,
                                    fontWeight: isHovered
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          organizer,
                          Icon(
                            isHovered
                                ? Icons.arrow_downward_rounded
                                : Icons.chevron_right,
                            color: isHovered ? gold : muted,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
    return Draggable<Map<String, String>>(
      data: folder,
      feedback: Material(
        color: paper,
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_rounded, color: gold, size: 18),
              const SizedBox(width: 8),
              Text(folder['name']!, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: .45, child: card),
      child: card,
    );
  }

  Widget _resourceCard(
    CreativeObject resource,
    List<Map<String, String>> folders, {
    bool grid = false,
    int? dragIndex,
  }) {
    final isMarked = markedResourceIds.contains(resource.id);
    final folderName = folders
        .where((folder) => folder['id'] == resource.meta['folderId'])
        .map((folder) => folder['name'])
        .firstOrNull;
    final organizer = PopupMenuButton<String>(
      tooltip: 'Organize resource',
      onSelected: (folder) async {
        if (folder == 'delete') {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Delete “${resource.title}”?'),
              content: const Text(
                'Are you sure you want to delete this resource? This cannot be undone.',
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
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          if (confirm == true) {
            remove(resource);
            markedResourceIds.remove(resource.id);
            toast('Deleted "${resource.title}"');
          }
        } else if (folder == 'mark') {
          setState(() {
            if (isMarked) {
              markedResourceIds.remove(resource.id);
            } else {
              markedResourceIds.add(resource.id);
            }
          });
        } else {
          _moveResourceToFolder(resource, folder);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'mark',
          child: Row(
            children: [
              Icon(
                isMarked ? Icons.check_box : Icons.check_box_outline_blank,
                size: 17,
              ),
              const SizedBox(width: 8),
              Text(isMarked ? 'Unmark' : 'Mark for batch action'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'root', child: Text('Remove from folder')),
        const PopupMenuDivider(),
        for (final folder in folders)
          PopupMenuItem(
            value: folder['id'],
            child: Text('Move to ${folder['name']}'),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 17, color: Color(0xFFA54141)),
              SizedBox(width: 8),
              Text('Delete resource', style: TextStyle(color: Color(0xFFA54141))),
            ],
          ),
        ),
      ],
      icon: const Icon(Icons.drive_file_move_outline, size: 19),
    );
    final card = Material(
      color: isMarked ? paleSage.withValues(alpha: .3) : paper,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (resourceSelectionMode || markedResourceIds.isNotEmpty) {
            setState(() {
              if (isMarked) {
                markedResourceIds.remove(resource.id);
              } else {
                markedResourceIds.add(resource.id);
              }
            });
          } else {
            preview(resource);
          }
        },
        onLongPress: () {
          setState(() {
            if (isMarked) {
              markedResourceIds.remove(resource.id);
            } else {
              markedResourceIds.add(resource.id);
              resourceSelectionMode = true;
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: isMarked ? paleSage.withValues(alpha: .3) : paper,
            border: Border.all(
              color: isMarked ? sage : line,
              width: isMarked ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: grid
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              height: double.infinity,
                              child: AssetThumbnail(store: store, asset: resource),
                            ),
                            Positioned(
                              top: 5,
                              left: 5,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (isMarked) {
                                      markedResourceIds.remove(resource.id);
                                    } else {
                                      markedResourceIds.add(resource.id);
                                    }
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: isMarked
                                        ? sage
                                        : paper.withValues(alpha: .85),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isMarked ? sage : muted,
                                    ),
                                  ),
                                  child: Icon(
                                    isMarked
                                        ? Icons.check
                                        : Icons.circle_outlined,
                                    size: 14,
                                    color: isMarked ? Colors.white : muted,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            resource.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        organizer,
                      ],
                    ),
                    Text(
                      '${resource.meta['mediaType'] ?? 'file'}${folderName == null ? '' : ' · $folderName'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: muted),
                    ),
                  ],
                )
              : SizedBox(
                  height: 66,
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            if (isMarked) {
                              markedResourceIds.remove(resource.id);
                            } else {
                              markedResourceIds.add(resource.id);
                            }
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: isMarked
                                  ? sage
                                  : paper.withValues(alpha: .85),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isMarked ? sage : muted,
                              ),
                            ),
                            child: Icon(
                              isMarked ? Icons.check : Icons.circle_outlined,
                              size: 14,
                              color: isMarked ? Colors.white : muted,
                            ),
                          ),
                        ),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 104,
                          height: double.infinity,
                          child: AssetThumbnail(store: store, asset: resource),
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              resource.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${resource.meta['mediaType'] ?? 'file'}${folderName == null ? '' : ' · $folderName'}',
                              style: TextStyle(fontSize: 11, color: muted),
                            ),
                          ],
                        ),
                      ),
                      organizer,
                      if (dragIndex != null)
                        ReorderableDragStartListener(
                          index: dragIndex,
                          child: Icon(Icons.drag_indicator, color: muted),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
    // Wrap in Draggable so the card can be dragged onto a folder DragTarget
    return Draggable<CreativeObject>(
      data: resource,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(10),
        color: paper,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insert_drive_file_outlined, size: 16, color: muted),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  resource.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: .45, child: card),
      child: card,
    );
  }

  Widget collection([String? requestedMode]) {
    final collectionMode = requestedMode ?? mode;
    final objects = collectionObjects(collectionMode);
    final media = collectionMode == 'Media library';
    final kind = switch (collectionMode) {
      'Concept Bank / Glossary' ||
      'Concept Bank' ||
      'Story bible' => 'definition',
      'Media library' => 'asset',
      'Research' => 'research',
      _ => 'note',
    };
    final subtitle = switch (collectionMode) {
      'Concept Bank / Glossary' || 'Concept Bank' || 'Story bible' =>
        'Definitions, formulas, recurring concepts, and core facts to anchor your knowledge.',
      'Media library' =>
        'Your diagrams, audio, papers, and references. Together.',
      'Research' => 'Follow your curiosity. Keep the source close.',
      _ => 'Capture first. Make sense of it later.',
    };
    return Column(
      children: [
        SectionHeading(
          'BUILD YOUR KNOWLEDGE',
          studyModeLabel(collectionMode),
          subtitle: subtitle,
          actions: [
            if (collectionMode == 'Concept Bank / Glossary' ||
                collectionMode == 'Concept Bank' ||
                collectionMode == 'Story bible')
              PopupMenuButton<String>(
                tooltip: 'Add to concept bank',
                onSelected: create,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'definition',
                    child: Text('Definition / Term'),
                  ),
                  PopupMenuItem(
                    value: 'formula',
                    child: Text('Formula / Equation'),
                  ),
                  PopupMenuItem(value: 'concept', child: Text('Concept')),
                  PopupMenuItem(value: 'rule', child: Text('Core Rule / Fact')),
                  PopupMenuItem(
                    value: 'character',
                    child: Text('Person / Thinker'),
                  ),
                ],
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.add, color: ink),
                ),
              )
            else
              FilledButton.icon(
                onPressed: importing
                    ? null
                    : () => media ? run(importFiles) : create(kind),
                icon: Icon(
                  media ? Icons.file_upload_outlined : Icons.add,
                  size: 16,
                ),
                label: Text(
                  media
                      ? 'Import files'
                      : 'New ${kind == 'note' ? 'note' : 'source'}',
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 0, 30, 21),
          child: TextField(
            key: ValueKey(collectionMode),
            decoration: InputDecoration(
              hintText:
                  'Filter ${studyModeLabel(collectionMode).toLowerCase()}…',
              prefixIcon: const Icon(Icons.search, size: 17),
            ),
            onChanged: (v) => setState(() => filter = v),
          ),
        ),
        Expanded(
          child: media
              ? resourceLibrary(objects)
              : objects.isEmpty
              ? EmptyState(
                  media ? Icons.photo_library_outlined : Icons.notes_outlined,
                  filter.isEmpty
                      ? 'A little space for something new.'
                      : 'No matching objects',
                  filter.isEmpty
                      ? 'Add your first ${media ? 'file' : kind} to this project.'
                      : 'Try another word.',
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(30, 0, 30, 30),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: media ? 260 : 330,
                    mainAxisExtent: media ? 238 : 235,
                    crossAxisSpacing: 15,
                    mainAxisSpacing: 15,
                  ),
                  itemCount: objects.length,
                  itemBuilder: (context, index) =>
                      objectCard(objects[index], media),
                ),
        ),
      ],
    );
  }

  Widget objectCard(CreativeObject o, bool media) => drag(
    o,
    DragTarget<CreativeObject>(
      onWillAcceptWithDetails: (d) => d.data.id != o.id,
      onAcceptWithDetails: (d) {
        if (!o.links.contains(d.data.id)) o.links.add(d.data.id);
        store.changed();
        toast('Linked ${d.data.title}');
      },
      builder: (context, candidates, rejected) => Material(
        color: candidates.isNotEmpty ? paleSage : paper,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () {
            setState(() => selectedId = o.id);
            if (media) {
              preview(o);
            } else if (mode == 'Concept Bank / Glossary' ||
                mode == 'Concept Bank' ||
                mode == 'Story bible') {
              openFloatingVideo(o);
            } else {
              edit(o);
            }
          },
          onSecondaryTap: () {
            setState(() {
              selectedId = o.id;
              dock = 'Inspector';
              showDock = true;
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              border: Border.all(
                color: selectedId == o.id ? sage : line,
                width: selectedId == o.id ? 1.7 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: selectedId == o.id
                  ? [
                      BoxShadow(
                        color: sage.withValues(alpha: .12),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (media)
                  Expanded(
                    child: SizedBox(
                      width: double.infinity,
                      child: AssetThumbnail(store: store, asset: o),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 12, 0),
                    child: Row(
                      children: [
                        Tag(
                          o.kind.toUpperCase(),
                          color: o.kind == 'note' ? gold : paleSage,
                        ),
                        const Spacer(),
                        PopupMenuButton<String>(
                          tooltip: 'Object actions',
                          onSelected: (v) {
                            if (v == 'delete') {
                              remove(o);
                            } else if (v == 'tray') {
                              o.meta['tray'] =
                                  !(o.meta['tray'] as bool? ?? false);
                              store.changed();
                            } else {
                              setState(() {
                                selectedId = o.id;
                                dock = 'Inspector';
                                showDock = true;
                              });
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'inspect',
                              child: Text('Inspect & link'),
                            ),
                            PopupMenuItem(
                              value: 'tray',
                              child: Text('Toggle temporary tray'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Remove'),
                            ),
                          ],
                          icon: const Icon(Icons.more_horiz, size: 17),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(18, media ? 14 : 12, 18, 9),
                  child: Text(
                    o.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Segoe UI',
                      fontSize: media ? 12 : 19,
                      height: 1.3,
                    ),
                  ),
                ),
                if (!media)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Text(
                        o.body,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.7,
                          color: muted,
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                  child: Row(
                    children: [
                      Text(
                        media
                            ? '${o.meta['mediaType']} · ${((o.meta['bytes'] as num? ?? 0) / 1024 / 1024).toStringAsFixed(1)} MB'
                            : '${o.links.length} linked objects',
                        style: TextStyle(fontSize: 9, color: muted),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: media ? 'Delete media' : 'Delete object',
                        iconSize: 16,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        color: const Color(0xFFA54141),
                        onPressed: () => remove(o),
                        icon: const Icon(Icons.delete_outline),
                      ),
                      Icon(
                        media ? Icons.open_in_full : Icons.arrow_outward,
                        size: 12,
                        color: muted,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
