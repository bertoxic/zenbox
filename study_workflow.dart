import 'dart:convert';
import 'model.dart';

// Keep persisted mode and object identifiers compatible with existing workspaces.
String studyModeLabel(String mode) => switch (mode) {
  'Overview' => 'Study home',
  'Study Guide / Summary Doc' => 'Study guides',
  'Concept Bank / Glossary' => 'Concepts & glossary',
  'Mind Map / Concept Board' => 'Concept map',
  'Media library' => 'Learning resources',
  'Storyboard' => 'Lesson planner',
  'Video' => 'Lesson rehearsal',
  'Scratchpad' => 'Quick notes',
  _ => mode,
};

String studyKindLabel(String kind) => switch (kind) {
  'script' => 'Topic note',
  'manuscript' => 'Study guide',
  'character' => 'Key concept',
  'location' => 'Context',
  'lore' => 'Background knowledge',
  'shot' => 'Lesson segment',
  'board' => 'Concept map',
  'asset' => 'Learning resource',
  'note' => 'Quick note',
  'card' => 'Flashcard',
  _ => kind,
};

List<CreativeObject> relatedStudyTools(
  Project project,
  CreativeObject source,
) => project.objects
    .where(
      (item) =>
          ['card', 'quiz'].contains(item.kind) &&
          (item.links.contains(source.id) ||
              source.links.contains(item.id) ||
              item.meta['sourceObjectId'] == source.id),
    )
    .toList();

void recordStudyCheckpoint(
  StudioStore store,
  CreativeObject source,
  String confidence,
) {
  store.snapshot(source);
  final checkpoints = List<dynamic>.from(source.meta['studyCheckpoints'] ?? []);
  checkpoints.insert(0, {
    'at': DateTime.now().toIso8601String(),
    'confidence': confidence,
  });
  source.meta['studyCheckpoints'] = checkpoints;
  source.meta['studyConfidence'] = confidence;
  store.changed();
}

void restoreStudySnapshot(StudioStore store, CreativeObject source, Map snapshot) {
  store.snapshot(source);
  source.body = snapshot['body'] as String;
  source.title = snapshot['title'] as String;
  if (snapshot['delta'] != null) {
    source.meta['delta'] = jsonDecode(jsonEncode(snapshot['delta']));
  } else {
    source.meta.remove('delta');
  }
  store.changed();
}
