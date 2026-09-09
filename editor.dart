import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'model.dart';
export 'rich_editor.dart';

Future<String?> askText(
  BuildContext context,
  String title, {
  String initial = '',
  String hint = 'Name',
  bool multiline = false,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 460,
        child: TextField(
          controller: controller,
          autofocus: true,
          minLines: multiline ? 5 : 1,
          maxLines: multiline ? 12 : 1,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: multiline
              ? null
              : (value) {
                  if (value.trim().isNotEmpty) {
                    Navigator.pop(context, value.trim());
                  }
                },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              Navigator.pop(context, controller.text.trim());
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  // The dialog's route finishes its reverse animation before its field is disposed.
  Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
  return result;
}

class ObjectForm extends StatefulWidget {
  const ObjectForm({super.key, required this.object, required this.onChanged});
  final CreativeObject object;
  final VoidCallback onChanged;
  @override
  State<ObjectForm> createState() => _ObjectFormState();
}

class _ObjectFormState extends State<ObjectForm> {
  late final title = TextEditingController(text: widget.object.title);
  late final body = TextEditingController(text: widget.object.body);
  @override
  void dispose() {
    title.dispose();
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      TextField(
        controller: title,
        decoration: const InputDecoration(labelText: 'Title'),
        onChanged: (v) {
          widget.object.title = v;
          widget.onChanged();
        },
      ),
      const SizedBox(height: 16),
      TextField(
        controller: body,
        minLines: 6,
        maxLines: 12,
        decoration: const InputDecoration(
          labelText: 'Notes & details',
          alignLabelWithHint: true,
        ),
        onChanged: (v) {
          widget.object.body = v;
          widget.onChanged();
        },
      ),
      if (widget.object.kind == 'research') ...[
        const SizedBox(height: 16),
        TextFormField(
          initialValue: widget.object.meta['url'] as String? ?? '',
          decoration: const InputDecoration(labelText: 'Source URL'),
          onChanged: (v) {
            widget.object.meta['url'] = v;
            widget.onChanged();
          },
        ),
      ],
      if (widget.object.kind == 'shot') ...[
        const SizedBox(height: 16),
        TextFormField(
          initialValue: '${widget.object.meta['camera'] ?? ''}',
          decoration: const InputDecoration(
            labelText: 'Framing & camera movement',
          ),
          onChanged: (v) {
            widget.object.meta['camera'] = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: '${widget.object.meta['duration'] ?? 5}',
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: const InputDecoration(labelText: 'Duration (seconds)'),
          onChanged: (v) {
            final n = double.tryParse(v);
            if (n != null && n > 0 && n <= 3600) {
              widget.object.meta['duration'] = n;
              widget.onChanged();
            }
          },
        ),
      ],
    ],
  );
}
