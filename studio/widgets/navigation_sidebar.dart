// ignore_for_file: invalid_use_of_protected_member
part of '../../studio.dart';

extension _StudioNavigationSidebar on _StudioState {
  Widget _navigationFolderEntry(Map<String, String> folder, {int depth = 0}) {
    final active =
        selectedResourceFolder == folder['id'] && mode == 'Media library';
    final directFiles = project
        .of('asset')
        .where((asset) => asset.meta['folderId'] == folder['id'])
        .length;
    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: () {
            navigate('Media library');
            setState(() => selectedResourceFolder = folder['id']!);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            margin: const EdgeInsets.only(bottom: 2),
            padding: EdgeInsets.fromLTRB(10 + depth * 12, 7, 10, 7),
            decoration: BoxDecoration(
              color: active
                  ? paleSage.withValues(alpha: .72)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 13,
                  color: active ? ink : muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    folder['name']!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                      color: active ? ink : muted,
                    ),
                  ),
                ),
                Text(
                  '$directFiles',
                  style: TextStyle(fontSize: 9, color: muted),
                ),
              ],
            ),
          ),
        ),
        for (final child in _foldersIn(folder['id']))
          _navigationFolderEntry(child, depth: depth + 1),
      ],
    );
  }

  Future<void> _chooseOverviewWallpaper() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Dashboard illustration',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Choose a Zenbox illustration or add your own image.',
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final option in bundledDashboardIllustrations)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        setState(() {
                          project.layout['overviewWallpaperAsset'] =
                              option.assetPath;
                          project.layout['dashboardWallpaperAsset'] =
                              option.assetPath;
                          project.layout.remove('overviewWallpaper');
                          project.layout.remove('dashboardWallpaper');
                        });
                        studioSettingsNotifier.value =
                            studioSettingsNotifier.value.copyWith(
                          dashboardWallpaperAsset: option.assetPath,
                          clearDashboardWallpaper: true,
                        );
                        saveLayout();
                        store.changed();
                        Navigator.pop(context);
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 120,
                            height: 74,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: (project.layout['overviewWallpaperAsset'] ??
                                            project.layout['dashboardWallpaperAsset'] ??
                                            studioSettingsNotifier.value.dashboardWallpaperAsset ??
                                            defaultDashboardWallpaperAsset) ==
                                        option.assetPath &&
                                    (project.layout['overviewWallpaper'] == null &&
                                        project.layout['dashboardWallpaper'] == null &&
                                        studioSettingsNotifier.value.dashboardWallpaper == null)
                                    ? sage
                                    : line,
                                width: (project.layout['overviewWallpaperAsset'] ??
                                            project.layout['dashboardWallpaperAsset'] ??
                                            studioSettingsNotifier.value.dashboardWallpaperAsset ??
                                            defaultDashboardWallpaperAsset) ==
                                        option.assetPath &&
                                    (project.layout['overviewWallpaper'] == null &&
                                        project.layout['dashboardWallpaper'] == null &&
                                        studioSettingsNotifier.value.dashboardWallpaper == null)
                                    ? 2.5
                                    : 1,
                              ),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.asset(option.assetPath, fit: BoxFit.cover),
                                if ((project.layout['overviewWallpaperAsset'] ??
                                            project.layout['dashboardWallpaperAsset'] ??
                                            studioSettingsNotifier.value.dashboardWallpaperAsset ??
                                            defaultDashboardWallpaperAsset) ==
                                        option.assetPath &&
                                    (project.layout['overviewWallpaper'] == null &&
                                        project.layout['dashboardWallpaper'] == null &&
                                        studioSettingsNotifier.value.dashboardWallpaper == null))
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: sage,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.check,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: 120,
                            child: Text(
                              option.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add_photo_alternate_outlined),
                title: const Text('Use custom image…'),
                subtitle: const Text('Pick any JPG, PNG, or WEBP from your computer'),
                onTap: () async {
                  final result = await FilePicker.pickFiles(
                    type: FileType.image,
                  );
                  if (result.isEmpty ||
                      result.single.path == null ||
                      !context.mounted) {
                    return;
                  }
                  final pickedPath = result.single.path!;
                  setState(() {
                    project.layout['overviewWallpaper'] = pickedPath;
                    project.layout['dashboardWallpaper'] = pickedPath;
                    project.layout.remove('overviewWallpaperAsset');
                    project.layout.remove('dashboardWallpaperAsset');
                  });
                  studioSettingsNotifier.value =
                      studioSettingsNotifier.value.copyWith(
                    dashboardWallpaper: pickedPath,
                    clearDashboardWallpaperAsset: true,
                  );
                  saveLayout();
                  store.changed();
                  if (context.mounted) Navigator.pop(context);
                },
              ),
              if (project.layout['overviewWallpaper'] != null ||
                  project.layout['dashboardWallpaper'] != null ||
                  project.layout['overviewWallpaperAsset'] != null ||
                  project.layout['dashboardWallpaperAsset'] != null ||
                  studioSettingsNotifier.value.dashboardWallpaper != null ||
                  studioSettingsNotifier.value.dashboardWallpaperAsset != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.restart_alt),
                  title: const Text('Restore default illustration'),
                  onTap: () {
                    setState(() {
                      project.layout.remove('overviewWallpaper');
                      project.layout.remove('dashboardWallpaper');
                      project.layout.remove('overviewWallpaperAsset');
                      project.layout.remove('dashboardWallpaperAsset');
                    });
                    studioSettingsNotifier.value =
                        studioSettingsNotifier.value.copyWith(
                      clearDashboardWallpaper: true,
                      clearDashboardWallpaperAsset: true,
                    );
                    saveLayout();
                    store.changed();
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget navigation(bool compact) => Container(
    width: compact ? 72 : 215,
    decoration: BoxDecoration(
      color: cream,
      border: Border(right: BorderSide(color: line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 25),
        if (!compact)
          Padding(
            padding: const EdgeInsets.only(left: 23, bottom: 14),
            child: Text(
              'STUDY WORKSPACE',
              style: TextStyle(fontSize: 9, letterSpacing: 1.7, color: muted),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (var i = 0; i < modes.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: DragTarget<CreativeObject>(
                    onAcceptWithDetails: (d) {
                      navigate(modes[i]);
                      setState(() => selectedId = d.data.id);
                      toast('Opened ${modes[i]} with "${d.data.title}"');
                    },
                    builder: (context, candidates, rejected) => Tooltip(
                      message: studyModeLabel(modes[i]),
                      child: Material(
                        color: candidates.isNotEmpty
                            ? paleSage
                            : mode == modes[i]
                            ? paleSage.withValues(alpha: .72)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => navigate(modes[i]),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: compact ? 13 : 12,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  modeIcons[i],
                                  size: 18,
                                  color: mode == modes[i] ? ink : muted,
                                ),
                                if (!compact) ...[
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      studyModeLabel(modes[i]),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: mode == modes[i]
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: mode == modes[i] ? ink : muted,
                                      ),
                                    ),
                                  ),
                                  if (modes[i] == 'Notes')
                                    Text(
                                      '${project.objects.where((o) => o.kind == 'script' || o.kind == 'manuscript').length}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: muted,
                                      ),
                                    ),
                                  if (modes[i] == 'Concept Bank / Glossary')
                                    Text(
                                      '${collectionObjects('Concept Bank / Glossary').length}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: muted,
                                      ),
                                    ),
                                  if (modes[i] == 'Quizzes & Flashcards')
                                    Text(
                                      '${project.objects.where((o) => o.kind == 'quiz' || o.kind == 'card').length}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: muted,
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // ── Resource folder tree: capped at one quarter of the dock height. ──
        if (!compact && resourceFolders.isNotEmpty)
          SizedBox(
            height: resourceTreeCollapsed
                ? 37
                : MediaQuery.sizeOf(context).height * .25,
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              padding: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: line)),
              ),
              child: Column(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(5),
                    onTap: () {
                      setState(
                        () => resourceTreeCollapsed = !resourceTreeCollapsed,
                      );
                      saveLayout();
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 5, 4, 5),
                      child: Row(
                        children: [
                          Icon(
                            resourceTreeCollapsed
                                ? Icons.chevron_right
                                : Icons.expand_more,
                            size: 16,
                            color: muted,
                          ),
                          Icon(
                            Icons.folder_open_outlined,
                            size: 11,
                            color: muted,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'FOLDERS',
                            style: TextStyle(
                              fontSize: 9,
                              letterSpacing: 1.2,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!resourceTreeCollapsed)
                    Expanded(
                      child: Scrollbar(
                        child: ListView(
                          padding: const EdgeInsets.only(bottom: 4),
                          children: [
                            for (final folder in _foldersIn(null))
                              _navigationFolderEntry(folder),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (!compact)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: paper.withValues(alpha: .6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline, color: gold, size: 20),
                  const SizedBox(height: 9),
                  const Text(
                    'A question to explore?',
                    style: TextStyle(fontFamily: 'Segoe UI', fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Capture it now. Connect it to your notes.',
                    style: TextStyle(fontSize: 10, color: muted),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: quickCapture,
                    child: const Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Quick capture',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(Icons.add, size: 15),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(10),
          child: compact
              ? IconButton(
                  tooltip: 'Settings & keyboard shortcuts',
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  onPressed: settings,
                  icon: const Icon(Icons.settings_outlined),
                )
              : Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: settings,
                        icon: const Icon(Icons.settings_outlined, size: 18),
                        label: const Text(
                          'Settings',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const Tag('LOCAL'),
                  ],
                ),
        ),
      ],
    ),
  );
}
