import 'dart:io';
import 'package:flutter/material.dart';
import 'package:zenbox/theme/theme.dart';

/// A compact, dependency-free Markdown reader for notes and AI answers.
/// It deliberately covers the writing patterns the app creates: headings,
/// lists, emphasis, quotes, dividers, fenced snippets, and inline images.
class MarkdownView extends StatelessWidget {
  const MarkdownView({
    super.key,
    required this.data,
    this.selectable = false,
    this.compact = false,
    this.mediaDir,
    this.textColor,
  });

  final String data;
  final bool selectable;
  final bool compact;
  final Color? textColor;

  /// Base directory for resolving relative image paths (e.g. `media/file.jpg`).
  /// When null, only absolute paths and URLs are supported.
  final String? mediaDir;

  @override
  Widget build(BuildContext context) {
    final effectiveTextColor = textColor ?? ink;
    final lines = data.replaceAll('\r\n', '\n').split('\n');
    final widgets = <Widget>[];
    var inCode = false;
    final code = StringBuffer();

    void flushCode() {
      if (code.isEmpty) return;
      widgets.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 7),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (textColor != null ? const Color(0xFF1E2820) : ink).withValues(alpha: .92),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            code.toString().trimRight(),
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: compact ? 10 : 12,
              height: 1.55,
              color: cream,
            ),
          ),
        ),
      );
      code.clear();
    }

    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final raw = lines[lineIndex];
      final lineText = raw.trimRight();
      if (lineText.trimLeft().startsWith('```')) {
        if (inCode) flushCode();
        inCode = !inCode;
        continue;
      }
      if (inCode) {
        code.writeln(lineText);
        continue;
      }
      final trimmed = lineText.trim();
      if (trimmed.isEmpty) {
        widgets.add(SizedBox(height: compact ? 5 : 9));
      } else if (lineIndex + 1 < lines.length &&
          trimmed.contains('|') &&
          _isTableDelimiter(lines[lineIndex + 1].trim())) {
        final rows = <List<String>>[_tableCells(trimmed)];
        lineIndex += 2;
        while (lineIndex < lines.length && lines[lineIndex].contains('|')) {
          rows.add(_tableCells(lines[lineIndex].trim()));
          lineIndex++;
        }
        lineIndex--;
        widgets.add(_table(rows));
      } else if (RegExp(r'^#{1,3}\s+').hasMatch(trimmed)) {
        final match = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(trimmed)!;
        final level = match.group(1)!.length;
        widgets.add(
          Padding(
            padding: EdgeInsets.only(top: level == 1 ? 12 : 8, bottom: 4),
            child: _rich(
              match.group(2)!,
              TextStyle(
                fontSize: (compact ? 15 : 22) - (level - 1) * (compact ? 2 : 3),
                height: 1.25,
                fontWeight: FontWeight.w700,
                color: effectiveTextColor,
              ),
            ),
          ),
        );
      } else if (trimmed == '---' || trimmed == '***' || trimmed == '___') {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Divider(color: line),
          ),
        );
      } else if (trimmed.startsWith('> ')) {
        widgets.add(
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: sage, width: 3)),
            ),
            child: _rich(
              trimmed.substring(2),
              TextStyle(
                fontSize: compact ? 11 : 13,
                height: 1.6,
                color: muted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        );
      } else if (RegExp(r"^\!\[.*?\]\((.+?)\)\s*$").hasMatch(trimmed)) {
        // Inline image: ![alt](src)
        final src = RegExp(
          r"^\!\[.*?\]\((.+?)\)",
        ).firstMatch(trimmed)!.group(1)!;
        Widget imgWidget;
        final isNetwork =
            src.startsWith('http://') || src.startsWith('https://');
        if (isNetwork) {
          imgWidget = Image.network(
            src,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _brokenImage(),
          );
        } else {
          final resolved =
              (mediaDir != null &&
                  !src.startsWith('/') &&
                  !RegExp(r'^[A-Za-z]:').hasMatch(src))
              ? '$mediaDir/$src'
              : src;
          imgWidget = Image.file(
            File(resolved),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _brokenImage(),
          );
        }
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: compact ? 160 : 320),
                child: imgWidget,
              ),
            ),
          ),
        );
      } else {
        final leadingSpaces = raw.length - raw.trimLeft().length;
        final indentLevel =
            leadingSpaces >= 2 ? (leadingSpaces / 2).floor() : 0;
        final checklist =
            RegExp(r'^[-*+]\s+\[([ xX])\]\s*(.*)$').firstMatch(trimmed);
        final list = RegExp(
          r'^(?:[-*+]\s+|\d+[.)]\s+)(.*)$',
        ).firstMatch(trimmed);

        if (checklist != null) {
          final isChecked = checklist.group(1)!.toLowerCase() == 'x';
          widgets.add(
            Padding(
              padding: EdgeInsets.only(
                left: indentLevel * (compact ? 12.0 : 16.0),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6, top: 1),
                    child: Icon(
                      isChecked
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: compact ? 12 : 15,
                      color: isChecked ? sage : muted,
                    ),
                  ),
                  Expanded(
                    child: _rich(
                      checklist.group(2)!,
                      TextStyle(
                        fontSize: compact ? 11 : 13,
                        height: 1.6,
                        color: isChecked ? muted : effectiveTextColor,
                        decoration:
                            isChecked ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          widgets.add(
            Padding(
              padding: EdgeInsets.only(
                left: indentLevel * (compact ? 12.0 : 16.0),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (list != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, top: 2),
                      child: Icon(
                        trimmed.startsWith(RegExp(r'\d'))
                            ? Icons.looks_one_outlined
                            : Icons.circle,
                        size: compact ? 7 : 8,
                        color: sage,
                      ),
                    ),
                  if (list != null)
                    Expanded(
                      child: _rich(
                        list.group(1)!,
                        TextStyle(
                          fontSize: compact ? 11 : 13,
                          height: 1.6,
                          color: effectiveTextColor,
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: _rich(
                        trimmed,
                        TextStyle(
                          fontSize: compact ? 11 : 13,
                          height: 1.65,
                          color: effectiveTextColor,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }
      }
    }
    if (inCode) flushCode();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
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

  bool _isTableDelimiter(String line) =>
      RegExp(r'^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$').hasMatch(line);

  List<String> _tableCells(String line) {
    var value = line.trim();
    if (value.startsWith('|')) value = value.substring(1);
    if (value.endsWith('|')) value = value.substring(0, value.length - 1);
    return value.split('|').map((cell) => cell.trim()).toList();
  }

  Widget _table(List<List<String>> rows) {
    final columns = rows.fold<int>(
      0,
      (count, row) => count > row.length ? count : row.length,
    );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
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
                for (var column = 0; column < columns; column++)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 7 : 10,
                      vertical: compact ? 5 : 8,
                    ),
                    child: _rich(
                      column < rows[rowIndex].length
                          ? rows[rowIndex][column]
                          : '',
                      TextStyle(
                        fontSize: compact ? 10 : 12,
                        height: 1.45,
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

  Widget _rich(String value, TextStyle base) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(
      r'(\*\*\*.+?\*\*\*|___.+?___|\*\*.+?\*\*|__.+?__|~~.+?~~|<u>.+?<\/u>|`.+?`|\*.+?\*|_.+?_|\[.+?\]\(.+?\))',
    );
    var cursor = 0;
    for (final match in pattern.allMatches(value)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: value.substring(cursor, match.start)));
      }
      final token = match.group(0)!;
      if (token.startsWith('***') || token.startsWith('___')) {
        spans.add(
          TextSpan(
            text: token.substring(3, token.length - 3),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontStyle: FontStyle.italic,
            ),
          ),
        );
      } else if (token.startsWith('**') || token.startsWith('__')) {
        spans.add(
          TextSpan(
            text: token.substring(2, token.length - 2),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else if (token.startsWith('~~')) {
        spans.add(
          TextSpan(
            text: token.substring(2, token.length - 2),
            style: const TextStyle(decoration: TextDecoration.lineThrough),
          ),
        );
      } else if (token.startsWith('<u>') && token.endsWith('</u>')) {
        spans.add(
          TextSpan(
            text: token.substring(3, token.length - 4),
            style: const TextStyle(decoration: TextDecoration.underline),
          ),
        );
      } else if (token.startsWith('`')) {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: TextStyle(
              fontFamily: 'Consolas',
              backgroundColor: paleSage.withValues(alpha: .55),
              color: textColor ?? ink,
            ),
          ),
        );
      } else if (token.startsWith('[') && token.contains('](')) {
        final labelEnd = token.indexOf('](');
        final label = token.substring(1, labelEnd);
        spans.add(
          TextSpan(
            text: label,
            style: TextStyle(
              color: sage,
              decoration: TextDecoration.underline,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      }
      cursor = match.end;
    }
    if (cursor < value.length) {
      spans.add(TextSpan(text: value.substring(cursor)));
    }
    final text = TextSpan(style: base, children: spans);
    return selectable ? SelectableText.rich(text) : Text.rich(text);
  }
}
