import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse, PointerDeviceKind;
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zenbox/services/ai.dart';
import 'package:zenbox/services/document_ops.dart';
import 'package:zenbox/widgets/editor.dart';
import 'package:zenbox/models/model.dart';
import 'package:zenbox/widgets/research_browser.dart';
import 'package:zenbox/theme/theme.dart';
import 'package:zenbox/widgets/visual.dart';
import 'package:zenbox/models/quiz_model.dart';
import 'package:zenbox/services/quiz_service.dart';
import 'package:zenbox/widgets/quiz_view.dart';
import 'package:zenbox/widgets/focus_mode.dart';
import 'package:zenbox/services/notification_service.dart';
import 'package:zenbox/services/pdf_exporter.dart';
import 'package:zenbox/models/study_workflow.dart';
import 'package:zenbox/widgets/markdown_view.dart';

// Studio Modular Structure
part 'studio/dialogs/project_dialogs.dart';
part 'studio/dialogs/settings_dialog.dart';
part 'studio/dialogs/command_palette.dart';
part 'studio/views/overview_view.dart';
part 'studio/views/notes_view.dart';
part 'studio/views/resource_library_view.dart';
part 'studio/views/storyboard_view.dart';
part 'studio/views/concept_bank_view.dart';
part 'studio/views/quiz_flashcards_view.dart';
part 'studio/widgets/top_bar.dart';
part 'studio/widgets/navigation_sidebar.dart';
part 'studio/widgets/status_bar.dart';
part 'studio/widgets/right_dock.dart';
part 'studio/widgets/tray.dart';

const modes = [
  'Overview',
  'Notes',
  'Concept Bank / Glossary',
  'Mind Map / Concept Board',
  'Media library',
  'Storyboard',
  'Research',
  'Quizzes & Flashcards',
];
const modeIcons = [
  Icons.space_dashboard_outlined,
  Icons.edit_note,
  Icons.library_books_outlined,
  Icons.account_tree_outlined,
  Icons.photo_library_outlined,
  Icons.view_carousel_outlined,
  Icons.travel_explore,
  Icons.school_outlined,
];

const dashboardWallpapers = [
  'assets/illustrations/learning_workspace_hero.png',
  'assets/illustrations/dashboard_hero.jpg',
  'assets/illustrations/dashboard_study_library.png',
  'assets/illustrations/dashboard_cozy_nook.png',
  'assets/illustrations/dashboard_note_arrangement.png',
  'assets/illustrations/dashboard_courses.jpg',
  'assets/illustrations/dashboard_concept_map.png',
  'assets/illustrations/dashboard_flashcards.png',
  'assets/illustrations/dashboard_headphones.png',
  'assets/illustrations/dashboard_tea_break.png',
];


class Studio extends StatefulWidget {
  const Studio({super.key, required this.store, this.studentMedia = false});
  final StudioStore store;
  final bool studentMedia;
  @override
  State<Studio> createState() => _StudioState();
}

class _FloatingWidgetEntry {
  const _FloatingWidgetEntry({
    required this.id,
    required this.asset,
    this.deckCards,
  });

  final int id;
  final CreativeObject asset;
  final List<CreativeObject>? deckCards;
}

class _StudioState extends State<Studio> with WidgetsBindingObserver {
  StudioStore get store => widget.store;
  Project get project => store.project;
  final ai = AiSession();
  String mode = 'Overview';
  String dock = 'AI';
  String? selectedId;
  bool showDock = true, showTray = false, focusMode = false, importing = false, isDraggingExternal = false;
  double dockWidth = 306;

  Future<void> handleExternalFilesDrop(List<dynamic> files) async {
    if (files.isEmpty) return;
    setState(() => importing = true);
    int count = 0;
    try {
      for (final file in files) {
        final path = file.path as String?;
        if (path == null || path.isEmpty) continue;
        final name = (file.name as String?)?.isNotEmpty == true
            ? file.name as String
            : path.split(Platform.pathSeparator).last;
        final asset = await store.importMedia(path, name);
        project.objects.add(asset);
        count++;
      }
      if (count > 0) {
        store.changed();
        navigate('Media library');
        toast('Saved $count file${count > 1 ? 's' : ''} to Media library');
      }
    } catch (e) {
      toast('Failed to import dropped files: $e');
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }
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
  String? dockResourceFolderId;
  final Set<String> markedResourceIds = {};
  bool resourceSelectionMode = false;
  bool splitView = false;
  String secondaryMode = 'Concept Bank / Glossary';
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

  void openFloatingFlashcardDeck(List<CreativeObject> cards) {
    if (cards.isEmpty) return;
    setState(() {
      floatingWidgets.add(
        _FloatingWidgetEntry(
          id: _nextFloatingWidgetId++,
          asset: cards.first,
          deckCards: cards,
        ),
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
    secondaryMode =
        project.layout['secondaryMode'] as String? ?? 'Concept Bank / Glossary';
    if (!modes.contains(secondaryMode)) secondaryMode = 'Concept Bank / Glossary';
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
      'Manuscript' ||
      'Study Guide' ||
      'Study Guide / Summary Doc' ||
      'Study guides' => 'Notes',
      'Story bible' ||
      'Concept Bank' ||
      'Glossary' ||
      'Scratchpad' ||
      'Quick notes' => 'Concept Bank / Glossary',
      'Canvas' || 'Mind Map' || 'Concept Board' => 'Mind Map / Concept Board',
      'Video' || 'Lesson rehearsal' || 'Lesson planner' => 'Storyboard',
      _ => value,
    };
    setState(() {
      mode = resolved;
      filter = '';
      if (splitView && secondaryMode == resolved) {
        secondaryMode = modes.firstWhere(
          (candidate) => candidate != resolved,
          orElse: () => 'Concept Bank / Glossary',
        );
      }
      if (resolved == 'Notes') {
        if (selected?.kind != 'script' && selected?.kind != 'manuscript') {
          selectedId = (project.of('script').firstOrNull ??
                  project.of('manuscript').firstOrNull)
              ?.id;
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
          'manuscript': 'Notes',
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
          'note': 'Concept Bank / Glossary',
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
    final doc = readDocument(o);
    final mdContent = deltaToMarkdown(doc.toDelta());
    final result = await FilePicker.saveFile(
      fileName: '${safeName(o.title)}.$ext',
      bytes: Uint8List.fromList(utf8.encode(mdContent)),
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
        onManage: manageProjectsDialog,
        onDelete: store.projects.length > 1
            ? () => deleteProjectDialog(project)
            : null,
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
            child: DropTarget(
              onDragEntered: (_) => setState(() => isDraggingExternal = true),
              onDragExited: (_) => setState(() => isDraggingExternal = false),
              onDragDone: (details) async {
                setState(() => isDraggingExternal = false);
                await handleExternalFilesDrop(details.files);
              },
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
                    deckCards: floatingWidgets[index].deckCards,
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
                if (isDraggingExternal)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          color: sage.withValues(alpha: 0.12),
                          border: Border.all(color: sage, width: 3),
                        ),
                        child: Center(
                          child: Card(
                            elevation: 8,
                            color: paper,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: sage, width: 1.5),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.file_download_outlined, size: 28, color: sage),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Drop files to add to Media library',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: ink,
                                    ),
                                  ),
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
        ),
      );

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
        return writing('Notes');
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
      case 'Concept Bank / Glossary':
      case 'Concept Bank':
      case 'Glossary':
      case 'Scratchpad':
        return conceptBankWorkspace();
      case 'Quizzes & Flashcards':
        return quizAndFlashcardsWorkspace();
      case 'Document Viewer':
        return documentViewerWorkspace();
      default:
        return collection(workspaceMode);
    }
  }

}
