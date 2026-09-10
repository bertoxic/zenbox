import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_kit/media_kit.dart';

int _serial = 0;
String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_serial++}';

class CreativeObject {
  CreativeObject({
    String? id,
    required this.kind,
    required this.title,
    this.body = '',
    Map<String, dynamic>? meta,
    List<String>? links,
  }) : id = id ?? newId(),
       meta = meta ?? {},
       links = links ?? [];
  final String id;
  String kind, title, body;
  Map<String, dynamic> meta;
  List<String> links;
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'title': title,
    'body': body,
    'meta': meta,
    'links': links,
  };
  factory CreativeObject.fromJson(Map<String, dynamic> j) => CreativeObject(
    id: j['id'] as String?,
    kind: j['kind'] as String? ?? 'note',
    title: j['title'] as String? ?? '',
    body: j['body'] as String? ?? '',
    meta: Map<String, dynamic>.from(j['meta'] as Map? ?? {}),
    links: (j['links'] as List?)?.map((e) => e.toString()).toList() ?? [],
  );
}

class Project {
  Project({
    String? id,
    required this.title,
    this.description = '',
    List<CreativeObject>? objects,
    Map<String, dynamic>? layout,
  }) : id = id ?? newId(),
       objects = objects ?? [],
       layout = layout ?? {};
  final String id;
  String title, description;
  List<CreativeObject> objects;
  Map<String, dynamic> layout;
  Iterable<CreativeObject> of(String kind) =>
      objects.where((e) => e.kind == kind);
  CreativeObject? object(String? id) {
    for (final o in objects) {
      if (o.id == id) return o;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'objects': objects.map((e) => e.toJson()).toList(),
    'layout': layout,
  };
  factory Project.fromJson(Map<String, dynamic> j) => Project(
    id: j['id'] as String? ?? newId(),
    title: j['title'] as String? ?? 'Untitled',
    description: j['description'] as String? ?? '',
    objects:
        (j['objects'] as List?)
            ?.whereType<Map>()
            .map((e) => CreativeObject.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        [],
    layout: Map<String, dynamic>.from(j['layout'] as Map? ?? {}),
  );
}

class StudioStore extends ChangeNotifier {
  late Directory directory;
  List<Project> projects = [];
  String currentId = '';
  Map<String, dynamic> settings = {};
  String? error;
  String saveState = 'All changes saved';
  Timer? _timer;
  final Map<String, Future<String?>> _thumbnailJobs = {};
  Project get project => projects.firstWhere(
    (e) => e.id == currentId,
    orElse: () => projects.first,
  );
  File get file => File('${directory.path}/zenbox.json');
  Future<void> load() async {
    final support = await getApplicationSupportDirectory();
    directory = Directory('${support.path}/Zenbox');
    await directory.create(recursive: true);
    await Directory('${directory.path}/media').create(recursive: true);
    if (!file.existsSync()) {
      final appData = Platform.environment['APPDATA'] ?? '';
      final candidates = [
        File('${directory.path}/studio.json'),
        File('${support.path}/Zenbox/zenbox.json'),
        File('${support.path}/Zenbox/studio.json'),
        File('${support.path}/Xandora Studio/studio.json'),
        File('${support.path}/studio.json'),
        if (appData.isNotEmpty) ...[
          File('$appData/com.xandorabox/Zenbox/Zenbox/zenbox.json'),
          File('$appData/com.xandorabox/Zenbox/Xandora Studio/studio.json'),
          File('$appData/com.xandorabox/Xandora Studio/studio.json'),
          File('$appData/com.bertoxic/Xandora Studio/studio.json'),
        ],
      ];
      for (final c in candidates) {
        if (c.existsSync()) {
          try {
            final content = c.readAsStringSync();
            if (content.trim().isNotEmpty) {
              file.writeAsStringSync(content, flush: true);
              final mediaDir = Directory('${c.parent.path}/media');
              if (mediaDir.existsSync() && c.parent.path != directory.path) {
                for (final item in mediaDir.listSync()) {
                  if (item is File) {
                    final dest =
                        '${directory.path}/media/${item.uri.pathSegments.last}';
                    if (!File(dest).existsSync()) item.copySync(dest);
                  }
                }
              }
              break;
            }
          } catch (_) {}
        }
      }
    }
    if (file.existsSync()) {
      try {
        _decode(file.readAsStringSync());
      } catch (e) {
        final backup = File('${file.path}.bak');
        if (backup.existsSync()) {
          _decode(backup.readAsStringSync());
          error =
              'Recovered your last backup. The damaged file has been preserved.';
        } else {
          rethrow;
        }
        file.copySync('${file.path}.damaged-${newId()}');
      }
    }
    settings.putIfAbsent('studentWorkspace', () => true);
    if (projects.isEmpty) {
      projects.add(seedProject());
      currentId = projects.first.id;
      save();
    }
  }

  void _decode(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    if (j['version'] != null && j['version'] != 1) {
      throw const FormatException('Unsupported studio file version');
    }
    final rawProjects = j['projects'];
    if (rawProjects is List) {
      projects = rawProjects
          .whereType<Map>()
          .map((e) => Project.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } else {
      projects = [];
    }
    currentId =
        j['currentId'] as String? ??
        (projects.isNotEmpty ? projects.first.id : '');
    settings = Map<String, dynamic>.from(j['settings'] as Map? ?? {});
  }

  void changed() {
    saveState = 'Saving…';
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 450), save);
    notifyListeners();
  }

  void save() {
    _timer?.cancel();
    try {
      final encoded = jsonEncode({
        'version': 1,
        'currentId': currentId,
        'projects': projects.map((e) => e.toJson()).toList(),
        'settings': settings,
      });
      final temp = File('${file.path}.tmp');
      temp.writeAsStringSync(encoded, flush: true);
      if (file.existsSync()) file.copySync('${file.path}.bak');
      temp.renameSync(file.path);
      saveState = 'All changes saved';
      error = null;
    } catch (e) {
      error = 'Could not save: $e';
      saveState = 'Save failed';
    }
    notifyListeners();
  }

  void select(Project p) {
    currentId = p.id;
    changed();
  }

  void add(CreativeObject o) {
    project.objects.add(o);
    changed();
  }

  void remove(CreativeObject o) {
    project.objects.remove(o);
    for (final item in project.objects) {
      item.links.remove(o.id);
    }
    changed();
  }

  String mediaPath(CreativeObject o) =>
      '${directory.path}/media/${o.meta['file']}';
  String thumbnailPath(CreativeObject o) =>
      '${directory.path}/media/${o.meta['thumbnail']}';

  /// Capture a small poster frame once and reuse it everywhere the video is
  /// represented. This keeps scrolling inexpensive and also upgrades media
  /// imported before thumbnails were introduced.
  Future<String?> ensureVideoThumbnail(CreativeObject o) async {
    if (o.meta['mediaType'] != 'video') return null;
    final existing = o.meta['thumbnail']?.toString();
    if (existing != null &&
        await File('${directory.path}/media/$existing').exists()) {
      return existing;
    }
    final inFlight = _thumbnailJobs[o.id];
    if (inFlight != null) return inFlight;
    late final Future<String?> job;
    job = _captureVideoThumbnail(
      o,
    ).whenComplete(() => _thumbnailJobs.remove(o.id));
    _thumbnailJobs[o.id] = job;
    return job;
  }

  Future<String?> _captureVideoThumbnail(CreativeObject o) async {
    final source = File(mediaPath(o));
    if (!await source.exists()) return null;
    final player = Player();
    try {
      await player.open(Media(source.path), play: false);
      await Future<void>.delayed(const Duration(milliseconds: 220));
      await player.seek(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 180));
      final bytes = await player.screenshot(format: 'image/jpeg');
      if (bytes == null || bytes.isEmpty) return null;
      final name = '${o.id}-thumb.jpg';
      await File(
        '${directory.path}/media/$name',
      ).writeAsBytes(bytes, flush: true);
      o.meta['thumbnail'] = name;
      changed();
      return name;
    } catch (_) {
      return null;
    } finally {
      await player.dispose();
    }
  }

  Future<CreativeObject> importMedia(String path, String name) async {
    final ext = name
        .split('.')
        .last
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]'), '');
    final id = newId();
    final dest = '$id.$ext';
    await File(path).copy('${directory.path}/media/$dest');
    final asset = CreativeObject(
      id: id,
      kind: 'asset',
      title: name,
      meta: {
        'file': dest,
        'mediaType': ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'].contains(ext)
            ? 'image'
            : ['mp4', 'mov', 'mkv', 'webm', 'avi'].contains(ext)
            ? 'video'
            : ['mp3', 'wav', 'ogg', 'm4a', 'flac'].contains(ext)
            ? 'audio'
            : 'file',
        'bytes': await File(path).length(),
      },
    );
    // Generate the poster during import, before it can appear in a long list.
    if (asset.meta['mediaType'] == 'video') await ensureVideoThumbnail(asset);
    return asset;
  }

  void snapshot(CreativeObject o) {
    final versions = List<dynamic>.from(o.meta['versions'] ?? []);
    versions.insert(0, {
      'at': DateTime.now().toIso8601String(),
      'body': o.body,
      'title': o.title,
      if (o.meta['delta'] != null)
        'delta': jsonDecode(jsonEncode(o.meta['delta'])),
    });
    o.meta['versions'] = versions.take(40).toList();
    changed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

Project seedProject() {
  final topic1 = CreativeObject(
    kind: 'script',
    title: '01 · Working Memory & Cognitive Load',
    body:
        '### 1. Working Memory Architecture\n\nWorking memory provides temporary storage and real-time manipulation of task-critical information.\n\n> **Key Takeaway:** Capacity is strictly bottlenecked (Miller\'s Law: 7 ± 2 items; modern consensus: ~4 chunks). Cognitive overload occurs when extraneous load consumes processing bandwidth.\n\n* **Phonological Loop:** Rehearses verbal and acoustic tokens.\n* **Visuospatial Sketchpad:** Holds spatial configurations and mental imagery.\n* **Central Executive:** Allocates attention and resolves cognitive conflict.\n\n--- \n**Review Prompt:** How does chunking alleviate extraneous cognitive load?',
    meta: {
      'status': 'Reviewed',
      'act': 'Unit 1 · Cognitive Architecture',
      'synopsis':
          'Exploration of working memory sub-systems and cognitive load management.',
    },
  );
  final defMemory = CreativeObject(
    kind: 'definition',
    title: 'Working Memory',
    body:
        'A limited-capacity system responsible for temporary maintenance and manipulation of information during complex cognitive tasks.',
    meta: {'role': 'Core Definition', 'category': 'Architecture'},
  );
  final formCurve = CreativeObject(
    kind: 'formula',
    title: 'Ebbinghaus Forgetting Curve',
    body:
        'R = e^(-t/S)\n\nWhere:\n• R = Retrievability / Memory Retention\n• t = Time elapsed since initial learning\n• S = Stability of memory trace (strengthened by spaced active retrieval)',
    meta: {'role': 'Mathematical Model', 'category': 'Quantitative'},
  );
  final ruleRecall = CreativeObject(
    kind: 'rule',
    title: 'Active Recall vs Recognition',
    body:
        'Rule: Never mistake passive recognition for durable active recall. Familiarity when rereading does not equal ability to generate solutions from memory. Always self-test.',
    meta: {'role': 'Core Rule / Fact', 'category': 'Metacognition'},
  );
  topic1.links.addAll([defMemory.id, formCurve.id, ruleRecall.id]);

  return Project(
    title: 'Cognitive Science & Learning Systems',
    description:
        'Structured study notes, concept glossary, and synthesized unit guides on human memory and active recall.',
    objects: [
      topic1,
      CreativeObject(
        kind: 'script',
        title: '02 · Synaptic Plasticity & LTP',
        body:
            '### 2. Neural Mechanisms of Consolidation\n\nLong-Term Potentiation (LTP) represents the persistent strengthening of synapses based on recent stimulation patterns.\n\n> **Key Takeaway:** Repeated active retrieval triggers dendritic spine remodeling and protein synthesis, transferring memory traces from the hippocampus to distributed neocortical networks.\n\n* **Active Retrieval Practice:** Generates potentiation signals superior to passive rereading.\n* **The Spacing Effect:** Distributed sessions interrupt synaptic decay before baseline loss.',
        meta: {'status': 'In progress', 'act': 'Unit 1 · Neural Mechanisms'},
      ),
      CreativeObject(
        kind: 'script',
        title: '03 · Spaced Retrieval Strategies',
        body:
            '### 3. Implementing Expanding Schedule Intervals\n\nOptimal review spacing expands exponentially: 1 day -> 3 days -> 7 days -> 21 days -> 60 days.',
        meta: {'status': 'Draft', 'act': 'Unit 2 · Practical Application'},
      ),
      CreativeObject(
        kind: 'manuscript',
        title: 'Unit 1 Summary · Cognitive Foundations',
        body:
            'The foundation of effective learning balances working memory limits against long-term consolidation mechanisms.\n\nWorking memory is bottlenecked by capacity, meaning instructional materials must minimize extraneous presentation overhead. Transitioning concepts into long-term memory demands effortful retrieval practice rather than passive re-reading.\n\nBy organizing concepts into structured mental models and testing retrieval early, students solidify synaptic pathways and build durable schemas.',
      ),
      defMemory,
      formCurve,
      ruleRecall,
      CreativeObject(
        kind: 'concept',
        title: 'Cognitive Load Theory',
        body:
            'Delineates mental effort into Intrinsic (inherent difficulty), Extraneous (presentation format), and Germane (schema construction). Good study systems minimize extraneous load to maximize germane processing.',
        meta: {'role': 'Framework'},
      ),
      CreativeObject(
        kind: 'note',
        title: 'Exam Preparation Checklist',
        body:
            '1. Test recall on working memory subcomponents.\n2. Calculate decay interval using forgetting curve.\n3. Diagram hippocampal-cortical dialogue.',
        meta: {'tray': true},
      ),
      CreativeObject(
        kind: 'note',
        title: 'Self-explanation technique',
        body:
            'When writing study notes, explain why a step works in your own words before looking at the solution.',
        meta: {'tray': true},
      ),
      CreativeObject(
        kind: 'research',
        title: 'Empirical Spacing Trials (Karpicke & Roediger)',
        body:
            'Landmark research confirming that retrieval practice produces large gains in long-term retention compared to repeated study with immediate restudy.',
        meta: {
          'url': 'https://en.wikipedia.org/wiki/Testing_effect',
          'status': 'Verified',
        },
      ),
      CreativeObject(
        kind: 'board',
        title: 'Working Memory',
        body:
            'Strict 4-chunk bottleneck · Central executive & phonological loop',
        meta: {'x': 100.0, 'y': 100.0, 'color': 0},
      ),
      CreativeObject(
        kind: 'board',
        title: 'Long-Term Memory',
        body: 'Distributed cortical schemas · Synaptic consolidation via LTP',
        meta: {'x': 460.0, 'y': 100.0, 'color': 1},
      ),
      CreativeObject(
        kind: 'board',
        title: 'Retrieval Practice Bridge',
        body:
            'Active testing forces retrieval from LTM back into WM, strengthening pathways',
        meta: {'x': 280.0, 'y': 240.0, 'color': 2},
      ),
    ],
  );
}
