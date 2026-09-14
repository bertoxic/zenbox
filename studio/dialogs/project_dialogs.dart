// ignore_for_file: invalid_use_of_protected_member
part of '../../studio.dart';

extension _StudioProjectDialogs on _StudioState {
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

  Future<bool> _showConfirmDeleteDialog(Project p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${p.title}”?'),
        content: Text(
          'This will permanently delete “${p.title}” and all ${p.objects.length} item(s) inside it. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFA54141),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete workspace'),
          ),
        ],
      ),
    );
    if (confirm != true) return false;
    final title = p.title;
    final wasCurrent = p.id == project.id;
    sequenceTimer?.cancel();
    final ok = store.deleteProject(p.id);
    if (ok) {
      if (wasCurrent) {
        restoreLayout();
        setState(() {
          selectedId = null;
          activeDocument = null;
          expandedScratchpadId = null;
          activePlayingQuiz = null;
          mode = 'Overview';
        });
      } else {
        setState(() {});
      }
      toast('Deleted workspace “$title”');
    }
    return ok;
  }

  Future<void> deleteProjectDialog([Project? target]) async {
    final p = target ?? project;
    if (store.projects.length <= 1) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cannot delete workspace'),
          content: const Text(
            'You cannot delete the only workspace. Create another workspace first before deleting this one.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    await _showConfirmDeleteDialog(p);
  }

  Future<void> manageProjectsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.folder_copy_outlined, size: 20, color: sage),
                const SizedBox(width: 10),
                const Text('Manage study workspaces'),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Switch between courses, create new workspaces, or delete workspaces you no longer need.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 340),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: store.projects.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final p = store.projects[index];
                        final isCurrent = p.id == store.project.id;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          leading: Icon(
                            isCurrent ? Icons.folder_open : Icons.folder,
                            color: isCurrent ? sage : muted,
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  p.title,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: isCurrent
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              if (isCurrent) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: sage.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Active',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: sage,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            '${p.objects.length} item(s) · ${p.description.isNotEmpty ? p.description : "No description"}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isCurrent)
                                TextButton(
                                  onPressed: () {
                                    sequenceTimer?.cancel();
                                    store.select(p);
                                    restoreLayout();
                                    Navigator.pop(ctx);
                                    setState(() {});
                                  },
                                  child: const Text('Open'),
                                ),
                              IconButton(
                                tooltip: store.projects.length > 1
                                    ? 'Delete workspace'
                                    : 'Cannot delete the only workspace',
                                icon: Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: store.projects.length > 1
                                      ? const Color(0xFFA54141)
                                      : muted.withValues(alpha: 0.4),
                                ),
                                onPressed: store.projects.length > 1
                                    ? () async {
                                        final deleted =
                                            await _showConfirmDeleteDialog(p);
                                        if (deleted) {
                                          setDialogState(() {});
                                          setState(() {});
                                        }
                                      }
                                    : null,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await createProject();
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New workspace'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

}
