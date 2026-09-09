import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse;
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

const modes = [
  'Overview',
  'Screenplay',
  'Manuscript',
  'Story bible',
  'Canvas',
  'Media library',
  'Storyboard',
  'Video',
  'Research',
  'Scratchpad',
];
const modeIcons = [
  Icons.space_dashboard_outlined,
  Icons.movie_edit,
  Icons.menu_book_outlined,
  Icons.people_outline,
  Icons.dashboard_customize_outlined,
  Icons.photo_library_outlined,
  Icons.view_carousel_outlined,
  Icons.video_library_outlined,
  Icons.travel_explore,
  Icons.edit_note,
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
  CreativeObject? get selected => project.object(selectedId);
  String? activeToastMessage;
  Timer? _toastTimer;
  SelectionRequest? lastSelection;

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
      selected!.body += '\n\n$newText';
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
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  void restoreLayout() {
    mode = project.layout['mode'] as String? ?? 'Overview';
    if (!modes.contains(mode)) mode = 'Overview';
    dock = project.layout['dock'] as String? ?? 'AI';
    if (!['AI', 'Inspector', 'Assets', 'Versions'].contains(dock)) dock = 'AI';
    showDock = project.layout['showDock'] as bool? ?? true;
    showTray = project.layout['showTray'] as bool? ?? false;
    dockWidth =
        (project.layout['dockWidth'] as num?)?.toDouble().clamp(260, 450) ??
        306;
    selectedId = project.layout['selected'] as String?;
  }

  void saveLayout() {
    if (widget.studentMedia) { store.changed(); return; }
    project.layout.addAll({
      'mode': mode,
      'dock': dock,
      'showDock': showDock,
      'showTray': showTray,
      'dockWidth': dockWidth,
      'selected': selectedId,
    });
    store.changed();
  }

  @override
  void dispose() {
    sequenceTimer?.cancel();
    _toastTimer?.cancel();
    ai.cancel();
    store.removeListener(refresh);
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
    setState(() {
      mode = value;
      filter = '';
      if (value == 'Screenplay' || value == 'Manuscript') {
        final kind = value == 'Screenplay' ? 'script' : 'manuscript';
        if (selected?.kind != kind) {
          selectedId = project.of(kind).firstOrNull?.id;
        }
      }
    });
    saveLayout();
  }

  void open(CreativeObject o) {
    final destination =
        {
          'script': 'Screenplay',
          'manuscript': 'Manuscript',
          'character': 'Story bible',
          'location': 'Story bible',
          'lore': 'Story bible',
          'board': 'Canvas',
          'asset': 'Media library',
          'shot': 'Storyboard',
          'research': 'Research',
          'note': 'Scratchpad',
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
      'A new creative project',
      hint: 'Project name',
    );
    if (name == null) return;
    final p = Project(title: name, description: 'A space for your next idea.');
    store.projects.add(p);
    store.select(p);
    setState(() {
      selectedId = null;
      mode = 'Overview';
    });
    saveLayout();
  }

  Future<void> create(String kind) async {
    final name = await askText(
      context,
      'New ${kind == 'script' ? 'scene' : kind}',
      hint: 'Give it a name',
    );
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
    if (!['script', 'manuscript', 'asset'].contains(kind)) await edit(o);
  }

  Future<void> edit(CreativeObject o) async {
    setState(() => selectedId = o.id);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit ${o.kind}'),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed ${o.title}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            p.objects.insert(index.clamp(0, p.objects.length), o);
            for (final entry in linked.entries) {
              p.object(entry.key)?.links = entry.value;
            }
            store.changed();
          },
        ),
      ),
    );
  }

  Future<void> importFiles() async {
    final p = project;
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Import into Xandora',
    );
    if (files.isEmpty) return;
    setState(() => importing = true);
    try {
      for (final file in files) {
        if (file.path == null) continue;
        if ([
          'txt',
          'md',
          'fountain',
        ].contains(file.name.split('.').last.toLowerCase())) {
          p.objects.add(
            CreativeObject(
              kind: file.name.endsWith('.fountain') ? 'script' : 'manuscript',
              title: file.name,
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
    final ext = o.kind == 'script' ? 'fountain' : 'md';
    final result = await FilePicker.saveFile(
      fileName: '${safeName(o.title)}.$ext',
      bytes: Uint8List.fromList(utf8.encode(o.body)),
      dialogTitle: 'Export document',
    );
    if (result != null) toast('Exported ${o.title}');
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
    }
    final result = await FilePicker.saveFile(
      fileName: '${safeName(project.title)}.xandora',
      bytes: Uint8List.fromList(ZipEncoder().encode(archive)),
      dialogTitle: 'Save portable project with media',
    );
    if (result != null) toast('Portable project saved with all media');
  }

  Future<void> importProject() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['xandora'],
      dialogTitle: 'Open a portable Xandora project',
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
    if (manifest == null) throw const FormatException('Not a Xandora project');
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
    }
    for (final asset in imported.of('asset')) {
      final name = asset.meta['file'] as String;
      final bytes = archive.findFile('media/$name')!.content;
      final newName = '${newId()}.${name.split('.').last}';
      await File(
        '${store.directory.path}/media/$newName',
      ).writeAsBytes(bytes, flush: true);
      asset.meta['file'] = newName;
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
    if (o.kind != 'asset') {
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
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        openFloatingVideo(o);
                      },
                      icon: const Icon(Icons.picture_in_picture_alt, size: 16),
                      label: Text(
                        o.meta['mediaType'] == 'video'
                            ? 'Pop out video'
                            : (o.meta['mediaType'] == 'image'
                                  ? 'Float image'
                                  : 'Float item'),
                      ),
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
  Widget build(BuildContext context) => widget.studentMedia ? Material(
    color: paper,
    child: Stack(children: [
      Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20,12,20,0),child:Wrap(spacing:8,children:[
          ChoiceChip(label:const Text('Presentation plan'),selected:mode!='Video',onSelected:(_)=>setState(()=>mode='Storyboard')),
          ChoiceChip(label:const Text('Preview sequence'),selected:mode=='Video',onSelected:(_)=>setState(()=>mode='Video')),
          TextButton.icon(icon:const Icon(Icons.link,size:16),label:const Text('Attach media to segment'),onPressed:shots.isEmpty?null:() async {
            final target=selected?.kind=='shot'?selected!:shots.first;
            await showDialog<void>(context:context,builder:(context)=>AlertDialog(title:Text('Media for ${target.title}'),content:SizedBox(width:400,height:400,child:ListView(children:project.of('asset').map((o)=>CheckboxListTile(title:Text(o.title),value:target.links.contains(o.id),onChanged:(v){if(v==true){target.links.add(o.id);}else{target.links.remove(o.id);}store.changed();Navigator.pop(context);})).toList())),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Done'))]));
          }),
        ])),
        Expanded(child:production()),
      ]),
      for(var i=0;i<floatingWidgets.length;i++)FloatingVideoPlayer(key:ValueKey(floatingWidgets[i].id),store:store,asset:floatingWidgets[i].asset,initialPosition:Offset(40+i*24,60+i*24),onClose:()=>closeFloatingWidget(floatingWidgets[i].id)),
    ]),
  ) : CallbackShortcuts(
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
                    showDock && !focusMode && constraints.maxWidth >= 1000;
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
                                Expanded(child: workspace()),
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
                                    () => dockWidth = (dockWidth - d.delta.dx)
                                        .clamp(260, 450),
                                  );
                                },
                                onHorizontalDragEnd: (_) => saveLayout(),
                                child: Container(
                                  width: 5,
                                  color: line.withValues(alpha: .5),
                                ),
                              ),
                            ),
                            SizedBox(width: dockWidth, child: rightDock()),
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
              initialPosition: Offset(120.0 + index * 28, 100.0 + index * 28),
              onClose: () => closeFloatingWidget(floatingWidgets[index].id),
            ),
          if (activeToastMessage != null)
            Positioned(
              bottom: 24,
              right: 24,
              child: LayoutBuilder(
                builder: (context, _) {
                  final screenWidth = MediaQuery.sizeOf(context).width;
                  final toastWidth = (screenWidth * 0.15).clamp(240.0, 360.0);
                  return Material(
                    elevation: 12,
                    color: Colors.transparent,
                    child: Container(
                      width: toastWidth,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: ink.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: sage.withValues(alpha: 0.5)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: paleSage),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              activeToastMessage!,
                              style: TextStyle(
                                fontSize: 12,
                                color: cream,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: dismissToast,
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: paleSage,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
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
            'xandora',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 24,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'STUDIO',
            style: TextStyle(fontSize: 8, letterSpacing: 2, color: muted),
          ),
        ],
        const SizedBox(width: 23),
        Container(width: 1, height: 23, color: line),
        const SizedBox(width: 18),
        Expanded(
          child: PopupMenuButton<String>(
            tooltip: 'Switch project',
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
              const PopupMenuItem(value: 'new', child: Text('+ New project')),
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
          icon: const Icon(Icons.vertical_split_outlined),
        ),
        const SizedBox(width: 10),
        PopupMenuButton<String>(
          onSelected: (v) =>
              run(v == 'project' ? exportProject : () => exportText(selected!)),
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'project',
              child: Text('Portable project (.xandora)'),
            ),
            if (selected != null && selected!.kind != 'asset')
              const PopupMenuItem(
                value: 'document',
                child: Text('Current document'),
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
              'YOUR WORKSPACE',
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
                      message: compact ? modes[i] : '',
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
                                      modes[i],
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
                    'An idea worth keeping?',
                    style: TextStyle(fontFamily: 'Georgia', fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Give it a little space to grow.',
                    style: TextStyle(fontSize: 10, color: muted),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: quickCapture,
                    child: const Row(
                      children: [
                        Text(
                          'Quick capture',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Spacer(),
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
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Settings & keyboard shortcuts',
                onPressed: settings,
                icon: const Icon(Icons.settings_outlined),
              ),
              if (!compact) ...[
                TextButton(
                  onPressed: settings,
                  child: Text(
                    'Settings',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
                const Spacer(),
                const Tag('LOCAL'),
              ],
            ],
          ),
        ),
      ],
    ),
  );
  Widget statusBar() => Container(
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
        if (importing)
          Text('Importing files…', style: TextStyle(fontSize: 9, color: muted)),
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
  Widget workspace() {
    switch (mode) {
      case 'Overview':
        return overview();
      case 'Screenplay':
      case 'Manuscript':
        return writing();
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
        return production();
      case 'Research':
        return ResearchBrowserView(store: store, onOpenNote: edit);
      default:
        return collection();
    }
  }

  Widget overview() => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          'A space for your imagination',
          'Make something meaningful.',
          subtitle: 'One project. Every part of your creative process.',
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
                  const Positioned.fill(
                    child: CustomPaint(painter: _LandscapePainter()),
                  ),
                  Positioned(
                    left: 27,
                    top: 26,
                    right: 170,
                    bottom: 22,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Tag('YOUR CURRENT PROJECT', color: paper),
                        const Spacer(),
                        Text(
                          project.title,
                          style: TextStyle(
                            fontFamily: 'Georgia',
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
                          onTap: () => navigate('Screenplay'),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Continue the story',
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
                'Documents',
                Icons.description_outlined,
              ),
              const SizedBox(width: 12),
              stat(
                '${project.of('character').length}',
                'Characters',
                Icons.people_outline,
              ),
              const SizedBox(width: 12),
              stat(
                '${project.of('asset').length}',
                'Media assets',
                Icons.photo_outlined,
              ),
              const SizedBox(width: 12),
              stat(
                '${project.objects.where((o) => ['script', 'manuscript'].contains(o.kind)).fold<int>(0, (n, o) => n + (o.body.trim().isEmpty ? 0 : o.body.trim().split(RegExp(r'\s+')).length))}',
                'Words written',
                Icons.edit_outlined,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Row(
            children: [
              const Text(
                'Pick up a thread',
                style: TextStyle(fontFamily: 'Georgia', fontSize: 21),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => navigate('Screenplay'),
                child: const Text(
                  'All documents  →',
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
                                    ? Icons.movie_edit
                                    : Icons.menu_book_outlined,
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
                                        ? 'Screenplay · ${o.meta['act'] ?? 'Unassigned act'}'
                                        : 'Manuscript',
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
                  label: const Text('Write your first scene'),
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
                style: TextStyle(fontFamily: 'Georgia', fontSize: 21),
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
                'Story bible',
                'Get to know your world.',
                Icons.people_outline,
                paleSage,
              ),
              exploreCard(
                'Canvas',
                'Connect the unexpected.',
                Icons.dashboard_customize_outlined,
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
                  style: const TextStyle(fontFamily: 'Georgia', fontSize: 23),
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
                style: const TextStyle(fontFamily: 'Georgia', fontSize: 18),
              ),
              const SizedBox(height: 7),
              Text(subtitle, style: TextStyle(fontSize: 10, color: muted)),
            ],
          ),
        ),
      ),
    ),
  );
  Widget writing() {
    final kind = mode == 'Screenplay' ? 'script' : 'manuscript';
    final documents = project.of(kind).toList();
    final current = selected?.kind == kind ? selected : null;
    return Column(
      children: [
        Container(
          height: 45,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: line)),
          ),
          padding: const EdgeInsets.only(left: 12, right: 8),
          child: Row(
            children: [
              Expanded(
                child: ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: false,
                  itemCount: documents.length,
                  onReorderItem: (oldIndex, newIndex) {
                    final item = documents.removeAt(oldIndex);
                    documents.insert(newIndex, item);
                    var n = 0;
                    for (var i = 0; i < project.objects.length; i++) {
                      if (project.objects[i].kind == kind) {
                        project.objects[i] = documents[n++];
                      }
                    }
                    store.changed();
                  },
                  itemBuilder: (context, index) {
                    final o = documents[index];
                    return ReorderableDragStartListener(
                      key: ValueKey(o.id),
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.only(
                          right: 5,
                          top: 6,
                          bottom: 6,
                        ),
                        child: TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: current?.id == o.id
                                ? paleSage.withValues(alpha: .45)
                                : Colors.transparent,
                          ),
                          onPressed: () {
                            setState(() => selectedId = o.id);
                            saveLayout();
                          },
                          child: Text(
                            o.title,
                            style: TextStyle(
                              fontSize: 10,
                              color: current?.id == o.id ? ink : muted,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              IconButton(
                tooltip: 'New ${kind == 'script' ? 'scene' : 'chapter'}',
                onPressed: () => create(kind),
                icon: const Icon(Icons.add, size: 17),
              ),
            ],
          ),
        ),
        Expanded(
          child: current == null
              ? EmptyState(
                  Icons.edit_outlined,
                  'The page is yours.',
                  'Create a ${kind == 'script' ? 'scene' : 'chapter'} to begin.',
                  action: FilledButton.icon(
                    onPressed: () => create(kind),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Start writing'),
                  ),
                )
              : DocumentEditor(
                  key: ValueKey(current.id),
                  store: store,
                  object: current,
                  onInspect: () {
                    setState(() {
                      dock = 'Inspector';
                      showDock = true;
                    });
                  },
                  onExport: () => run(() => exportText(current)),
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

  List<CreativeObject> collectionObjects() {
    final kinds = switch (mode) {
      'Story bible' => ['character', 'location', 'lore'],
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

  Widget collection() {
    final objects = collectionObjects();
    final media = mode == 'Media library';
    final kind = switch (mode) {
      'Story bible' => 'character',
      'Media library' => 'asset',
      'Research' => 'research',
      _ => 'note',
    };
    final subtitle = switch (mode) {
      'Story bible' =>
        'The people, places, and rules that make your story yours.',
      'Media library' =>
        'Your images, footage, audio, and references. Together.',
      'Research' => 'Follow your curiosity. Keep the source close.',
      _ => 'Capture first. Make sense of it later.',
    };
    return Column(
      children: [
        SectionHeading(
          'Your shared project',
          mode,
          subtitle: subtitle,
          actions: [
            if (mode == 'Story bible')
              PopupMenuButton<String>(
                tooltip: 'Add to story bible',
                onSelected: create,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'character', child: Text('Character')),
                  PopupMenuItem(value: 'location', child: Text('Location')),
                  PopupMenuItem(value: 'lore', child: Text('World / lore')),
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
            key: ValueKey(mode),
            decoration: InputDecoration(
              hintText: 'Filter ${mode.toLowerCase()}…',
              prefixIcon: const Icon(Icons.search, size: 17),
            ),
            onChanged: (v) => setState(() => filter = v),
          ),
        ),
        Expanded(
          child: objects.isEmpty
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
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              border: Border.all(color: selectedId == o.id ? sage : line),
              borderRadius: BorderRadius.circular(8),
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
                      fontFamily: media ? 'Segoe UI' : 'Georgia',
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
    builder: (context, candidates, rejected) => Container(
      height: 98,
      decoration: BoxDecoration(
        color: candidates.isNotEmpty ? paleSage : const Color(0xFFECEDE2),
        border: Border(top: BorderSide(color: line)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 18),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.inventory_2_outlined, size: 17, color: muted),
              const SizedBox(height: 5),
              Text(
                'TEMPORARY TRAY',
                style: TextStyle(fontSize: 8, color: muted, letterSpacing: 1),
              ),
            ],
          ),
          const SizedBox(width: 18),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final o in project.objects.where(
                  (o) => o.meta['tray'] == true,
                ))
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 17,
                    ),
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
                                  o.kind == 'script'
                                      ? Icons.movie_outlined
                                      : (o.kind == 'research'
                                            ? Icons.travel_explore
                                            : Icons.note_outlined),
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
                                  style: TextStyle(
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
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Capture a thought',
            onPressed: quickCapture,
            icon: const Icon(Icons.add, size: 18),
          ),
        ],
      ),
    ),
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

  Widget production() {
    final items = shots;
    final video = mode == 'Video';
    final current = selected?.kind == 'shot' ? selected : items.firstOrNull;
    final asset = current == null ? null : shotAsset(current);
    return Column(
      children: [
        SectionHeading(
          widget.studentMedia ? 'Present what you understand' : 'From page to picture',
          widget.studentMedia ? (video ? 'Presentation preview' : 'Your presentation, step by step') : (video ? 'The sequence' : 'A story, frame by frame'),
          subtitle:
              '${items.length} shots · ${items.fold<double>(0, (n, o) => n + (o.meta['duration'] as num? ?? 5).toDouble()).toStringAsFixed(1)} seconds · drag shots to reorder',
          actions: [
            IconButton(
              tooltip: storyboardGridView
                  ? 'Switch to Timeline Sequence view'
                  : 'Switch to Corkboard Grid view',
              onPressed: () =>
                  setState(() => storyboardGridView = !storyboardGridView),
              icon: Icon(
                storyboardGridView
                    ? Icons.view_agenda_outlined
                    : Icons.grid_view_rounded,
              ),
            ),
            IconButton(
              tooltip: 'Export shot list as CSV',
              onPressed: () => run(exportShots),
              icon: const Icon(Icons.download_outlined),
            ),
            FilledButton.icon(
              onPressed: () => create('shot'),
              icon: const Icon(Icons.add, size: 16),
              label: Text(widget.studentMedia ? 'New segment' : 'New shot'),
            ),
          ],
        ),
        Expanded(
          child: items.isEmpty
              ? EmptyState(
                  Icons.movie_creation_outlined,
                  widget.studentMedia ? 'Plan your first explanation.' : 'Frame your first moment.',
                  widget.studentMedia ? 'Add a presentation segment, write its talking points, and attach an image or recording.' : 'Add a shot, then link a scene and reference image.',
                  action: FilledButton(
                    onPressed: () => create('shot'),
                    child: Text(widget.studentMedia ? 'Add segment' : 'Add shot'),
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
                                        current?.title ?? 'Select a shot',
                                        style: TextStyle(
                                          fontFamily: 'Georgia',
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
                          Tag(current?.meta['camera'] as String? ?? 'Shot'),
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
      ['Shot', 'Description', 'Camera', 'Duration (s)', 'Linked scene'],
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
      fileName: '${safeName(project.title)}-shots.csv',
      bytes: Uint8List.fromList(utf8.encode(csv)),
    );
    if (result != null) toast('Shot list exported');
  }

  Widget rightDock() => ColoredBox(
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
              for (final name in ['AI', 'Inspector', 'Assets', 'Versions'])
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
            index: ['AI', 'Inspector', 'Assets', 'Versions'].indexOf(dock),
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
        'Select a document, card, or shot to see its details and connections.',
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
                Tag(o.kind.toUpperCase()),
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
                fontFamily: 'Georgia',
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
                decoration: const InputDecoration(labelText: 'Act / section'),
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
                  labelText: 'Synopsis',
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
                  labelText: 'Framing / movement',
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
                    subtitle: Text(o.kind),
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

  Widget dockAssets() => Column(
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
        child: project.of('asset').isEmpty
            ? const EmptyState(
                Icons.photo_outlined,
                'Gather your references',
                'Import images, footage, or sound. Drag them onto shots, canvas, or inspector.',
              )
            : GridView.count(
                crossAxisCount: 2,
                childAspectRatio: 1,
                padding: const EdgeInsets.all(12),
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                children: [
                  for (final o in project.of('asset'))
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
  Widget versions() {
    final o = selected;
    final versions = List<dynamic>.from(o?.meta['versions'] ?? []);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Revision history',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Save revision',
                onPressed: o == null ? null : () => store.snapshot(o),
                icon: const Icon(Icons.add, size: 17),
              ),
            ],
          ),
        ),
        Expanded(
          child: versions.isEmpty
              ? const EmptyState(
                  Icons.history,
                  'Keep your possibilities',
                  'Save a revision before a big change. Restore it whenever you need.',
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
                                    'Revision restored; previous content kept in history',
                                  );
                                },
                                child: const Text(
                                  'Restore this revision',
                                  style: TextStyle(fontSize: 10),
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: 'Delete this revision',
                                iconSize: 15,
                                color: muted,
                                onPressed: () {
                                  final removed = versions.removeAt(index);
                                  o!.meta['versions'] = versions;
                                  store.changed();
                                  setState(() {});
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text('Revision deleted'),
                                      action: SnackBarAction(
                                        label: 'Undo',
                                        onPressed: () {
                                          versions.insert(index, removed);
                                          o.meta['versions'] = versions;
                                          store.changed();
                                          setState(() {});
                                        },
                                      ),
                                    ),
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
            title: const Text('Studio Preferences & Customization'),
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
                                child: Text('Courier New (Screenplay)'),
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
                        labelText: 'Creative AI Tone',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Balanced Producer',
                          child: Text('Balanced Producer (Structure & beats)'),
                        ),
                        DropdownMenuItem(
                          value: 'Critique & Polish',
                          child: Text('Critique & Polish (Sharp line editing)'),
                        ),
                        DropdownMenuItem(
                          value: 'Creative Outliner',
                          child: Text(
                            'Creative Outliner (Expansive worldbuilding)',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Screenplay Specialist',
                          child: Text(
                            'Screenplay Specialist (Dialogue & action)',
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
                      title: const Text('New project'),
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
                    if (modes[i].toLowerCase().contains(query))
                      ListTile(
                        leading: Icon(modeIcons[i], size: 19),
                        title: Text(
                          'Go to ${modes[i]}',
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
                        o.kind,
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

class _LandscapePainter extends CustomPainter {
  const _LandscapePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFC7D2BF),
    );
    canvas.drawCircle(
      Offset(w * .83, h * .29),
      39,
      Paint()..color = const Color(0xFFEDE3C3),
    );
    final far = Path()
      ..moveTo(w * .43, h)
      ..cubicTo(w * .63, h * .2, w * .75, h * .95, w, h * .43)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(far, Paint()..color = const Color(0xFFA3B39A));
    final near = Path()
      ..moveTo(w * .54, h)
      ..cubicTo(w * .67, h * .57, w * .84, h * .89, w, h * .63)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(near, Paint()..color = sage);
    final x = w * .855;
    canvas.drawPath(
      Path()
        ..moveTo(x - 9, h * .7)
        ..lineTo(x - 5, h * .35)
        ..lineTo(x + 5, h * .35)
        ..lineTo(x + 10, h * .7)
        ..close(),
      Paint()..color = cream,
    );
    canvas.drawRect(
      Rect.fromLTWH(x - 7, h * .31, 14, h * .055),
      Paint()..color = ink.withValues(alpha: .7),
    );
    canvas.drawPath(
      Path()
        ..moveTo(x - 10, h * .31)
        ..lineTo(x, h * .265)
        ..lineTo(x + 10, h * .31)
        ..close(),
      Paint()..color = ink,
    );
    canvas.drawRect(
      Rect.fromLTWH(x - 3, h * .319, 6, h * .026),
      Paint()..color = gold,
    );
    final light = Path()
      ..moveTo(x, h * .333)
      ..lineTo(w * .61, h * .2)
      ..lineTo(w * .61, h * .44)
      ..close();
    canvas.drawPath(light, Paint()..color = paper.withValues(alpha: .16));
  }

  @override
  bool shouldRepaint(_LandscapePainter oldDelegate) => false;
}
