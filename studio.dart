import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse, PointerDeviceKind;
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ai.dart';
import 'document_ops.dart';
import 'editor.dart';
import 'model.dart';
import 'research_browser.dart';
import 'theme.dart';
import 'visual.dart';
import 'quiz_model.dart';
import 'quiz_service.dart';
import 'quiz_view.dart';
import 'focus_mode.dart';
import 'notification_service.dart';
import 'pdf_exporter.dart';
import 'study_workflow.dart';

const modes = [
  'Overview',
  'Notes',
  'Study Guide / Summary Doc',
  'Concept Bank / Glossary',
  'Mind Map / Concept Board',
  'Media library',
  'Storyboard',
  'Video',
  'Research',
  'Scratchpad',
  'Quizzes & Flashcards',
];
const modeIcons = [
  Icons.space_dashboard_outlined,
  Icons.edit_note,
  Icons.auto_stories_outlined,
  Icons.library_books_outlined,
  Icons.account_tree_outlined,
  Icons.photo_library_outlined,
  Icons.view_carousel_outlined,
  Icons.video_library_outlined,
  Icons.travel_explore,
  Icons.lightbulb_outline,
  Icons.school_outlined,
];

const dashboardWallpapers = [
  'assets/illustrations/learning_workspace_hero.png',
  'assets/illustrations/dashboard_hero.jpg',
  'assets/illustrations/dashboard_study_library.png',
  'assets/illustrations/dashboard_cozy_nook.png',
  'assets/illustrations/dashboard_note_arrangement.png',
];

class Studio extends StatefulWidget {
  const Studio({super.key, required this.store, this.studentMedia = false});
  final StudioStore store;
  final bool studentMedia;
  @override
  State<Studio> createState() => _StudioState();
}

class _FloatingWidgetEntry {
  const _FloatingWidgetEntry({required this.id, required this.asset});

  final int id;
  final CreativeObject asset;
}

class _StudioState extends State<Studio> with WidgetsBindingObserver {
  StudioStore get store => widget.store;
  Project get project => store.project;
  final ai = AiSession();
  String mode = 'Overview';
  String dock = 'AI';
  String? selectedId;
  bool showDock = true, showTray = false, focusMode = false, importing = false;
  double dockWidth = 306;
  String filter = '';
  Timer? sequenceTimer;
  int playingShot = -1;
  final List<_FloatingWidgetEntry> floatingWidgets = [];
  int _nextFloatingWidgetId = 0;
  bool storyboardGridView = false;
  bool scratchpadGridView = false;
  bool resourceGridView = false;
  bool resourceTreeCollapsed = false;
  String selectedResourceFolder = 'all';
  bool splitView = false;
  String secondaryMode = 'Scratchpad';
  double splitRatio = .5;
  CreativeObject? get selected => project.object(selectedId);
  String? activeToastMessage;
  Timer? _toastTimer;
  SelectionRequest? lastSelection;
  final ScrollController _trayScrollController = ScrollController();
  CreativeObject? activeDocument;
  String? previousModeBeforeDocument;
  String? expandedScratchpadId;
  QuizData? activePlayingQuiz;

  void openQuizGenerator({
    CreativeObject? source,
    QuizData? existingQuiz,
    StudyToolOutput output = StudyToolOutput.quiz,
  }) {
    QuizModal.show(
      context,
      store: store,
      session: ai,
      initialSource: source,
      initialOutput: output,
      existingQuiz: existingQuiz,
    );
  }

  void openFloatingVideo(CreativeObject asset) {
    setState(() {
      floatingWidgets.add(
        _FloatingWidgetEntry(id: _nextFloatingWidgetId++, asset: asset),
      );
    });
  }

  void closeFloatingWidget(int id) {
    setState(() => floatingWidgets.removeWhere((widget) => widget.id == id));
  }

  void applySelectionReplace(String newText) {
    if (lastSelection != null) {
      final targetObj = project.object(lastSelection!.objectId);
      if (targetObj != null) {
        store.snapshot(targetObj);
        try {
          replaceRange(
            targetObj,
            lastSelection!.start,
            lastSelection!.end,
            newText,
          );
          store.changed();
          setState(() {});
          toast('Replaced selected text in "${targetObj.title}"');
          return;
        } catch (_) {
          if (targetObj.body.contains(lastSelection!.text)) {
            targetObj.body = targetObj.body.replaceFirst(
              lastSelection!.text,
              newText,
            );
            store.changed();
            setState(() {});
            toast('Replaced text in "${targetObj.title}"');
            return;
          }
        }
      }
    }
    if (selected != null) {
      store.snapshot(selected!);
      appendText(selected!, newText);
      store.changed();
      setState(() {});
      toast('Text added to "${selected!.title}"');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    restoreLayout();
    if (widget.studentMedia) mode = 'Storyboard';
    store.addListener(refresh);
    BackgroundQuizManager.instance.tasksNotifier.addListener(refresh);
    BackgroundQuizManager.instance.addCompletionListener(
      _onBackgroundStudyToolCompleted,
    );
  }

  void _onBackgroundStudyToolCompleted(BackgroundQuizTask task) {
    if (!mounted || task.status != BackgroundQuizStatus.completed) return;
    final isCards = task.output == StudyToolOutput.flashcards;
    TopNotification.show(
      context,
      isCards
          ? '${task.savedObjects.length} flashcards generated in “${task.resultQuiz?.quizTitle ?? 'New deck'}”.'
          : 'Quiz “${task.resultQuiz?.quizTitle ?? task.sourceTitle}” has been generated.',
      icon: isCards ? Icons.style_outlined : Icons.quiz_outlined,
      duration: const Duration(seconds: 5),
    );
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  void restoreLayout() {
    mode = project.layout['mode'] as String? ?? 'Overview';
    if (!modes.contains(mode)) mode = 'Overview';
    dock = project.layout['dock'] as String? ?? 'AI';
    if (!['AI', 'Inspector', 'Assets', 'Focus', 'Progress'].contains(dock))
      dock = 'AI';
    showDock = project.layout['showDock'] as bool? ?? false;
    showTray = project.layout['showTray'] as bool? ?? false;
    dockWidth =
        (project.layout['dockWidth'] as num?)?.toDouble().clamp(260, 450) ??
        306;
    selectedId = project.layout['selected'] as String?;
    splitView = project.layout['splitView'] == true;
    scratchpadGridView = project.layout['scratchpadGridView'] == true;
    resourceGridView = project.layout['resourceGridView'] == true;
    resourceTreeCollapsed = project.layout['resourceTreeCollapsed'] == true;
    secondaryMode = project.layout['secondaryMode'] as String? ?? 'Scratchpad';
    if (!modes.contains(secondaryMode)) secondaryMode = 'Scratchpad';
    splitRatio =
        (project.layout['splitRatio'] as num?)?.toDouble().clamp(.25, .75) ??
        .5;
  }

  void saveLayout() {
    if (widget.studentMedia) {
      store.changed();
      return;
    }
    project.layout.addAll({
      'mode': mode,
      'dock': dock,
      'showDock': showDock,
      'showTray': showTray,
      'dockWidth': dockWidth,
      'selected': selectedId,
      'splitView': splitView,
      'scratchpadGridView': scratchpadGridView,
      'resourceGridView': resourceGridView,
      'resourceTreeCollapsed': resourceTreeCollapsed,
      'secondaryMode': secondaryMode,
      'splitRatio': splitRatio,
    });
    store.changed();
  }

  @override
  void dispose() {
    sequenceTimer?.cancel();
    _toastTimer?.cancel();
    _trayScrollController.dispose();
    ai.cancel();
    store.removeListener(refresh);
    BackgroundQuizManager.instance.tasksNotifier.removeListener(refresh);
    BackgroundQuizManager.instance.removeCompletionListener(
      _onBackgroundStudyToolCompleted,
    );
    store.save();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    store.save();
    return store.error == null ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) store.save();
  }

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      toast('$e');
    }
  }

  void toast(String text) {
    _toastTimer?.cancel();
    if (mounted) {
      setState(() => activeToastMessage = text);
      _toastTimer = Timer(const Duration(milliseconds: 2800), () {
        if (mounted) setState(() => activeToastMessage = null);
      });
    }
  }

  void dismissToast() {
    _toastTimer?.cancel();
    if (mounted) {
      setState(() => activeToastMessage = null);
    }
  }

  void navigate(String value) {
    sequenceTimer?.cancel();
    playingShot = -1;
    final resolved = switch (value) {
      'Screenplay' => 'Notes',
      'Manuscript' || 'Study Guide' => 'Study Guide / Summary Doc',
      'Story bible' ||
      'Concept Bank' ||
      'Glossary' => 'Concept Bank / Glossary',
      'Canvas' || 'Mind Map' || 'Concept Board' => 'Mind Map / Concept Board',
      _ => value,
    };
    setState(() {
      mode = resolved;
      filter = '';
      if (splitView && secondaryMode == resolved) {
        secondaryMode = modes.firstWhere(
          (candidate) => candidate != resolved,
          orElse: () => 'Scratchpad',
        );
      }
      if (resolved == 'Notes' || resolved == 'Study Guide / Summary Doc') {
        final kind = resolved == 'Notes' ? 'script' : 'manuscript';
        if (selected?.kind != kind) {
          selectedId = project.of(kind).firstOrNull?.id;
        }
      }
    });
    saveLayout();
  }

  void open(CreativeObject o) {
    if (o.kind == 'card') {
      setState(() => selectedId = o.id);
      reviewCard(o);
      return;
    }
    if (o.kind == 'quiz') {
      try {
        final quiz = QuizData.fromJson(jsonDecode(o.body));
        navigate('Quizzes & Flashcards');
        setState(() {
          selectedId = o.id;
          activePlayingQuiz = quiz;
        });
      } catch (_) {
        toast(
          'This quiz could not be opened. Its saved content is still available in Details.',
        );
      }
      return;
    }
    final destination =
        {
          'script': 'Notes',
          'manuscript': 'Study Guide / Summary Doc',
          'character': 'Concept Bank / Glossary',
          'location': 'Concept Bank / Glossary',
          'lore': 'Concept Bank / Glossary',
          'definition': 'Concept Bank / Glossary',
          'formula': 'Concept Bank / Glossary',
          'concept': 'Concept Bank / Glossary',
          'rule': 'Concept Bank / Glossary',
          'board': 'Mind Map / Concept Board',
          'asset': 'Media library',
          'shot': 'Storyboard',
          'research': 'Research',
          'note': 'Scratchpad',
          'card': 'Quizzes & Flashcards',
          'quiz': 'Quizzes & Flashcards',
          'generation': mode,
        }[o.kind] ??
        'Overview';
    navigate(destination);
    setState(() => selectedId = o.id);
    saveLayout();
    if (o.kind == 'asset') preview(o);
  }

  Future<void> createProject() async {
    final name = await askText(
      context,
      'A new study workspace',
      hint: 'Workspace / Course name',
    );
    if (name == null) return;
    final p = Project(
      title: name,
      description: 'A study workspace for notes, concepts, and guides.',
    );
    store.projects.add(p);
    store.select(p);
    setState(() {
      selectedId = null;
      mode = 'Overview';
    });
    saveLayout();
  }

  Future<void> create(String kind) async {
    final label = switch (kind) {
      'script' => 'topic / section',
      'manuscript' => 'chapter / study unit',
      'definition' => 'definition',
      'formula' => 'formula',
      'concept' => 'concept',
      'rule' => 'core rule / fact',
      'shot' => 'lesson segment',
      'character' => 'key concept',
      'location' => 'context',
      'lore' => 'background knowledge',
      _ => kind,
    };
    final name = await askText(context, 'New $label', hint: 'Give it a title');
    if (name == null) return;
    final o = CreativeObject(
      kind: kind,
      title: name,
      meta: {
        'status': 'Draft',
        if (kind == 'note') 'tray': true,
        if (kind == 'shot') 'duration': 5.0,
      },
    );
    store.add(o);
    open(o);
    if (kind == 'note' ||
        [
          'definition',
          'formula',
          'concept',
          'rule',
          'character',
          'location',
          'lore',
        ].contains(kind)) {
      openFloatingVideo(o);
    } else if (!['script', 'manuscript', 'asset'].contains(kind)) {
      await edit(o);
    }
  }

  Future<void> edit(CreativeObject o) async {
    setState(() => selectedId = o.id);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit ${studyKindLabel(o.kind)}'),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: ObjectForm(
              key: ValueKey(o.id),
              object: o,
              onChanged: store.changed,
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> remove(CreativeObject o) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove “${o.title}”?'),
        content: const Text(
          'This object and its links will be removed from the project.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final index = project.objects.indexOf(o);
    final p = project;
    final linked = {
      for (final item in p.objects.where((item) => item.links.contains(o.id)))
        item.id: List<String>.from(item.links),
    };
    store.remove(o);
    if (selectedId == o.id) selectedId = null;
    if (!mounted) return;
    TopNotification.show(
      context,
      'Removed ${o.title}',
      icon: Icons.delete_outline,
      actionLabel: 'Undo',
      onAction: () {
        p.objects.insert(index.clamp(0, p.objects.length), o);
        for (final entry in linked.entries) {
          p.object(entry.key)?.links = entry.value;
        }
        store.changed();
      },
    );
  }

  Future<void> importFiles() async {
    final p = project;
    final files = await FilePicker.pickFiles(dialogTitle: 'Import into Zenbox');
    if (files.isEmpty) return;
    setState(() => importing = true);
    try {
      for (final file in files) {
        if (file.path == null) continue;
        final ext = file.name.split('.').last.toLowerCase();
        if (['txt', 'md'].contains(ext)) {
          final isGuide = mode.startsWith('Study Guide');
          p.objects.add(
            CreativeObject(
              kind: isGuide ? 'manuscript' : 'script',
              title: file.name.replaceAll(
                RegExp(r'\.(md|txt)$', caseSensitive: false),
                '',
              ),
              body: await File(file.path!).readAsString(),
            ),
          );
        } else {
          p.objects.add(await store.importMedia(file.path!, file.name));
        }
        store.changed();
      }
      toast('Imported ${files.length} files');
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> exportText(CreativeObject o) async {
    const ext = 'md';
    final result = await FilePicker.saveFile(
      fileName: '${safeName(o.title)}.$ext',
      bytes: Uint8List.fromList(utf8.encode(o.body)),
      dialogTitle: 'Export document as Markdown',
    );
    if (result != null) toast('Markdown exported: ${o.title}');
  }

  Future<void> exportPdf(CreativeObject o) async {
    final result = await FilePicker.saveFile(
      fileName: '${safeName(o.title)}.pdf',
      bytes: await NotePdfExporter(store: store, project: project).build(o),
      dialogTitle: 'Export note as PDF',
    );
    if (result != null) toast('PDF exported: ${o.title}');
  }

  String safeName(String value) =>
      value.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  Future<void> exportProject() async {
    store.save();
    final archive = Archive();
    final manifest = utf8.encode(
      jsonEncode({'version': 1, 'project': project.toJson()}),
    );
    archive.addFile(ArchiveFile('project.json', manifest.length, manifest));
    for (final asset in project.of('asset')) {
      final file = File(store.mediaPath(asset));
      if (!await file.exists()) {
        throw Exception(
          'Missing media: ${asset.title}. Restore the file before making a portable backup.',
        );
      }
      final bytes = await file.readAsBytes();
      archive.addFile(
        ArchiveFile('media/${asset.meta['file']}', bytes.length, bytes),
      );
      final posterName = asset.meta['thumbnail'];
      if (posterName is String) {
        final poster = File('${store.directory.path}/media/$posterName');
        if (await poster.exists()) {
          final posterBytes = await poster.readAsBytes();
          archive.addFile(
            ArchiveFile('media/$posterName', posterBytes.length, posterBytes),
          );
        }
      }
    }
    final result = await FilePicker.saveFile(
      fileName: '${safeName(project.title)}.zenbox',
      bytes: Uint8List.fromList(ZipEncoder().encode(archive)),
      dialogTitle: 'Save portable Zenbox project with media',
    );
    if (result != null) toast('Portable Zenbox project saved with all media');
  }

  Future<void> importProject() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['zenbox', 'xandora'],
      dialogTitle: 'Open a portable Zenbox project',
    );
    if (file == null) return;
    if (await File(file.path!).length() > 512 * 1024 * 1024) {
      throw const FormatException(
        'This archive exceeds the 512 MB import limit.',
      );
    }
    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    if (archive.files.fold<int>(0, (sum, f) => sum + f.size) >
        1024 * 1024 * 1024) {
      throw const FormatException('Expanded project exceeds 1 GB.');
    }
    final manifest = archive.findFile('project.json');
    if (manifest == null) {
      throw const FormatException('Not a valid Zenbox project archive');
    }
    final data =
        jsonDecode(utf8.decode(manifest.content)) as Map<String, dynamic>;
    if (data['version'] != 1) {
      throw const FormatException('Unsupported project version');
    }
    final imported = Project.fromJson(
      Map<String, dynamic>.from(data['project']),
    );
    final ids = imported.objects.map((o) => o.id).toSet();
    if (ids.length != imported.objects.length) {
      throw const FormatException('Duplicate object IDs');
    }
    for (final asset in imported.of('asset')) {
      final name = asset.meta['file'];
      if (name is! String || !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(name)) {
        throw const FormatException('Invalid media filename');
      }
      if (archive.findFile('media/$name') == null) {
        throw FormatException('Missing media: $name');
      }
      final posterName = asset.meta['thumbnail'];
      if (posterName is String &&
          (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(posterName) ||
              archive.findFile('media/$posterName') == null)) {
        asset.meta.remove('thumbnail');
      }
    }
    for (final asset in imported.of('asset')) {
      final name = asset.meta['file'] as String;
      final bytes = archive.findFile('media/$name')!.content;
      final newName = '${newId()}.${name.split('.').last}';
      await File(
        '${store.directory.path}/media/$newName',
      ).writeAsBytes(bytes, flush: true);
      asset.meta['file'] = newName;
      final posterName = asset.meta['thumbnail'];
      if (posterName is String) {
        final posterBytes = archive.findFile('media/$posterName')!.content;
        final newPosterName = '${newId()}-thumb.jpg';
        await File(
          '${store.directory.path}/media/$newPosterName',
        ).writeAsBytes(posterBytes, flush: true);
        asset.meta['thumbnail'] = newPosterName;
      }
    }
    final p = Project(
      title: imported.title,
      description: imported.description,
      objects: imported.objects,
      layout: imported.layout,
    );
    store.projects.add(p);
    store.select(p);
    restoreLayout();
    toast('Project imported');
  }

  Future<void> preview(CreativeObject o) async {
    if (o.kind == 'quiz') {
      try {
        final data = QuizData.fromJson(jsonDecode(o.body));
        openQuizGenerator(existingQuiz: data);
        return;
      } catch (_) {}
    }
    final docExt =
        o.meta['file']?.toString().split('.').last.toLowerCase() ?? '';
    final isDoc =
        [
          'pdf',
          'docx',
          'doc',
          'txt',
          'md',
          'csv',
          'json',
          'log',
        ].contains(docExt) ||
        o.meta['mediaType'] == 'document' ||
        o.kind == 'source';

    if (isDoc) {
      setState(() {
        activeDocument = o;
        previousModeBeforeDocument = mode;
        mode = 'Document Viewer';
      });
      return;
    }
    if (o.kind != 'asset' && o.kind != 'source') {
      openFloatingVideo(o);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 1050,
          height: 690,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
                child: Row(
                  children: [
                    Expanded(child: Text(o.title)),
                    TextButton.icon(
                      onPressed: () => run(() async {
                        final result = await FilePicker.saveFile(
                          fileName: safeName(o.title),
                          bytes: await File(store.mediaPath(o)).readAsBytes(),
                        );
                        if (result != null) toast('Original exported');
                      }),
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Export original'),
                    ),
                    Builder(
                      builder: (context) {
                        final docExt =
                            o.meta['file']
                                ?.toString()
                                .split('.')
                                .last
                                .toLowerCase() ??
                            '';
                        final isDoc =
                            [
                              'pdf',
                              'docx',
                              'doc',
                              'txt',
                              'md',
                              'csv',
                              'json',
                              'log',
                            ].contains(docExt) ||
                            o.meta['mediaType'] == 'document' ||
                            o.kind == 'source';
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isDoc)
                              TextButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  openQuizGenerator(source: o);
                                },
                                icon: const Icon(Icons.quiz_outlined, size: 16),
                                label: const Text('Quiz or cards'),
                              ),
                            TextButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                openFloatingVideo(o);
                              },
                              icon: const Icon(
                                Icons.picture_in_picture_alt,
                                size: 16,
                              ),
                              label: Text(
                                o.meta['mediaType'] == 'video'
                                    ? 'Pop out video'
                                    : (o.meta['mediaType'] == 'image'
                                          ? 'Float image'
                                          : isDoc
                                          ? 'Pop out document'
                                          : 'Float item'),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: MediaPreview(
                  key: ValueKey(o.id),
                  store: store,
                  asset: o,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> quickCapture() async {
    final text = await askText(
      context,
      'Catch a thought',
      hint: 'A line of dialogue, a question, a wild idea…',
      multiline: true,
    );
    if (text == null) return;
    final o = CreativeObject(
      kind: 'note',
      title: text.split('\n').first.length > 55
          ? '${text.substring(0, 55)}…'
          : text.split('\n').first,
      body: text,
      meta: {'tray': true},
    );
    store.add(o);
    toast('Thought saved to your scratchpad');
  }

  Future<void> commandPalette() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _CommandPalette(
        project: project,
        onMode: navigate,
        onObject: open,
        onCapture: quickCapture,
        onNew: createProject,
      ),
    );
  }

  Widget drag(CreativeObject o, Widget child) => Draggable<CreativeObject>(
    data: o,
    feedback: Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(7),
      color: paper,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Text(o.title, style: TextStyle(fontSize: 12, color: ink)),
      ),
    ),
    childWhenDragging: Opacity(opacity: .45, child: child),
    child: child,
  );
  @override
  Widget build(BuildContext context) => widget.studentMedia
      ? Material(
          color: paper,
          child: Stack(
            children: [
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Presentation plan'),
                          selected: mode != 'Video',
                          onSelected: (_) =>
                              setState(() => mode = 'Storyboard'),
                        ),
                        ChoiceChip(
                          label: const Text('Preview sequence'),
                          selected: mode == 'Video',
                          onSelected: (_) => setState(() => mode = 'Video'),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.link, size: 16),
                          label: const Text('Attach media to segment'),
                          onPressed: shots.isEmpty
                              ? null
                              : () async {
                                  final target = selected?.kind == 'shot'
                                      ? selected!
                                      : shots.first;
                                  await showDialog<void>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: Text('Media for ${target.title}'),
                                      content: SizedBox(
                                        width: 400,
                                        height: 400,
                                        child: ListView(
                                          children: project
                                              .of('asset')
                                              .map(
                                                (o) => CheckboxListTile(
                                                  title: Text(o.title),
                                                  value: target.links.contains(
                                                    o.id,
                                                  ),
                                                  onChanged: (v) {
                                                    if (v == true) {
                                                      target.links.add(o.id);
                                                    } else {
                                                      target.links.remove(o.id);
                                                    }
                                                    store.changed();
                                                    Navigator.pop(context);
                                                  },
                                                ),
                                              )
                                              .toList(),
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text('Done'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: production()),
                ],
              ),
              for (var i = 0; i < floatingWidgets.length; i++)
                FloatingVideoPlayer(
                  key: ValueKey(floatingWidgets[i].id),
                  store: store,
                  asset: floatingWidgets[i].asset,
                  initialPosition: Offset(40 + i * 24, 60 + i * 24),
                  onClose: () => closeFloatingWidget(floatingWidgets[i].id),
                ),
            ],
          ),
        )
      : CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                commandPalette,
            const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
              store.save();
              toast(store.saveState);
            },
            const SingleActivator(
              LogicalKeyboardKey.space,
              control: true,
              shift: true,
            ): quickCapture,
            const SingleActivator(LogicalKeyboardKey.keyB, control: true): () {
              setState(() => focusMode = !focusMode);
            },
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (focusMode) setState(() => focusMode = false);
            },
          },
          child: Focus(
            autofocus: true,
            child: Stack(
              children: [
                Scaffold(
                  body: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 1100;
                      final dockVisible =
                          showDock &&
                          !focusMode &&
                          constraints.maxWidth >= 1000;
                      return Column(
                        children: [
                          topBar(compact),
                          Expanded(
                            child: Row(
                              children: [
                                if (!focusMode) navigation(compact),
                                Expanded(
                                  child: Column(
                                    children: [
                                      Expanded(
                                        child: splitView && !focusMode
                                            ? splitWorkspace()
                                            : TweenAnimationBuilder<double>(
                                                key: ValueKey(mode),
                                                tween: Tween(begin: 0, end: 1),
                                                duration: Duration(
                                                  milliseconds:
                                                      MediaQuery.disableAnimationsOf(
                                                        context,
                                                      )
                                                      ? 0
                                                      : 180,
                                                ),
                                                builder: (_, opacity, child) =>
                                                    Opacity(
                                                      opacity: opacity,
                                                      child: child,
                                                    ),
                                                child: workspace(),
                                              ),
                                      ),
                                      if (showTray && !focusMode) tray(),
                                    ],
                                  ),
                                ),
                                if (dockVisible) ...[
                                  MouseRegion(
                                    cursor: SystemMouseCursors.resizeColumn,
                                    child: GestureDetector(
                                      onHorizontalDragUpdate: (d) {
                                        setState(
                                          () => dockWidth =
                                              (dockWidth - d.delta.dx).clamp(
                                                260,
                                                450,
                                              ),
                                        );
                                      },
                                      onHorizontalDragEnd: (_) => saveLayout(),
                                      child: Container(
                                        width: 5,
                                        color: line.withValues(alpha: .5),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: dockWidth,
                                    child: rightDock(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          statusBar(),
                          if (store.error != null)
                            Container(
                              width: double.infinity,
                              color: const Color(0xFFF0DDD2),
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                store.error!,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                for (var index = 0; index < floatingWidgets.length; index++)
                  FloatingVideoPlayer(
                    key: ValueKey(floatingWidgets[index].id),
                    store: store,
                    asset: floatingWidgets[index].asset,
                    initialPosition: Offset(
                      120.0 + index * 28,
                      100.0 + index * 28,
                    ),
                    onClose: () =>
                        closeFloatingWidget(floatingWidgets[index].id),
                  ),
                if (activeToastMessage != null)
                  Positioned(
                    top: 18,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Material(
                        elevation: 12,
                        color: Colors.transparent,
                        child: Container(
                          constraints: const BoxConstraints(
                            maxWidth: 440,
                            minWidth: 220,
                          ),
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                          decoration: BoxDecoration(
                            color: ink.withValues(alpha: 0.96),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: sage.withValues(alpha: 0.6),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.22),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: paleSage,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  activeToastMessage!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: cream,
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: dismissToast,
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(3),
                                  child: Icon(
                                    Icons.close,
                                    size: 13,
                                    color: paleSage.withValues(alpha: 0.8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
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
                (p) => PopupMenuItem(value: p.id, child: Text(p.title)),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'new', child: Text('+ New course')),
              const PopupMenuItem(
                value: 'import',
                child: Text('Import project…'),
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
                secondaryMode = mode == 'Scratchpad'
                    ? 'Mind Map / Concept Board'
                    : 'Scratchpad';
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
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Wrap(
            runSpacing: 8,
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Dashboard illustration'),
                subtitle: Text(
                  'Choose a Zenbox illustration or add your own image.',
                ),
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final asset in dashboardWallpapers)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        setState(() {
                          project.layout['overviewWallpaperAsset'] = asset;
                          project.layout.remove('overviewWallpaper');
                        });
                        saveLayout();
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: 118,
                        height: 74,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color:
                                project.layout['overviewWallpaperAsset'] ==
                                    asset
                                ? sage
                                : line,
                            width:
                                project.layout['overviewWallpaperAsset'] ==
                                    asset
                                ? 2
                                : 1,
                          ),
                        ),
                        child: Image.asset(asset, fit: BoxFit.cover),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add_photo_alternate_outlined),
                title: const Text('Use my image…'),
                onTap: () async {
                  final result = await FilePicker.pickFiles(
                    type: FileType.image,
                  );
                  if (result.isEmpty ||
                      result.single.path == null ||
                      !context.mounted)
                    return;
                  setState(() {
                    project.layout['overviewWallpaper'] = result.single.path;
                    project.layout.remove('overviewWallpaperAsset');
                  });
                  saveLayout();
                  if (context.mounted) Navigator.pop(context);
                },
              ),
              if (project.layout['overviewWallpaper'] != null ||
                  project.layout['overviewWallpaperAsset'] != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.restart_alt),
                  title: const Text('Restore default illustration'),
                  onTap: () {
                    setState(() {
                      project.layout.remove('overviewWallpaper');
                      project.layout.remove('overviewWallpaperAsset');
                    });
                    saveLayout();
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
              for (final i in [0, 1, 2, 3, 4, 10, 6, 7, 8, 5, 9])
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
                                  if (modes[i] == 'Scratchpad')
                                    Text(
                                      '${project.of('note').length}',
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
  Widget statusBar() {
    final runningStudyTools = BackgroundQuizManager.instance.tasksNotifier.value
        .where((task) => task.status == BackgroundQuizStatus.running)
        .toList();
    return Container(
      height: 27,
      color: paper,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Icon(
            store.error == null
                ? Icons.check_circle_outline
                : Icons.error_outline,
            size: 11,
            color: store.error == null ? sage : Colors.red,
          ),
          const SizedBox(width: 6),
          Text(store.saveState, style: TextStyle(fontSize: 9, color: muted)),
          const SizedBox(width: 20),
          Text(
            '${project.objects.length} objects',
            style: TextStyle(fontSize: 9, color: muted),
          ),
          const Spacer(),
          if (runningStudyTools.isNotEmpty) ...[
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.7, color: sage),
            ),
            const SizedBox(width: 7),
            Text(
              runningStudyTools.length == 1
                  ? 'Generating ${runningStudyTools.first.output == StudyToolOutput.quiz ? 'quiz' : 'flashcards'}…'
                  : 'Generating ${runningStudyTools.length} study tools…',
              style: TextStyle(
                fontSize: 9,
                color: sage,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 18),
          ],
          if (importing)
            Text(
              'Importing files…',
              style: TextStyle(fontSize: 9, color: muted),
            ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 20),
            ),
            onPressed: () {
              setState(() => showTray = !showTray);
              saveLayout();
            },
            child: Text(
              '${showTray ? 'Hide' : 'Show'} temporary tray',
              style: TextStyle(fontSize: 9, color: muted),
            ),
          ),
          const SizedBox(width: 15),
          Text(
            'MADE FOR YOUR NEXT IDEA',
            style: TextStyle(fontSize: 8, color: muted, letterSpacing: 1.2),
          ),
        ],
      ),
    );
  }

  Widget splitWorkspace() => LayoutBuilder(
    builder: (context, constraints) {
      final horizontal = constraints.maxWidth >= 820;
      final secondary = Column(
        children: [
          Container(
            height: 42,
            padding: const EdgeInsets.only(left: 12, right: 4),
            decoration: BoxDecoration(
              color: cream.withValues(alpha: .65),
              border: Border(bottom: BorderSide(color: line)),
            ),
            child: Row(
              children: [
                Icon(Icons.splitscreen_outlined, size: 15, color: sage),
                const SizedBox(width: 8),
                Text(
                  'SECOND PANE',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
                const Spacer(),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: secondaryMode == mode
                        ? modes.firstWhere((candidate) => candidate != mode)
                        : secondaryMode,
                    isDense: true,
                    borderRadius: BorderRadius.circular(8),
                    items: modes
                        .where((candidate) => candidate != mode)
                        .map(
                          (candidate) => DropdownMenuItem(
                            value: candidate,
                            child: Text(
                              studyModeLabel(candidate),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => secondaryMode = value);
                      saveLayout();
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Close split workspace',
                  iconSize: 17,
                  onPressed: () {
                    setState(() => splitView = false);
                    saveLayout();
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(child: workspace(secondaryMode)),
        ],
      );
      final primaryFlex = (splitRatio * 1000).round();
      final secondaryFlex = 1000 - primaryFlex;
      final divider = MouseRegion(
        cursor: horizontal
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        child: GestureDetector(
          key: const ValueKey('workspace-split-divider'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: horizontal
              ? (details) => setState(() {
                  splitRatio =
                      (splitRatio + details.delta.dx / constraints.maxWidth)
                          .clamp(.25, .75);
                })
              : null,
          onHorizontalDragEnd: horizontal ? (_) => saveLayout() : null,
          onVerticalDragUpdate: horizontal
              ? null
              : (details) => setState(() {
                  splitRatio =
                      (splitRatio + details.delta.dy / constraints.maxHeight)
                          .clamp(.25, .75);
                }),
          onVerticalDragEnd: horizontal ? null : (_) => saveLayout(),
          child: SizedBox(
            width: horizontal ? 9 : double.infinity,
            height: horizontal ? double.infinity : 9,
            child: Center(
              child: Container(
                width: horizontal ? 2 : 42,
                height: horizontal ? 42 : 2,
                decoration: BoxDecoration(
                  color: sage.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      );
      return horizontal
          ? Row(
              children: [
                Expanded(flex: primaryFlex, child: workspace()),
                divider,
                Expanded(flex: secondaryFlex, child: secondary),
              ],
            )
          : Column(
              children: [
                Expanded(flex: primaryFlex, child: workspace()),
                divider,
                Expanded(flex: secondaryFlex, child: secondary),
              ],
            );
    },
  );

  Widget workspace([String? requestedMode]) {
    final workspaceMode = requestedMode ?? mode;
    switch (workspaceMode) {
      case 'Overview':
        return overview();
      case 'Notes':
      case 'Screenplay':
      case 'Study Guide / Summary Doc':
      case 'Study Guide':
      case 'Manuscript':
        return writing(workspaceMode);
      case 'Mind Map / Concept Board':
      case 'Mind Map':
      case 'Canvas':
        return CanvasWorkspace(
          key: ValueKey(project.id),
          store: store,
          edit: edit,
          remove: remove,
          select: (o) {
            setState(() => selectedId = o.id);
          },
        );
      case 'Storyboard':
      case 'Video':
        return production(workspaceMode);
      case 'Research':
        return ResearchBrowserView(store: store, onOpenNote: edit);
      case 'Scratchpad':
        return scratchpadWorkspace();
      case 'Quizzes & Flashcards':
        return quizAndFlashcardsWorkspace();
      case 'Document Viewer':
        return documentViewerWorkspace();
      default:
        return collection(workspaceMode);
    }
  }

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
            builder: (context, candidates, rejected) => Container(
              height: 220,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: candidates.isNotEmpty
                    ? sage.withValues(alpha: .2)
                    : paleSage,
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
                            project.layout['overviewWallpaper'] as String?;
                        final illustration =
                            project.layout['overviewWallpaperAsset']
                                as String? ??
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
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Color(0xF2E4ECD9),
                              Color(0xD8E4ECD9),
                              Color(0x28E4ECD9),
                              Color(0x00E4ECD9),
                            ],
                            stops: [0, .40, .70, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 27,
                    top: 26,
                    right: MediaQuery.sizeOf(context).width < 760 ? 120 : 340,
                    bottom: 22,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Tag('CURRENT COURSE', color: paper),
                        const Spacer(),
                        Text(
                          project.title,
                          style: TextStyle(
                            fontFamily: 'Segoe UI',
                            fontSize: 31,
                            height: 1.12,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          project.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.6,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 16),
                        InkWell(
                          onTap: () => navigate('Notes'),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Continue studying',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(width: 9),
                              Icon(Icons.arrow_forward, size: 15),
                            ],
                          ),
                        ),
                      ],
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
            ),
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
              const Text(
                'Continue learning',
                style: TextStyle(fontFamily: 'Segoe UI', fontSize: 21),
              ),
              const Spacer(),
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
                'Storyboard',
                'See the story unfold.',
                Icons.view_carousel_outlined,
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
                title,
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

  Widget writing([String? requestedMode]) {
    final writingMode = requestedMode ?? mode;
    final kind = (writingMode == 'Notes' || writingMode == 'Screenplay')
        ? 'script'
        : 'manuscript';
    final documents = project.of(kind).toList();
    final current = selected?.kind == kind ? selected : documents.firstOrNull;
    if (current == null) {
      return EmptyState(
        Icons.edit_outlined,
        'Start with a topic you want to understand.',
        'Create a ${kind == 'script' ? 'topic' : 'study unit'} to begin.',
        action: FilledButton.icon(
          onPressed: () => create(kind),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Create note'),
        ),
      );
    }
    return Column(
      children: [
        studyActions(current),
        Expanded(
          child: DocumentEditor(
            key: ValueKey(current.id),
            store: store,
            object: current,
            siblingDocuments: documents,
            onSwitchDocument: (document) {
              setState(() => selectedId = document.id);
              saveLayout();
            },
            onNewDocument: () => create(kind),
            onInspect: () {
              setState(() {
                dock = 'Inspector';
                showDock = true;
              });
            },
            onExport: () => run(() => exportPdf(current)),
            onAskAi: (req) {
              lastSelection = req;
              setState(() {
                dock = 'AI';
                showDock = true;
              });
              ai.ask('Regarding "${req.text}":\n${req.action}');
            },
            onPreview: preview,
            onDelete: () => remove(current),
          ),
        ),
      ],
    );
  }

  List<CreativeObject> collectionObjects([String? requestedMode]) {
    final collectionMode = requestedMode ?? mode;
    final kinds = switch (collectionMode) {
      'Concept Bank / Glossary' || 'Concept Bank' || 'Story bible' => [
        'definition',
        'formula',
        'concept',
        'rule',
        'character',
        'location',
        'lore',
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
      ],
    );
  }

  Widget _resourceFolderCard(
    Map<String, String> folder,
    List<CreativeObject> assets, {
    bool grid = false,
  }) {
    final itemCount = assets
        .where((asset) => asset.meta['folderId'] == folder['id'])
        .length;
    final organizer = PopupMenuButton<String>(
      tooltip: 'Folder options',
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
      icon: const Icon(Icons.more_horiz, size: 18),
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
              onTap: () {
                navigate('Media library');
                setState(() => selectedResourceFolder = folder['id']!);
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isHovered ? Colors.transparent : line,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: grid
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.folder_rounded,
                            size: 58,
                            color: isHovered ? gold : gold,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  folder['name']!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              organizer,
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$itemCount ${itemCount == 1 ? 'resource' : 'resources'}',
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                          if (isHovered)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
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
    final folderName = folders
        .where((folder) => folder['id'] == resource.meta['folderId'])
        .map((folder) => folder['name'])
        .firstOrNull;
    final organizer = PopupMenuButton<String>(
      tooltip: 'Organize resource',
      onSelected: (folder) {
        if (folder == 'delete') {
          remove(resource);
        } else {
          _moveResourceToFolder(resource, folder);
        }
      },
      itemBuilder: (_) => [
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
              Icon(Icons.delete_outline, size: 17),
              SizedBox(width: 8),
              Text('Delete resource'),
            ],
          ),
        ),
      ],
      icon: const Icon(Icons.drive_file_move_outline, size: 19),
    );
    final card = Material(
      color: paper,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => preview(resource),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            border: Border.all(color: line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: grid
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: double.infinity,
                          child: AssetThumbnail(store: store, asset: resource),
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
  Widget tray() => DragTarget<CreativeObject>(
    onAcceptWithDetails: (d) {
      d.data.meta['tray'] = true;
      store.changed();
    },
    builder: (context, candidates, rejected) {
      final trayItems = project.objects
          .where((o) => o.meta['tray'] == true)
          .toList();
      return Container(
        height: 84,
        decoration: BoxDecoration(
          color: candidates.isNotEmpty ? paleSage : cream,
          border: Border(top: BorderSide(color: line)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.inventory_2_outlined, size: 17, color: muted),
                const SizedBox(height: 4),
                Text(
                  'TEMPORARY TRAY',
                  style: TextStyle(fontSize: 8, color: muted, letterSpacing: 1),
                ),
                Text(
                  '${trayItems.length} pinned',
                  style: TextStyle(
                    fontSize: 8,
                    color: sage,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            if (trayItems.isNotEmpty)
              IconButton(
                tooltip: 'Scroll left',
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: () {
                  if (_trayScrollController.hasClients) {
                    _trayScrollController.animateTo(
                      (_trayScrollController.offset - 260).clamp(
                        0.0,
                        _trayScrollController.position.maxScrollExtent,
                      ),
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  }
                },
              ),
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                    PointerDeviceKind.stylus,
                  },
                ),
                child: Scrollbar(
                  controller: _trayScrollController,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _trayScrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 14,
                    ),
                    itemCount: trayItems.length,
                    itemBuilder: (context, index) {
                      final o = trayItems[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: drag(
                          o,
                          Container(
                            width: 230,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: paper,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: line),
                            ),
                            child: Row(
                              children: [
                                if (o.kind == 'asset' &&
                                    o.meta['mediaType'] == 'image')
                                  Container(
                                    width: 34,
                                    height: 34,
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: line),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: AssetThumbnail(
                                        store: store,
                                        asset: o,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  )
                                else if (o.kind == 'asset')
                                  Container(
                                    width: 34,
                                    height: 34,
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      color: paleSage.withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Icon(
                                      o.meta['mediaType'] == 'video'
                                          ? Icons.videocam_outlined
                                          : Icons.attachment,
                                      size: 17,
                                      color: sage,
                                    ),
                                  )
                                else
                                  Container(
                                    width: 34,
                                    height: 34,
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      color: cream,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Icon(
                                      o.kind == 'quiz'
                                          ? Icons.quiz_outlined
                                          : (o.kind == 'card'
                                                ? Icons.flip_to_back_outlined
                                                : (o.kind == 'script'
                                                      ? Icons.movie_outlined
                                                      : (o.kind == 'research'
                                                            ? Icons
                                                                  .travel_explore
                                                            : Icons
                                                                  .note_outlined))),
                                      size: 17,
                                      color: sage,
                                    ),
                                  ),
                                Expanded(
                                  child: InkWell(
                                    onTap: () => open(o),
                                    child: Text(
                                      o.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Float in overlay (PIP)',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                  onPressed: () => openFloatingVideo(o),
                                  icon: const Icon(
                                    Icons.picture_in_picture_alt,
                                    size: 14,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remove from tray',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 20,
                                    minHeight: 20,
                                  ),
                                  onPressed: () {
                                    o.meta['tray'] = false;
                                    store.changed();
                                  },
                                  icon: const Icon(Icons.close, size: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            if (trayItems.isNotEmpty)
              IconButton(
                tooltip: 'Scroll right',
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: () {
                  if (_trayScrollController.hasClients) {
                    _trayScrollController.animateTo(
                      (_trayScrollController.offset + 260).clamp(
                        0.0,
                        _trayScrollController.position.maxScrollExtent,
                      ),
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  }
                },
              ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Capture a thought',
              onPressed: quickCapture,
              icon: const Icon(Icons.add, size: 18),
            ),
            const SizedBox(width: 8),
          ],
        ),
      );
    },
  );
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
    final productionMode = requestedMode ?? mode;
    final video = productionMode == 'Video';
    final current = selected?.kind == 'shot' ? selected : items.firstOrNull;
    final asset = current == null ? null : shotAsset(current);
    return Column(
      children: [
        SectionHeading(
          widget.studentMedia
              ? 'Present what you understand'
              : 'EXPLAIN & REMEMBER',
          widget.studentMedia
              ? (video
                    ? 'Presentation preview'
                    : 'Your presentation, step by step')
              : (video
                    ? 'Rehearse your explanation'
                    : 'Plan a lesson, topic by topic'),
          subtitle:
              '${items.length} segments · ${items.fold<double>(0, (n, o) => n + (o.meta['duration'] as num? ?? 5).toDouble()).toStringAsFixed(1)} seconds · drag segments to reorder',
          actions: [
            IconButton(
              tooltip: storyboardGridView
                  ? 'Switch to lesson sequence'
                  : 'Switch to topic cards',
              onPressed: () =>
                  setState(() => storyboardGridView = !storyboardGridView),
              icon: Icon(
                storyboardGridView
                    ? Icons.view_agenda_outlined
                    : Icons.grid_view_rounded,
              ),
            ),
            IconButton(
              tooltip: 'Export lesson plan as CSV',
              onPressed: () => run(exportShots),
              icon: const Icon(Icons.download_outlined),
            ),
            FilledButton.icon(
              onPressed: () => create('shot'),
              icon: const Icon(Icons.add, size: 16),
              label: Text(widget.studentMedia ? 'New segment' : 'New segment'),
            ),
          ],
        ),
        Expanded(
          child: items.isEmpty
              ? EmptyState(
                  Icons.movie_creation_outlined,
                  widget.studentMedia
                      ? 'Plan your first explanation.'
                      : 'Explain your first topic.',
                  widget.studentMedia
                      ? 'Add a presentation segment, write its talking points, and attach an image or recording.'
                      : 'Break a chapter into steps. Link each segment to notes, diagrams, or recordings.',
                  action: FilledButton(
                    onPressed: () => create('shot'),
                    child: Text(
                      widget.studentMedia ? 'Add segment' : 'Add segment',
                    ),
                  ),
                )
              : video
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(30, 0, 30, 20),
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: ink,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: asset != null
                              ? MediaPreview(
                                  key: ValueKey('${asset.id}-$playingShot'),
                                  store: store,
                                  asset: asset,
                                  autoplay: playingShot >= 0,
                                )
                              : Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.panorama_outlined,
                                        size: 38,
                                        color: paleSage,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        current?.title ?? 'Select a segment',
                                        style: TextStyle(
                                          fontFamily: 'Segoe UI',
                                          fontSize: 24,
                                          color: cream,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 35,
                                        ),
                                        child: Text(
                                          current?.body ?? '',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: paleSage,
                                            fontSize: 12,
                                            height: 1.7,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      TextButton(
                                        onPressed: () {
                                          setState(() {
                                            selectedId = current?.id;
                                            dock = 'Inspector';
                                            showDock = true;
                                          });
                                        },
                                        child: Text(
                                          'Link footage or a storyboard frame',
                                          style: TextStyle(
                                            color: gold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          IconButton(
                            tooltip: playingShot >= 0
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
                              size: 30,
                              color: ink,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              current?.title ?? '',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Tag(
                            current?.meta['camera'] as String? ?? 'Explanation',
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${current?.meta['duration'] ?? 5}s',
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : storyboardGridView
              ? GridView.builder(
                  padding: const EdgeInsets.fromLTRB(30, 0, 30, 25),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 330,
                    mainAxisExtent: 320,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final shot = items[index];
                    return StoryboardCard(
                      key: ValueKey(shot.id),
                      store: store,
                      shot: shot,
                      index: index,
                      selected: selectedId == shot.id,
                      isGrid: true,
                      onTap: () {
                        setState(() {
                          selectedId = shot.id;
                          dock = 'Inspector';
                          showDock = true;
                        });
                      },
                      onEdit: () => edit(shot),
                      onPlayVideo: openFloatingVideo,
                      onDelete: () => remove(shot),
                    );
                  },
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(30, 0, 30, 25),
                  buildDefaultDragHandles: false,
                  itemCount: items.length,
                  onReorderItem: reorderShots,
                  itemBuilder: (context, index) {
                    final shot = items[index];
                    return StoryboardCard(
                      key: ValueKey(shot.id),
                      store: store,
                      shot: shot,
                      index: index,
                      selected: selectedId == shot.id,
                      isGrid: false,
                      onTap: () {
                        setState(() {
                          selectedId = shot.id;
                          dock = 'Inspector';
                          showDock = true;
                        });
                      },
                      onEdit: () => edit(shot),
                      onPlayVideo: openFloatingVideo,
                      onDelete: () => remove(shot),
                    );
                  },
                ),
        ),
        if (video && items.isNotEmpty)
          Container(
            height: 111,
            decoration: BoxDecoration(
              color: Color(0xFFEAECE1),
              border: Border(top: BorderSide(color: line)),
            ),
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(14),
              itemCount: items.length,
              buildDefaultDragHandles: false,
              onReorderItem: reorderShots,
              itemBuilder: (context, index) {
                final shot = items[index];
                return ReorderableDragStartListener(
                  key: ValueKey(shot.id),
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: InkWell(
                      onTap: () {
                        sequenceTimer?.cancel();
                        setState(() {
                          playingShot = -1;
                          selectedId = shot.id;
                        });
                      },
                      child: Container(
                        width:
                            ((shot.meta['duration'] as num? ?? 5).toDouble() *
                                    15)
                                .clamp(105, 230),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: current?.id == shot.id ? paleSage : paper,
                          border: Border.all(
                            color: current?.id == shot.id ? sage : line,
                          ),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shot.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            Row(
                              children: [
                                Icon(
                                  Icons.movie_outlined,
                                  size: 12,
                                  color: muted,
                                ),
                                const Spacer(),
                                Text(
                                  '${shot.meta['duration'] ?? 5}s',
                                  style: TextStyle(fontSize: 9, color: muted),
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
    final folders = _foldersIn(null);
    final rootAssets = project
        .of('asset')
        .where((asset) => asset.meta['folderId'] == null)
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
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
          child: rootAssets.isEmpty && folders.isEmpty
              ? const EmptyState(
                  Icons.photo_outlined,
                  'Gather your references',
                  'Import diagrams, lectures, or audio. Connect them to lesson segments, concept maps, or notes.',
                )
              : GridView.count(
                  crossAxisCount: 2,
                  childAspectRatio: 1,
                  padding: const EdgeInsets.all(12),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  children: [
                    for (final folder in folders)
                      _resourceFolderCard(
                        folder,
                        project.of('asset').toList(),
                        grid: true,
                      ),
                    for (final o in rootAssets)
                      drag(
                        o,
                        InkWell(
                          onTap: () => preview(o),
                          child: Column(
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

  Future<void> settings() async {
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final currentSettings = studioSettingsNotifier.value;
          return AlertDialog(
            title: const Text('Study preferences'),
            content: SizedBox(
              width: 580,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'THEME & PALETTE',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: StudioThemePreset.values.map((preset) {
                        final isSelected =
                            currentSettings.themePreset == preset;
                        return InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            final updated = currentSettings.copyWith(
                              themePreset: preset,
                            );
                            studioSettingsNotifier.value = updated;
                            setDialogState(() {});
                            setState(() {});
                          },
                          child: Container(
                            width: 170,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: preset.paper,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected ? preset.primary : line,
                                width: isSelected ? 2 : 1,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: preset.primary.withValues(
                                          alpha: 0.2,
                                        ),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: preset.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: preset.background,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: line),
                                      ),
                                    ),
                                    const Spacer(),
                                    if (isSelected)
                                      Icon(
                                        Icons.check_circle,
                                        size: 16,
                                        color: preset.primary,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  preset.label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: preset.ink,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  preset.description,
                                  style: TextStyle(fontSize: 10, color: muted),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'EDITOR & TYPOGRAPHY',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: currentSettings.editorFont,
                            decoration: const InputDecoration(
                              labelText: 'Primary Font',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'Georgia',
                                child: Text('Georgia (Serif)'),
                              ),
                              DropdownMenuItem(
                                value: 'Segoe UI',
                                child: Text('Segoe UI (Clean Sans)'),
                              ),
                              DropdownMenuItem(
                                value: 'Courier New',
                                child: Text('Courier New (Monospace / Code)'),
                              ),
                              DropdownMenuItem(
                                value: 'Consolas',
                                child: Text('Consolas (Monospace)'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                studioSettingsNotifier.value = currentSettings
                                    .copyWith(editorFont: val);
                                setDialogState(() {});
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: DropdownButtonFormField<double>(
                            initialValue: currentSettings.editorLineHeight,
                            decoration: const InputDecoration(
                              labelText: 'Line Spacing',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 1.5,
                                child: Text('1.5x (Compact)'),
                              ),
                              DropdownMenuItem(
                                value: 1.75,
                                child: Text('1.75x (Standard)'),
                              ),
                              DropdownMenuItem(
                                value: 2.0,
                                child: Text('2.0x (Relaxed)'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                studioSettingsNotifier.value = currentSettings
                                    .copyWith(editorLineHeight: val);
                                setDialogState(() {});
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      initialValue: currentSettings.autoSaveSeconds,
                      decoration: const InputDecoration(
                        labelText: 'Autosave Cadence',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 5,
                          child: Text('Every 5 seconds (Real-time)'),
                        ),
                        DropdownMenuItem(
                          value: 15,
                          child: Text('Every 15 seconds (Standard)'),
                        ),
                        DropdownMenuItem(
                          value: 30,
                          child: Text('Every 30 seconds'),
                        ),
                        DropdownMenuItem(
                          value: 60,
                          child: Text('Every 60 seconds'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          studioSettingsNotifier.value = currentSettings
                              .copyWith(autoSaveSeconds: val);
                          setDialogState(() {});
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'AI ASSISTANT CUSTOMIZATION',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: currentSettings.aiPersona,
                      decoration: const InputDecoration(
                        labelText: 'Learning assistant style',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Balanced Producer',
                          child: Text('Study Tutor & Academic Mentor'),
                        ),
                        DropdownMenuItem(
                          value: 'Critique & Polish',
                          child: Text('Socratic Tutor (Active recall)'),
                        ),
                        DropdownMenuItem(
                          value: 'Creative Outliner',
                          child: Text(
                            'Summary Specialist (High-yield synthesis)',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Screenplay Specialist',
                          child: Text(
                            'Detailed Researcher (Citations & evidence)',
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          studioSettingsNotifier.value = currentSettings
                              .copyWith(aiPersona: val);
                          setDialogState(() {});
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: Colors.transparent,
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Token Typewriter Animation',
                          style: TextStyle(fontSize: 13),
                        ),
                        subtitle: const Text(
                          'Render generated AI responses text-by-text with live cursor',
                          style: TextStyle(fontSize: 11),
                        ),
                        value: currentSettings.typewriterEffect,
                        onChanged: (val) {
                          studioSettingsNotifier.value = currentSettings
                              .copyWith(typewriterEffect: val);
                          setDialogState(() {});
                        },
                      ),
                    ),
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.auto_awesome_outlined),
                        title: const Text(
                          'AI providers & API keys',
                          style: TextStyle(fontSize: 13),
                        ),
                        subtitle: const Text(
                          'Configure Gemini, OpenAI, Claude, or local Ollama endpoints',
                          style: TextStyle(fontSize: 11),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.pop(context);
                          showAiSettings(this.context, store, ai);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'PROJECT DETAILS',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: project.title,
                      decoration: const InputDecoration(
                        labelText: 'Project name',
                      ),
                      onChanged: (v) {
                        if (v.trim().isNotEmpty) {
                          project.title = v;
                          store.changed();
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: project.description,
                      decoration: const InputDecoration(
                        labelText: 'Creative intention & logline',
                      ),
                      maxLines: 2,
                      onChanged: (v) {
                        project.description = v;
                        store.changed();
                      },
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'KEYBOARD SHORTCUTS',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Ctrl K     Search & commands\nCtrl S     Save now\nCtrl B     Focus mode\nCtrl Shift Space     Quick capture\nCtrl Z / Ctrl Y     Undo / redo in editor',
                      style: TextStyle(fontSize: 12, height: 1.9),
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'LOCAL PROJECT STORAGE',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SelectableText(
                      store.directory.path,
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your work autosaves locally on this computer. Export a portable project bundle to back it up or transfer.',
                      style: TextStyle(fontSize: 11, height: 1.6, color: muted),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () => run(importProject),
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: const Text('Import a portable project'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget scratchpadWorkspace() {
    final notes = project.of('note').where((o) {
      if (filter.isEmpty) return true;
      return '${o.title} ${o.body}'.toLowerCase().contains(
        filter.toLowerCase(),
      );
    }).toList();

    return Column(
      children: [
        SectionHeading(
          'Quick capture & brainstorms',
          'Scratchpad',
          subtitle:
              'Click any note to edit it in a movable floating window while you keep working.',
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
                  hintText: 'Filter scratchpad...',
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
            FilledButton.icon(
              onPressed: () {
                final newNote = CreativeObject(
                  kind: 'note',
                  title: 'New Scratchpad Note',
                  body: '',
                  meta: {
                    'status': 'Idea',
                    'createdAt': DateTime.now().toIso8601String(),
                  },
                );
                store.add(newNote);
                setState(() {
                  selectedId = newNote.id;
                });
                openFloatingVideo(newNote);
                toast('Created new scratchpad note');
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New note'),
            ),
          ],
        ),
        Expanded(
          child: notes.isEmpty
              ? const EmptyState(
                  Icons.lightbulb_outline,
                  'Your scratchpad is empty',
                  'Capture rapid thoughts, definitions, or exam reminders. Click "New note" above.',
                )
              : scratchpadGridView
              ? GridView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 16,
                  ),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 340,
                    mainAxisExtent: 190,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: notes.length,
                  itemBuilder: (context, index) =>
                      scratchpadGridCard(notes[index]),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 16,
                  ),
                  itemCount: notes.length,
                  itemBuilder: (context, index) {
                    final note = notes[index];
                    final isExpanded = expandedScratchpadId == note.id;

                    return AnimatedContainer(
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
                                          color: sage.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          'EDITING NOTE',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.8,
                                            color: sage,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      IconButton(
                                        tooltip: 'Pop out in floating window',
                                        iconSize: 17,
                                        icon: const Icon(
                                          Icons.picture_in_picture_alt,
                                        ),
                                        onPressed: () =>
                                            openFloatingVideo(note),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete note',
                                        iconSize: 17,
                                        color: const Color(0xFFA54141),
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () {
                                          remove(note);
                                          if (expandedScratchpadId == note.id) {
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
                                    key: ValueKey('${note.id}-scratch-title'),
                                    initialValue: note.title,
                                    style: const TextStyle(
                                      fontFamily: 'Segoe UI',
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: 'Note Title…',
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
                                      note.title = v;
                                      store.changed();
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  TextFormField(
                                    key: ValueKey('${note.id}-scratch-body'),
                                    initialValue: note.body,
                                    maxLines: null,
                                    minLines: 6,
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.65,
                                      color: ink,
                                    ),
                                    decoration: InputDecoration(
                                      hintText:
                                          'Type your scratchpad note, equations, or study thoughts here…',
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
                                      note.body = v;
                                      store.changed();
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  const Divider(height: 1),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Text(
                                        '${note.body.trim().isEmpty ? 0 : note.body.trim().split(RegExp(r'\s+')).length} words · ${note.body.length} chars',
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
                                setState(() => selectedId = note.id);
                                openFloatingVideo(note);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            note.title,
                                            style: const TextStyle(
                                              fontFamily: 'Segoe UI',
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          Icons.unfold_more,
                                          size: 16,
                                          color: muted,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      note.body.isEmpty
                                          ? 'Empty note — click to expand and write…'
                                          : note.body,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.5,
                                        color: note.body.isEmpty
                                            ? muted.withValues(alpha: 0.6)
                                            : muted,
                                        fontStyle: note.body.isEmpty
                                            ? FontStyle.italic
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget scratchpadGridCard(CreativeObject note) => Material(
    color: paper,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        setState(() => selectedId = note.id);
        openFloatingVideo(note);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selectedId == note.id ? sage : line),
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
                    color: paleSage.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(Icons.lightbulb_outline, size: 15, color: sage),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Open floating note',
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => openFloatingVideo(note),
                  icon: const Icon(Icons.picture_in_picture_alt_outlined),
                ),
                IconButton(
                  tooltip: 'Delete note',
                  iconSize: 16,
                  color: const Color(0xFFA54141),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => remove(note),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              note.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Segoe UI',
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Expanded(
              child: Text(
                note.body.isEmpty
                    ? 'Empty note — use the edit icon to write.'
                    : note.body,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: muted,
                  fontStyle: note.body.isEmpty ? FontStyle.italic : null,
                ),
              ),
            ),
            Text(
              '${note.body.trim().isEmpty ? 0 : note.body.trim().split(RegExp(r'\s+')).length} words',
              style: TextStyle(fontSize: 9, color: muted),
            ),
          ],
        ),
      ),
    ),
  );

  Widget documentViewerWorkspace() {
    if (activeDocument == null) {
      return const Center(child: Text('No document selected'));
    }
    final doc = activeDocument!;
    return Column(
      children: [
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: paper,
            border: Border(bottom: BorderSide(color: line)),
          ),
          child: Row(
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                onPressed: () {
                  setState(() {
                    mode = previousModeBeforeDocument ?? 'Media library';
                    activeDocument = null;
                  });
                },
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('Back', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 14),
              Icon(Icons.description, size: 18, color: sage),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  doc.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TextButton.icon(
                onPressed: () => run(() async {
                  final result = await FilePicker.saveFile(
                    fileName: safeName(doc.title),
                    bytes: await File(store.mediaPath(doc)).readAsBytes(),
                  );
                  if (result != null) toast('Original exported');
                }),
                icon: const Icon(Icons.download, size: 16),
                label: const Text(
                  'Export original',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: sage,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                onPressed: () => openQuizGenerator(source: doc),
                icon: const Icon(Icons.quiz_outlined, size: 16),
                label: const Text(
                  'Quiz or cards',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Pop out in floating window',
                onPressed: () => openFloatingVideo(doc),
                icon: const Icon(Icons.picture_in_picture_alt, size: 19),
              ),
            ],
          ),
        ),
        Expanded(
          child: MediaPreview(
            key: ValueKey(doc.id),
            store: store,
            asset: doc,
            autoplay: true,
            compactDocumentHeader: true,
          ),
        ),
      ],
    );
  }

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
                        _buildFlashcardDeckSection(cards),
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

  Widget _buildFlashcardDeckSection(List<CreativeObject> cards) {
    final first = cards.first;
    String metadataText(String key) => first.meta[key]?.toString().trim() ?? '';
    final title = metadataText('deckTitle').isNotEmpty
        ? metadataText('deckTitle')
        : metadataText('source').isNotEmpty
        ? metadataText('source')
        : metadataText('deck').isNotEmpty
        ? metadataText('deck')
        : 'Ungrouped flashcards';
    final description = metadataText('deckDescription').isNotEmpty
        ? metadataText('deckDescription')
        : '${cards.length} ${cards.length == 1 ? 'card' : 'cards'} in this deck';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: line),
      ),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: gold.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.style_outlined, size: 18, color: gold),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10, color: muted),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: cream,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: line),
          ),
          child: Text(
            '${cards.length}',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ),
        children: [
          for (var index = 0; index < cards.length; index++)
            _buildFlashcardListItem(cards[index], index + 1),
        ],
      ),
    );
  }

  Widget _buildFlashcardListItem(CreativeObject card, int number) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
    decoration: BoxDecoration(
      color: cream.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: line.withValues(alpha: .8)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 25,
          height: 25,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: paper,
            shape: BoxShape.circle,
            border: Border.all(color: line),
          ),
          child: Text(
            '$number',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: muted,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                card.title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                card.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, height: 1.4, color: muted),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Practise flashcard',
          iconSize: 16,
          onPressed: () => reviewCard(card),
          icon: const Icon(Icons.school_outlined),
        ),
        IconButton(
          tooltip: 'Open flashcard',
          iconSize: 16,
          visualDensity: VisualDensity.compact,
          onPressed: () => openFloatingVideo(card),
          icon: const Icon(Icons.open_in_new),
        ),
        IconButton(
          tooltip: 'Edit card',
          iconSize: 16,
          visualDensity: VisualDensity.compact,
          onPressed: () => edit(card),
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Delete card',
          iconSize: 16,
          visualDensity: VisualDensity.compact,
          color: const Color(0xFFA54141),
          onPressed: () => remove(card),
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
  );
}

class _CommandPalette extends StatefulWidget {
  const _CommandPalette({
    required this.project,
    required this.onMode,
    required this.onObject,
    required this.onCapture,
    required this.onNew,
  });
  final Project project;
  final void Function(String) onMode;
  final void Function(CreativeObject) onObject;
  final VoidCallback onCapture, onNew;
  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  String query = '';
  void act(VoidCallback action) {
    Navigator.pop(context);
    action();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: 650,
      height: 520,
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(17),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Find an object or jump to a workspace…',
                  suffixText: 'ESC',
                ),
                onChanged: (v) => setState(() => query = v.toLowerCase()),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: [
                  if (query.isEmpty) ...[
                    ListTile(
                      leading: const Icon(Icons.add),
                      title: const Text('New course'),
                      onTap: () => act(widget.onNew),
                    ),
                    ListTile(
                      leading: const Icon(Icons.edit_note),
                      title: const Text('Quick capture'),
                      trailing: Text(
                        'Ctrl Shift Space',
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                      onTap: () => act(widget.onCapture),
                    ),
                  ],
                  for (var i = 0; i < modes.length; i++)
                    if (studyModeLabel(modes[i]).toLowerCase().contains(query))
                      ListTile(
                        leading: Icon(modeIcons[i], size: 19),
                        title: Text(
                          'Go to ${studyModeLabel(modes[i])}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        onTap: () => act(() => widget.onMode(modes[i])),
                      ),
                  const Divider(),
                  for (final o
                      in widget.project.objects
                          .where(
                            (o) => '${o.title} ${o.body}'
                                .toLowerCase()
                                .contains(query),
                          )
                          .take(50))
                    ListTile(
                      leading: const Icon(Icons.description_outlined, size: 18),
                      title: Text(
                        o.title,
                        style: const TextStyle(fontSize: 12),
                      ),
                      subtitle: Text(
                        studyKindLabel(o.kind),
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                      onTap: () => act(() => widget.onObject(o)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
