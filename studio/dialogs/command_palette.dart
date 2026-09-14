part of '../../studio.dart';

class _CommandPalette extends StatefulWidget {
  const _CommandPalette({
    required this.project,
    required this.onMode,
    required this.onObject,
    required this.onCapture,
    required this.onNew,
    this.onManage,
    this.onDelete,
  });
  final Project project;
  final void Function(String) onMode;
  final void Function(CreativeObject) onObject;
  final VoidCallback onCapture, onNew;
  final VoidCallback? onManage, onDelete;
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
                    if (widget.onManage != null)
                      ListTile(
                        leading: const Icon(Icons.tune),
                        title: const Text('Manage courses / workspaces'),
                        onTap: () => act(widget.onManage!),
                      ),
                    if (widget.onDelete != null)
                      ListTile(
                        leading: const Icon(
                          Icons.delete_outline,
                          color: Color(0xFFA54141),
                        ),
                        title: const Text(
                          'Delete current course…',
                          style: TextStyle(color: Color(0xFFA54141)),
                        ),
                        onTap: () => act(widget.onDelete!),
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
                  if (query.isNotEmpty) ...[
                    if ('manage courses workspaces'.contains(query) &&
                        widget.onManage != null)
                      ListTile(
                        leading: const Icon(Icons.tune),
                        title: const Text('Manage courses / workspaces'),
                        onTap: () => act(widget.onManage!),
                      ),
                    if ('delete current course workspace'.contains(query) &&
                        widget.onDelete != null)
                      ListTile(
                        leading: const Icon(
                          Icons.delete_outline,
                          color: Color(0xFFA54141),
                        ),
                        title: const Text(
                          'Delete current course…',
                          style: TextStyle(color: Color(0xFFA54141)),
                        ),
                        onTap: () => act(widget.onDelete!),
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
