import 'dart:convert';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:flutter_quill/quill_delta.dart' as qd;
import 'model.dart';

q.Document readDocument(CreativeObject object) {
  final delta = object.meta['delta'];
  if (delta is List) return q.Document.fromJson(List<dynamic>.from(delta));
  return q.Document.fromJson([
    {'insert': object.body.endsWith('\n') ? object.body : '${object.body}\n'},
  ]);
}

void storeDocument(CreativeObject object, q.Document document) {
  object.meta['delta'] = document.toDelta().toJson();
  object.body = document.toPlainText();
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

/// Converts AI Markdown into Quill's native Delta format. This intentionally
/// handles the common AI writing syntax directly instead of relying on an
/// experimental converter that can reject partially streamed Markdown.
qd.Delta markdownToDelta(String markdown) {
  final delta = qd.Delta();
  final lines = _flattenMarkdownTables(markdown).split('\n');
  var inCodeBlock = false;
  for (final rawLine in lines) {
    final trimmed = rawLine.trim();
    if (trimmed.startsWith('```')) {
      inCodeBlock = !inCodeBlock;
      continue;
    }
    final lineAttributes = <String, dynamic>{};
    var text = rawLine;
    if (inCodeBlock) {
      lineAttributes['code-block'] = true;
    } else {
      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      final ordered = RegExp(r'^\d+[.)]\s+(.*)$').firstMatch(trimmed);
      final bullet = RegExp(r'^[-*+]\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        text = heading.group(2)!;
        lineAttributes['heading'] = heading.group(1)!.length;
      } else if (ordered != null) {
        text = ordered.group(1)!;
        lineAttributes['list'] = 'ordered';
      } else if (bullet != null) {
        text = bullet.group(1)!;
        lineAttributes['list'] = 'bullet';
      } else if (trimmed.startsWith('> ')) {
        text = trimmed.substring(2);
        lineAttributes['blockquote'] = true;
      }
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
      // AI responses can end with an unfinished marker. Treat its remaining
      // text as formatted rather than exposing the raw Markdown token.
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
    if (value.startsWith('**', index)) {
      nextIndex = formatted('**', const {'bold': true}, index);
    } else if (value.startsWith('__', index)) {
      // Zenbox accepts double underscores as an explicit underline shorthand.
      nextIndex = formatted('__', const {'underline': true}, index);
    } else if (value.startsWith('~~', index)) {
      nextIndex = formatted('~~', const {'strike': true}, index);
    } else if (value.startsWith('<u>', index)) {
      final end = value.indexOf('</u>', index + 3);
      if (end < 0) {
        plain.write('<u>');
      } else {
        flushPlain();
        _insertMarkdownInline(delta, value.substring(index + 3, end), {
          ...attributes,
          'underline': true,
        });
        nextIndex = end + 4;
      }
    } else if (value[index] == '*' || value[index] == '_') {
      final marker = value[index];
      nextIndex = formatted(marker, const {'italic': true}, index);
    } else if (value[index] == '`') {
      nextIndex = formatted('`', const {'code': true}, index);
    } else if (value[index] == '[') {
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

/// Flutter Quill's Markdown converter has experimental table embeds, while the
/// editor uses a custom embed set. Flatten standard Markdown tables to aligned,
/// editable tab-separated lines instead of producing an unsupported embed.
String _flattenMarkdownTables(String markdown) {
  final lines = markdown.replaceAll('\r\n', '\n').split('\n');
  final output = <String>[];
  for (var index = 0; index < lines.length; index++) {
    final current = lines[index].trim();
    if (index + 1 < lines.length &&
        current.contains('|') &&
        _isMarkdownTableDelimiter(lines[index + 1].trim())) {
      output.add('**${_markdownTableCells(current).join('    ')}**');
      index += 2;
      while (index < lines.length && lines[index].contains('|')) {
        output.add(_markdownTableCells(lines[index].trim()).join('\t'));
        index++;
      }
      index--;
      continue;
    }
    output.add(lines[index]);
  }
  return output.join('\n');
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
  if (object.meta['delta'] != null ||
      ['script', 'manuscript'].contains(object.kind)) {
    final doc = readDocument(object);
    // Retain the visual separation previous transfers had, but insert a Delta
    // so all Markdown formatting is immediately editable in the note editor.
    doc.insert(doc.length - 1, '\n');
    doc.replace(doc.length - 1, 0, markdownToDelta(text));
    storeDocument(object, doc);
  } else {
    object.body += '\n\n$text';
  }
}

void setMarkdownDocument(CreativeObject object, String text) {
  storeDocument(object, q.Document.fromDelta(markdownToDelta(text)));
}

void prependText(CreativeObject object, String text) {
  if (object.meta['delta'] != null ||
      ['script', 'manuscript'].contains(object.kind)) {
    final doc = readDocument(object);
    doc.replace(0, 0, markdownToDelta('$text\n'));
    storeDocument(object, doc);
  } else {
    object.body = object.body.isEmpty ? text : '$text\n\n${object.body}';
  }
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
