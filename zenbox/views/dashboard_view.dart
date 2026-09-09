import 'package:flutter/material.dart';
import '../../zenbox_model.dart';
import '../../zenbox_theme.dart';

class DashboardView extends StatelessWidget {
  const DashboardView({
    super.key,
    required this.store,
    required this.onNavigate,
  });
  final ZenboxStore store;
  final void Function(String mode, {String? courseId, String? noteId})
  onNavigate;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(28),
      children: [
        zenHeading(
          'Student Knowledge Hub',
          'A quiet place for ambitious ideas. Keep your learning connected.',
        ),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: forest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MAKE ROOM FOR UNDERSTANDING',
                style: TextStyle(color: olive, letterSpacing: 2, fontSize: 10),
              ),
              const SizedBox(height: 14),
              Text(
                '${store.dueCards.length} ideas ready to revisit',
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Georgia',
                  fontSize: 27,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Recall first. Reopen your notes second. A little practice goes a long way.',
                style: TextStyle(color: Colors.white70, height: 1.5),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => onNavigate('Review'),
                icon: const Icon(Icons.school_outlined),
                label: const Text('Begin a study session'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _stat('${store.notes.length}', 'Connected notes'),
            _stat(
              '${store.sources.length + store.assets.length}',
              'Research & assets',
            ),
            _stat(
              '${store.tasks.where((t) => !t.isCompleted).length}',
              'Open assignments',
            ),
            _stat(
              '${store.sessions.fold<int>(0, (s, e) => s + e.durationMinutes)} min',
              'Focused learning',
            ),
          ],
        ),
        const SizedBox(height: 28),
        const Text(
          'Enrolled Courses',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 14),
        ...store.courses.map(
          (c) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 9,
                ),
                leading: CircleAvatar(
                  backgroundColor: olive.withValues(alpha: .2),
                  child: const Icon(Icons.auto_stories_outlined, color: moss),
                ),
                title: Text(
                  c.code,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text('${c.title}\n${c.instructor}'),
                isThreeLine: true,
                trailing: const Icon(Icons.north_east, size: 18),
                onTap: () => onNavigate('Notes', courseId: c.id),
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Pick up where you left off',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
        ),
        ...store.notes
            .take(5)
            .map(
              (n) => ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(n.title),
                subtitle: Text(store.getCourse(n.courseId)?.code ?? 'Personal'),
                onTap: () => onNavigate('Notes', noteId: n.id),
              ),
            ),
      ],
    ),
  );
  Widget _stat(String value, String label) => SizedBox(
    width: 165,
    child: zenPanel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: secondaryInk, fontSize: 11),
          ),
        ],
      ),
    ),
  );
}
