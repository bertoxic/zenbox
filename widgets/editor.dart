import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:zenbox/services/document_ops.dart';
import 'package:zenbox/models/model.dart';
import 'package:zenbox/theme/theme.dart';
export 'package:zenbox/widgets/rich_editor.dart';

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
  q.QuillController? _quillController;
  final FocusNode _quillFocusNode = FocusNode();
  final ScrollController _quillScrollController = ScrollController();
  bool _rawMarkdown = false;

  @override
  void initState() {
    super.initState();
    if (widget.object.kind == 'shot') {
      final doc = readDocument(widget.object);
      _quillController = q.QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      );
      _quillController!.addListener(_onQuillChanged);
    }
  }

  void _onQuillChanged() {
    if (_quillController == null) return;
    storeDocument(widget.object, _quillController!.document);
    body.text = widget.object.body;
    widget.onChanged();
  }

  void _format(q.Attribute attribute) {
    if (_quillController == null) return;
    _quillController!.formatSelection(attribute);
    _quillFocusNode.requestFocus();
  }

  void _toggle(q.Attribute attribute) {
    if (_quillController == null) return;
    final active = _quillController!
            .getSelectionStyle()
            .attributes[attribute.key]
            ?.value ==
        attribute.value;
    _format(q.Attribute.clone(attribute, active ? null : attribute.value));
  }

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    if (_quillController != null) {
      _quillController!.removeListener(_onQuillChanged);
      _quillController!.dispose();
      _quillFocusNode.dispose();
      _quillScrollController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
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
      if (widget.object.kind == 'shot') ...[
        Row(
          children: [
            Text(
              'Talking points & notes',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: Icon(
                _rawMarkdown ? Icons.format_paint_outlined : Icons.code,
                size: 14,
              ),
              label: Text(
                _rawMarkdown ? 'Rich text' : 'Markdown syntax',
                style: const TextStyle(fontSize: 11),
              ),
              onPressed: () {
                setState(() {
                  _rawMarkdown = !_rawMarkdown;
                  if (!_rawMarkdown && _quillController != null) {
                    final newDoc = q.Document.fromDelta(markdownToDelta(body.text));
                    _quillController!.document = newDoc;
                    storeDocument(widget.object, newDoc);
                  }
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_rawMarkdown)
          TextField(
            controller: body,
            minLines: 6,
            maxLines: 12,
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Write in Markdown syntax (# Heading, **bold**, etc.)',
              alignLabelWithHint: true,
            ),
            onChanged: (v) {
              widget.object.body = v;
              if (_quillController != null) {
                final doc = q.Document.fromDelta(markdownToDelta(v));
                widget.object.meta['delta'] = doc.toDelta().toJson();
              }
              widget.onChanged();
            },
          )
        else
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: cream,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: line),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: paper,
                    border: Border(bottom: BorderSide(color: line)),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Undo',
                          iconSize: 16,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                          icon: const Icon(Icons.undo),
                          onPressed: _quillController?.undo,
                        ),
                        IconButton(
                          tooltip: 'Redo',
                          iconSize: 16,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                          icon: const Icon(Icons.redo),
                          onPressed: _quillController?.redo,
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Bold (Ctrl+B)',
                          iconSize: 16,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                          icon: const Icon(Icons.format_bold),
                          onPressed: () => _toggle(q.Attribute.bold),
                        ),
                        IconButton(
                          tooltip: 'Italic (Ctrl+I)',
                          iconSize: 16,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                          icon: const Icon(Icons.format_italic),
                          onPressed: () => _toggle(q.Attribute.italic),
                        ),
                        IconButton(
                          tooltip: 'Underline (Ctrl+U)',
                          iconSize: 16,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                          icon: const Icon(Icons.format_underlined),
                          onPressed: () => _toggle(q.Attribute.underline),
                        ),
                        IconButton(
                          tooltip: 'Strikethrough',
                          iconSize: 16,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                          icon: const Icon(Icons.format_strikethrough),
                          onPressed: () => _toggle(q.Attribute.strikeThrough),
                        ),
                        IconButton(
                          tooltip: 'Inline code',
                          iconSize: 16,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                          icon: const Icon(Icons.code),
                          onPressed: () => _toggle(q.Attribute.inlineCode),
                        ),
                        PopupMenuButton<q.Attribute>(
                          tooltip: 'Headings',
                          iconSize: 16,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                          icon: const Icon(Icons.title),
                          onSelected: _toggle,
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: q.Attribute.h1,
                              child: Text('Heading 1', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ),
                            PopupMenuItem(
                              value: q.Attribute.h2,
                              child: Text('Heading 2', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            ),
                            PopupMenuItem(
                              value: q.Attribute.h3,
                              child: Text('Heading 3', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ],
                        ),
                        IconButton(
                          tooltip: 'Bullet list',
                          iconSize: 16,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                          icon: const Icon(Icons.format_list_bulleted),
                          onPressed: () => _toggle(q.Attribute.ul),
                        ),
                        IconButton(
                          tooltip: 'Numbered list',
                          iconSize: 16,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                          icon: const Icon(Icons.format_list_numbered),
                          onPressed: () => _toggle(q.Attribute.ol),
                        ),
                        IconButton(
                          tooltip: 'Blockquote',
                          iconSize: 16,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                          icon: const Icon(Icons.format_quote),
                          onPressed: () => _toggle(q.Attribute.blockQuote),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: _quillController != null
                        ? q.QuillEditor(
                            controller: _quillController!,
                            focusNode: _quillFocusNode,
                            scrollController: _quillScrollController,
                            config: const q.QuillEditorConfig(
                              placeholder: 'Write talking points, explanation notes...',
                              padding: EdgeInsets.zero,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
      ] else ...[
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
      ],
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
            labelText: 'Teaching approach & visual cues',
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
