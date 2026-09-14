// ignore_for_file: invalid_use_of_protected_member
part of '../../studio.dart';

extension _StudioTopBar on _StudioState {
  Widget topBar(bool compact) => Container(
    height: 64,
    decoration: BoxDecoration(
      color: paper,
      border: Border(bottom: BorderSide(color: line)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 21),
    child: Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: ink,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.all_inclusive, color: paleSage, size: 23),
        ),
        if (!compact) ...[
          const SizedBox(width: 10),
          const Text(
            'zenbox',
            style: TextStyle(
              fontFamily: 'Segoe UI',
              fontSize: 24,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'STUDY',
            style: TextStyle(fontSize: 8, letterSpacing: 2, color: muted),
          ),
        ],
        const SizedBox(width: 23),
        Container(width: 1, height: 23, color: line),
        const SizedBox(width: 18),
        Expanded(
          child: PopupMenuButton<String>(
            tooltip: 'Switch course',
            onSelected: (id) {
              if (id == 'new') {
                createProject();
              } else if (id == 'manage') {
                manageProjectsDialog();
              } else if (id == 'delete') {
                deleteProjectDialog(project);
              } else if (id == 'import') {
                run(importProject);
              } else {
                sequenceTimer?.cancel();
                store.select(store.projects.firstWhere((p) => p.id == id));
                restoreLayout();
                setState(() {});
              }
            },
            itemBuilder: (_) => [
              ...store.projects.map(
                (p) => PopupMenuItem(
                  value: p.id,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.title,
                          style: TextStyle(
                            fontWeight: p.id == project.id
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (p.id == project.id)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Icon(Icons.check, size: 16, color: sage),
                        ),
                    ],
                  ),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'new',
                child: Row(
                  children: [
                    Icon(Icons.add, size: 16),
                    SizedBox(width: 8),
                    Text('New course'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'manage',
                child: Row(
                  children: [
                    Icon(Icons.tune, size: 16),
                    SizedBox(width: 8),
                    Text('Manage courses…'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.file_download_outlined, size: 16),
                    SizedBox(width: 8),
                    Text('Import project…'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'delete',
                enabled: store.projects.length > 1,
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: store.projects.length > 1
                          ? const Color(0xFFA54141)
                          : muted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Delete current course…',
                      style: TextStyle(
                        color: store.projects.length > 1
                            ? const Color(0xFFA54141)
                            : muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.folder_open, size: 16, color: sage),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    project.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Icon(Icons.expand_more, size: 15, color: muted),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: commandPalette,
          icon: const Icon(Icons.search, size: 16),
          label: Text(
            compact ? 'Search' : 'Search anything    Ctrl K',
            style: const TextStyle(fontSize: 11),
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: 'Focus mode · Ctrl+B',
          onPressed: () => setState(() => focusMode = !focusMode),
          icon: Icon(focusMode ? Icons.fullscreen_exit : Icons.fullscreen),
        ),
        IconButton(
          tooltip: 'Toggle right dock',
          onPressed: () {
            setState(() => showDock = !showDock);
            saveLayout();
          },
          icon: const Icon(Icons.view_sidebar_outlined),
        ),
        IconButton(
          tooltip: splitView ? 'Close split workspace' : 'Open split workspace',
          onPressed: () {
            setState(() {
              splitView = !splitView;
              if (secondaryMode == mode) {
                secondaryMode = mode == 'Concept Bank / Glossary'
                    ? 'Mind Map / Concept Board'
                    : 'Concept Bank / Glossary';
              }
            });
            saveLayout();
          },
          icon: Icon(
            splitView ? Icons.vertical_split : Icons.vertical_split_outlined,
            color: splitView ? sage : null,
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: () => openQuizGenerator(source: selected),
          icon: Icon(Icons.auto_awesome, size: 15, color: sage),
          label: Text(
            compact ? 'Study tool' : 'Quiz or flashcards',
            style: const TextStyle(fontSize: 11),
          ),
        ),
        const SizedBox(width: 10),
        PopupMenuButton<String>(
          onSelected: (v) => run(switch (v) {
            'project' => exportProject,
            'pdf' => () => exportPdf(selected!),
            _ => () => exportText(selected!),
          }),
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'project',
              child: Text('Portable project (.zenbox)'),
            ),
            if (selected != null && selected!.kind != 'asset')
              const PopupMenuItem(
                value: 'pdf',
                child: Text('Current note as PDF'),
              ),
            if (selected != null && selected!.kind != 'asset')
              const PopupMenuItem(
                value: 'markdown',
                child: Text('Current note as Markdown'),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: ink,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.ios_share, color: cream, size: 14),
                SizedBox(width: 8),
                Text('Export', style: TextStyle(color: cream, fontSize: 11)),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
