import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ai.dart';
import 'document_ops.dart';
import 'model.dart';
import 'research_browser.dart';
import 'rich_editor.dart';
import 'notification_service.dart';
import 'studio.dart' show Studio;
import 'visual.dart' show AssetThumbnail;
import 'zenbox_model.dart';
import 'zenbox_theme.dart';
import 'zenbox/reader.dart';
import 'zenbox/views/dashboard_view.dart';
import 'zenbox/views/review_view.dart';
import 'zenbox/views/tasks_view.dart';

class ZenboxShell extends StatefulWidget {
  const ZenboxShell({super.key, required this.store});
  final ZenboxStore store;
  @override
  State<ZenboxShell> createState() => _ZenboxShellState();
}

class _ZenboxShellState extends State<ZenboxShell> {
  static const modes = [
    'Home',
    'Notes',
    'Review',
    'Research',
    'Canvas',
    'Tasks',
    'Library',
    'Media',
  ];
  static const icons = [
    Icons.space_dashboard_outlined,
    Icons.edit_note,
    Icons.school_outlined,
    Icons.travel_explore,
    Icons.account_tree_outlined,
    Icons.checklist,
    Icons.folder_open_outlined,
    Icons.video_library_outlined,
  ];
  static const decks = [
    'AI',
    'Assets',
    'Preview',
    'Sources',
    'Outline',
    'Links',
    'History',
    'Properties',
  ];
  final ai = AiSession();
  String mode = 'Home', deck = 'AI';
  String? selectedId, previewId;
  bool focus = false, showTray = true, showDeck = true, web = false;
  double deckWidth = 360;
  SelectionRequest? selection;
  Timer? ticker;
  DateTime? focusEnd;
  int focusMinutes = 25;
  ZenboxStore get store => widget.store;
  CreativeObject? get selected => store.project.object(selectedId ?? '');
  CreativeObject? get preview => store.project.object(previewId ?? '');
  @override
  void initState() {
    super.initState();
    mode = store.project.layout['mode'] as String? ?? 'Home';
    if (!modes.contains(mode)) mode = 'Home';
    deck = store.project.layout['deck'] as String? ?? 'AI';
    if (!decks.contains(deck)) deck = 'AI';
    showTray = store.project.layout['showTray'] != false;
    selectedId = store.project.layout['selected'] as String?;
    deckWidth = (store.project.layout['deckWidth'] as num?)?.toDouble() ?? 360;
    focusEnd = DateTime.tryParse(
      store.project.layout['focusEnd']?.toString() ?? '',
    );
    if (focusEnd != null) _startTicker();
  }

  @override
  void dispose() {
    ticker?.cancel();
    ai.cancel();
    ai.pendingPrompt.dispose();
    super.dispose();
  }

  void saveLayout() {
    store.project.layout.addAll({
      'mode': mode,
      'deck': deck,
      'showTray': showTray,
      'selected': selectedId,
      'deckWidth': deckWidth,
    });
    store.changed();
  }

  void navigate(String next, {String? courseId, String? noteId}) {
    if (courseId != null) store.selectCourse(courseId);
    setState(() {
      mode = modes.contains(next) ? next : 'Notes';
      if (noteId != null) selectedId = noteId;
    });
    saveLayout();
  }

  void open(CreativeObject o) {
    setState(() {
      selectedId = o.id;
      if (o.meta['file'] != null ||
          ['source', 'research', 'evidence'].contains(o.kind)) {
        mode = 'Research';
        web = false;
      } else if (o.kind == 'concept') {
        mode = 'Canvas';
      } else if (o.kind == 'task') {
        mode = 'Tasks';
      } else if (o.kind == 'card') {
        mode = 'Review';
      } else {
        mode = 'Notes';
      }
    });
    saveLayout();
  }

  void showPreview(CreativeObject o) {
    setState(() {
      previewId = o.id;
      deck = 'Preview';
      showDeck = true;
    });
    saveLayout();
  }

  void ask(String text) {
    setState(() {
      deck = 'AI';
      showDeck = true;
    });
    ai.ask(text);
    saveLayout();
  }

  void message(String text) {
    if (mounted) {
      TopNotification.show(context, text);
    }
  }

  Future<Map<String, String>?> form(
    String title,
    Map<String, String> fields,
  ) async {
    final controllers = fields.map(
      (k, v) => MapEntry(k, TextEditingController(text: v)),
    );
    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: controllers.entries
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: TextField(
                        controller: e.value,
                        minLines:
                            e.key == 'Text' ||
                                e.key == 'Answer' ||
                                e.key == 'Claim'
                            ? 3
                            : 1,
                        maxLines:
                            e.key == 'Text' ||
                                e.key == 'Answer' ||
                                e.key == 'Claim'
                            ? 8
                            : 1,
                        decoration: InputDecoration(labelText: e.key),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              controllers.map((k, v) => MapEntry(k, v.text.trim())),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> newNote({String? text, String title = 'Untitled note'}) async {
    final o = StudentNote(
      title: title,
      body: text ?? '',
      courseId: store.activeCourseId ?? '',
    );
    store.addNote(o);
    open(o);
  }

  Future<void> capture(
    CreativeObject source,
    String quote,
    String locator,
  ) async {
    final values = await form('Capture evidence', {
      'Claim': '',
      'Location': locator,
      'Text': quote,
    });
    if (values == null || values['Text']!.isEmpty) return;
    final e = EvidenceBlock(
      sourceId: source.id,
      quoteText: values['Text']!,
      claimStatement: values['Claim']!,
      pageOrTimestamp: values['Location']!,
    );
    e.meta['course'] = source.meta['course'];
    e.meta['tray'] = true;
    store.addEvidence(e);
    message('Evidence saved with its source and added to the tray.');
  }

  Future<void> importFiles({bool tray = false}) async {
    try {
      final files = await FilePicker.pickFiles(allowMultiple: true);
      for (final f in files) {
        if (f.path != null) {
          final o = await store.importAsset(f.path!, f.name, toTray: tray);
          showPreview(o);
        }
      }
      if (files.isNotEmpty)
        message('${files.length} file(s) available in Assets and Library.');
    } catch (e) {
      message('Import failed: $e');
    }
  }

  Future<void> exportObject(CreativeObject o) async {
    try {
      final path = await FilePicker.saveFile(
        fileName: '${o.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')}.md',
        bytes: utf8.encode('# ${o.title}\n\n${o.body}'),
      );
      if (path != null) message('Document exported.');
    } catch (e) {
      message('Export failed: $e');
    }
  }

  Future<void> backup() async {
    try {
      store.save();
      final archive = Archive();
      final json = utf8.encode(
        jsonEncode({
          'projects': store.projects.map((p) => p.toJson()).toList(),
          'currentId': store.currentId,
          'settings': store.settings,
        }),
      );
      archive.addFile(ArchiveFile('zenbox.json', json.length, json));
      for (final f in Directory(
        '${store.directory.path}/media',
      ).listSync().whereType<File>()) {
        final bytes = await f.readAsBytes();
        archive.addFile(
          ArchiveFile('media/${f.uri.pathSegments.last}', bytes.length, bytes),
        );
      }
      final data = ZipEncoder().encode(archive);
      final saved = await FilePicker.saveFile(
        fileName: 'zenbox-backup.zip',
        bytes: Uint8List.fromList(data),
      );
      if (saved != null) message('Workspace and attachments exported.');
    } catch (e) {
      message('Backup failed: $e');
    }
  }

  Future<void> importWorkspace() async {
    try {
      final f = await FilePicker.pickFile();
      if (f?.path == null) return;
      final archive = ZipDecoder().decodeBytes(
        await File(f!.path!).readAsBytes(),
      );
      final manifest =
          archive.findFile('zenbox.json') ?? archive.findFile('studio.json');
      if (manifest == null)
        throw const FormatException('No workspace manifest found.');
      final data =
          jsonDecode(utf8.decode(manifest.content)) as Map<String, dynamic>;
      final imported = (data['projects'] as List)
          .map((p) => Project.fromJson(Map<String, dynamic>.from(p)))
          .toList();
      // Remap object IDs and attachment names; existing work is never replaced.
      final ids = <String, String>{
        for (final p in imported)
          for (final o in p.objects) o.id: newId(),
      };
      final files = <String, String>{};
      for (final entry in archive.files) {
        if (!entry.isFile || !entry.name.startsWith('media/')) continue;
        final name = entry.name.substring(6);
        if (name.isEmpty ||
            name.contains('/') ||
            name.contains('\\') ||
            name.contains('..'))
          continue;
        final dest =
            '${newId()}.${name.split('.').last.replaceAll(RegExp('[^a-zA-Z0-9]'), '')}';
        await File(
          '${store.directory.path}/media/$dest',
        ).writeAsBytes(entry.content);
        files[name] = dest;
      }
      store.checkpoint();
      for (final p in imported) {
        final objects = p.objects.map((o) {
          final json = o.toJson();
          json['id'] = ids[o.id];
          final meta = Map<String, dynamic>.from(o.meta);
          for (final key in ['course', 'noteId', 'sourceId']) {
            if (ids.containsKey(meta[key])) meta[key] = ids[meta[key]];
          }
          if (files.containsKey(meta['file']))
            meta['file'] = files[meta['file']];
          json['meta'] = meta;
          json['links'] = o.links.map((id) => ids[id] ?? id).toList();
          if (['script', 'manuscript', 'scratchpad'].contains(o.kind))
            json['kind'] = 'note';
          return studentObject(CreativeObject.fromJson(json));
        }).toList();
        store.projects.add(
          Project(
            title: '${p.title} (imported)',
            description: p.description,
            objects: objects,
          ),
        );
      }
      store.currentId = store.projects.last.id;
      store.selectCourse(null);
      setState(() {
        selectedId = null;
        mode = 'Home';
      });
      store.changed();
      message('Imported as a separate workspace, including attachments.');
    } catch (e) {
      message('Workspace import failed: $e');
    }
  }

  void _startTicker() {
    ticker?.cancel();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (focusEnd != null && !DateTime.now().isBefore(focusEnd!)) {
        ticker?.cancel();
        focusEnd = null;
        store.project.layout.remove('focusEnd');
        store.logStudySession(
          StudySession(
            courseId: store.activeCourseId ?? '',
            durationMinutes: focusMinutes,
          ),
        );
        message('Focus session complete. Take a short break.');
      }
      setState(() {});
    });
  }

  void toggleTimer() {
    setState(() {
      if (focusEnd != null) {
        focusEnd = null;
        ticker?.cancel();
        store.project.layout.remove('focusEnd');
      } else {
        focusEnd = DateTime.now().add(Duration(minutes: focusMinutes));
        store.project.layout['focusEnd'] = focusEnd!.toIso8601String();
        _startTicker();
      }
    });
    store.changed();
  }

  String get timerText {
    if (focusEnd == null) return 'Focus timer';
    final secs = math.max(0, focusEnd!.difference(DateTime.now()).inSeconds);
    return '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
  }

  Future<void> search() async {
    String query = '';
    String? kind;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => Dialog(
          child: SizedBox(
            width: 700,
            height: 550,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search notes, source text, evidence, cards…',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (s) => update(() => query = s),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final k in [
                        'All',
                        'note',
                        'source',
                        'asset',
                        'evidence',
                        'concept',
                        'card',
                        'task',
                      ])
                        FilterChip(
                          label: Text(k),
                          selected: (kind ?? 'All') == k,
                          onSelected: (_) =>
                              update(() => kind = k == 'All' ? null : k),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      children: store
                          .search(
                            query,
                            kind: kind,
                            courseId: store.activeCourseId,
                          )
                          .where((o) => o.kind != 'generation')
                          .take(100)
                          .map(
                            (o) => ListTile(
                              leading: Icon(objectIcon(o)),
                              title: Text(o.title),
                              subtitle: Text(
                                '${o.kind} · ${o.body.replaceAll('\n', ' ')}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                open(o);
                              },
                            ),
                          )
                          .toList(),
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

  IconData objectIcon(CreativeObject o) =>
      o.meta['file']?.toString().endsWith('.pdf') == true
      ? Icons.picture_as_pdf_outlined
      : switch (o.kind) {
          'source' || 'research' => Icons.public,
          'evidence' => Icons.format_quote,
          'card' => Icons.style_outlined,
          'concept' => Icons.hub_outlined,
          'task' => Icons.check_box_outlined,
          'asset' => Icons.perm_media_outlined,
          _ => Icons.description_outlined,
        };
  Widget objectTile(CreativeObject o, {bool compact = false}) =>
      Draggable<CreativeObject>(
        data: o,
        feedback: Material(
          elevation: 5,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(o.title),
          ),
        ),
        child: ListTile(
          dense: compact,
          selected: selectedId == o.id,
          leading: SizedBox(
            width: 28,
            height: 32,
            child: o.meta['file'] != null
                ? AssetThumbnail(store: store, asset: o)
                : Icon(objectIcon(o), size: 21),
          ),
          title: Text(o.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${o.kind}${o.meta['aiContext'] == true ? ' · AI context' : ''}',
            style: const TextStyle(fontSize: 10),
          ),
          onTap: () => open(o),
          onLongPress: () => showPreview(o),
          trailing: PopupMenuButton<String>(
            tooltip: 'Object actions',
            onSelected: (v) {
              switch (v) {
                case 'preview':
                  showPreview(o);
                case 'tray':
                  store.setTray(o, o.meta['tray'] != true);
                case 'context':
                  store.setContext(o, o.meta['aiContext'] != true);
                case 'link':
                  if (selected != null && selected!.id != o.id) {
                    selected!.links.add(o.id);
                    store.changed();
                    message('Linked to ${selected!.title}');
                  }
                case 'popout':
                  popout(o);
                case 'delete':
                  store.remove(o);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'preview',
                child: Text('Preview in side deck'),
              ),
              const PopupMenuItem(
                value: 'popout',
                child: Text('Open large reader'),
              ),
              PopupMenuItem(
                value: 'tray',
                child: Text(
                  o.meta['tray'] == true
                      ? 'Remove from tray'
                      : 'Keep in temporary tray',
                ),
              ),
              PopupMenuItem(
                value: 'context',
                child: Text(
                  o.meta['aiContext'] == true
                      ? 'Remove AI context'
                      : 'Include in AI context',
                ),
              ),
              const PopupMenuItem(
                value: 'link',
                child: Text('Link to active note'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete object (undo available)'),
              ),
            ],
          ),
        ),
      );
  Widget reader(CreativeObject o) => SourceReader(
    key: ValueKey(o.id),
    store: store,
    object: o,
    onCapture: (q, l) => capture(o, q, l),
    onAsk: ask,
  );
  void popout(CreativeObject o) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 1100,
          height: 850,
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: 16),
                  const Expanded(child: Text('Source reader')),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Expanded(child: reader(o)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): search,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): newNote,
        const SingleActivator(LogicalKeyboardKey.f11): () =>
            setState(() => focus = !focus),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: LayoutBuilder(
            builder: (context, size) {
              final wide = size.maxWidth > 1050;
              return Column(
                children: [
                  Container(
                    height: 66,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: const BoxDecoration(
                      color: surface,
                      border: Border(bottom: BorderSide(color: edge)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.spa_outlined, color: moss),
                        const SizedBox(width: 10),
                        const Text(
                          'ZENBOX',
                          style: TextStyle(
                            letterSpacing: 3,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: search,
                              icon: const Icon(Icons.search, size: 17),
                              label: const Text('Search workspace…'),
                            ),
                          ),
                        ),
                        if (size.maxWidth > 750)
                          DropdownButton<String?>(
                            value:
                                store.courses.any(
                                  (c) => c.id == store.activeCourseId,
                                )
                                ? store.activeCourseId
                                : null,
                            underline: const SizedBox.shrink(),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('All courses'),
                              ),
                              ...store.courses.map(
                                (c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.code),
                                ),
                              ),
                            ],
                            onChanged: store.selectCourse,
                          ),
                        IconButton(
                          tooltip: focus
                              ? 'Leave focus mode (F11)'
                              : 'Focus mode (F11)',
                          onPressed: () => setState(() => focus = !focus),
                          icon: Icon(
                            focus
                                ? Icons.fullscreen_exit
                                : Icons.center_focus_strong,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Toggle side deck',
                          onPressed: () => setState(() => showDeck = !showDeck),
                          icon: const Icon(Icons.view_sidebar_outlined),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Workspace menu',
                          onSelected: (v) async {
                            switch (v) {
                              case 'backup':
                                await backup();
                              case 'import':
                                await importWorkspace();
                              case 'files':
                                await importFiles();
                              case 'course':
                                final f = await form('Add a course', {
                                  'Code': '',
                                  'Title': '',
                                  'Instructor': '',
                                });
                                if (f != null && f['Title']!.isNotEmpty)
                                  store.addCourse(
                                    Course(
                                      code: f['Code']!,
                                      title: f['Title']!,
                                      instructor: f['Instructor']!,
                                    ),
                                  );
                              case 'workspace':
                                final f = await form('New workspace', {
                                  'Title': '',
                                });
                                if (f != null && f['Title']!.isNotEmpty) {
                                  final p = Project(
                                    title: f['Title']!,
                                    objects: [],
                                  );
                                  store.projects.add(p);
                                  store.currentId = p.id;
                                  store.selectCourse(null);
                                  navigate('Home');
                                }
                              case 'ai':
                                if (mounted) showAiSettings(context, store, ai);
                              default:
                                if (v.startsWith('switch:')) {
                                  store.currentId = v.substring(7);
                                  store.selectCourse(null);
                                  selectedId = null;
                                  navigate('Home');
                                }
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'course',
                              child: Text('Add course'),
                            ),
                            const PopupMenuItem(
                              value: 'workspace',
                              child: Text('New workspace'),
                            ),
                            const PopupMenuItem(
                              value: 'files',
                              child: Text('Import files'),
                            ),
                            const PopupMenuItem(
                              value: 'backup',
                              child: Text('Export workspace with attachments'),
                            ),
                            const PopupMenuItem(
                              value: 'import',
                              child: Text('Import Zenbox / Xandora backup'),
                            ),
                            const PopupMenuItem(
                              value: 'ai',
                              child: Text('Local AI & provider settings'),
                            ),
                            const PopupMenuDivider(),
                            ...store.projects.map(
                              (p) => PopupMenuItem(
                                value: 'switch:${p.id}',
                                child: Text(p.title),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        if (!focus)
                          NavigationRail(
                            selectedIndex: modes.indexOf(mode),
                            onDestinationSelected: (i) => navigate(modes[i]),
                            backgroundColor: forest,
                            indicatorColor: olive.withValues(alpha: .25),
                            selectedIconTheme: const IconThemeData(
                              color: Colors.white,
                            ),
                            unselectedIconTheme: const IconThemeData(
                              color: Colors.white60,
                            ),
                            selectedLabelTextStyle: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                            unselectedLabelTextStyle: const TextStyle(
                              color: Colors.white60,
                              fontSize: 10,
                            ),
                            labelType: NavigationRailLabelType.all,
                            minWidth: 78,
                            groupAlignment: -1,
                            destinations: [
                              for (var i = 0; i < modes.length; i++)
                                NavigationRailDestination(
                                  icon: Icon(icons[i]),
                                  label: Text(modes[i]),
                                ),
                            ],
                            trailing: Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: IconButton(
                                    tooltip: 'New note',
                                    onPressed: newNote,
                                    icon: const Icon(
                                      Icons.add_circle_outline,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(child: mainView()),
                  if (showTray && !focus) Material(color: surface, child: trayView()),
                            ],
                          ),
                        ),
                        if (showDeck && !focus) ...[
                          if (wide)
                            MouseRegion(
                              cursor: SystemMouseCursors.resizeColumn,
                              child: GestureDetector(
                                onHorizontalDragUpdate: (d) => setState(
                                  () => deckWidth = (deckWidth - d.delta.dx)
                                      .clamp(310, 520),
                                ),
                                onHorizontalDragEnd: (_) => saveLayout(),
                                child: Container(width: 5, color: edge),
                              ),
                            ),
                          SizedBox(
                            width: wide
                                ? deckWidth
                                : math.min(330, size.maxWidth * .4),
                            child: deckView(),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    height: 34,
                    color: surface,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(
                          store.error == null
                              ? Icons.cloud_done_outlined
                              : Icons.error_outline,
                          size: 13,
                          color: store.error == null ? moss : Colors.red,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          store.error ??
                              store.storageWarning ??
                              'Saved locally · ${store.project.title}',
                          style: const TextStyle(fontSize: 10),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Undo workspace action',
                          padding: EdgeInsets.zero,
                          onPressed: store.canUndo ? store.undo : null,
                          icon: const Icon(Icons.undo, size: 16),
                        ),
                        IconButton(
                          tooltip: 'Redo workspace action',
                          padding: EdgeInsets.zero,
                          onPressed: store.canRedo ? store.redo : null,
                          icon: const Icon(Icons.redo, size: 16),
                        ),
                        TextButton.icon(
                          onPressed: toggleTimer,
                          icon: Icon(
                            focusEnd == null
                                ? Icons.timer_outlined
                                : Icons.pause,
                            size: 14,
                          ),
                          label: Text(
                            timerText,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() => showTray = !showTray);
                            saveLayout();
                          },
                          child: Text(
                            'Tray ${store.tray.length}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget mainView() => switch (mode) {
    'Media' => Studio(store:store,studentMedia:true),
    'Home' => DashboardView(store: store, onNavigate: navigate),
    'Review' => ReviewView(store: store),
    'Tasks' => TasksView(store: store),
    'Canvas' => ConceptCanvas(
      store: store,
      onOpen: open,
      onAdd: () async {
        final f = await form('New concept', {'Name': '', 'Text': ''});
        if (f != null && f['Name']!.isNotEmpty)
          store.addConcept(
            ConceptNode(
              courseId: store.activeCourseId ?? '',
              name: f['Name']!,
              body: f['Text']!,
            ),
          );
      },
    ),
    'Library' => Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: zenHeading(
            'Your study library',
            'Documents, images, recordings, and reference material.',
            action: IconButton(
              tooltip: 'Import assets',
              onPressed: importFiles,
              icon: const Icon(Icons.upload_file),
            ),
          ),
        ),
        Expanded(
          child: ListView(children: store.assets.map(objectTile).toList()),
        ),
      ],
    ),
    'Research' => Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('Sources & reading'),
                selected: !web,
                onSelected: (_) => setState(() => web = false),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Research browser'),
                selected: web,
                onSelected: (_) => setState(() => web = true),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Add source',
                onPressed: () async {
                  final f = await form('New research source', {
                    'Title': '',
                    'Author': '',
                    'Year': '',
                    'URL': '',
                    'Text': '',
                  });
                  if (f != null && f['Title']!.isNotEmpty) {
                    final o = ResearchSource(
                      courseId: store.activeCourseId ?? '',
                      title: f['Title']!,
                      author: f['Author']!,
                      publicationYear: f['Year']!,
                      url: f['URL']!,
                      body: f['Text']!,
                    );
                    store.addSource(o);
                    open(o);
                  }
                },
                icon: const Icon(Icons.add_link),
              ),
              IconButton(
                tooltip: 'Import PDF or document',
                onPressed: importFiles,
                icon: const Icon(Icons.upload_file),
              ),
            ],
          ),
        ),
        Expanded(
          child: web
              ? ResearchBrowserView(store: store, onOpenNote: open)
              : selected != null &&
                    (selected!.meta['file'] != null ||
                        [
                          'source',
                          'research',
                          'evidence',
                        ].contains(selected!.kind))
              ? reader(selected!)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    zenHeading(
                      'Research with a paper trail',
                      'Open a source, capture evidence, and keep the original within reach.',
                    ),
                    ...store.sources.map(objectTile),
                    ...store.assets.map(objectTile),
                    ...store.evidence.map(objectTile),
                  ],
                ),
        ),
      ],
    ),
    _ => notesView(),
  };
  Widget notesView() {
    final editable =
        selected != null &&
        [
          'note',
          'script',
          'manuscript',
          'scratchpad',
          'concept',
        ].contains(selected!.kind);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: store.notes
                        .where(
                          (n) =>
                              store.activeCourseId == null ||
                              n.courseId == store.activeCourseId,
                        )
                        .map(
                          (n) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InputChip(
                              label: Text(
                                n.title,
                                overflow: TextOverflow.ellipsis,
                              ),
                              selected: selectedId == n.id,
                              onPressed: () => open(n),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'New note',
                onPressed: newNote,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        Expanded(
          child: editable
              ? DocumentEditor(
                  key: ValueKey(selected!.id),
                  store: store,
                  object: selected!,
                  onInspect: () => setState(() => deck = 'Properties'),
                  onExport: () => exportObject(selected!),
                  onAskAi: (s) {
                    selection = s;
                    ask(
                      '${s.action}\n\nSelected passage from ${selected!.title}:\n${s.text}',
                    );
                  },
                  onPreview: showPreview,
                  onDelete: () {
                    store.remove(selected!);
                    setState(() => selectedId = null);
                  },
                )
              : ListView(
                  padding: const EdgeInsets.all(28),
                  children: [
                    zenHeading(
                      'Make the material your own',
                      'Write, connect, and turn your notes into questions.',
                      action: FilledButton.icon(
                        onPressed: newNote,
                        icon: const Icon(Icons.add),
                        label: const Text('New note'),
                      ),
                    ),
                    ...store.notes
                        .where(
                          (n) =>
                              store.activeCourseId == null ||
                              n.courseId == store.activeCourseId,
                        )
                        .map(objectTile),
                  ],
                ),
        ),
      ],
    );
  }

  Widget trayView() => DragTarget<Object>(
    onWillAcceptWithDetails: (d) =>
        d.data is CreativeObject || d.data is String,
    onAcceptWithDetails: (d) {
      if (d.data is CreativeObject) {
        store.setTray(d.data as CreativeObject, true);
      } else {
        final o = StudentNote(
          title: 'Quick capture',
          body: d.data as String,
          courseId: store.activeCourseId ?? '',
        );
        o.meta['tray'] = true;
        store.addNote(o);
      }
    },
    builder: (context, candidates, rejected) => Container(
      height: 122,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: candidates.isEmpty ? edge : moss, width: candidates.isEmpty ? 1 : 3)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 34,
            child: Row(
              children: [
                const SizedBox(width: 16),
                const Icon(Icons.inbox_outlined, size: 15),
                const SizedBox(width: 8),
                const Text(
                  'TEMPORARY TRAY',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Drop references here · originals stay in place',
                    style: TextStyle(fontSize: 10, color: secondaryInk),
                  ),
                ),
                IconButton(
                  tooltip: 'Quick capture',
                  onPressed: () async {
                    final f = await form('Quick capture', {'Text': ''});
                    if (f != null && f['Text']!.isNotEmpty) {
                      final o = StudentNote(
                        title: 'Quick capture',
                        body: f['Text']!,
                        courseId: store.activeCourseId ?? '',
                      );
                      o.meta['tray'] = true;
                      store.addNote(o);
                    }
                  },
                  icon: const Icon(Icons.add, size: 16),
                ),
                IconButton(
                  tooltip: 'Import to tray',
                  onPressed: () => importFiles(tray: true),
                  icon: const Icon(Icons.upload_file, size: 16),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              children: store.tray
                  .map(
                    (o) => Draggable<CreativeObject>(
                      data: o,
                      feedback: Material(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(o.title),
                        ),
                      ),
                      child: Container(
                        width: 185,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: edge),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListTile(
                          dense: true,
                          leading: Icon(objectIcon(o), size: 18),
                          title: Text(
                            o.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: () => showPreview(o),
                          trailing: IconButton(
                            tooltip: 'Remove reference from tray',
                            icon: const Icon(Icons.close, size: 13),
                            onPressed: () => store.setTray(o, false),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    ),
  );
  Widget deckView() => Material(
    color: surface,
    child: Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: decks
                .map(
                  (d) => TextButton(
                    onPressed: () {
                      setState(() => deck = d);
                      saveLayout();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: deck == d ? forest : secondaryInk,
                      backgroundColor: deck == d
                          ? olive.withValues(alpha: .18)
                          : null,
                    ),
                    child: Text(d, style: const TextStyle(fontSize: 11)),
                  ),
                )
                .toList(),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: decks.indexOf(deck),
            children: [
              AiPanel(
                store: store,
                session: ai,
                selected: selected,
                onInsert: (text) {
                  if (selected != null &&
                      [
                        'note',
                        'script',
                        'manuscript',
                      ].contains(selected!.kind)) {
                    store.snapshot(selected!);
                    appendText(selected!, text);
                    store.changed();
                  } else {
                    newNote(text: text, title: 'AI study draft');
                  }
                },
                onReplace: (text) {
                  final s = selection;
                  if (s == null) {
                    message(
                      'Select a passage in your note before replacing text.',
                    );
                    return;
                  }
                  final o = store.project.object(s.objectId);
                  if (o == null) return;
                  try {
                    store.snapshot(o);
                    replaceRange(o, s.start, s.end, text, expected: s.text);
                    store.changed();
                  } catch (e) {
                    message(e.toString());
                  }
                },
                onOpenObject: open,
                onNavigateStudio: (m, id, d, t) {
                  setState(() {
                    if (d != null && decks.contains(d)) deck = d;
                    if (t != null) showTray = t;
                  });
                  navigate(m, noteId: id);
                },
                onProjectCreated: (_) => navigate('Home'),
              ),
              Column(
                children: [
                  ListTile(
                    title: const Text(
                      'Assets',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${store.assets.length} files · drag into your note',
                    ),
                    trailing: IconButton(
                      tooltip: 'Import assets',
                      onPressed: importFiles,
                      icon: const Icon(Icons.add),
                    ),
                  ),
                  Expanded(
                    child: store.assets.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.upload_file,
                                    size: 34,
                                    color: olive,
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Keep PDFs, documents, images, and recordings within reach.',
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton(
                                    onPressed: importFiles,
                                    child: const Text('Import files'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView(
                            children: store.assets
                                .map((o) => objectTile(o, compact: true))
                                .toList(),
                          ),
                  ),
                ],
              ),
              preview == null
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Open a tray item or choose “Preview in side deck” on any object.',
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            tooltip: 'Open large reader',
                            onPressed: () => popout(preview!),
                            icon: const Icon(Icons.open_in_full, size: 16),
                          ),
                        ),
                        Expanded(child: reader(preview!)),
                      ],
                    ),
              ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  const ListTile(
                    title: Text('Sources & evidence'),
                    subtitle: Text('Keep claims connected to their origins.'),
                  ),
                  ...store.sources.map((o) => objectTile(o, compact: true)),
                  ...store.evidence.map((o) => objectTile(o, compact: true)),
                ],
              ),
              outlineView(),
              linksView(),
              historyView(),
              propertiesView(),
            ],
          ),
        ),
      ],
    ),
  );
  Widget outlineView() {
    final o = selected;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          'Document outline',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        if (o == null)
          const Text('Open a note to see its structure.')
        else
          ...o.body
              .split('\n')
              .where((s) => s.trim().isNotEmpty && s.length < 110)
              .take(30)
              .map(
                (s) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.short_text, size: 15),
                  title: Text(s.replaceFirst(RegExp(r'^#+\s*'), '')),
                  onTap: () => Clipboard.setData(ClipboardData(text: s)),
                ),
              ),
      ],
    );
  }

  Widget linksView() {
    final o = selected;
    final back = store.project.objects.where(
      (other) => o != null && other.links.contains(o.id),
    );
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const ListTile(title: Text('Linked knowledge')),
        if (o == null)
          const Text('Open an object to explore connections.')
        else ...[
          const Text('OUTGOING', style: TextStyle(fontSize: 10)),
          ...o.links
              .map(store.project.object)
              .whereType<CreativeObject>()
              .map((e) => objectTile(e, compact: true)),
          const Divider(),
          const Text('BACKLINKS', style: TextStyle(fontSize: 10)),
          ...back.map((e) => objectTile(e, compact: true)),
        ],
      ],
    );
  }

  Widget historyView() {
    final o = selected;
    final versions = List<dynamic>.from(o?.meta['versions'] ?? []);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Versions', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        if (o != null)
          OutlinedButton.icon(
            onPressed: () => store.snapshot(o),
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('Save a checkpoint'),
          ),
        ...versions.reversed.map(
          (v) => ListTile(
            title: Text(v['title'] ?? 'Snapshot'),
            subtitle: Text(v['at'] ?? ''),
            trailing: IconButton(
              tooltip: 'Restore this version',
              onPressed: () {
                store.checkpoint();
                store.snapshot(o!);
                o.title = v['title'] ?? o.title;
                o.body = v['body'] ?? '';
                if (v['delta'] != null) {
                  o.meta['delta'] = v['delta'];
                } else {
                  o.meta.remove('delta');
                }
                store.changed();
              },
              icon: const Icon(Icons.restore),
            ),
          ),
        ),
        if (versions.isEmpty)
          const Text(
            'Save a checkpoint before major changes. AI insertions also preserve a version.',
          ),
      ],
    );
  }

  Widget propertiesView() {
    final o = selected;
    if (o == null)
      return const Center(child: Text('Select an object to inspect it.'));
    final citation =
        '${o.meta['author'] ?? 'Unknown author'}. (${o.meta['year'] ?? 'n.d.'}). ${o.title}. ${o.meta['url'] ?? ''}';
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          o.title,
          style: const TextStyle(fontFamily: 'Georgia', fontSize: 21),
        ),
        const SizedBox(height: 8),
        Text(
          '${o.kind} · ${o.id}',
          style: const TextStyle(fontSize: 10, color: secondaryInk),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Keep in tray'),
          value: o.meta['tray'] == true,
          onChanged: (v) => store.setTray(o, v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Include in AI context'),
          subtitle: const Text('Sent with your next AI request.'),
          value: o.meta['aiContext'] == true,
          onChanged: (v) => store.setContext(o, v),
        ),
        DropdownButtonFormField<String?>(
          initialValue: store.courses.any((c) => c.id == o.meta['course'])
              ? o.meta['course']
              : null,
          decoration: const InputDecoration(labelText: 'Course'),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Personal'),
            ),
            ...store.courses.map(
              (c) => DropdownMenuItem(value: c.id, child: Text(c.code)),
            ),
          ],
          onChanged: (v) {
            o.meta['course'] = v;
            store.changed();
          },
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () async {
            final f = await form('Object properties', {
              'Title': o.title,
              'Tags': (o.meta['tags'] as List? ?? []).join(', '),
              'Author': o.meta['author']?.toString() ?? '',
              'Year': o.meta['year']?.toString() ?? '',
              'URL': o.meta['url']?.toString() ?? '',
            });
            if (f != null) {
              store.checkpoint();
              o.title = f['Title']!;
              o.meta.addAll({
                'tags': f['Tags']!
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList(),
                'author': f['Author'],
                'year': f['Year'],
                'url': f['URL'],
              });
              store.changed();
            }
          },
          child: const Text('Edit metadata'),
        ),
        const SizedBox(height: 18),
        const Text('Citation', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SelectableText(
          citation,
          style: const TextStyle(fontSize: 12, height: 1.5),
        ),
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: citation));
            message(
              'Citation copied. Check author and publication metadata before submission.',
            );
          },
          icon: const Icon(Icons.copy, size: 14),
          label: const Text('Copy citation'),
        ),
        OutlinedButton(
          onPressed: () => ask(
            'Create grounded recall cards from ${o.title}. Read the object first. Use apply_workspace_changes with kind card, title as question, body as answer, links [${o.id}], and meta course ${o.meta['course'] ?? ''}. Do not invent source claims.',
          ),
          child: const Text('Create recall cards with AI'),
        ),
        OutlinedButton(
          onPressed: () => exportObject(o),
          child: const Text('Export as Markdown'),
        ),
      ],
    );
  }
}

class ConceptCanvas extends StatefulWidget {
  const ConceptCanvas({
    super.key,
    required this.store,
    required this.onOpen,
    required this.onAdd,
  });
  final ZenboxStore store;
  final void Function(CreativeObject) onOpen;
  final VoidCallback onAdd;
  @override
  State<ConceptCanvas> createState() => _ConceptCanvasState();
}

class _ConceptCanvasState extends State<ConceptCanvas> {
  String? linking;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Concept canvas',
                style: TextStyle(fontFamily: 'Georgia', fontSize: 25),
              ),
            ),
            if (linking != null)
              TextButton(
                onPressed: () => setState(() => linking = null),
                child: const Text('Cancel link'),
              ),
            IconButton(
              tooltip: 'Add concept',
              onPressed: widget.onAdd,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
      if (linking != null)
        const Text(
          'Choose another concept to connect. Tap a node’s link icon to begin.',
        ),
      Expanded(
        child: InteractiveViewer(
          constrained: false,
          boundaryMargin: const EdgeInsets.all(500),
          minScale: .3,
          maxScale: 2,
          child: DragTarget<CreativeObject>(
            onAcceptWithDetails: (d) {
              widget.store.addConcept(
                ConceptNode(
                  courseId: widget.store.activeCourseId ?? '',
                  name: d.data.title,
                  body: '',
                  links: [d.data.id],
                  x: 100,
                  y: 180,
                ),
              );
            },
            builder: (context, accepted, rejected) => SizedBox(
              width: 1500,
              height: 1100,
              child: Stack(
                children: [
                  CustomPaint(
                    size: const Size(1500, 1100),
                    painter: _Connections(widget.store),
                  ),
                  ...widget.store.concepts
                      .where(
                        (n) =>
                            widget.store.activeCourseId == null ||
                            n.meta['course'] == widget.store.activeCourseId,
                      )
                      .map(
                        (n) => Positioned(
                          left: n.x,
                          top: n.y,
                          child: GestureDetector(
                            onPanStart: (_) => widget.store.checkpoint(),
                            onPanUpdate: (d) =>
                                widget.store.updateConceptPosition(
                                  n.id,
                                  (n.x + d.delta.dx).clamp(0, 1250),
                                  (n.y + d.delta.dy).clamp(0, 900),
                                ),
                            onDoubleTap: () => widget.onOpen(n),
                            child: SizedBox(
                              width: 230,
                              child: zenPanel(
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.hub_outlined,
                                          size: 16,
                                          color: moss,
                                        ),
                                        const Spacer(),
                                        IconButton(
                                          tooltip: linking == null
                                              ? 'Connect concept'
                                              : 'Link to this concept',
                                          icon: const Icon(
                                            Icons.link,
                                            size: 16,
                                          ),
                                          onPressed: () {
                                            if (linking == null) {
                                              setState(() => linking = n.id);
                                            } else if (linking != n.id) {
                                              widget.store.addRelation(
                                                ConceptRelation(
                                                  sourceConceptId: linking!,
                                                  targetConceptId: n.id,
                                                ),
                                              );
                                              setState(() => linking = null);
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                    Text(
                                      n.title,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      n.body,
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        height: 1.5,
                                      ),
                                    ),
                                    ...n.links
                                        .map(widget.store.project.object)
                                        .whereType<CreativeObject>()
                                        .map(
                                          (o) => TextButton(
                                            onPressed: () => widget.onOpen(o),
                                            child: Text(
                                              o.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                  ],
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
        ),
      ),
    ],
  );
}

class _Connections extends CustomPainter {
  _Connections(this.store);
  final ZenboxStore store;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = olive
      ..strokeWidth = 2;
    for (final r in store.relations) {
      if (r.links.length < 2) continue;
      final a = store.project.object(r.links[0]),
          b = store.project.object(r.links[1]);
      if (a is! ConceptNode || b is! ConceptNode) continue;
      final from = Offset(a.x + 115, a.y + 85),
          to = Offset(b.x + 115, b.y + 85);
      canvas.drawLine(from, to, paint);
      final label = TextPainter(
        text: TextSpan(
          text: r.title,
          style: const TextStyle(
            color: moss,
            fontSize: 11,
            backgroundColor: surface,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, (from + to) / 2);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
