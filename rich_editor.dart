import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'document_ops.dart';
import 'editor.dart' show askText;
import 'model.dart';
import 'theme.dart';
import 'visual.dart';
import 'markdown_view.dart';

class DocumentEditor extends StatefulWidget {
  const DocumentEditor({
    super.key,
    required this.store,
    required this.object,
    required this.onInspect,
    required this.onExport,
    required this.onAskAi,
    required this.onPreview,
    required this.onDelete,
    this.siblingDocuments = const [],
    this.onSwitchDocument,
    this.onNewDocument,
  });

  final StudioStore store;
  final CreativeObject object;
  final VoidCallback onInspect, onExport;
  final void Function(SelectionRequest) onAskAi;
  final void Function(CreativeObject) onPreview;
  final FutureOr<void> Function() onDelete;
  final List<CreativeObject> siblingDocuments;
  final ValueChanged<CreativeObject>? onSwitchDocument;
  final VoidCallback? onNewDocument;

  @override
  State<DocumentEditor> createState() => _DocumentEditorState();
}

class _DocumentEditorState extends State<DocumentEditor> {
  late q.QuillController controller;
  final focus = FocusNode();
  final scroll = ScrollController();
  final editorKey = GlobalKey<q.EditorState>();
  final portal = OverlayPortalController();
  Timer? selectionTimer;
  late String savedDelta;
  bool syncing = false;
  double textSize = 15;
  double pageZoom = 1.0;
  bool markdownPreview = false;
  bool _rawMarkdownMode = false;
  late final TextEditingController _markdownTextController =
      TextEditingController();
  TextSelection selection = const TextSelection.collapsed(offset: 0);

  bool get script => widget.object.kind == 'script';

  final List<Map<String, dynamic>> textColors = [
    {
      'name': 'Default Ink',
      'value': '#303C34',
      'color': const Color(0xFF303C34),
    },
    {
      'name': 'Sage Green',
      'value': '#536B50',
      'color': const Color(0xFF536B50),
    },
    {
      'name': 'Amber Bronze',
      'value': '#A26C38',
      'color': const Color(0xFFA26C38),
    },
    {'name': 'Crimson', 'value': '#A54141', 'color': const Color(0xFFA54141)},
    {
      'name': 'Deep Cobalt',
      'value': '#456C9C',
      'color': const Color(0xFF456C9C),
    },
    {
      'name': 'Plum Violet',
      'value': '#78598C',
      'color': const Color(0xFF78598C),
    },
    {'name': 'Charcoal', 'value': '#1F1F1F', 'color': const Color(0xFF1F1F1F)},
  ];

  final List<Map<String, dynamic>> highlightColors = [
    {'name': 'Warm Gold', 'value': '#FCEBB6', 'color': const Color(0xFFFCEBB6)},
    {'name': 'Soft Sage', 'value': '#D9E8D4', 'color': const Color(0xFFD9E8D4)},
    {'name': 'Sky Blue', 'value': '#D0E5F5', 'color': const Color(0xFFD0E5F5)},
    {'name': 'Rose Pink', 'value': '#FCD5DC', 'color': const Color(0xFFFCD5DC)},
    {'name': 'Peach', 'value': '#FEE4CB', 'color': const Color(0xFFFEE4CB)},
    {'name': 'Lavender', 'value': '#E8DBFC', 'color': const Color(0xFFE8DBFC)},
  ];

  @override
  void initState() {
    super.initState();
    controller = q.QuillController(
      document: readDocument(widget.object),
      selection: const TextSelection.collapsed(offset: 0),
    );
    savedDelta = jsonEncode(controller.document.toDelta().toJson());
    controller.addListener(changed);
    scroll.addListener(hideSelection);
  }

  void hideSelection() {
    if (portal.isShowing) portal.hide();
  }

  void showSelectionPopup() {
    if (!mounted) return;
    selection = controller.selection;
    if (selection.isValid && !selection.isCollapsed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && selection.isValid && !selection.isCollapsed) {
          if (!portal.isShowing) {
            portal.show();
          } else {
            setState(() {});
          }
        }
      });
    } else {
      hideSelection();
    }
  }

  void changed() {
    if (syncing) return;
    final delta = jsonEncode(controller.document.toDelta().toJson());
    if (delta != savedDelta) {
      savedDelta = delta;
      storeDocument(widget.object, controller.document);
      widget.store.changed();
    }
    selection = controller.selection;
    selectionTimer?.cancel();
    if (!selection.isValid || selection.isCollapsed) {
      hideSelection();
      return;
    }
    selectionTimer = Timer(const Duration(milliseconds: 25), () {
      showSelectionPopup();
    });
  }

  /// Markdown preview normally reads the plain-text note body. Quill embeds do
  /// not exist in that string, so turn image embeds into local Markdown image
  /// links while preserving their original position in the note.
  String markdownPreviewData() {
    return deltaToMarkdown(controller.document.toDelta());
  }

  void _syncRawMarkdownToDocument() {
    final text = _markdownTextController.text;
    final newDoc = q.Document.fromDelta(markdownToDelta(text));
    syncing = true;
    controller.document = newDoc;
    savedDelta = jsonEncode(newDoc.toDelta().toJson());
    storeDocument(widget.object, newDoc);
    widget.store.changed();
    syncing = false;
  }

  void toggleMarkdownView() {
    if (markdownPreview && _rawMarkdownMode) {
      _syncRawMarkdownToDocument();
    }
    setState(() {
      markdownPreview = !markdownPreview;
      if (markdownPreview) {
        _markdownTextController.text = markdownPreviewData();
      }
    });
  }

  @override
  void didUpdateWidget(DocumentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final doc = readDocument(widget.object);
    final delta = jsonEncode(doc.toDelta().toJson());
    if (delta != savedDelta) {
      syncing = true;
      controller.document = doc;
      controller.updateSelection(
        TextSelection.collapsed(
          offset: math.min(
            selection.start.clamp(0, doc.length - 1),
            doc.length - 1,
          ),
        ),
        q.ChangeSource.local,
      );
      savedDelta = delta;
      syncing = false;
      hideSelection();
    }
  }

  @override
  void dispose() {
    _markdownTextController.dispose();
    selectionTimer?.cancel();
    controller.removeListener(changed);
    controller.dispose();
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  void insertText(String value) {
    final sel = controller.selection;
    final at = sel.start.clamp(0, controller.document.length - 1);
    controller.replaceText(
      at,
      sel.isValid ? sel.end - sel.start : 0,
      value,
      TextSelection.collapsed(offset: at + value.length),
    );
    focus.requestFocus();
  }

  void insertMarkdown(String value) {
    final sel = controller.selection;
    final at = sel.start.clamp(0, controller.document.length - 1);
    final len = sel.isValid && !sel.isCollapsed ? sel.end - sel.start : 0;
    final delta = markdownToDelta(value);
    controller.replaceText(
      at,
      len,
      delta,
      TextSelection.collapsed(offset: at + delta.length),
    );
    focus.requestFocus();
  }

  Future<void> pasteMarkdown() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final value = clipboard?.text;
    if (value == null || value.isEmpty) return;
    insertMarkdown(value.replaceAll('\r\n', '\n'));
  }

  void embed(CreativeObject object, {Offset? position}) {
    final at = position == null
        ? controller.selection.start.clamp(0, controller.document.length - 1)
        : (editorKey.currentState?.renderEditor
                      .getPositionForOffset(position)
                      .offset ??
                  controller.selection.start)
              .clamp(0, controller.document.length - 1);

    if (object.kind == 'generation' ||
        object.kind == 'note' ||
        object.kind == 'research' ||
        object.kind == 'evidence') {
      final markdown = markdownToDelta(object.body);
      controller.replaceText(
        at,
        0,
        markdown,
        TextSelection.collapsed(offset: at + markdown.length),
      );
      return;
    }
    final embedKey = object.kind == 'asset'
        ? switch (object.meta['mediaType']) {
            'image' => 'studio-image',
            'video' => 'studio-video',
            _ => 'studio-object',
          }
        : 'studio-object';
    final inlineMedia =
        embedKey == 'studio-image' || embedKey == 'studio-video';
    if (inlineMedia) {
      controller.replaceText(
        at,
        0,
        q.BlockEmbed(embedKey, object.id),
        TextSelection.collapsed(offset: at + 1),
      );
    } else {
      controller.replaceText(
        at,
        0,
        '\n',
        TextSelection.collapsed(offset: at + 1),
      );
      controller.replaceText(
        at + 1,
        0,
        q.BlockEmbed(embedKey, object.id),
        TextSelection.collapsed(offset: at + 2),
      );
      controller.replaceText(
        at + 2,
        0,
        '\n',
        TextSelection.collapsed(offset: at + 3),
      );
    }
    if (!widget.object.links.contains(object.id)) {
      widget.object.links.add(object.id);
    }
    widget.store.changed();
    focus.requestFocus();
  }

  void format(q.Attribute attribute) {
    controller.updateSelection(selection, q.ChangeSource.local);
    controller.formatSelection(attribute);
    focus.requestFocus();
  }

  void toggle(q.Attribute attribute) {
    final active =
        controller.getSelectionStyle().attributes[attribute.key]?.value ==
        attribute.value;
    format(q.Attribute.clone(attribute, active ? null : attribute.value));
  }

  void ask(String action) {
    if (selection.isCollapsed) return;
    final text = controller.document.toPlainText().substring(
      selection.start,
      selection.end,
    );
    hideSelection();
    widget.onAskAi(
      SelectionRequest(
        objectId: widget.object.id,
        start: selection.start,
        end: selection.end,
        text: text,
        action: action,
      ),
    );
  }

  void _showAskAiDialog(BuildContext context) {
    if (selection.isCollapsed) return;
    final text = controller.document.toPlainText().substring(
      selection.start,
      selection.end,
    );
    final customPromptController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.auto_awesome, size: 18, color: gold),
            const SizedBox(width: 8),
            const Text('Ask study AI', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: paleSage.withValues(alpha: .3),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: line),
                ),
                child: Row(
                  children: [
                    Icon(Icons.format_quote, size: 16, color: sage),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        text.length > 140 ? '${text.substring(0, 140)}…' : text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: customPromptController,
                autofocus: true,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText:
                      'Explain this concept, check my reasoning, create recall questions…',
                  suffixIcon: IconButton(
                    icon: Icon(Icons.send, size: 18, color: ink),
                    tooltip: 'Send instruction',
                    onPressed: () {
                      final val = customPromptController.text.trim();
                      if (val.isNotEmpty) {
                        Navigator.pop(ctx);
                        ask(val);
                      }
                    },
                  ),
                ),
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty) {
                    Navigator.pop(ctx);
                    ask(val.trim());
                  }
                },
              ),
              const SizedBox(height: 16),
              Text(
                'QUICK ACTIONS',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.bold,
                  color: muted,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    [
                          'Ask AI to rewrite',
                          'Polish dialogue',
                          'Make punchier',
                          'Expand sensory detail',
                          'Shorten & tighten',
                          'Explain / Analyze tone',
                          'Continue from here',
                        ]
                        .map(
                          (action) => ActionChip(
                            avatar: Icon(
                              Icons.auto_awesome,
                              size: 12,
                              color: gold,
                            ),
                            label: Text(
                              action,
                              style: const TextStyle(fontSize: 11),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              ask(action);
                            },
                          ),
                        )
                        .toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget formatTools({bool floating = false}) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 2,
    children: [
      IconButton(
        tooltip: 'Bold · Ctrl+B',
        onPressed: () => toggle(q.Attribute.bold),
        icon: const Icon(Icons.format_bold, size: 18),
      ),
      IconButton(
        tooltip: 'Italic · Ctrl+I',
        onPressed: () => toggle(q.Attribute.italic),
        icon: const Icon(Icons.format_italic, size: 18),
      ),
      IconButton(
        tooltip: 'Underline · Ctrl+U',
        onPressed: () => toggle(q.Attribute.underline),
        icon: const Icon(Icons.format_underlined, size: 18),
      ),
      IconButton(
        tooltip: 'Strikethrough',
        onPressed: () => toggle(q.Attribute.strikeThrough),
        icon: const Icon(Icons.format_strikethrough, size: 18),
      ),
      IconButton(
        tooltip: 'Inline code',
        onPressed: () => toggle(q.Attribute.inlineCode),
        icon: const Icon(Icons.code, size: 18),
      ),
      if (floating) ...[
        PopupMenuButton<String>(
          tooltip: 'Text color',
          icon: const Icon(Icons.format_color_text, size: 19),
          onSelected: (v) => format(q.ColorAttribute(v)),
          itemBuilder: (_) => textColors
              .map(
                (c) => PopupMenuItem(
                  value: c['value'] as String,
                  child: Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: c['color'] as Color,
                          shape: BoxShape.circle,
                          border: Border.all(color: line),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        c['name'] as String,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
        PopupMenuButton<String>(
          tooltip: 'Text highlight',
          icon: const Icon(Icons.border_color_outlined, size: 18),
          onSelected: (v) =>
              format(q.BackgroundAttribute(v == 'none' ? null : v)),
          itemBuilder: (_) => [
            ...highlightColors.map(
              (c) => PopupMenuItem(
                value: c['value'] as String,
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 18,
                      decoration: BoxDecoration(
                        color: c['color'] as Color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      c['name'] as String,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'none',
              child: Row(
                children: [
                  Icon(Icons.format_color_reset, size: 16, color: muted),
                  const SizedBox(width: 10),
                  const Text('Clear highlight', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        PopupMenuButton<String>(
          tooltip: 'Font family',
          onSelected: (v) => format(q.FontAttribute(v)),
          itemBuilder: (_) =>
              [
                    'Courier New',
                    'Georgia',
                    'Segoe UI',
                    'Arial',
                    'Times New Roman',
                    'Trebuchet MS',
                  ]
                  .map(
                    (v) => PopupMenuItem(
                      value: v,
                      child: Text(
                        v,
                        style: TextStyle(fontFamily: v, fontSize: 13),
                      ),
                    ),
                  )
                  .toList(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.font_download_outlined, size: 15, color: ink),
                const SizedBox(width: 4),
                const Text(
                  'Font',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
                const Icon(Icons.expand_more, size: 14),
              ],
            ),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Font size',
          onSelected: (v) => format(q.SizeAttribute(v)),
          itemBuilder: (_) => [
            '11',
            '12',
            '14',
            '16',
            '18',
            '20',
            '24',
            '28',
            '36',
          ].map((v) => PopupMenuItem(value: v, child: Text('$v pt'))).toList(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Size',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
                Icon(Icons.expand_more, size: 14),
              ],
            ),
          ),
        ),
      ],
      if (!floating) ...[
        PopupMenuButton<q.Attribute>(
          tooltip: 'Heading style',
          icon: const Icon(Icons.title, size: 17),
          onSelected: toggle,
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: q.Attribute.h1,
              child: Text(
                'Heading 1',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            PopupMenuItem(
              value: q.Attribute.h2,
              child: Text(
                'Heading 2',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            PopupMenuItem(
              value: q.Attribute.h3,
              child: Text(
                'Heading 3',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
        IconButton(
          tooltip: 'Align left',
          onPressed: () => format(q.Attribute.leftAlignment),
          icon: const Icon(Icons.format_align_left, size: 17),
        ),
        IconButton(
          tooltip: 'Center',
          onPressed: () => format(q.Attribute.centerAlignment),
          icon: const Icon(Icons.format_align_center, size: 17),
        ),
        IconButton(
          tooltip: 'Bullet list',
          onPressed: () => toggle(q.Attribute.ul),
          icon: const Icon(Icons.format_list_bulleted, size: 17),
        ),
        IconButton(
          tooltip: 'Numbered list',
          onPressed: () => toggle(q.Attribute.ol),
          icon: const Icon(Icons.format_list_numbered, size: 17),
        ),
        IconButton(
          tooltip: 'Checklist',
          onPressed: () => toggle(q.Attribute.unchecked),
          icon: const Icon(Icons.checklist, size: 17),
        ),
        IconButton(
          tooltip: 'Quote',
          onPressed: () => toggle(q.Attribute.blockQuote),
          icon: const Icon(Icons.format_quote, size: 17),
        ),
        IconButton(
          tooltip: 'Code block',
          onPressed: () => toggle(q.Attribute.codeBlock),
          icon: const Icon(Icons.data_object, size: 17),
        ),
        IconButton(
          tooltip: 'Horizontal rule',
          onPressed: () {
            final at = controller.selection.start.clamp(0, controller.document.length - 1);
            controller.replaceText(
              at,
              0,
              q.BlockEmbed('divider', 'hr'),
              TextSelection.collapsed(offset: at + 1),
            );
            controller.replaceText(
              at + 1,
              0,
              '\n',
              TextSelection.collapsed(offset: at + 2),
            );
            focus.requestFocus();
          },
          icon: const Icon(Icons.horizontal_rule, size: 17),
        ),
      ],
      InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: selection.isCollapsed ? null : () => _showAskAiDialog(context),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: paleSage.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: sage.withValues(alpha: .5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome,
                size: 14,
                color: selection.isCollapsed ? muted : gold,
              ),
              const SizedBox(width: 6),
              Text(
                'Ask AI',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selection.isCollapsed ? muted : ink,
                ),
              ),
              const SizedBox(width: 3),
              const Icon(Icons.arrow_drop_down, size: 14),
            ],
          ),
        ),
      ),
      if (floating) ...[
        Draggable<String>(
          data: controller.document.toPlainText().substring(
            selection.start,
            selection.end,
          ),
          feedback: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(6),
            color: ink,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              constraints: const BoxConstraints(maxWidth: 240),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.note_add_outlined, size: 14, color: cream),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      controller.document
                          .toPlainText()
                          .substring(selection.start, selection.end)
                          .trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: cream),
                    ),
                  ),
                ],
              ),
            ),
          ),
          child: Tooltip(
            message: 'Drag text to Research Notes or Study Notes',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(Icons.drag_indicator, size: 16, color: sage),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Copy',
          onPressed: () => Clipboard.setData(
            ClipboardData(
              text: controller.document.toPlainText().substring(
                selection.start,
                selection.end,
              ),
            ),
          ),
          icon: const Icon(Icons.copy, size: 15),
        ),
      ],
    ],
  );

  Widget selectionOverlay(BuildContext context) {
    final render = editorKey.currentState?.renderEditor;
    if (render == null ||
        !render.attached ||
        !render.hasSize ||
        selection.isCollapsed ||
        !selection.isValid) {
      return const SizedBox.shrink();
    }
    if (render.debugNeedsLayout) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            portal.isShowing &&
            selection.isValid &&
            !selection.isCollapsed) {
          setState(() {});
        }
      });
      return const SizedBox.shrink();
    }
    Rect rect;
    try {
      rect = render.getLocalRectForCaret(TextPosition(offset: selection.end));
    } catch (_) {
      return const SizedBox.shrink();
    }
    Offset global;
    try {
      global = render.localToGlobal(rect.bottomLeft);
    } catch (_) {
      return const SizedBox.shrink();
    }
    final screen = MediaQuery.sizeOf(context);

    final leftPos = (global.dx - 120).clamp(
      16.0,
      math.max(16.0, screen.width - 580),
    );
    final topPos = (global.dy + 12).clamp(
      16.0,
      math.max(16.0, screen.height - 110),
    );

    return Positioned(
      left: leftPos.toDouble(),
      top: topPos.toDouble(),
      width: math.min(560.0, screen.width - 32),
      child: TextFieldTapRegion(
        child: Material(
          elevation: 12,
          color: paper,
          shadowColor: ink.withValues(alpha: .22),
          borderRadius: BorderRadius.circular(9),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              border: Border.all(color: sage.withValues(alpha: .6)),
              borderRadius: BorderRadius.circular(9),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: formatTools(floating: true),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plain = controller.document.toPlainText().replaceAll('\uFFFC', '');
    final words = plain.trim().isEmpty
        ? 0
        : plain.trim().split(RegExp(r'\s+')).length;

    return OverlayPortal(
      controller: portal,
      overlayChildBuilder: selectionOverlay,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hasRoomForHeader =
              !constraints.hasBoundedHeight || constraints.maxHeight >= 46;
          final hasRoomForToolbar =
              !constraints.hasBoundedHeight || constraints.maxHeight >= 126;
          final hasRoomForFooter =
              !constraints.hasBoundedHeight || constraints.maxHeight >= 78;
          return Column(
            children: [
              if (hasRoomForHeader)
                Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: line)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        script ? Icons.edit_note : Icons.auto_stories_outlined,
                        size: 17,
                        color: sage,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: widget.siblingDocuments.isEmpty
                            ? Text(
                                widget.object.title,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : PopupMenuButton<String>(
                                tooltip: 'Switch document',
                                onSelected: (id) {
                                  final matches = widget.siblingDocuments.where(
                                    (document) => document.id == id,
                                  );
                                  if (matches.isNotEmpty) {
                                    widget.onSwitchDocument?.call(
                                      matches.first,
                                    );
                                  }
                                },
                                itemBuilder: (_) => widget.siblingDocuments
                                    .map(
                                      (document) => PopupMenuItem(
                                        value: document.id,
                                        child: Row(
                                          children: [
                                            if (document.id == widget.object.id)
                                              Icon(
                                                Icons.check,
                                                size: 15,
                                                color: sage,
                                              )
                                            else
                                              const SizedBox(width: 15),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                document.title,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                    .toList(),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        widget.object.title,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.expand_more, size: 16),
                                  ],
                                ),
                              ),
                      ),
                      if (widget.onNewDocument != null)
                        IconButton(
                          tooltip: script
                              ? 'New topic / note'
                              : 'New study unit',
                          onPressed: widget.onNewDocument,
                          icon: const Icon(Icons.add, size: 17),
                        ),
                      IconButton(
                        tooltip: 'Rename',
                        onPressed: () async {
                          final value = await askText(
                            context,
                            'Rename document',
                            initial: widget.object.title,
                          );
                          if (value != null) {
                            widget.object.title = value;
                            widget.store.changed();
                          }
                        },
                        icon: const Icon(Icons.edit_outlined, size: 16),
                      ),
                      IconButton(
                        tooltip: markdownPreview
                            ? 'Notes rich text'
                            : 'Markdown view',
                        onPressed: toggleMarkdownView,
                        icon: Icon(
                          markdownPreview
                              ? Icons.edit_note
                              : Icons.preview_outlined,
                          size: 17,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Save note snapshot',
                        onPressed: () => widget.store.snapshot(widget.object),
                        icon: const Icon(Icons.history, size: 17),
                      ),
                      IconButton(
                        tooltip: 'Export note as PDF',
                        onPressed: widget.onExport,
                        icon: const Icon(Icons.download_outlined, size: 17),
                      ),
                      IconButton(
                        tooltip: 'Delete document',
                        onPressed: () => widget.onDelete(),
                        color: const Color(0xFFA54141),
                        icon: const Icon(Icons.delete_outline, size: 17),
                      ),
                    ],
                  ),
                ),
              if (hasRoomForToolbar)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  decoration: BoxDecoration(
                    color: paper,
                    border: Border(bottom: BorderSide(color: line)),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: TextFieldTapRegion(
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Undo',
                            onPressed: controller.undo,
                            icon: const Icon(Icons.undo, size: 17),
                          ),
                          IconButton(
                            tooltip: 'Redo',
                            onPressed: controller.redo,
                            icon: const Icon(Icons.redo, size: 17),
                          ),
                          formatTools(),
                          if (script)
                            PopupMenuButton<String>(
                              tooltip: 'Study elements',
                              onSelected: insertText,
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: '\n### Topic / Section Heading\n\n',
                                  child: Text('Topic / Section Heading'),
                                ),
                                PopupMenuItem(
                                  value: '\n> **Key Takeaway:** \n\n',
                                  child: Text('Key Takeaway / Summary Callout'),
                                ),
                                PopupMenuItem(
                                  value: '\n* **Term / Concept:** \n',
                                  child: Text('Definition / Concept Item'),
                                ),
                                PopupMenuItem(
                                  value:
                                      '\n---\n**Review Question / Checkpoint:** \n\n',
                                  child: Text('Review Question / Check'),
                                ),
                              ],
                              icon: const Icon(Icons.playlist_add, size: 17),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: DragTarget<Object>(
                  onWillAcceptWithDetails: (d) {
                    if (d.data is CreativeObject) {
                      return (d.data as CreativeObject).id != widget.object.id;
                    }
                    return d.data is String;
                  },
                  onAcceptWithDetails: (d) {
                    if (d.data is CreativeObject) {
                      embed(d.data as CreativeObject, position: d.offset);
                    } else if (d.data is String) {
                      final at = (editorKey.currentState?.renderEditor
                                    .getPositionForOffset(d.offset)
                                    .offset ??
                                controller.selection.start)
                            .clamp(0, controller.document.length - 1);
                      final delta = markdownToDelta(d.data as String);
                      controller.replaceText(
                        at,
                        0,
                        delta,
                        TextSelection.collapsed(offset: at + delta.length),
                      );
                      focus.requestFocus();
                    }
                  },
                  builder: (context, candidates, rejected) => Container(
                    color: candidates.isEmpty
                        ? cream
                        : paleSage.withValues(alpha: .4),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                            child: Transform.scale(
                              scale: pageZoom,
                              alignment: Alignment.topCenter,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: paper,
                                  border: Border.all(
                                    color: candidates.isEmpty ? line : sage,
                                    width: candidates.isEmpty ? 1 : 2,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (markdownPreview)
                                      Column(
                                        children: [
                                          Container(
                                            height: 42,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 24,
                                            ),
                                            decoration: BoxDecoration(
                                              color: paper,
                                              border: Border(
                                                bottom: BorderSide(color: line),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.code,
                                                  size: 16,
                                                  color: sage,
                                                ),
                                                const SizedBox(width: 8),
                                                const Text(
                                                  'Markdown',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                SegmentedButton<bool>(
                                                  segments: const [
                                                    ButtonSegment(
                                                      value: false,
                                                      label: Text(
                                                        'Preview',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                      icon: Icon(
                                                        Icons
                                                            .visibility_outlined,
                                                        size: 14,
                                                      ),
                                                    ),
                                                    ButtonSegment(
                                                      value: true,
                                                      label: Text(
                                                        'Raw Syntax',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                      icon: Icon(
                                                        Icons.code,
                                                        size: 14,
                                                      ),
                                                    ),
                                                  ],
                                                  selected: {_rawMarkdownMode},
                                                  onSelectionChanged: (set) {
                                                    setState(() {
                                                      _rawMarkdownMode =
                                                          set.first;
                                                      if (_rawMarkdownMode) {
                                                        _markdownTextController
                                                                .text =
                                                            markdownPreviewData();
                                                      } else {
                                                        _syncRawMarkdownToDocument();
                                                      }
                                                    });
                                                  },
                                                  style: const ButtonStyle(
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    tapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                  ),
                                                ),
                                                const Spacer(),
                                                TextButton.icon(
                                                  onPressed: () {
                                                    final text =
                                                        _rawMarkdownMode
                                                            ? _markdownTextController
                                                                .text
                                                            : markdownPreviewData();
                                                    Clipboard.setData(
                                                      ClipboardData(text: text),
                                                    );
                                                  },
                                                  icon: const Icon(
                                                    Icons.copy,
                                                    size: 14,
                                                  ),
                                                  label: const Text(
                                                    'Copy Markdown',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            child: _rawMarkdownMode
                                                ? Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 48,
                                                          vertical: 24,
                                                        ),
                                                    child: TextField(
                                                      controller:
                                                          _markdownTextController,
                                                      maxLines: null,
                                                      expands: true,
                                                      style: const TextStyle(
                                                        fontFamily: 'Consolas',
                                                        fontSize: 13,
                                                        height: 1.6,
                                                      ),
                                                      decoration:
                                                          const InputDecoration(
                                                            border: InputBorder
                                                                .none,
                                                            hintText:
                                                                'Enter Markdown here...',
                                                          ),
                                                      onChanged: (_) =>
                                                          _syncRawMarkdownToDocument(),
                                                    ),
                                                  )
                                                : SingleChildScrollView(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 48,
                                                          vertical: 40,
                                                        ),
                                                    child: MarkdownView(
                                                      data:
                                                          markdownPreviewData(),
                                                      selectable: true,
                                                    ),
                                                  ),
                                          ),
                                        ],
                                      )
                                    else
                                      Listener(
                                        onPointerDown: (_) =>
                                            focus.requestFocus(),
                                        onPointerUp: (_) =>
                                            showSelectionPopup(),
                                        child: CallbackShortcuts(
                                          bindings: {
                                            const SingleActivator(
                                              LogicalKeyboardKey.keyV,
                                              control: true,
                                            ): pasteMarkdown,
                                          },
                                          child: q.QuillEditor(
                                            controller: controller,
                                            focusNode: focus,
                                            scrollController: scroll,
                                            config: q.QuillEditorConfig(
                                              editorKey: editorKey,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 48,
                                                    vertical: 40,
                                                  ),
                                              placeholder:
                                                  'Write, select text for interactive tools, or drop assets here…',
                                              embedBuilders: [
                                                DividerEmbedBuilder(),
                                                TableEmbedBuilder(),
                                                MarkdownImageEmbedBuilder(),
                                                StudioImageEmbedBuilder(
                                                  store: widget.store,
                                                  project: widget.store.project,
                                                  onPreview: widget.onPreview,
                                                ),
                                                StudioVideoEmbedBuilder(
                                                  store: widget.store,
                                                  project: widget.store.project,
                                                  onPreview: widget.onPreview,
                                                ),
                                                StudioEmbedBuilder(
                                                  store: widget.store,
                                                  project: widget.store.project,
                                                  onPreview: widget.onPreview,
                                                ),
                                              ],
                                              customStyles: q.DefaultStyles(
                                                paragraph:
                                                    q.DefaultTextBlockStyle(
                                                      TextStyle(
                                                        fontFamily: script
                                                            ? 'Courier New'
                                                            : 'Georgia',
                                                        fontSize: textSize,
                                                        height: 1.75,
                                                        color: ink,
                                                      ),
                                                      const q.HorizontalSpacing(
                                                        0,
                                                        0,
                                                      ),
                                                      const q.VerticalSpacing(
                                                        0,
                                                        0,
                                                      ),
                                                      const q.VerticalSpacing(
                                                        0,
                                                        0,
                                                      ),
                                                      null,
                                                    ),
                                              ),
                                              contextMenuBuilder: (context, state) {
                                                final items = state
                                                    .contextMenuButtonItems
                                                    .map((item) {
                                                      if (item.type ==
                                                          ContextMenuButtonType
                                                              .paste) {
                                                        return ContextMenuButtonItem(
                                                          type: ContextMenuButtonType
                                                              .paste,
                                                          label: item.label,
                                                          onPressed: () {
                                                            state.hideToolbar();
                                                            pasteMarkdown();
                                                          },
                                                        );
                                                      }
                                                      return item;
                                                    })
                                                    .toList();
                                                return AdaptiveTextSelectionToolbar.buttonItems(
                                                  anchors: state
                                                      .contextMenuAnchors,
                                                  buttonItems: items,
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (candidates.isNotEmpty)
                          Positioned(
                            top: 14,
                            right: 40,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: gold,
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [
                                  BoxShadow(
                                    color: ink.withValues(alpha: .15),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.download, size: 16, color: ink),
                                  const SizedBox(width: 8),
                                  Text(
                                    'DROP ASSET TO EMBED IN NOTE',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                      color: ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (hasRoomForFooter)
                Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  decoration: BoxDecoration(
                    color: paper,
                    border: Border(top: BorderSide(color: line)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '$words words',
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                      const SizedBox(width: 14),
                      Flexible(
                        child: Text(
                          'Highlight text for floating formatting · Drag assets to embed · Autosaved',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(fontSize: 10, color: muted),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Page zoom:',
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                      IconButton(
                        tooltip: 'Zoom out page (10%)',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 26,
                          minHeight: 26,
                        ),
                        onPressed: () => setState(
                          () => pageZoom = (pageZoom - 0.1).clamp(0.6, 1.8),
                        ),
                        icon: const Icon(Icons.remove, size: 13),
                      ),
                      InkWell(
                        onTap: () => setState(() => pageZoom = 1.0),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Text(
                            '${(pageZoom * 100).round()}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: ink,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Zoom in page (10%)',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 26,
                          minHeight: 26,
                        ),
                        onPressed: () => setState(
                          () => pageZoom = (pageZoom + 0.1).clamp(0.6, 1.8),
                        ),
                        icon: const Icon(Icons.add, size: 13),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Text:',
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                      IconButton(
                        tooltip: 'Smaller text',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        onPressed: () => setState(
                          () => textSize = (textSize - 1).clamp(11, 25),
                        ),
                        icon: const Icon(Icons.text_decrease, size: 13),
                      ),
                      Text(
                        '${textSize.round()}pt',
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                      IconButton(
                        tooltip: 'Larger text',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        onPressed: () => setState(
                          () => textSize = (textSize + 1).clamp(11, 25),
                        ),
                        icon: const Icon(Icons.text_increase, size: 13),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Images use a non-expanded embed so the editor treats them like a compact
/// inline sidecar. That leaves the rest of the writing column available for
/// the surrounding manuscript or screenplay text instead of reserving a
/// full-width media row.
class StudioImageEmbedBuilder extends q.EmbedBuilder {
  StudioImageEmbedBuilder({
    required this.store,
    required this.project,
    required this.onPreview,
  });

  final StudioStore store;
  final Project project;
  final void Function(CreativeObject) onPreview;

  @override
  String get key => 'studio-image';

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, q.EmbedContext embedContext) {
    final data = _StudioImageEmbedData.parse(embedContext.node.value.data);
    final object = project.object(data.objectId);
    if (object == null) return const Text('Linked image is unavailable');
    return _ResizableStudioImageEmbed(
      store: store,
      object: object,
      isVideo: false,
      initialWidth: data.width,
      initialHeight: data.height,
      onPreview: () => onPreview(object),
      onRemove: () {
        final at = embedContext.node.documentOffset;
        embedContext.controller.replaceText(
          at,
          1,
          '',
          TextSelection.collapsed(offset: at),
        );
      },
      onResizeEnd: (width, height) {
        final at = embedContext.node.documentOffset;
        embedContext.controller.replaceText(
          at,
          1,
          q.BlockEmbed(
            key,
            _StudioImageEmbedData(
              objectId: object.id,
              width: width,
              height: height,
            ).encode(),
          ),
          TextSelection.collapsed(offset: at + 1),
        );
      },
    );
  }
}

class StudioVideoEmbedBuilder extends q.EmbedBuilder {
  StudioVideoEmbedBuilder({
    required this.store,
    required this.project,
    required this.onPreview,
  });

  final StudioStore store;
  final Project project;
  final void Function(CreativeObject) onPreview;

  @override
  String get key => 'studio-video';

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, q.EmbedContext embedContext) {
    final data = _StudioImageEmbedData.parse(embedContext.node.value.data);
    final object = project.object(data.objectId);
    if (object == null) return const Text('Linked video is unavailable');
    return _ResizableStudioImageEmbed(
      store: store,
      object: object,
      isVideo: true,
      initialWidth: data.width,
      initialHeight: data.height,
      onPreview: () => onPreview(object),
      onRemove: () {
        final at = embedContext.node.documentOffset;
        embedContext.controller.replaceText(
          at,
          1,
          '',
          TextSelection.collapsed(offset: at),
        );
      },
      onResizeEnd: (width, height) {
        final at = embedContext.node.documentOffset;
        embedContext.controller.replaceText(
          at,
          1,
          q.BlockEmbed(
            key,
            _StudioImageEmbedData(
              objectId: object.id,
              width: width,
              height: height,
            ).encode(),
          ),
          TextSelection.collapsed(offset: at + 1),
        );
      },
    );
  }
}

class _StudioImageEmbedData {
  const _StudioImageEmbedData({
    required this.objectId,
    this.width = 188,
    this.height = 112,
  });

  final String objectId;
  final double width;
  final double height;

  factory _StudioImageEmbedData.parse(Object? value) {
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic> && decoded['id'] is String) {
          return _StudioImageEmbedData(
            objectId: decoded['id'] as String,
            width: (decoded['width'] as num?)?.toDouble() ?? 188,
            height: (decoded['height'] as num?)?.toDouble() ?? 112,
          );
        }
      } on FormatException {
        // Older image embeds only stored the asset ID.
      }
      return _StudioImageEmbedData(objectId: value);
    }
    return const _StudioImageEmbedData(objectId: '');
  }

  String encode() =>
      jsonEncode({'id': objectId, 'width': width, 'height': height});
}

class _ResizableStudioImageEmbed extends StatefulWidget {
  const _ResizableStudioImageEmbed({
    required this.store,
    required this.object,
    required this.isVideo,
    required this.initialWidth,
    required this.initialHeight,
    required this.onPreview,
    required this.onRemove,
    required this.onResizeEnd,
  });

  final StudioStore store;
  final CreativeObject object;
  final bool isVideo;
  final double initialWidth;
  final double initialHeight;
  final VoidCallback onPreview;
  final VoidCallback onRemove;
  final void Function(double width, double height) onResizeEnd;

  @override
  State<_ResizableStudioImageEmbed> createState() =>
      _ResizableStudioImageEmbedState();
}

class _ResizableStudioImageEmbedState
    extends State<_ResizableStudioImageEmbed> {
  static const _minWidth = 120.0;
  static const _minHeight = 80.0;
  static const _maxWidth = 680.0;
  static const _maxHeight = 520.0;

  late double width;
  late double height;
  Player? player;
  VideoController? videoController;

  @override
  void initState() {
    super.initState();
    width = widget.initialWidth;
    height = widget.initialHeight;
    if (widget.isVideo) {
      player = Player();
      videoController = VideoController(player!);
      player!
          .open(Media(widget.store.mediaPath(widget.object)), play: false)
          .catchError((_) {});
    }
  }

  @override
  void didUpdateWidget(covariant _ResizableStudioImageEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialWidth != widget.initialWidth ||
        oldWidget.initialHeight != widget.initialHeight) {
      width = widget.initialWidth;
      height = widget.initialHeight;
    }
  }

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  void updateSize(
    Offset delta, {
    required bool horizontal,
    required bool vertical,
  }) {
    setState(() {
      if (horizontal) width = (width + delta.dx).clamp(_minWidth, _maxWidth);
      if (vertical) height = (height + delta.dy).clamp(_minHeight, _maxHeight);
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 5, 12, 5),
    child: SizedBox(
      width: width,
      child: Material(
        color: cream,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            border: Border.all(color: line),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: InkWell(
                        onTap: widget.onPreview,
                        child: AssetThumbnail(
                          store: widget.store,
                          asset: widget.object,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    if (widget.isVideo && videoController != null)
                      Positioned.fill(
                        child: Video(controller: videoController!),
                      ),
                    if (widget.isVideo)
                      const Center(
                        child: Icon(
                          Icons.play_circle_fill,
                          size: 28,
                          color: Colors.white70,
                        ),
                      ),
                    Positioned(
                      top: 3,
                      left: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .62),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          widget.isVideo ? 'VIDEO' : 'IMAGE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .5,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 1,
                      right: 1,
                      child: IconButton(
                        tooltip: 'Remove media from document',
                        iconSize: 14,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 25,
                          minHeight: 25,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: .58),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: widget.onRemove,
                        icon: const Icon(Icons.close),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 10,
                      bottom: 10,
                      width: 10,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeLeftRight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onHorizontalDragUpdate: (details) => updateSize(
                            details.delta,
                            horizontal: true,
                            vertical: false,
                          ),
                          onHorizontalDragEnd: (_) =>
                              widget.onResizeEnd(width, height),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 0,
                      height: 10,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeUpDown,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onVerticalDragUpdate: (details) => updateSize(
                            details.delta,
                            horizontal: false,
                            vertical: true,
                          ),
                          onVerticalDragEnd: (_) =>
                              widget.onResizeEnd(width, height),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      width: 16,
                      height: 16,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeUpLeftDownRight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onPanUpdate: (details) => updateSize(
                            details.delta,
                            horizontal: true,
                            vertical: true,
                          ),
                          onPanEnd: (_) => widget.onResizeEnd(width, height),
                          child: Align(
                            alignment: Alignment.bottomRight,
                            child: Icon(
                              Icons.south_east,
                              size: 12,
                              color: muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.object.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class StudioEmbedBuilder extends q.EmbedBuilder {
  StudioEmbedBuilder({
    required this.store,
    required this.project,
    required this.onPreview,
  });

  final StudioStore store;
  final Project project;
  final void Function(CreativeObject) onPreview;

  @override
  String get key => 'studio-object';

  @override
  Widget build(BuildContext context, q.EmbedContext embedContext) {
    final object = project.object(embedContext.node.value.data as String);
    if (object == null) return const Text('Linked object is unavailable');
    final media = object.kind == 'asset';
    final mediaType = object.meta['mediaType'] as String? ?? 'file';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cream,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (media) ...[
            if (mediaType == 'image')
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 200,
                    height: 140,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: line),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        onTap: () => onPreview(object),
                        child: Stack(
                          children: [
                            Center(
                              child: AssetThumbnail(
                                store: store,
                                asset: object,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Material(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => onPreview(object),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.picture_in_picture_alt,
                                          size: 11,
                                          color: Colors.white,
                                        ),
                                        SizedBox(width: 3),
                                        Text(
                                          'Float',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Tag('IMAGE REFERENCE', color: paleSage),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Float in overlay (PIP)',
                              iconSize: 15,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 26,
                                minHeight: 26,
                              ),
                              onPressed: () => onPreview(object),
                              icon: const Icon(Icons.picture_in_picture_alt),
                            ),
                            IconButton(
                              tooltip: 'Remove embed from document',
                              iconSize: 15,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 26,
                                minHeight: 26,
                              ),
                              onPressed: () {
                                final at = embedContext.node.documentOffset;
                                embedContext.controller.replaceText(
                                  at,
                                  1,
                                  '',
                                  TextSelection.collapsed(offset: at),
                                );
                              },
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          object.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          object.body.trim().isNotEmpty
                              ? object.body.trim()
                              : 'Reference asset embedded in your note. Open the original to inspect it.',
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.5,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            else if (mediaType == 'video')
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: ink,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Play video in floating player',
                        iconSize: 48,
                        color: cream,
                        onPressed: () => onPreview(object),
                        icon: const Icon(Icons.play_circle_fill),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Video Attachment · ${object.title}',
                        style: TextStyle(fontSize: 11, color: cream),
                      ),
                    ],
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: paleSage.withValues(alpha: .3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      mediaType == 'audio'
                          ? Icons.audiotrack
                          : Icons.insert_drive_file,
                      color: sage,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        object.title,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (mediaType != 'image') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  media
                      ? (mediaType == 'video'
                            ? Icons.videocam_outlined
                            : Icons.attachment)
                      : Icons.link,
                  size: 15,
                  color: sage,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    object.title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Float in overlay (PIP)',
                  onPressed: () => onPreview(object),
                  icon: const Icon(Icons.picture_in_picture_alt, size: 17),
                ),
                IconButton(
                  tooltip: 'Remove embed from document',
                  onPressed: () {
                    final at = embedContext.node.documentOffset;
                    embedContext.controller.replaceText(
                      at,
                      1,
                      '',
                      TextSelection.collapsed(offset: at),
                    );
                  },
                  icon: const Icon(Icons.close, size: 15),
                ),
              ],
            ),
          ],
          if (!media)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                object.body,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, height: 1.7),
              ),
            ),
        ],
      ),
    );
  }
}

class DividerEmbedBuilder extends q.EmbedBuilder {
  @override
  String get key => 'divider';

  @override
  Widget build(BuildContext context, q.EmbedContext embedContext) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Divider(color: line, thickness: 1.5),
    );
  }
}

class TableEmbedBuilder extends q.EmbedBuilder {
  @override
  String get key => 'table';

  @override
  Widget build(BuildContext context, q.EmbedContext embedContext) {
    final raw = embedContext.node.value.data;
    List<List<String>> rows = [];
    if (raw is String) {
      try {
        final parsed = jsonDecode(raw) as List;
        rows = parsed
            .map((r) => (r as List).map((c) => c.toString()).toList())
            .toList();
      } catch (_) {}
    } else if (raw is List) {
      rows = raw
          .map((r) => (r as List).map((c) => c.toString()).toList())
          .toList();
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    final columns = rows.fold<int>(
      0,
      (count, row) => count > row.length ? count : row.length,
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        border: TableBorder.symmetric(inside: BorderSide(color: line)),
        columnWidths: {
          for (var index = 0; index < columns; index++)
            index: const FlexColumnWidth(),
        },
        children: [
          for (var rowIndex = 0; rowIndex < rows.length; rowIndex++)
            TableRow(
              decoration: BoxDecoration(
                color: rowIndex == 0 ? paleSage.withValues(alpha: .7) : paper,
              ),
              children: [
                for (var colIndex = 0; colIndex < columns; colIndex++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    child: Text(
                      colIndex < rows[rowIndex].length
                          ? rows[rowIndex][colIndex]
                          : '',
                      style: TextStyle(
                        fontSize: 12,
                        color: ink,
                        fontWeight: rowIndex == 0
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class MarkdownImageEmbedBuilder extends q.EmbedBuilder {
  @override
  String get key => 'image';

  @override
  Widget build(BuildContext context, q.EmbedContext embedContext) {
    final src = embedContext.node.value.data?.toString() ?? '';
    if (src.isEmpty) return const SizedBox.shrink();
    final isNetwork = src.startsWith('http://') || src.startsWith('https://');
    Widget img;
    if (isNetwork) {
      img = Image.network(
        src,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _brokenImage(),
      );
    } else {
      img = Image.file(
        File(src),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _brokenImage(),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: img,
        ),
      ),
    );
  }

  Widget _brokenImage() => Container(
    height: 60,
    decoration: BoxDecoration(
      color: sage.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Center(
      child: Icon(Icons.broken_image_outlined, color: muted, size: 22),
    ),
  );
}
