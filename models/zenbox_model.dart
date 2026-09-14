import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:zenbox/models/model.dart';

class Course extends CreativeObject {
  Course({
    String? id,
    required String code,
    required String title,
    String instructor = '',
    String targetGrade = '',
    Map<String, dynamic>? meta,
  }) : super(
         id: id,
         kind: 'course',
         title: title,
         meta:
             meta ??
             {
               'code': code,
               'instructor': instructor,
               'targetGrade': targetGrade,
             },
       );
  String get code => meta['code'] as String? ?? '';
  String get instructor => meta['instructor'] as String? ?? '';
  String get targetGrade => meta['targetGrade'] as String? ?? '';
  set targetGrade(String value) => meta['targetGrade'] = value;
}

class StudentNote extends CreativeObject {
  StudentNote({
    String? id,
    String courseId = '',
    required String title,
    String body = '',
    List<String> tags = const [],
    List<String>? links,
    Map<String, dynamic>? meta,
  }) : super(
         id: id,
         kind: 'note',
         title: title,
         body: body,
         links: links,
         meta: meta ?? {'course': courseId, 'tags': tags},
       );
  String get courseId => meta['course'] as String? ?? '';
  bool get isPinned => meta['pinned'] == true;
}

class ResearchSource extends CreativeObject {
  ResearchSource({
    String? id,
    required String title,
    String courseId = '',
    String author = '',
    String publicationYear = '',
    String sourceKind = 'article',
    String url = '',
    String body = '',
    Map<String, dynamic>? meta,
    List<String>? links,
  }) : super(
         id: id,
         kind: 'source',
         title: title,
         body: body,
         links: links,
         meta:
             meta ??
             {
               'course': courseId,
               'author': author,
               'year': publicationYear,
               'sourceKind': sourceKind,
               'url': url,
             },
       );
  String get apaCitation =>
      '${meta['author'] ?? 'Unknown author'}. (${meta['year']?.toString().isNotEmpty == true ? meta['year'] : 'n.d.'}). $title. ${meta['url'] ?? ''}'
          .trim();
}

class EvidenceBlock extends CreativeObject {
  EvidenceBlock({
    String? id,
    required String sourceId,
    required String quoteText,
    String claimStatement = '',
    String pageOrTimestamp = '',
    Map<String, dynamic>? meta,
    List<String>? links,
  }) : super(
         id: id,
         kind: 'evidence',
         title: claimStatement.isEmpty ? 'Captured evidence' : claimStatement,
         body: quoteText,
         links: links ?? [sourceId],
         meta:
             meta ??
             {
               'sourceId': sourceId,
               'locator': pageOrTimestamp,
               'claim': claimStatement,
               'capturedAt': DateTime.now().toIso8601String(),
             },
       );
  String get sourceId => meta['sourceId'] as String? ?? '';
  String get claimStatement => meta['claim'] as String? ?? title;
  String get quoteText => body;
  String get pageOrTimestamp => meta['locator'] as String? ?? '';
}

enum ReviewRating { again, hard, good, easy }

class Flashcard extends CreativeObject {
  Flashcard({
    String? id,
    String courseId = '',
    String? noteId,
    required String question,
    required String answer,
    DateTime? nextReviewDate,
    int repetitionCount = 0,
    double intervalDays = 0,
    double easeFactor = 2.5,
    Map<String, dynamic>? meta,
    List<String>? links,
  }) : super(
         id: id,
         kind: 'card',
         title: question,
         body: answer,
         links: links ?? [if (noteId != null) noteId],
         meta:
             meta ??
             {
               'course': courseId,
               'noteId': noteId,
               'due': (nextReviewDate ?? DateTime.now()).toIso8601String(),
               'repetitions': repetitionCount,
               'interval': intervalDays,
               'ease': easeFactor,
             },
       );
  String get question => title;
  String get answer => body;
  String get courseId => meta['course'] as String? ?? '';
  DateTime get nextReviewDate =>
      DateTime.tryParse(meta['due']?.toString() ?? '') ?? DateTime(2000);
  bool get isDue => !nextReviewDate.isAfter(DateTime.now());
  int get repetitionCount => (meta['repetitions'] as num?)?.toInt() ?? 0;
  double get intervalDays => (meta['interval'] as num?)?.toDouble() ?? 0;
  double get easeFactor => (meta['ease'] as num?)?.toDouble() ?? 2.5;
  String get masteryLevel => meta['mastery'] as String? ?? 'untested';
}

class ConceptNode extends CreativeObject {
  ConceptNode({
    String? id,
    String courseId = '',
    required String name,
    String body = '',
    double x = 40,
    double y = 40,
    Map<String, dynamic>? meta,
    List<String>? links,
  }) : super(
         id: id,
         kind: 'concept',
         title: name,
         body: body,
         links: links,
         meta: meta ?? {'course': courseId, 'x': x, 'y': y},
       );
  String get name => title;
  double get x => (meta['x'] as num?)?.toDouble() ?? 40;
  double get y => (meta['y'] as num?)?.toDouble() ?? 40;
}

class ConceptRelation extends CreativeObject {
  ConceptRelation({
    String? id,
    required String sourceConceptId,
    required String targetConceptId,
    String label = 'relates to',
    Map<String, dynamic>? meta,
    List<String>? links,
  }) : super(
         id: id,
         kind: 'relation',
         title: label,
         links: links ?? [sourceConceptId, targetConceptId],
         meta: meta ?? {},
       );
}

class StudentTask extends CreativeObject {
  StudentTask({
    String? id,
    String courseId = '',
    required String title,
    String priority = 'normal',
    Map<String, dynamic>? meta,
  }) : super(
         id: id,
         kind: 'task',
         title: title,
         meta:
             meta ??
             {
               'course': courseId,
               'priority': priority,
               'done': false,
               'due': DateTime.now()
                   .add(const Duration(days: 2))
                   .toIso8601String(),
             },
       );
  bool get isCompleted => meta['done'] == true;
}

class StudySession extends CreativeObject {
  StudySession({
    String? id,
    String courseId = '',
    required int durationMinutes,
    int cardsReviewed = 0,
    Map<String, dynamic>? meta,
  }) : super(
         id: id,
         kind: 'session',
         title: 'Study session',
         meta:
             meta ??
             {
               'course': courseId,
               'minutes': durationMinutes,
               'cards': cardsReviewed,
               'at': DateTime.now().toIso8601String(),
             },
       );
  int get durationMinutes => (meta['minutes'] as num?)?.toInt() ?? 0;
  int get cardsReviewed => (meta['cards'] as num?)?.toInt() ?? 0;
}

CreativeObject studentObject(CreativeObject o) {
  if (o.runtimeType != CreativeObject) return o;
  final meta = o.meta, links = o.links;
  return switch (o.kind) {
    'course' => Course(
      id: o.id,
      code: meta['code']?.toString() ?? '',
      title: o.title,
      meta: meta,
    ),
    'note' => StudentNote(
      id: o.id,
      title: o.title,
      body: o.body,
      meta: meta,
      links: links,
    ),
    'research' || 'source' => ResearchSource(
      id: o.id,
      title: o.title,
      body: o.body,
      meta: meta,
      links: links,
    ),
    'card' => Flashcard(
      id: o.id,
      question: o.title,
      answer: o.body,
      meta: meta,
      links: links,
    ),
    'concept' => ConceptNode(
      id: o.id,
      name: o.title,
      body: o.body,
      meta: meta,
      links: links,
    ),
    'task' => StudentTask(id: o.id, title: o.title, meta: meta),
    'evidence' => EvidenceBlock(
      id: o.id,
      sourceId: meta['sourceId']?.toString() ?? '',
      quoteText: o.body,
      claimStatement: o.title,
      meta: meta,
      links: links,
    ),
    'relation' => ConceptRelation(
      id: o.id,
      sourceConceptId: '',
      targetConceptId: '',
      label: o.title,
      meta: meta,
      links: links,
    ),
    'session' => StudySession(id: o.id, durationMinutes: 0, meta: meta),
    _ => o,
  };
}

class ZenboxStore extends StudioStore {
  Database? _database;
  bool _ready = false;
  bool _restoring = false;
  final List<String> _undo = [];
  final List<String> _redo = [];
  String? activeCourseId;
  String? storageWarning;
  @override
  File get file => File('${directory.path}/zenbox.json');
  List<Course> get courses => project.objects.whereType<Course>().toList();
  List<StudentNote> get notes =>
      project.objects.whereType<StudentNote>().toList();
  List<ResearchSource> get sources =>
      project.objects.whereType<ResearchSource>().toList();
  List<EvidenceBlock> get evidence =>
      project.objects.whereType<EvidenceBlock>().toList();
  List<ConceptNode> get concepts =>
      project.objects.whereType<ConceptNode>().toList();
  List<ConceptRelation> get relations =>
      project.objects.whereType<ConceptRelation>().toList();
  List<StudentTask> get tasks =>
      project.objects.whereType<StudentTask>().toList();
  List<Flashcard> get flashcards =>
      project.objects.whereType<Flashcard>().toList();
  List<StudySession> get sessions =>
      project.objects.whereType<StudySession>().toList();
  List<Flashcard> get dueCards => flashcards.where((c) => c.isDue).toList();
  List<CreativeObject> get assets =>
      project.objects.where((o) => o.meta['file'] != null).toList();
  List<CreativeObject> get tray =>
      project.objects.where((o) => o.meta['tray'] == true).toList();
  List<CreativeObject> get aiContext => project.objects
      .where((o) => o.meta['aiContext'] == true && o.meta['private'] != true)
      .toList();
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  Course? getCourse(String? id) => courses.where((o) => o.id == id).firstOrNull;

  @override
  Future<void> load({Directory? customDir}) async {
    directory =
        customDir ??
        Directory('${(await getApplicationSupportDirectory()).path}/Zenbox');
    await directory.create(recursive: true);
    await Directory('${directory.path}/media').create(recursive: true);
    try {
      _database = sqlite3.open('${directory.path}/knowledge.sqlite');
      _database!.execute('PRAGMA journal_mode=WAL');
      _database!.execute(
        'CREATE TABLE IF NOT EXISTS workspace (id INTEGER PRIMARY KEY, data TEXT NOT NULL)',
      );
      _database!.execute(
        'CREATE VIRTUAL TABLE IF NOT EXISTS knowledge_search USING fts5(id UNINDEXED, title, body, metadata)',
      );
    } catch (e) {
      storageWarning = 'Search index unavailable: $e';
    }
    String? saved;
    // JSON remains the readable recovery snapshot and is written before the index.
    if (file.existsSync()) saved = await file.readAsString();
    if (saved == null) {
      final legacy = File('${directory.path}/studio.json');
      if (legacy.existsSync()) saved = await legacy.readAsString();
    }
    if (saved == null && customDir == null) {
      final supportParent = directory.parent.parent;
      final candidates = [
        File('${supportParent.path}/Xandora Studio/Zenbox/zenbox.json'),
        File('${supportParent.path}/zenbox/Zenbox/zenbox.json'),
        File('${supportParent.path}/Xandora Studio/Zenbox/studio.json'),
        File('${supportParent.path}/zenbox/Zenbox/studio.json'),
      ];
      for (final candidate in candidates) {
        if (candidate.existsSync()) {
          try {
            final content = await candidate.readAsString();
            if (content.trim().isNotEmpty) {
              saved = content;
              break;
            }
          } catch (_) {}
        }
      }
    }
    if (saved == null && _database != null) {
      final rows = _database!.select('SELECT data FROM workspace WHERE id=1');
      if (rows.isNotEmpty) saved = rows.first['data'] as String;
    }
    if (saved != null) {
      try {
        _decodeStudent(saved);
      } catch (_) {
        File? backup = File('${file.path}.bak');
        if (!backup.existsSync()) {
          backup = File('${directory.path}/studio.json.bak');
        }
        if (!backup.existsSync()) rethrow;
        final damaged = File('${file.path}.damaged-${newId()}');
        if (file.existsSync()) await file.copy(damaged.path);
        _decodeStudent(await backup.readAsString());
        storageWarning =
            'Recovered the previous save. The damaged snapshot was preserved.';
      }
    }
    if (projects.isEmpty) {
      projects = [studentWorkspace()];
      currentId = projects.first.id;
    }
    settings.putIfAbsent('endpoint', () => 'http://127.0.0.1:11434/v1');
    settings.putIfAbsent('aiToolsEnabled', () => true);
    settings['studentWorkspace'] = true;
    _normalize();
    activeCourseId = project.layout['courseId'] as String?;
    _ready = true;
    save();
  }

  void _decodeStudent(String text) {
    final data = jsonDecode(text) as Map<String, dynamic>;
    final isV1Schema = data['schema'] == 'zenbox-student-v1' ||
        (!data.containsKey('projects') &&
            (data.containsKey('courses') || data.containsKey('notes')));

    if (isV1Schema) {
      final objects = <CreativeObject>[];

      for (final raw in (data['courses'] as List? ?? [])) {
        if (raw is! Map) continue;
        final c = Map<String, dynamic>.from(raw);
        final id = c['id']?.toString();
        final code = c['code']?.toString() ?? '';
        final title = c['title']?.toString() ?? '';
        final instructor = c['instructor']?.toString() ?? '';
        final targetGrade = c['targetGrade']?.toString() ?? '';
        objects.add(
          Course(
            id: id,
            code: code,
            title: title,
            instructor: instructor,
            targetGrade: targetGrade,
            meta: {
              ...c,
              'code': code,
              'instructor': instructor,
              'targetGrade': targetGrade,
            },
          ),
        );
      }

      for (final raw in (data['notes'] as List? ?? [])) {
        if (raw is! Map) continue;
        final n = Map<String, dynamic>.from(raw);
        final id = n['id']?.toString();
        final courseId = n['courseId']?.toString() ?? '';
        final title = n['title']?.toString() ?? '';
        final body = n['body']?.toString() ?? '';
        final tags = (n['tags'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
        final linkedConcepts = (n['linkedConceptIds'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
        final linkedSources = (n['linkedSourceIds'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
        final links = <String>{...linkedConcepts, ...linkedSources}.toList();
        final meta = <String, dynamic>{
          'course': courseId,
          'tags': tags,
          'pinned': n['isPinned'] == true,
          if (n['deltaJson'] != null) 'delta': n['deltaJson'],
          if (n['createdAt'] != null) 'createdAt': n['createdAt'],
          if (n['updatedAt'] != null) 'updatedAt': n['updatedAt'],
        };
        objects.add(
          StudentNote(
            id: id,
            courseId: courseId,
            title: title,
            body: body,
            tags: tags,
            links: links,
            meta: meta,
          ),
        );
      }

      for (final raw in (data['sources'] as List? ?? [])) {
        if (raw is! Map) continue;
        final s = Map<String, dynamic>.from(raw);
        final id = s['id']?.toString();
        final title = s['title']?.toString() ?? '';
        final author = s['author']?.toString() ?? '';
        final url = s['url']?.toString() ?? '';
        final year = s['publicationYear']?.toString() ?? '';
        final sourceKind = s['sourceKind']?.toString() ?? 'article';
        final body = (s['notes'] ?? s['body'])?.toString() ?? '';
        final courseId = s['courseId']?.toString() ?? '';
        objects.add(
          ResearchSource(
            id: id,
            title: title,
            courseId: courseId,
            author: author,
            publicationYear: year,
            sourceKind: sourceKind,
            url: url,
            body: body,
            meta: {
              ...s,
              'course': courseId,
              'author': author,
              'url': url,
              'year': year,
              'sourceKind': sourceKind,
            },
          ),
        );
      }

      for (final raw in (data['evidence'] as List? ?? [])) {
        if (raw is! Map) continue;
        final e = Map<String, dynamic>.from(raw);
        final id = e['id']?.toString();
        final sourceId = e['sourceId']?.toString() ?? '';
        final quoteText = (e['quoteText'] ?? e['body'])?.toString() ?? '';
        final claimStatement = (e['claimStatement'] ?? e['title'])?.toString() ?? '';
        final pageOrTimestamp = (e['pageOrTimestamp'] ?? e['locator'])?.toString() ?? '';
        objects.add(
          EvidenceBlock(
            id: id,
            sourceId: sourceId,
            quoteText: quoteText,
            claimStatement: claimStatement,
            pageOrTimestamp: pageOrTimestamp,
            links: [if (sourceId.isNotEmpty) sourceId],
            meta: {
              ...e,
              'sourceId': sourceId,
              'locator': pageOrTimestamp,
              'claim': claimStatement,
              'annotation': e['annotation']?.toString() ?? '',
            },
          ),
        );
      }

      for (final raw in (data['flashcards'] as List? ?? [])) {
        if (raw is! Map) continue;
        final f = Map<String, dynamic>.from(raw);
        final id = f['id']?.toString();
        final courseId = f['courseId']?.toString() ?? '';
        final noteId = f['noteId']?.toString();
        final conceptId = f['conceptId']?.toString();
        final question = (f['question'] ?? f['title'])?.toString() ?? '';
        final answer = (f['answer'] ?? f['body'])?.toString() ?? '';
        final intervalDays = (f['intervalDays'] ?? f['interval'] as num?)?.toDouble() ?? 0.0;
        final repetitionCount = (f['repetitionCount'] ?? f['repetitions'] as num?)?.toInt() ?? 0;
        final easeFactor = (f['easeFactor'] ?? f['ease'] as num?)?.toDouble() ?? 2.5;
        final due = f['nextReviewDate']?.toString() ?? f['due']?.toString();
        final links = <String>[
          if (noteId != null && noteId.isNotEmpty) noteId,
          if (conceptId != null && conceptId.isNotEmpty) conceptId,
        ];
        objects.add(
          Flashcard(
            id: id,
            courseId: courseId,
            noteId: noteId,
            question: question,
            answer: answer,
            intervalDays: intervalDays,
            repetitionCount: repetitionCount,
            easeFactor: easeFactor,
            links: links,
            meta: {
              ...f,
              'course': courseId,
              'noteId': noteId,
              'conceptId': conceptId,
              'due': due ?? DateTime.now().toIso8601String(),
              'repetitions': repetitionCount,
              'interval': intervalDays,
              'ease': easeFactor,
              'mastery': f['masteryLevel']?.toString() ?? 'learning',
              'lastReviewed': f['lastReviewedDate']?.toString(),
            },
          ),
        );
      }

      for (final raw in (data['concepts'] as List? ?? [])) {
        if (raw is! Map) continue;
        final c = Map<String, dynamic>.from(raw);
        final id = c['id']?.toString();
        final courseId = c['courseId']?.toString() ?? '';
        final name = (c['name'] ?? c['title'])?.toString() ?? '';
        final body = (c['summary'] ?? c['body'])?.toString() ?? '';
        final x = (c['x'] as num?)?.toDouble() ?? 40.0;
        final y = (c['y'] as num?)?.toDouble() ?? 40.0;
        objects.add(
          ConceptNode(
            id: id,
            courseId: courseId,
            name: name,
            body: body,
            x: x,
            y: y,
            meta: {
              ...c,
              'course': courseId,
              'x': x,
              'y': y,
              'mastery': c['masteryLevel']?.toString() ?? 'learning',
              if (c['colorHex'] != null) 'colorHex': c['colorHex'],
            },
          ),
        );
      }

      for (final raw in (data['relations'] as List? ?? [])) {
        if (raw is! Map) continue;
        final r = Map<String, dynamic>.from(raw);
        final id = r['id']?.toString();
        final sourceId = r['sourceConceptId']?.toString() ?? '';
        final targetId = r['targetConceptId']?.toString() ?? '';
        final label = (r['label'] ?? r['title'])?.toString() ?? 'relates to';
        objects.add(
          ConceptRelation(
            id: id,
            sourceConceptId: sourceId,
            targetConceptId: targetId,
            label: label,
            links: [
              if (sourceId.isNotEmpty) sourceId,
              if (targetId.isNotEmpty) targetId,
            ],
            meta: r,
          ),
        );
      }

      for (final raw in (data['tasks'] as List? ?? [])) {
        if (raw is! Map) continue;
        final t = Map<String, dynamic>.from(raw);
        final id = t['id']?.toString();
        final courseId = t['courseId']?.toString() ?? '';
        final title = t['title']?.toString() ?? '';
        final priority = t['priority']?.toString() ?? 'normal';
        final isDone = t['isCompleted'] == true || t['done'] == true;
        final due = t['dueDate']?.toString() ?? t['due']?.toString();
        objects.add(
          StudentTask(
            id: id,
            courseId: courseId,
            title: title,
            priority: priority,
            meta: {
              ...t,
              'course': courseId,
              'priority': priority,
              'done': isDone,
              ?'due': due,
              if (t['notes'] != null) 'notes': t['notes'],
            },
          ),
        );
      }

      for (final raw in (data['sessions'] as List? ?? [])) {
        if (raw is! Map) continue;
        final s = Map<String, dynamic>.from(raw);
        final id = s['id']?.toString();
        final courseId = s['courseId']?.toString() ?? '';
        final durationMinutes = (s['durationMinutes'] ?? s['minutes'] as num?)?.toInt() ?? 0;
        final cardsReviewed = (s['cardsReviewed'] ?? s['cards'] as num?)?.toInt() ?? 0;
        objects.add(
          StudySession(
            id: id,
            courseId: courseId,
            durationMinutes: durationMinutes,
            cardsReviewed: cardsReviewed,
            meta: s,
          ),
        );
      }

      final actCourse = data['activeCourseId'] as String?;
      final newProj = Project(
        id: newId(),
        title: 'My learning space',
        description: 'Notes, research, and ideas that grow together.',
        objects: objects,
        layout: {
          'mode': 'Overview',
          ?'courseId': actCourse,
        },
      );
      projects = [newProj];
      currentId = newProj.id;
      activeCourseId = actCourse;
      settings = Map<String, dynamic>.from(data['settings'] as Map? ?? {});
    } else {
      final rawProjects = data['projects'];
      if (rawProjects is List) {
        projects = rawProjects
            .whereType<Map>()
            .map((e) => Project.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } else {
        projects = [];
      }
      currentId = data['currentId'] as String? ?? (projects.isNotEmpty ? projects.first.id : '');
      settings = Map<String, dynamic>.from(data['settings'] as Map? ?? {});
    }
  }

  void _normalize() {
    for (final p in projects) {
      for (var i = 0; i < p.objects.length; i++) {
        p.objects[i] = studentObject(p.objects[i]);
      }
    }
  }

  @override
  void changed() {
    _normalize();
    super.changed();
  }

  @override
  void save() {
    if (!_ready) return;
    super.save();
    if (error != null || _database == null) return;
    try {
      _database!.execute('BEGIN IMMEDIATE');
      _database!.execute(
        'INSERT OR REPLACE INTO workspace(id,data) VALUES(1,?)',
        [file.readAsStringSync()],
      );
      _database!.execute('DELETE FROM knowledge_search');
      final statement = _database!.prepare(
        'INSERT INTO knowledge_search(id,title,body,metadata) VALUES(?,?,?,?)',
      );
      try {
        for (final p in projects) {
          for (final o in p.objects) {
            if (o.kind != 'generation')
              statement.execute([o.id, o.title, o.body, jsonEncode(o.meta)]);
          }
        }
      } finally {
        statement.dispose();
      }
      _database!.execute('COMMIT');
    } catch (e) {
      try {
        _database!.execute('ROLLBACK');
      } catch (_) {}
      storageWarning = 'Search index needs rebuilding: $e';
    }
  }

  void checkpoint() {
    if (_restoring) return;
    _undo.add(jsonEncode(project.toJson()));
    if (_undo.length > 40) _undo.removeAt(0);
    _redo.clear();
  }

  void undo() => _restore(_undo, _redo);
  void redo() => _restore(_redo, _undo);
  void _restore(List<String> from, List<String> to) {
    if (from.isEmpty) return;
    _restoring = true;
    to.add(jsonEncode(project.toJson()));
    final index = projects.indexOf(project);
    projects[index] = Project.fromJson(
      jsonDecode(from.removeLast()) as Map<String, dynamic>,
    );
    _restoring = false;
    changed();
  }

  @override
  void add(CreativeObject o) {
    checkpoint();
    project.objects.insert(0, studentObject(o));
    changed();
  }

  @override
  void remove(CreativeObject o) {
    checkpoint();
    super.remove(o);
  }

  void addCourse(Course o) => add(o);
  void updateCourse(Course o) => changed();
  void selectCourse(String? id) {
    activeCourseId = id;
    project.layout['courseId'] = id;
    changed();
  }

  void deleteCourse(String id) {
    checkpoint();
    final ids = project.objects
        .where((o) => o.id == id || o.meta['course'] == id)
        .map((o) => o.id)
        .toSet();
    project.objects.removeWhere((o) => ids.contains(o.id));
    for (final o in project.objects) {
      o.links.removeWhere(ids.contains);
    }
    if (activeCourseId == id) activeCourseId = null;
    changed();
  }

  void addNote(StudentNote o) => add(o);
  void updateNote(StudentNote o) => changed();
  void togglePinNote(String id) {
    final o = project.object(id);
    if (o != null) {
      o.meta['pinned'] = o.meta['pinned'] != true;
      changed();
    }
  }

  void deleteNote(String id) {
    checkpoint();
    project.objects.removeWhere(
      (o) =>
          o.id == id ||
          o.kind == 'card' && (o.meta['noteId'] == id || o.links.contains(id)),
    );
    for (final o in project.objects) {
      o.links.remove(id);
    }
    changed();
  }

  void addSource(ResearchSource o) => add(o);
  void deleteSource(String id) {
    checkpoint();
    project.objects.removeWhere(
      (o) => o.id == id || o.kind == 'evidence' && o.meta['sourceId'] == id,
    );
    for (final o in project.objects) {
      o.links.remove(id);
    }
    changed();
  }

  void addEvidence(EvidenceBlock o) => add(o);
  void addFlashcard(Flashcard o) => add(o);
  void addConcept(ConceptNode o) => add(o);
  void updateConceptPosition(String id, double x, double y) {
    final o = project.object(id);
    o?.meta.addAll({'x': x, 'y': y});
    changed();
  }

  void addRelation(ConceptRelation o) => add(o);
  void deleteRelation(String id) {
    final o = project.object(id);
    if (o != null) remove(o);
  }

  void addTask(StudentTask o) => add(o);
  void toggleTask(String id) {
    final o = project.object(id);
    if (o != null) {
      o.meta['done'] = o.meta['done'] != true;
      changed();
    }
  }

  void deleteTask(String id) {
    final o = project.object(id);
    if (o != null) remove(o);
  }

  void logStudySession(StudySession o) => add(o);
  void setTray(CreativeObject o, bool pinned) {
    checkpoint();
    o.meta['tray'] = pinned;
    changed();
  }

  void setContext(CreativeObject o, bool included) {
    o.meta['aiContext'] = included;
    changed();
  }

  void reviewCard(Flashcard card, ReviewRating rating) {
    checkpoint();
    final interval = card.intervalDays, ease = card.easeFactor;
    final newEase = math.max(
      1.3,
      ease +
          switch (rating) {
            ReviewRating.again => -.2,
            ReviewRating.hard => -.15,
            ReviewRating.good => 0,
            ReviewRating.easy => .15,
          },
    );
    final days = switch (rating) {
      ReviewRating.again => 1.0,
      ReviewRating.hard => math.max(1.0, interval * 1.2),
      ReviewRating.good =>
        card.repetitionCount == 0
            ? 1.0
            : card.repetitionCount == 1
            ? 6.0
            : interval * ease,
      ReviewRating.easy => math.max(4.0, interval * newEase * 1.3),
    };
    card.meta.addAll({
      'ease': newEase,
      'interval': days,
      'repetitions': rating == ReviewRating.again
          ? 0
          : card.repetitionCount + 1,
      'due': DateTime.now()
          .add(Duration(minutes: (days * 1440).round()))
          .toIso8601String(),
      'mastery': switch (rating) {
        ReviewRating.again => 'learning',
        ReviewRating.hard => 'fragile',
        ReviewRating.good => 'familiar',
        ReviewRating.easy => 'mastered',
      },
    });
    final history = List<dynamic>.from(card.meta['reviews'] ?? []);
    history.add({
      'at': DateTime.now().toIso8601String(),
      'rating': rating.name,
    });
    card.meta['reviews'] = history;
    changed();
  }

  List<CreativeObject> search(String query, {String? courseId, String? kind}) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty);
    final matches = project.objects
        .where(
          (o) =>
              (courseId == null || o.meta['course'] == courseId) &&
              (kind == null || o.kind == kind) &&
              words.every(
                (w) => '${o.title} ${o.body} ${jsonEncode(o.meta)}'
                    .toLowerCase()
                    .contains(w),
              ),
        )
        .toList();
    // Rank persisted matches with FTS5; include current unsaved edits above.
    if (_database != null && words.isNotEmpty) {
      try {
        final expression = words.map((w) => '"${w.replaceAll('"', '""')}"*').join(' AND ');
        final rows = _database!.select('SELECT id FROM knowledge_search WHERE knowledge_search MATCH ? ORDER BY rank', [expression]);
        final rank = <String,int>{for(var i=0;i<rows.length;i++)rows[i]['id'] as String:i};
        matches.sort((a,b)=>(rank[a.id] ?? -1).compareTo(rank[b.id] ?? -1));
      } catch (_) { /* Literal substring search still covers an unavailable index. */ }
    }
    return matches;
  }

  Future<CreativeObject> importAsset(
    String path,
    String name, {
    String? courseId,
    bool toTray = false,
  }) async {
    final hash = (await sha256.bind(File(path).openRead()).first).toString();
    final duplicate = assets.where((o) => o.meta['hash'] == hash).firstOrNull;
    if (duplicate != null) {
      if (toTray) setTray(duplicate, true);
      return duplicate;
    }
    final o = await importMedia(path, name);
    o.meta.addAll({
      'hash': hash,
      'course': courseId ?? activeCourseId,
      'tray': toTray,
      'importedAt': DateTime.now().toIso8601String(),
    });
    add(o);
    return o;
  }

  @override
  void dispose() {
    if (_ready) save();
    _database?.dispose();
    super.dispose();
  }
}

Project studentWorkspace() {
  final cs = Course(
    id: 'cs101',
    code: 'CS 101',
    title: 'Data Structures',
    instructor: 'Dr. Ellis',
  );
  final cog = Course(
    id: 'cog220',
    code: 'COG 220',
    title: 'Cognitive Psychology',
    instructor: 'Dr. Morgan',
  );
  final hist = Course(
    id: 'hist110',
    code: 'HIST 110',
    title: 'History & Evidence',
    instructor: 'Dr. Patel',
  );
  final note = StudentNote(
    id: 'note-avl',
    courseId: cs.id,
    title: 'AVL trees & balanced search',
    body:
        'AVL trees\n\nAn AVL tree is a binary search tree whose left and right subtree heights differ by at most one at every node.\n\nRotations restore balance after insertion or deletion. Because the tree height is logarithmic, search remains efficient.\n\nActive recall\nExplain when a single rotation is enough and when a double rotation is needed.\n',
    meta: {'course': cs.id, 'pinned': true, 'tray': true},
  );
  final memory = StudentNote(
    id: 'note-memory',
    courseId: cog.id,
    title: 'Retrieval, spacing, and understanding',
    body:
        'Retrieval practice\n\nTry to recall an idea before reopening the notes. Compare your explanation with the source and revise what you missed.\n\nSpacing\nReturn to the material after a delay. Plan several short sessions over time.\n',
  );
  return Project(
    title: 'My learning space',
    description: 'Notes, research, and ideas that grow together.',
    objects: [
      cs,
      cog,
      hist,
      note,
      memory,
      ResearchSource(
        id: 'source-memory',
        courseId: cog.id,
        title: 'Retrieval practice and learning',
        author: 'Karpicke, J. D., & Roediger, H. L.',
        publicationYear: '2008',
        url: 'https://doi.org/10.1126/science.1152408',
        body:
            'A source record for your reading. Import the paper, select a passage, and capture your evidence with its page reference.',
      ),
      ResearchSource(
        id: 'source-method',
        courseId: hist.id,
        title: 'Reading primary sources',
        sourceKind: 'reading',
        body:
            'Separate an author’s claims from the evidence. Record context, date, authorship, and competing interpretations.',
      ),
      ConceptNode(
        id: 'concept-avl',
        courseId: cs.id,
        name: 'AVL balancing',
        body: 'Rebalance search trees using rotations.',
        x: 60,
        y: 60,
        links: [note.id],
      ),
      ConceptNode(
        id: 'concept-recall',
        courseId: cog.id,
        name: 'Active recall',
        body: 'Retrieve before rereading.',
        x: 430,
        y: 80,
        links: [memory.id],
      ),
      ConceptNode(
        id: 'concept-evidence',
        courseId: hist.id,
        name: 'Evidence & interpretation',
        body: 'Every claim needs a traceable source.',
        x: 240,
        y: 330,
      ),
      Flashcard(
        courseId: cs.id,
        noteId: note.id,
        question: 'What is the AVL balance invariant?',
        answer:
            'At every node, the left and right subtree heights differ by at most one.',
      ),
      Flashcard(
        courseId: cog.id,
        noteId: memory.id,
        question: 'How do retrieval practice and rereading differ?',
        answer:
            'Retrieval asks you to produce an answer from memory; rereading presents the answer again.',
      ),
      Flashcard(
        courseId: hist.id,
        question: 'What context should you record for a primary source?',
        answer: 'Authorship, date, audience, purpose, and historical setting.',
      ),
      StudentTask(courseId: cs.id, title: 'Practice AVL rotations'),
      StudentTask(
        courseId: cog.id,
        title: 'Read and annotate the retrieval paper',
      ),
      StudentTask(
        courseId: hist.id,
        title: 'Outline the source analysis essay',
      ),
    ],
    layout: {'mode': 'Home', 'deck': 'AI', 'showTray': true},
  );
}
