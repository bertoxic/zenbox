import 'dart:convert';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:flutter_quill/quill_delta.dart' as qd;
import 'model.dart';

q.Document readDocument(CreativeObject object) {
  final delta = object.meta['delta'];
  if (delta is List && delta.isNotEmpty) {
    return q.Document.fromJson(List<dynamic>.from(delta));
  }
  if (object.body.trim().isNotEmpty) {
    return q.Document.fromDelta(markdownToDelta(object.body));
  }
  return q.Document();
}

void storeDocument(CreativeObject object, q.Document document) {
  object.meta['delta'] = document.toDelta().toJson();
  object.body = deltaToMarkdown(document.toDelta());
}

void replaceRange(
  CreativeObject object,
  int start,
  int end,
  String text, {
  String? expected,
}) {
  final doc = readDocument(object);
  final plain = doc.toPlainText();
  if (start < 0 || end < start || end > doc.length - 1) {
    throw const FormatException(
      'The selected range no longer exists. Select the text again.',
    );
  }
  if (expected != null && plain.substring(start, end) != expected) {
    throw const FormatException(
      'The selected text has changed. Select it again before applying this response.',
    );
  }
  doc.replace(start, end - start, markdownToDelta(text));
  storeDocument(object, doc);
}

/// Converts Markdown into Quill's native Delta format.
/// Supports headings, bold, italic, strikethrough, inline code, underline,
/// links, bullet/ordered lists, checklists, nested indentation, blockquotes,
/// fenced code blocks, horizontal dividers, images, and tables.
qd.Delta markdownToDelta(String markdown) {
  final delta = qd.Delta();
  final normalized = markdown.replaceAll('\r\n', '\n');
  final lines = normalized.split('\n');
  var inCodeBlock = false;

  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    final rawLine = lines[lineIndex];
    final trimmed = rawLine.trim();

    // Check for fenced code block toggle
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      inCodeBlock = !inCodeBlock;
      continue;
    }

    if (inCodeBlock) {
      delta.insert(rawLine);
      delta.insert('\n', {'code-block': true});
      continue;
    }

    // Check for Markdown table: header row followed by delimiter row
    if (lineIndex + 1 < lines.length &&
        trimmed.contains('|') &&
        _isMarkdownTableDelimiter(lines[lineIndex + 1].trim())) {
      final rows = <List<String>>[_markdownTableCells(trimmed)];
      lineIndex += 2;
      while (lineIndex < lines.length && lines[lineIndex].trim().contains('|')) {
        rows.add(_markdownTableCells(lines[lineIndex].trim()));
        lineIndex++;
      }
      lineIndex--;
      delta.insert({'table': jsonEncode(rows)});
      delta.insert('\n');
      continue;
    }

    // Check for horizontal divider: ---, ***, ___
    if (RegExp(r'^\s*([-*_])\s*(\1\s*){2,}\s*$').hasMatch(rawLine) &&
        !trimmed.contains('|')) {
      delta.insert({'divider': 'hr'});
      delta.insert('\n');
      continue;
    }

    // Check for standalone image: ![alt](url)
    final standaloneImage =
        RegExp(r'^\s*!\[(.*?)\]\((.*?)\)\s*$').firstMatch(trimmed);
    if (standaloneImage != null) {
      delta.insert({'image': standaloneImage.group(2)!});
      delta.insert('\n');
      continue;
    }

    // Parse leading indentation (2 spaces, 4 spaces, or tab per level)
    final leadingSpaces = rawLine.length - rawLine.trimLeft().length;
    final indentLevel = leadingSpaces >= 2 ? (leadingSpaces / 2).floor() : 0;

    final lineAttributes = <String, dynamic>{};
    var text = rawLine;

    final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
    final checklist =
        RegExp(r'^[-*+]\s+\[([ xX])\]\s*(.*)$').firstMatch(trimmed);
    final bullet = RegExp(r'^[-*+]\s+(.*)$').firstMatch(trimmed);
    final ordered = RegExp(r'^\d+[.)]\s+(.*)$').firstMatch(trimmed);
    final quote = RegExp(r'^(>+)\s*(.*)$').firstMatch(trimmed);

    if (heading != null) {
      final level = heading.group(1)!.length;
      text = heading.group(2)!.trim();
      // Strip trailing hashes if present (e.g. ## Heading ##)
      text = text.replaceAll(RegExp(r'\s*#+$'), '');
      lineAttributes['header'] = level;
      lineAttributes['heading'] = level;
    } else if (checklist != null) {
      final isChecked = checklist.group(1)!.toLowerCase() == 'x';
      text = checklist.group(2)!;
      lineAttributes['list'] = isChecked ? 'checked' : 'unchecked';
      if (indentLevel > 0) lineAttributes['indent'] = indentLevel;
    } else if (bullet != null) {
      text = bullet.group(1)!;
      lineAttributes['list'] = 'bullet';
      if (indentLevel > 0) lineAttributes['indent'] = indentLevel;
    } else if (ordered != null) {
      text = ordered.group(1)!;
      lineAttributes['list'] = 'ordered';
      if (indentLevel > 0) lineAttributes['indent'] = indentLevel;
    } else if (quote != null) {
      final quoteDepth = quote.group(1)!.length;
      text = quote.group(2)!;
      lineAttributes['blockquote'] = true;
      if (quoteDepth > 1) lineAttributes['indent'] = quoteDepth - 1;
    }

    _insertMarkdownInline(delta, text);
    delta.insert('\n', lineAttributes.isEmpty ? null : lineAttributes);
  }

  return delta;
}

void _insertMarkdownInline(
  qd.Delta delta,
  String value, [
  Map<String, dynamic> attributes = const {},
]) {
  var plain = StringBuffer();
  void flushPlain() {
    if (plain.isNotEmpty) {
      delta.insert(plain.toString(), attributes.isEmpty ? null : attributes);
      plain = StringBuffer();
    }
  }

  int? formatted(String marker, Map<String, dynamic> style, int index) {
    final end = value.indexOf(marker, index + marker.length);
    if (end < 0) {
      // Unfinished marker: degrade gracefully by treating text as styled
      flushPlain();
      _insertMarkdownInline(delta, value.substring(index + marker.length), {
        ...attributes,
        ...style,
      });
      return value.length;
    }
    flushPlain();
    _insertMarkdownInline(delta, value.substring(index + marker.length, end), {
      ...attributes,
      ...style,
    });
    return end + marker.length;
  }

  var index = 0;
  while (index < value.length) {
    int? nextIndex;

    // Inline image ![alt](url)
    if (value.startsWith('![', index)) {
      final labelEnd = value.indexOf('](', index + 2);
      final urlEnd = labelEnd < 0 ? -1 : value.indexOf(')', labelEnd + 2);
      if (labelEnd >= 0 && urlEnd >= 0) {
        flushPlain();
        final url = value.substring(labelEnd + 2, urlEnd);
        delta.insert({'image': url});
        index = urlEnd + 1;
        continue;
      }
    }

    // Bold + Italic: ***text*** or ___text___
    if (value.startsWith('***', index)) {
      nextIndex = formatted('***', const {'bold': true, 'italic': true}, index);
    } else if (value.startsWith('___', index)) {
      nextIndex = formatted('___', const {'bold': true, 'italic': true}, index);
    }
    // Bold: **text** or __text__
    else if (value.startsWith('**', index)) {
      nextIndex = formatted('**', const {'bold': true}, index);
    } else if (value.startsWith('__', index)) {
      nextIndex = formatted('__', const {'bold': true}, index);
    }
    // Strikethrough: ~~text~~
    else if (value.startsWith('~~', index)) {
      nextIndex = formatted('~~', const {'strike': true}, index);
    }
    // Underline: <u>text</u>
    else if (value.startsWith('<u>', index)) {
      final end = value.indexOf('</u>', index + 3);
      if (end < 0) {
        plain.write('<u>');
        index += 3;
        continue;
      } else {
        flushPlain();
        _insertMarkdownInline(delta, value.substring(index + 3, end), {
          ...attributes,
          'underline': true,
        });
        index = end + 4;
        continue;
      }
    }
    // Inline code: `code`
    else if (value[index] == '`') {
      final end = value.indexOf('`', index + 1);
      if (end < 0) {
        plain.write('`');
        index += 1;
        continue;
      } else {
        flushPlain();
        final codeText = value.substring(index + 1, end);
        delta.insert(codeText, {...attributes, 'code': true});
        index = end + 1;
        continue;
      }
    }
    // Italic: *text* or _text_
    else if (value[index] == '*' || value[index] == '_') {
      final marker = value[index];
      nextIndex = formatted(marker, const {'italic': true}, index);
    }
    // Link: [text](url)
    else if (value[index] == '[') {
      final labelEnd = value.indexOf('](', index + 1);
      final urlEnd = labelEnd < 0 ? -1 : value.indexOf(')', labelEnd + 2);
      if (labelEnd < 0 || urlEnd < 0) {
        plain.write(value[index]);
      } else {
        flushPlain();
        _insertMarkdownInline(delta, value.substring(index + 1, labelEnd), {
          ...attributes,
          'link': value.substring(labelEnd + 2, urlEnd),
        });
        nextIndex = urlEnd + 1;
      }
    } else {
      plain.write(value[index]);
    }
    index = nextIndex ?? index + 1;
  }
  flushPlain();
}

/// Converts a Quill Delta into clean, standard Markdown syntax.
String deltaToMarkdown(qd.Delta delta) {
  final lines = _splitDeltaIntoLines(delta);
  final output = StringBuffer();
  var inCodeBlock = false;
  var orderedCounter = 0;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final lineAttrs = line.lineAttributes;

    // Fenced code blocks
    final isCode = lineAttrs['code-block'] != null;
    if (isCode) {
      if (!inCodeBlock) {
        if (output.isNotEmpty && !output.toString().endsWith('\n\n')) {
          output.writeln();
        }
        output.writeln('```');
        inCodeBlock = true;
      }
      final codeText = line.spans.map((s) => s.plainText).join();
      output.writeln(codeText);
      continue;
    } else if (inCodeBlock) {
      output.writeln('```');
      inCodeBlock = false;
    }

    // Reset ordered counter if leaving ordered list
    final listType = lineAttrs['list']?.toString();
    if (listType != 'ordered') {
      orderedCounter = 0;
    }

    // Check for custom embeds on line
    if (line.spans.length == 1 && line.spans.first.isEmbed) {
      final embed = line.spans.first.embedData!;
      final embedKey = embed.keys.first;

      if (embedKey == 'divider' || embedKey == 'horizontal-rule') {
        if (output.isNotEmpty && !output.toString().endsWith('\n\n')) {
          output.writeln();
        }
        output.writeln('---');
        continue;
      }

      if (embedKey == 'image') {
        final src = embed[embedKey]?.toString() ?? '';
        output.writeln('![]($src)');
        continue;
      }

      if (embedKey == 'studio-image') {
        final raw = embed[embedKey];
        String title = 'Image';
        String path = '';
        if (raw is String) {
          try {
            final parsed = jsonDecode(raw);
            title = parsed['title']?.toString() ?? 'Image';
            path = parsed['id']?.toString() ?? '';
          } catch (_) {
            path = raw;
          }
        }
        output.writeln('![$title]($path)');
        continue;
      }

      if (embedKey == 'table') {
        final raw = embed[embedKey];
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
          if (output.isNotEmpty && !output.toString().endsWith('\n\n')) {
            output.writeln();
          }
          output.write(_formatMarkdownTable(tableRows));
          output.writeln();
          continue;
        }
      }
    }

    // Headings
    final header = (lineAttrs['header'] ?? lineAttrs['heading']) as num?;
    if (header != null && header > 0) {
      final hashes = '#' * header.toInt();
      final content = _formatSpansToMarkdown(line.spans);
      output.writeln('$hashes $content');
      continue;
    }

    // Lists
    if (listType != null) {
      final indent = (lineAttrs['indent'] as num?)?.toInt() ?? 0;
      final indentPrefix = '  ' * indent;
      final content = _formatSpansToMarkdown(line.spans);
      switch (listType) {
        case 'bullet':
          output.writeln('$indentPrefix- $content');
          break;
        case 'ordered':
          orderedCounter++;
          output.writeln('$indentPrefix$orderedCounter. $content');
          break;
        case 'unchecked':
          output.writeln('$indentPrefix- [ ] $content');
          break;
        case 'checked':
          output.writeln('$indentPrefix- [x] $content');
          break;
        default:
          output.writeln('$indentPrefix- $content');
      }
      continue;
    }

    // Blockquote
    if (lineAttrs['blockquote'] == true) {
      final indent = (lineAttrs['indent'] as num?)?.toInt() ?? 0;
      final quotePrefix = '>' * (indent + 1) + ' ';
      final content = _formatSpansToMarkdown(line.spans);
      output.writeln('$quotePrefix$content');
      continue;
    }

    // Normal paragraph or blank line
    final content = _formatSpansToMarkdown(line.spans);
    output.writeln(content);
  }

  if (inCodeBlock) {
    output.writeln('```');
  }

  return output.toString().trimRight();
}

String _formatSpansToMarkdown(List<_DeltaSpan> spans) {
  final merged = _mergeAdjacentSpans(spans);
  final buffer = StringBuffer();

  for (final span in merged) {
    if (span.isEmbed) {
      final embed = span.embedData!;
      final key = embed.keys.first;
      if (key == 'image') {
        buffer.write('![](${embed[key]})');
      }
      continue;
    }

    final text = span.plainText;
    if (text.isEmpty) continue;

    final attrs = span.attributes;
    final isCode = attrs['code'] == true;
    if (isCode) {
      buffer.write('`$text`');
      continue;
    }

    // Extract whitespace to keep markdown markers tight around characters
    final leading = RegExp(r'^\s*').stringMatch(text) ?? '';
    final trailing = RegExp(r'\s*$').stringMatch(text) ?? '';
    final core = text.substring(leading.length, text.length - trailing.length);

    if (core.isEmpty) {
      buffer.write(text);
      continue;
    }

    var formatted = core;

    if (attrs['underline'] == true) {
      formatted = '<u>$formatted</u>';
    }
    if (attrs['strike'] == true) {
      formatted = '~~$formatted~~';
    }
    final isBold = attrs['bold'] == true;
    final isItalic = attrs['italic'] == true;
    if (isBold && isItalic) {
      formatted = '***$formatted***';
    } else if (isBold) {
      formatted = '**$formatted**';
    } else if (isItalic) {
      formatted = '*$formatted*';
    }
    if (attrs['link'] != null) {
      formatted = '[$formatted](${attrs['link']})';
    }

    buffer.write('$leading$formatted$trailing');
  }

  return buffer.toString();
}

List<_DeltaSpan> _mergeAdjacentSpans(List<_DeltaSpan> spans) {
  if (spans.length <= 1) return spans;
  final result = <_DeltaSpan>[];

  for (final span in spans) {
    if (result.isNotEmpty &&
        !span.isEmbed &&
        !result.last.isEmbed &&
        _mapsEqual(span.attributes, result.last.attributes)) {
      final prev = result.removeLast();
      result.add(_DeltaSpan('${prev.plainText}${span.plainText}', prev.attributes));
    } else {
      result.add(span);
    }
  }

  return result;
}

bool _mapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (a[key] != b[key]) return false;
  }
  return true;
}

List<_DeltaLine> _splitDeltaIntoLines(qd.Delta delta) {
  final lines = <_DeltaLine>[];
  var currentLine = _DeltaLine();

  for (final raw in delta.toJson()) {
    final insert = raw['insert'];
    final attributes = Map<String, dynamic>.from(raw['attributes'] as Map? ?? {});

    if (insert is String) {
      final parts = insert.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) {
          currentLine.spans.add(_DeltaSpan(parts[i], attributes));
        }
        if (i < parts.length - 1) {
          currentLine.lineAttributes = Map<String, dynamic>.from(attributes);
          lines.add(currentLine);
          currentLine = _DeltaLine();
        }
      }
    } else if (insert is Map) {
      currentLine.spans.add(
        _DeltaSpan(Map<String, dynamic>.from(insert), attributes),
      );
    }
  }

  if (currentLine.spans.isNotEmpty || currentLine.lineAttributes.isNotEmpty) {
    lines.add(currentLine);
  }

  return lines;
}

class _DeltaLine {
  final List<_DeltaSpan> spans = [];
  Map<String, dynamic> lineAttributes = {};
}

class _DeltaSpan {
  _DeltaSpan(this.data, [Map<String, dynamic>? attrs])
      : attributes = attrs ?? const {};

  final dynamic data;
  final Map<String, dynamic> attributes;

  bool get isEmbed => data is Map;
  Map<String, dynamic>? get embedData => data is Map ? data as Map<String, dynamic> : null;
  String get plainText => data is String ? data as String : '';
}

String _formatMarkdownTable(List<List<String>> rows) {
  if (rows.isEmpty) return '';
  final colCount = rows.fold<int>(0, (max, row) => row.length > max ? row.length : max);
  final buffer = StringBuffer();

  // Header row
  final header = rows.first;
  final headerCells = List.generate(
    colCount,
    (i) => i < header.length ? header[i] : '',
  );
  buffer.writeln('| ${headerCells.join(' | ')} |');

  // Delimiter row
  final delimiters = List.generate(colCount, (_) => '---');
  buffer.writeln('| ${delimiters.join(' | ')} |');

  // Data rows
  for (var r = 1; r < rows.length; r++) {
    final row = rows[r];
    final cells = List.generate(
      colCount,
      (i) => i < row.length ? row[i] : '',
    );
    buffer.writeln('| ${cells.join(' | ')} |');
  }

  return buffer.toString().trimRight();
}

bool _isMarkdownTableDelimiter(String line) =>
    RegExp(r'^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$').hasMatch(line);

List<String> _markdownTableCells(String line) {
  var value = line.trim();
  if (value.startsWith('|')) value = value.substring(1);
  if (value.endsWith('|')) value = value.substring(0, value.length - 1);
  return value.split('|').map((cell) => cell.trim()).toList();
}

void appendText(CreativeObject object, String text) {
  final doc = readDocument(object);
  final newDelta = markdownToDelta(text);
  if (doc.isEmpty() || doc.toPlainText().trim().isEmpty) {
    storeDocument(object, q.Document.fromDelta(newDelta));
    return;
  }
  final docLength = doc.length;
  final insertOffset = docLength > 0 ? docLength - 1 : 0;
  final plain = doc.toPlainText();
  if (insertOffset > 0 && !plain.endsWith('\n\n')) {
    if (!plain.endsWith('\n')) {
      doc.insert(insertOffset, '\n\n');
    } else {
      doc.insert(insertOffset, '\n');
    }
  }
  final updatedOffset = doc.length - 1;
  doc.replace(updatedOffset, 0, newDelta);
  storeDocument(object, doc);
}

void setMarkdownDocument(CreativeObject object, String text) {
  storeDocument(object, q.Document.fromDelta(markdownToDelta(text)));
}

void prependText(CreativeObject object, String text) {
  final doc = readDocument(object);
  final newDelta = markdownToDelta('$text\n');
  if (doc.isEmpty() || doc.toPlainText().trim().isEmpty) {
    storeDocument(object, q.Document.fromDelta(newDelta));
    return;
  }
  doc.replace(0, 0, newDelta);
  storeDocument(object, doc);
}

Map<String, dynamic> deepMap(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)));

class SelectionRequest {
  SelectionRequest({
    required this.objectId,
    required this.start,
    required this.end,
    required this.text,
    required this.action,
  });
  final String objectId, text, action;
  final int start, end;
  Map<String, dynamic> toJson() => {
    'objectId': objectId,
    'start': start,
    'end': end,
    'text': text,
    'action': action,
  };
}
