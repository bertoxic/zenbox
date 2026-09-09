import 'package:flutter/material.dart';
import '../../zenbox_model.dart';
import '../../zenbox_theme.dart';

class TasksView extends StatelessWidget {
  const TasksView({super.key, required this.store});
  final ZenboxStore store;
  Future<void> _add(BuildContext context) async {
    final title = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New assignment'),
        content: TextField(
          controller: title,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'What needs to be done?',
          ),
          onSubmitted: (s) => Navigator.pop(context, s),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, title.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (value != null && value.trim().isNotEmpty)
      store.addTask(
        StudentTask(courseId: store.activeCourseId ?? '', title: value.trim()),
      );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(28),
      children: [
        zenHeading(
          'Assignments & Academic Tasks',
          'Turn big deadlines into manageable next steps.',
          action: IconButton(
            tooltip: 'Add assignment',
            onPressed: () => _add(context),
            icon: const Icon(Icons.add),
          ),
        ),
        ...store.tasks
            .where(
              (t) =>
                  store.activeCourseId == null ||
                  t.meta['course'] == store.activeCourseId,
            )
            .map(
              (t) => Card(
                child: ListTile(
                  leading: Checkbox(
                    value: t.isCompleted,
                    onChanged: (_) => store.toggleTask(t.id),
                  ),
                  title: Text(
                    t.title,
                    style: TextStyle(
                      decoration: t.isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  subtitle: Text(
                    '${store.getCourse(t.meta['course'])?.code ?? 'Personal'} · ${t.meta['priority']} · Due ${(t.meta['due'] as String? ?? '').split('T').first}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'date') {
                        final date = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          initialDate:
                              DateTime.tryParse(t.meta['due'] ?? '') ??
                              DateTime.now(),
                        );
                        if (date != null) {
                          t.meta['due'] = date.toIso8601String();
                          store.changed();
                        }
                      } else if (v == 'delete') {
                        store.deleteTask(t.id);
                      } else {
                        t.meta['priority'] = v;
                        store.changed();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'date', child: Text('Set deadline')),
                      PopupMenuItem(
                        value: 'high',
                        child: Text('High priority'),
                      ),
                      PopupMenuItem(
                        value: 'normal',
                        child: Text('Normal priority'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete assignment'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        if (store.tasks.isEmpty)
          const Text('Add an assignment to plan your next step.'),
      ],
    ),
  );
}
