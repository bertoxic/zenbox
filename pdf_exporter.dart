import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:media_kit/media_kit.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;

import 'document_ops.dart';
import 'model.dart';

/// Creates a portable, print-quality representation of a rich Zenbox note.
///
/// Text is written as native PDF text (rather than a screenshot), so it stays
/// sharp at every zoom level. Media embeds use the dimensions stored by the
/// editor; video embeds are represented by a captured frame.
class NotePdfExporter {
  NotePdfExporter({required this.store, required this.project});

  final StudioStore store;
  final Project project;

  Future<Uint8List> build(CreativeObject note) async {
    // Always use the Delta as the source of truth. The plain-text body does
    // not contain Quill image embeds, so choosing a Markdown-only path here
    // used to silently drop images whenever a note also contained Markdown.
    final blocks = _blocksFromDelta(readDocument(note).toDelta().toJson());
    return _RichNotePdfRenderer(this).build(note.title, blocks);
  }

  Future<void> _renderMedia(_PdfCanvas canvas, _MediaEmbed media) async {
    final asset = project.object(media.objectId);
    if (asset == null) {
      canvas.addMediaPlaceholder('Linked media is unavailable', media);
      return;
    }
    final path = store.mediaPath(asset);
    Uint8List? bytes;
    if (asset.meta['mediaType'] == 'video') {
      bytes = await _videoFrame(File(path));
    } else if (asset.meta['mediaType'] == 'image') {
      final file = File(path);
      if (await file.exists()) bytes = await file.readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) {
      canvas.addMediaPlaceholder(
        asset.meta['mediaType'] == 'video'
            ? 'Video thumbnail unavailable\n${asset.title}'
            : 'Image unavailable\n${asset.title}',
        media,
        isVideo: asset.meta['mediaType'] == 'video',
      );
      return;
    }
    try {
      final decoded = image.decodeImage(bytes);
      if (decoded == null) throw const FormatException('Unsupported image');
      final baked = image.bakeOrientation(decoded);
      final jpeg = Uint8List.fromList(image.encodeJpg(baked, quality: 96));
      canvas.addImage(
        _PdfImage(jpeg: jpeg, width: baked.width, height: baked.height),
        media,
        isVideo: asset.meta['mediaType'] == 'video',
        caption: asset.meta['mediaType'] == 'video' ? asset.title : null,
      );
    } catch (_) {
      canvas.addMediaPlaceholder(
        'Media could not be decoded\n${asset.title}',
        media,
      );
    }
  }

  Future<Uint8List?> _videoFrame(File file) async {
    if (!await file.exists()) return null;
    final player = Player();
    try {
      await player.open(Media(file.path), play: false);
      // Seeking avoids a black first frame in many common video encodings.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await player.seek(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      return await player.screenshot(format: 'image/jpeg');
    } catch (_) {
      return null;
    } finally {
      await player.dispose();
    }
  }

  List<_ExportBlock> _blocksFromDelta(List<dynamic> delta) {
    final result = <_ExportBlock>[];
    final spans = <_TextSpan>[];

    void flush(Map<String, dynamic> lineAttributes) {
      if (spans.isNotEmpty || lineAttributes.isNotEmpty) {
        result.add(
          _ExportBlock(
            spans: List<_TextSpan>.from(spans),
            lineAttributes: lineAttributes,
          ),
        );
      }
      spans.clear();
    }

    for (final raw in delta) {
      if (raw is! Map) continue;
      final op = Map<String, dynamic>.from(raw);
      final attributes = Map<String, dynamic>.from(
        op['attributes'] as Map? ?? {},
      );
      final insert = op['insert'];
      if (insert is String) {
        final chunks = insert.split('\n');
        for (var i = 0; i < chunks.length; i++) {
          if (chunks[i].isNotEmpty) {
            spans.add(
              _TextSpan(chunks[i], Map<String, dynamic>.from(attributes)),
            );
          }
          if (i < chunks.length - 1) flush(attributes);
        }
      } else if (insert is Map) {
        final embed = Map<String, dynamic>.from(insert);
        final key = embed.isEmpty ? null : embed.keys.first;
        if (key == 'studio-image' || key == 'studio-video') {
          flush(const {});
          result.add(_ExportBlock(media: _MediaEmbed.parse(embed[key])));
        } else if (key == 'divider' || key == 'horizontal-rule') {
          flush(const {});
          result.add(const _ExportBlock());
        } else if (key == 'table') {
          flush(const {});
          final raw = embed[key];
          List<List<String>> tableRows = [];
          if (raw is String) {
            try {
              final parsed = jsonDecode(raw) as List;
              tableRows = parsed
                  .map((row) => (row as List).map((c) => c.toString()).toList())
                  .toList();
            } catch (_) {}
          } else if (raw is List) {
            tableRows = raw
                .map((row) => (row as List).map((c) => c.toString()).toList())
                .toList();
          }
          if (tableRows.isNotEmpty) {
            result.add(_ExportBlock(table: tableRows));
          }
        }
      }
    }
    flush(const {});
    return _renderMarkdownWithinDelta(result);
  }

  List<_ExportBlock> _renderMarkdownWithinDelta(List<_ExportBlock> blocks) {
    final rendered = <_ExportBlock>[];
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      if (!_isPlainTextBlock(block)) {
        rendered.add(block);
        continue;
      }
      final text = block.spans.map((span) => span.text).join();
      if (index + 1 < blocks.length &&
          text.trim().contains('|') &&
          _isPlainTextBlock(blocks[index + 1]) &&
          _isTableDelimiter(
            blocks[index + 1].spans.map((span) => span.text).join().trim(),
          )) {
        final rows = <List<String>>[_tableCells(text.trim())];
        index += 2;
        while (index < blocks.length && _isPlainTextBlock(blocks[index])) {
          final row = blocks[index].spans.map((span) => span.text).join();
          if (!row.contains('|')) break;
          rows.add(_tableCells(row.trim()));
          index++;
        }
        index--;
        rendered.add(_ExportBlock(table: rows));
        continue;
      }
      if (_looksLikeMarkdown(text)) {
        rendered.addAll(_blocksFromMarkdown(text));
      } else {
        rendered.add(block);
      }
    }
    return rendered;
  }

  bool _isPlainTextBlock(_ExportBlock block) =>
      block.media == null &&
      block.table == null &&
      block.lineAttributes.isEmpty &&
      block.spans.isNotEmpty &&
      block.spans.every((span) => span.attributes.isEmpty);

  bool _looksLikeMarkdown(String text) => RegExp(
    r'^(#{1,6}\s+|>\s+|[-*+]\s+|\d+[.)]\s+)|\*\*[^*]+\*\*|__[^_]+__|~~[^~]+~~|^\s*\|.*\|\s*$',
    multiLine: true,
  ).hasMatch(text);

  List<_ExportBlock> _blocksFromMarkdown(String markdown) {
    final lines = markdown.replaceAll('\r\n', '\n').split('\n');
    final blocks = <_ExportBlock>[];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trimRight();
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        blocks.add(const _ExportBlock());
        continue;
      }
      // A standard Markdown table has a pipe-separated header followed by a
      // delimiter row. It is emitted as cells, never as literal pipes.
      if (index + 1 < lines.length &&
          trimmed.contains('|') &&
          _isTableDelimiter(lines[index + 1].trim())) {
        final rows = <List<String>>[_tableCells(trimmed)];
        index += 2;
        while (index < lines.length && lines[index].contains('|')) {
          rows.add(_tableCells(lines[index].trim()));
          index++;
        }
        index--;
        blocks.add(_ExportBlock(table: rows));
        continue;
      }
      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      final quote = trimmed.startsWith('> ');
      final list = RegExp(
        r'^(?:([-*+])\s+|(\d+)[.)]\s+)(.*)$',
      ).firstMatch(trimmed);
      final text = heading != null
          ? heading.group(2)!
          : quote
          ? trimmed.substring(2)
          : list != null
          ? list.group(3)!
          : trimmed;
      blocks.add(
        _ExportBlock(
          spans: _markdownSpans(text),
          lineAttributes: {
            if (heading != null) 'heading': heading.group(1)!.length,
            if (quote) 'blockquote': true,
            if (list != null)
              'list': list.group(1) == null ? 'ordered' : 'bullet',
          },
        ),
      );
    }
    return blocks;
  }

  bool _isTableDelimiter(String line) =>
      RegExp(r'^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$').hasMatch(line);

  List<String> _tableCells(String line) {
    var value = line.trim();
    if (value.startsWith('|')) value = value.substring(1);
    if (value.endsWith('|')) value = value.substring(0, value.length - 1);
    return value.split('|').map((cell) => cell.trim()).toList();
  }

  List<_TextSpan> _markdownSpans(String text) {
    final result = <_TextSpan>[];
    final pattern = RegExp(
      r'(\*\*.+?\*\*|__.+?__|~~.+?~~|`.+?`|\*.+?\*|_.+?_)',
    );
    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        result.add(_TextSpan(text.substring(cursor, match.start), const {}));
      }
      final token = match.group(0)!;
      if (token.startsWith('**')) {
        result.add(
          _TextSpan(token.substring(2, token.length - 2), const {'bold': true}),
        );
      } else if (token.startsWith('__')) {
        result.add(
          _TextSpan(token.substring(2, token.length - 2), const {
            'underline': true,
          }),
        );
      } else if (token.startsWith('~~')) {
        result.add(
          _TextSpan(token.substring(2, token.length - 2), const {
            'strike': true,
          }),
        );
      } else if (token.startsWith('*') || token.startsWith('_')) {
        result.add(
          _TextSpan(token.substring(1, token.length - 1), const {
            'italic': true,
          }),
        );
      } else {
        result.add(_TextSpan(token.substring(1, token.length - 1), const {}));
      }
      cursor = match.end;
    }
    if (cursor < text.length)
      result.add(_TextSpan(text.substring(cursor), const {}));
    return result;
  }
}

/// Uses the PDF package's layout engine rather than manually estimating glyph
/// widths. The previous handwritten writer could only encode ASCII and used a
/// fixed character-width heuristic, which turned bullets into question marks
/// and made adjacent styled spans overlap.
class _RichNotePdfRenderer {
  _RichNotePdfRenderer(this.source);

  final NotePdfExporter source;

  static const _ink = pdf.PdfColor.fromInt(0xff243023);
  static const _title = pdf.PdfColor.fromInt(0xff1c321a);
  static const _accent = pdf.PdfColor.fromInt(0xff42562e);
  static const _muted = pdf.PdfColor.fromInt(0xff586252);
  static const _rule = pdf.PdfColor.fromInt(0xff94a68c);
  static const _headerFill = pdf.PdfColor.fromInt(0xffd6e3cc);
  static const _placeholderFill = pdf.PdfColor.fromInt(0xffe6ebe2);

  Future<Uint8List> build(String title, List<_ExportBlock> blocks) async {
    final fonts = await _EmbeddedNoteFonts.load();
    final content = <pw.Widget>[
      pw.Text(
        title.trim().isEmpty ? 'Untitled note' : title,
        style: fonts.style(22, bold: true, color: _title),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8, bottom: 15),
        child: pw.Container(height: .7, color: _accent),
      ),
    ];

    var orderedList = 0;
    for (final block in blocks) {
      if (block.media != null) {
        content.add(await _media(block.media!, fonts));
        content.add(pw.SizedBox(height: 9));
      } else if (block.table != null) {
        content.add(_table(block.table!, fonts));
        content.add(pw.SizedBox(height: 10));
      } else if (block.spans.isNotEmpty || block.lineAttributes.isNotEmpty) {
        final list = block.lineAttributes['list']?.toString();
        final prefix = switch (list) {
          'bullet' => '• ',
          'ordered' => '${++orderedList}. ',
          'unchecked' => '[ ] ',
          'checked' => '[x] ',
          _ => '',
        };
        if (list == null) orderedList = 0;
        content.add(_paragraph(block, fonts, prefix));
      } else {
        content.add(pw.SizedBox(height: 7));
      }
    }

    final document = pw.Document(title: title, author: 'Zenbox');
    document.addPage(
      pw.MultiPage(
        pageFormat: pdf.PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(54, 58, 54, 56),
        build: (_) => content,
      ),
    );
    return document.save();
  }

  pw.Widget _paragraph(
    _ExportBlock block,
    _EmbeddedNoteFonts fonts,
    String prefix,
  ) {
    final heading = (block.lineAttributes['header'] as num? ??
            block.lineAttributes['heading'] as num?)
        ?.toInt();
    final quote = block.lineAttributes.containsKey('blockquote');
    final indent = (block.lineAttributes['indent'] as num?)?.toInt() ?? 0;
    final size = heading == null
        ? 11.5
        : (24 - (heading - 1) * 2.2).clamp(13.0, 24.0).toDouble();
    final isHeading = heading != null;
    final children = <pw.InlineSpan>[
      if (prefix.isNotEmpty)
        pw.TextSpan(
          text: prefix,
          style: fonts.style(size, color: _accent, bold: isHeading),
        ),
      ...block.spans.map(
        (span) => pw.TextSpan(
          text: span.text,
          style: _spanStyle(span.attributes, fonts, size, isHeading),
        ),
      ),
    ];
    pw.Widget result = pw.RichText(text: pw.TextSpan(children: children));
    if (quote) {
      result = pw.Container(
        decoration: const pw.BoxDecoration(
          border: pw.Border(left: pw.BorderSide(color: _accent, width: 2)),
        ),
        padding: const pw.EdgeInsets.only(left: 12),
        child: result,
      );
    }
    return pw.Padding(
      padding: pw.EdgeInsets.only(
        left: indent * 18,
        bottom: heading == null ? 6 : 11,
      ),
      child: result,
    );
  }

  pw.Widget _table(List<List<String>> rows, _EmbeddedNoteFonts fonts) {
    if (rows.isEmpty) return pw.SizedBox();
    final columns = rows.fold<int>(
      0,
      (count, row) => count > row.length ? count : row.length,
    );
    if (columns == 0) return pw.SizedBox();
    return pw.Table(
      border: pw.TableBorder.all(color: _rule, width: .5),
      children: [
        for (var rowIndex = 0; rowIndex < rows.length; rowIndex++)
          pw.TableRow(
            repeat: rowIndex == 0,
            decoration: rowIndex == 0
                ? const pw.BoxDecoration(color: _headerFill)
                : null,
            verticalAlignment: pw.TableCellVerticalAlignment.top,
            children: [
              for (var column = 0; column < columns; column++)
                pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.RichText(
                    text: pw.TextSpan(
                      children: _inlineMarkdown(
                        column < rows[rowIndex].length
                            ? rows[rowIndex][column]
                            : '',
                        fonts,
                        9.5,
                        bold: rowIndex == 0,
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Future<pw.Widget> _media(_MediaEmbed embed, _EmbeddedNoteFonts fonts) async {
    final asset = source.project.object(embed.objectId);
    final size = _mediaSize(embed);
    if (asset == null) {
      return _mediaPlaceholder('Linked media is unavailable', size, fonts);
    }

    Uint8List? bytes;
    final isVideo = asset.meta['mediaType'] == 'video';
    final file = File(source.store.mediaPath(asset));
    if (isVideo) {
      bytes = await source._videoFrame(file);
    } else if (asset.meta['mediaType'] == 'image' && await file.exists()) {
      bytes = await file.readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) {
      final label = isVideo
          ? 'Video thumbnail unavailable\n${asset.title}'
          : 'Image unavailable\n${asset.title}';
      return _mediaPlaceholder(label, size, fonts);
    }

    try {
      final decoded = image.decodeImage(bytes);
      if (decoded == null) throw const FormatException('Unsupported image');
      final baked = image.bakeOrientation(decoded);
      final jpeg = Uint8List.fromList(image.encodeJpg(baked, quality: 96));
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: size.$1,
            height: size.$2,
            child: pw.Image(pw.MemoryImage(jpeg), fit: pw.BoxFit.contain),
          ),
          if (isVideo)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(
                'Video · ${asset.title}',
                style: fonts.style(9, italic: true, color: _muted),
              ),
            ),
        ],
      );
    } catch (_) {
      return _mediaPlaceholder(
        'Media could not be decoded\n${asset.title}',
        size,
        fonts,
      );
    }
  }

  pw.Widget _mediaPlaceholder(
    String label,
    (double, double) size,
    _EmbeddedNoteFonts fonts,
  ) => pw.Container(
    width: size.$1,
    height: size.$2,
    alignment: pw.Alignment.center,
    decoration: const pw.BoxDecoration(
      color: _placeholderFill,
      border: pw.Border.fromBorderSide(pw.BorderSide(color: _rule)),
    ),
    padding: const pw.EdgeInsets.all(16),
    child: pw.Text(
      label,
      textAlign: pw.TextAlign.center,
      style: fonts.style(10, color: _muted),
    ),
  );

  (double, double) _mediaSize(_MediaEmbed embed) {
    const maxWidth = 487.28;
    final requestedWidth = embed.width.clamp(72, 480).toDouble() * .75;
    final requestedHeight = embed.height.clamp(54, 360).toDouble() * .75;
    final width = requestedWidth.clamp(72, maxWidth).toDouble();
    return (width, requestedHeight * (width / requestedWidth));
  }

  List<pw.InlineSpan> _inlineMarkdown(
    String value,
    _EmbeddedNoteFonts fonts,
    double size, {
    bool bold = false,
  }) => source
      ._markdownSpans(value)
      .map(
        (span) => pw.TextSpan(
          text: span.text,
          style: _spanStyle(span.attributes, fonts, size, bold),
        ),
      )
      .toList();

  pw.TextStyle _spanStyle(
    Map<String, dynamic> attributes,
    _EmbeddedNoteFonts fonts,
    double size,
    bool heading,
  ) {
    final bold = attributes.containsKey('bold') || heading;
    final italic = attributes.containsKey('italic');
    final decorations = <pw.TextDecoration>[
      if (attributes.containsKey('underline')) pw.TextDecoration.underline,
      if (attributes.containsKey('strike')) pw.TextDecoration.lineThrough,
    ];
    return fonts.style(
      size,
      bold: bold,
      italic: italic,
      color: _color(attributes['color']?.toString()) ?? _ink,
      decoration: decorations.isEmpty
          ? null
          : pw.TextDecoration.combine(decorations),
    );
  }

  pdf.PdfColor? _color(String? value) {
    final parsed = _PdfColor.parse(value);
    if (parsed == null) return null;
    return pdf.PdfColor.fromInt(
      0xff000000 | (parsed.red << 16) | (parsed.green << 8) | parsed.blue,
    );
  }
}

class _EmbeddedNoteFonts {
  const _EmbeddedNoteFonts({
    required this.regular,
    required this.bold,
    required this.italic,
    required this.boldItalic,
  });

  final pw.Font regular;
  final pw.Font bold;
  final pw.Font italic;
  final pw.Font boldItalic;

  static Future<_EmbeddedNoteFonts> load() async {
    Future<pw.Font> read(String path, pw.Font fallback) async {
      final file = File(path);
      if (!await file.exists()) return fallback;
      return pw.Font.ttf(ByteData.sublistView(await file.readAsBytes()));
    }

    // Zenbox uses the Windows system UI face. Embedding its four faces gives
    // PDF viewers the same metrics and Unicode coverage as the note editor.
    final regular = await read(
      r'C:\Windows\Fonts\segoeui.ttf',
      pw.Font.helvetica(),
    );
    final bold = await read(r'C:\Windows\Fonts\segoeuib.ttf', regular);
    final italic = await read(r'C:\Windows\Fonts\segoeuii.ttf', regular);
    final boldItalic = await read(r'C:\Windows\Fonts\segoeuiz.ttf', bold);
    return _EmbeddedNoteFonts(
      regular: regular,
      bold: bold,
      italic: italic,
      boldItalic: boldItalic,
    );
  }

  pw.TextStyle style(
    double size, {
    bool bold = false,
    bool italic = false,
    pdf.PdfColor? color,
    pw.TextDecoration? decoration,
  }) => pw.TextStyle(
    font: bold && italic
        ? boldItalic
        : bold
        ? this.bold
        : italic
        ? this.italic
        : regular,
    fontSize: size,
    color: color,
    decoration: decoration,
  );
}

class _TextSpan {
  const _TextSpan(this.text, this.attributes);
  final String text;
  final Map<String, dynamic> attributes;
}

class _ExportBlock {
  const _ExportBlock({
    this.spans = const [],
    this.lineAttributes = const {},
    this.media,
    this.table,
  });
  final List<_TextSpan> spans;
  final Map<String, dynamic> lineAttributes;
  final _MediaEmbed? media;
  final List<List<String>>? table;
}

class _MediaEmbed {
  const _MediaEmbed({
    required this.objectId,
    required this.width,
    required this.height,
  });
  final String objectId;
  final double width;
  final double height;

  factory _MediaEmbed.parse(Object? value) {
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          return _MediaEmbed(
            objectId: decoded['id']?.toString() ?? '',
            width: (decoded['width'] as num?)?.toDouble() ?? 188,
            height: (decoded['height'] as num?)?.toDouble() ?? 112,
          );
        }
      } on FormatException {
        // Old embeds stored only the object id.
      }
      return _MediaEmbed(objectId: value, width: 188, height: 112);
    }
    return const _MediaEmbed(objectId: '', width: 188, height: 112);
  }
}

class _PdfImage {
  const _PdfImage({
    required this.jpeg,
    required this.width,
    required this.height,
  });
  final Uint8List jpeg;
  final int width;
  final int height;
}

class _PdfCanvas {
  _PdfCanvas(this.writer) {
    _newPage();
  }

  static const pageWidth = 595.28;
  static const pageHeight = 841.89;
  static const left = 54.0;
  static const right = 54.0;
  static const top = 58.0;
  static const bottom = 56.0;
  final _PdfWriter writer;
  final List<StringBuffer> _pages = [];
  late StringBuffer _page;
  double _y = pageHeight - top;
  int _imageNumber = 0;
  int _orderedList = 0;

  void _newPage() {
    _page = StringBuffer();
    _pages.add(_page);
    _y = pageHeight - top;
    _orderedList = 0;
  }

  void _need(double height) {
    if (_y - height < bottom) _newPage();
  }

  void addTitle(String title) {
    final lines = _wrapPlain(title, 22, pageWidth - left - right);
    _need(lines.length * 28 + 18);
    for (final line in lines) {
      _text(
        left,
        _y,
        line,
        font: 'F2',
        size: 22,
        color: const _PdfColor(28, 50, 26),
      );
      _y -= 28;
    }
    _page.write(
      '0.26 0.34 0.18 RG 0.7 w $left ${_y + 8} m ${pageWidth - right} ${_y + 8} l S\n',
    );
    _y -= 18;
  }

  void addParagraph(_ExportBlock block) {
    final heading = (block.lineAttributes['header'] as num? ??
            block.lineAttributes['heading'] as num?)
        ?.toInt();
    final list = block.lineAttributes['list']?.toString();
    final quote = block.lineAttributes.containsKey('blockquote');
    final indent = (block.lineAttributes['indent'] as num?)?.toInt() ?? 0;
    final fontSize = heading == null
        ? 11.5
        : (24 - (heading - 1) * 2.2).clamp(13.0, 24.0).toDouble();
    final lineHeight = heading == null ? 17.5 : fontSize * 1.35;
    final extraIndent = quote ? 16.0 : indent * 18.0;
    final prefix = switch (list) {
      'bullet' => '• ',
      'ordered' => '${++_orderedList}. ',
      'unchecked' => '[ ] ',
      'checked' => '[x] ',
      _ => '',
    };
    if (list == null) _orderedList = 0;
    final lines = _wrapSpans(
      block.spans,
      fontSize,
      pageWidth - left - right - extraIndent - (prefix.isEmpty ? 0 : 18),
    );
    if (lines.isEmpty) {
      _y -= lineHeight * .55;
      return;
    }
    _need(lines.length * lineHeight + (heading == null ? 4 : 12));
    if (quote) {
      _page.write(
        '0.26 0.34 0.18 RG 2 w ${left + 2} ${_y + 4} m ${left + 2} ${_y - lines.length * lineHeight + 5} l S\n',
      );
    }
    for (var i = 0; i < lines.length; i++) {
      if (_y - lineHeight < bottom) _newPage();
      var x = left + extraIndent;
      if (i == 0 && prefix.isNotEmpty) {
        _text(
          x,
          _y,
          prefix,
          font: 'F1',
          size: fontSize,
          color: const _PdfColor(66, 86, 46),
        );
        x += 18;
      }
      for (final span in lines[i]) {
        final style = _styleFor(span.attributes, fontSize, heading != null);
        _text(
          x,
          _y,
          span.text,
          font: style.font,
          size: style.size,
          color: style.color,
          underline: style.underline,
          strike: style.strike,
        );
        x += _measure(span.text, style.size);
      }
      _y -= lineHeight;
    }
    _y -= heading == null ? 4 : 9;
  }

  void addTable(List<List<String>> rows) {
    if (rows.isEmpty) return;
    final columnCount = rows.fold<int>(
      0,
      (count, row) => count > row.length ? count : row.length,
    );
    if (columnCount == 0) return;
    const cellPadding = 5.0;
    final tableWidth = pageWidth - left - right;
    final columnWidth = tableWidth / columnCount;
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      final wrapped = <List<String>>[];
      var lineCount = 1;
      for (var column = 0; column < columnCount; column++) {
        final lines = _wrapPlain(
          column < row.length ? row[column] : '',
          9.5,
          columnWidth - cellPadding * 2,
        );
        wrapped.add(lines);
        if (lines.length > lineCount) lineCount = lines.length;
      }
      final rowHeight = lineCount * 12.5 + cellPadding * 2;
      _need(rowHeight + 2);
      final bottomY = _y - rowHeight;
      for (var column = 0; column < columnCount; column++) {
        final x = left + column * columnWidth;
        if (rowIndex == 0) {
          _page.write(
            '0.84 0.89 0.80 rg $x $bottomY $columnWidth $rowHeight re f\n',
          );
        }
        _page.write(
          '0.58 0.65 0.55 RG 0.45 w $x $bottomY $columnWidth $rowHeight re S\n',
        );
        var textY = _y - cellPadding - 9.5;
        for (final text in wrapped[column]) {
          _text(
            x + cellPadding,
            textY,
            text,
            font: rowIndex == 0 ? 'F2' : 'F1',
            size: 9.5,
            color: const _PdfColor(36, 48, 35),
          );
          textY -= 12.5;
        }
      }
      _y = bottomY - 2;
    }
    _y -= 6;
  }

  void addImage(
    _PdfImage image,
    _MediaEmbed embed, {
    required bool isVideo,
    String? caption,
  }) {
    final target = _mediaSize(embed);
    final captionHeight = caption == null ? 0.0 : 17.0;
    _need(target.$2 + captionHeight + 14);
    final name = 'Im${_imageNumber++}';
    writer.addImage(name, image);
    _page.write(
      'q ${target.$1.toStringAsFixed(2)} 0 0 ${target.$2.toStringAsFixed(2)} $left ${(_y - target.$2).toStringAsFixed(2)} cm /$name Do Q\n',
    );
    if (isVideo) {
      final centerX = left + target.$1 / 2;
      final centerY = _y - target.$2 / 2;
      _page.write(
        '0 0 0 rg 0.55 g ${centerX - 17} ${centerY - 17} 34 34 re f\n1 1 1 rg ${centerX - 4} ${centerY - 8} m ${centerX - 4} ${centerY + 8} l ${centerX + 10} $centerY l h f\n',
      );
    }
    _y -= target.$2 + 5;
    if (caption != null) {
      _text(
        left,
        _y,
        'Video · $caption',
        font: 'F3',
        size: 9,
        color: const _PdfColor(88, 98, 82),
      );
      _y -= captionHeight;
    }
    _y -= 9;
  }

  void addMediaPlaceholder(
    String text,
    _MediaEmbed embed, {
    bool isVideo = false,
  }) {
    final target = _mediaSize(embed);
    _need(target.$2 + 14);
    _page.write(
      '0.90 0.92 0.87 rg $left ${_y - target.$2} ${target.$1} ${target.$2} re f\n0.38 0.45 0.34 RG 1 w $left ${_y - target.$2} ${target.$1} ${target.$2} re S\n',
    );
    final icon = isVideo ? '▶' : '▧';
    _text(
      left + 16,
      _y - 28,
      icon,
      font: 'F1',
      size: 17,
      color: const _PdfColor(66, 86, 46),
    );
    var labelY = _y - 50;
    for (final line in text.split('\n')) {
      _text(
        left + 16,
        labelY,
        line,
        font: 'F1',
        size: 10,
        color: const _PdfColor(55, 67, 50),
      );
      labelY -= 14;
    }
    _y -= target.$2 + 14;
  }

  (double, double) _mediaSize(_MediaEmbed embed) {
    final maxWidth = pageWidth - left - right;
    final requestedWidth = embed.width.clamp(72, 480).toDouble() * .75;
    final requestedHeight = embed.height.clamp(54, 360).toDouble() * .75;
    final width = requestedWidth.clamp(72, maxWidth).toDouble();
    final height = requestedHeight * (width / requestedWidth);
    return (width, height);
  }

  void _text(
    double x,
    double y,
    String value, {
    required String font,
    required double size,
    required _PdfColor color,
    bool underline = false,
    bool strike = false,
  }) {
    if (value.isEmpty) return;
    final escaped = _escape(value);
    _page.write(
      'BT /$font ${size.toStringAsFixed(2)} Tf ${color.pdf} rg $x ${y.toStringAsFixed(2)} Td ($escaped) Tj ET\n',
    );
    if (underline) {
      final width = _measure(value, size);
      _page.write(
        '${color.pdf} RG 0.55 w $x ${(y - 1.5).toStringAsFixed(2)} m ${(x + width).toStringAsFixed(2)} ${(y - 1.5).toStringAsFixed(2)} l S\n',
      );
    }
    if (strike) {
      final width = _measure(value, size);
      final strikeY = y + size * .28;
      _page.write(
        '${color.pdf} RG 0.55 w $x ${strikeY.toStringAsFixed(2)} m ${(x + width).toStringAsFixed(2)} ${strikeY.toStringAsFixed(2)} l S\n',
      );
    }
  }

  List<List<_TextSpan>> _wrapSpans(
    List<_TextSpan> spans,
    double fontSize,
    double maxWidth,
  ) {
    final lines = <List<_TextSpan>>[[]];
    var used = 0.0;
    for (final span in spans) {
      for (final word in RegExp(r'\s+|[^\s]+').allMatches(span.text)) {
        final piece = word.group(0)!;
        final style = _styleFor(span.attributes, fontSize, false);
        final width = _measure(piece, style.size);
        if (used > 0 && used + width > maxWidth && piece.trim().isNotEmpty) {
          lines.add([]);
          used = 0;
        }
        if (!(used == 0 && piece.trim().isEmpty)) {
          lines.last.add(_TextSpan(piece, span.attributes));
          used += width;
        }
      }
    }
    return lines.where((line) => line.isNotEmpty).toList();
  }

  List<String> _wrapPlain(String value, double size, double maxWidth) {
    final out = <String>[];
    var current = '';
    for (final word in value.split(RegExp(r'\s+'))) {
      final candidate = current.isEmpty ? word : '$current $word';
      if (current.isNotEmpty && _measure(candidate, size) > maxWidth) {
        out.add(current);
        current = word;
      } else {
        current = candidate;
      }
    }
    if (current.isNotEmpty) out.add(current);
    return out.isEmpty ? ['Untitled note'] : out;
  }

  _TextStyle _styleFor(
    Map<String, dynamic> attributes,
    double base,
    bool heading,
  ) {
    final bold = attributes.containsKey('bold') || heading;
    final italic = attributes.containsKey('italic');
    final font = bold && italic
        ? 'F4'
        : bold
        ? 'F2'
        : italic
        ? 'F3'
        : 'F1';
    return _TextStyle(
      font: font,
      size: base,
      color:
          _PdfColor.parse(attributes['color']?.toString()) ??
          const _PdfColor(36, 48, 35),
      underline: attributes.containsKey('underline'),
      strike: attributes.containsKey('strike'),
    );
  }

  double _measure(String text, double size) {
    var units = 0.0;
    for (final char in text.codeUnits) {
      if (char == 32) {
        units += .28;
      } else if ('ilI.,:;!|'.codeUnits.contains(char)) {
        units += .28;
      } else if ('MW@#%'.codeUnits.contains(char)) {
        units += .84;
      } else {
        units += .53;
      }
    }
    return units * size;
  }

  String _escape(String value) => value
      .replaceAll('\\', r'\\')
      .replaceAll('(', r'\(')
      .replaceAll(')', r'\)')
      .replaceAll(RegExp(r'[^\x20-\x7E]'), '?');

  Uint8List finish() =>
      writer.finish(_pages.map((page) => page.toString()).toList());
}

class _TextStyle {
  const _TextStyle({
    required this.font,
    required this.size,
    required this.color,
    required this.underline,
    required this.strike,
  });
  final String font;
  final double size;
  final _PdfColor color;
  final bool underline;
  final bool strike;
}

class _PdfColor {
  const _PdfColor(this.red, this.green, this.blue);
  final int red;
  final int green;
  final int blue;
  String get pdf =>
      '${(red / 255).toStringAsFixed(3)} ${(green / 255).toStringAsFixed(3)} ${(blue / 255).toStringAsFixed(3)}';

  static _PdfColor? parse(String? value) {
    if (value == null) return null;
    final hex = value.replaceAll('#', '');
    if (hex.length != 6) return null;
    try {
      return _PdfColor(
        int.parse(hex.substring(0, 2), radix: 16),
        int.parse(hex.substring(2, 4), radix: 16),
        int.parse(hex.substring(4, 6), radix: 16),
      );
    } on FormatException {
      return null;
    }
  }
}

class _PdfWriter {
  _PdfWriter({required this.title});
  final String title;
  final List<Uint8List> _objects = [];
  final Map<String, int> _images = {};

  void addImage(String name, _PdfImage image) {
    if (_images.containsKey(name)) return;
    _images[name] = _addStream(
      '<< /Type /XObject /Subtype /Image /Width ${image.width} /Height ${image.height} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode',
      image.jpeg,
    );
  }

  Uint8List finish(List<String> pages) {
    final contentIds = pages
        .map(
          (page) => _addStream('<<', Uint8List.fromList(latin1.encode(page))),
        )
        .toList();
    final pagesId = _objects.length + pages.length + 1;
    final imageResources = _images.entries
        .map((entry) => '/${entry.key} ${entry.value} 0 R')
        .join(' ');
    for (final contentId in contentIds) {
      _addObject(
        '<< /Type /Page /Parent $pagesId 0 R /MediaBox [0 0 ${_PdfCanvas.pageWidth} ${_PdfCanvas.pageHeight}] /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> /F2 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >> /F3 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Oblique >> /F4 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica-BoldOblique >> >> /XObject << $imageResources >> >> /Contents $contentId 0 R >>',
      );
    }
    _addObject(
      '<< /Type /Pages /Kids [${List.generate(contentIds.length, (i) => '${_images.length + contentIds.length + i + 1} 0 R').join(' ')}] /Count ${contentIds.length} >>',
    );
    final catalogId = _addObject('<< /Type /Catalog /Pages $pagesId 0 R >>');
    final infoId = _addObject(
      '<< /Title (${_escape(title)}) /Producer (Zenbox) >>',
    );
    return _assemble(catalogId, infoId);
  }

  int _addObject(String value) {
    _objects.add(Uint8List.fromList(latin1.encode('$value\n')));
    return _objects.length;
  }

  int _addStream(String dictionaryStart, Uint8List bytes) {
    final prefix = '$dictionaryStart /Length ${bytes.length} >>\nstream\n';
    final suffix = Uint8List.fromList(latin1.encode('\nendstream\n'));
    _objects.add(
      Uint8List.fromList([...latin1.encode(prefix), ...bytes, ...suffix]),
    );
    return _objects.length;
  }

  Uint8List _assemble(int catalogId, int infoId) {
    final builder = BytesBuilder();
    builder.add(latin1.encode('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n'));
    final offsets = <int>[0];
    for (var i = 0; i < _objects.length; i++) {
      offsets.add(builder.length);
      builder.add(latin1.encode('${i + 1} 0 obj\n'));
      builder.add(_objects[i]);
      builder.add(latin1.encode('endobj\n'));
    }
    final xref = builder.length;
    builder.add(
      latin1.encode('xref\n0 ${_objects.length + 1}\n0000000000 65535 f \n'),
    );
    for (final offset in offsets.skip(1)) {
      builder.add(
        latin1.encode('${offset.toString().padLeft(10, '0')} 00000 n \n'),
      );
    }
    builder.add(
      latin1.encode(
        'trailer\n<< /Size ${_objects.length + 1} /Root $catalogId 0 R /Info $infoId 0 R >>\nstartxref\n$xref\n%%EOF',
      ),
    );
    return builder.toBytes();
  }

  String _escape(String value) => value
      .replaceAll('\\', r'\\')
      .replaceAll('(', r'\(')
      .replaceAll(')', r'\)')
      .replaceAll(RegExp(r'[^\x20-\x7E]'), '?');
}
