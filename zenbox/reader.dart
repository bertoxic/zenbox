import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';
import '../model.dart';
import '../visual.dart';
import '../zenbox_model.dart';
import '../zenbox_theme.dart';

class DocumentBlock {
  const DocumentBlock(
    this.text, {
    this.heading = false,
    this.cells,
    this.image,
  });
  final String text;
  final bool heading;
  final List<List<String>>? cells;
  final Uint8List? image;
}

/// DOCX content stays on the device. Namespace prefixes are not assumed.
List<DocumentBlock> readDocx(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final document = archive.findFile('word/document.xml');
  if (document == null)
    throw const FormatException('This file does not contain a Word document.');
  final xml = XmlDocument.parse(utf8.decode(document.content));
  final relationships = <String, String>{};
  final rels = archive.findFile('word/_rels/document.xml.rels');
  if (rels != null)
    for (final e in XmlDocument.parse(
      utf8.decode(rels.content),
    ).descendants.whereType<XmlElement>()) {
      if (e.name.local == 'Relationship' &&
          e.getAttribute('TargetMode') != 'External')
        relationships[e.getAttribute('Id') ?? ''] =
            e.getAttribute('Target') ?? '';
    }
  String plain(XmlElement e) => e.descendants
      .whereType<XmlElement>()
      .map(
        (n) => switch (n.name.local) {
          't' => n.innerText,
          'tab' => '\t',
          'br' => '\n',
          _ => '',
        },
      )
      .join();
  final body = xml.descendants.whereType<XmlElement>().firstWhere(
    (e) => e.name.local == 'body',
  );
  final blocks = <DocumentBlock>[];
  for (final e in body.childElements) {
    if (e.name.local == 'tbl') {
      final rows = e.childElements
          .where((n) => n.name.local == 'tr')
          .map(
            (row) => row.childElements
                .where((n) => n.name.local == 'tc')
                .map(plain)
                .toList(),
          )
          .toList();
      blocks.add(
        DocumentBlock(rows.map((r) => r.join(' | ')).join('\n'), cells: rows),
      );
    } else if (e.name.local == 'p') {
      final style = e.descendants
          .whereType<XmlElement>()
          .where((n) => n.name.local == 'pStyle')
          .firstOrNull;
      final heading =
          style?.attributes.any(
            (a) =>
                a.name.local == 'val' &&
                RegExp('heading|title', caseSensitive: false).hasMatch(a.value),
          ) ??
          false;
      blocks.add(DocumentBlock(plain(e), heading: heading));
      for (final blip in e.descendants.whereType<XmlElement>().where(
        (n) => n.name.local == 'blip',
      )) {
        final id = blip.attributes
            .where((a) => a.name.local == 'embed')
            .firstOrNull
            ?.value;
        final target = relationships[id];
        if (target != null && !target.contains('..')) {
          final entry = archive.findFile(
            target.startsWith('/') ? target.substring(1) : 'word/$target',
          );
          if (entry != null)
            blocks.add(
              DocumentBlock('', image: Uint8List.fromList(entry.content)),
            );
        }
      }
    }
  }
  return blocks;
}

class SourceReader extends StatefulWidget {
  const SourceReader({
    super.key,
    required this.store,
    required this.object,
    required this.onCapture,
    required this.onAsk,
  });
  final ZenboxStore store;
  final CreativeObject object;
  final void Function(String quote, String locator) onCapture;
  final void Function(String prompt) onAsk;
  @override
  State<SourceReader> createState() => _SourceReaderState();
}

class _SourceReaderState extends State<SourceReader> {
  final pdf = PdfViewerController();
  PdfTextSearcher? searcher;
  String selection = '', locator = '';
  int page = 1, pages = 0;
  String? error;
  List<DocumentBlock>? blocks;
  bool extracting = false;
  String get extension =>
      widget.object.meta['file']?.toString().split('.').last.toLowerCase() ??
      '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (widget.object.meta['file'] == null) return;
    try {
      final path = widget.store.mediaPath(widget.object);
      if (extension == 'docx')
        blocks = readDocx(await File(path).readAsBytes());
      if (['txt', 'md', 'csv', 'json', 'log', 'srt', 'vtt'].contains(extension))
        blocks = [DocumentBlock(await File(path).readAsString())];
      if (blocks != null) {
        widget.object.body = blocks!.map((b) => b.text).join('\n\n');
        widget.object.meta['textIndexed'] = true;
        widget.store.changed();
      }
    } catch (e) {
      error = 'The document could not be read: $e';
    }
    if (mounted) setState(() {});
  }

  Future<void> _indexPdf(PdfDocument document) async {
    if (extracting || widget.object.meta['textIndexed'] == true) return;
    extracting = true;
    try {
      final text = <String>[];
      for (final p in document.pages) {
        if (!mounted) return;
        final raw = await p.loadText();
        text.add('[Page ${p.pageNumber}]\n${raw?.fullText ?? ''}');
      }
      widget.object.body = text.join('\n\n');
      widget.object.meta['textIndexed'] = true;
      widget.object.meta['pages'] = document.pages.length;
      widget.store.changed();
    } catch (e) {
      if (mounted)
        setState(
          () => error =
              'The PDF is viewable, but its text could not be indexed: $e',
        );
    } finally {
      extracting = false;
    }
  }

  @override
  void dispose() {
    searcher?.removeListener(_repaint);
    searcher?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPdf = extension == 'pdf';
    return Column(
      children: [
        Container(
          color: surface,
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.menu_book_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.object.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    onPressed: selection.trim().isEmpty
                        ? null
                        : () => widget.onCapture(selection, locator),
                    icon: const Icon(Icons.format_quote, size: 16),
                    label: const Text('Capture evidence'),
                  ),
                  OutlinedButton.icon(
                    onPressed: selection.trim().isEmpty
                        ? null
                        : () => widget.onAsk(
                            'Explain this passage from ${widget.object.title} ($locator). Distinguish what the source says from your interpretation.\n\n$selection',
                          ),
                    icon: const Icon(Icons.auto_awesome, size: 16),
                    label: const Text('Explain'),
                  ),
                  if (isPdf) ...[
                    IconButton(
                      tooltip: 'Previous page',
                      onPressed: page > 1
                          ? () => pdf.goToPage(pageNumber: page - 1)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text('$page / $pages'),
                    IconButton(
                      tooltip: 'Next page',
                      onPressed: page < pages
                          ? () => pdf.goToPage(pageNumber: page + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ],
              ),
              if (isPdf)
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Find in PDF…',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onSubmitted: (s) {
                    searcher?.startTextSearch(s);
                  },
                  onChanged: (s) {
                    if (s.isEmpty) searcher?.startTextSearch('');
                  },
                ),
              if (isPdf && searcher?.matches.isNotEmpty == true)
                TextButton(
                  onPressed: () => searcher?.goToNextMatch(),
                  child: Text('${searcher!.matches.length} matches · Next'),
                ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              error!,
              style: const TextStyle(color: Colors.deepOrange),
            ),
          ),
        Expanded(
          child: isPdf
              ? PdfViewer.file(
                  widget.store.mediaPath(widget.object),
                  controller: pdf,
                  initialPageNumber:
                      (widget.object.meta['readingPage'] as num?)?.toInt() ?? 1,
                  params: PdfViewerParams(
                    backgroundColor: canvas,
                    pagePaintCallbacks: [if(searcher!=null)searcher!.pageTextMatchPaintCallback],
                    onViewerReady: (document, controller) {
                      searcher?.dispose();
                      searcher = PdfTextSearcher(controller)..addListener(_repaint);
                      setState(() => pages = document.pages.length);
                      _indexPdf(document);
                    },
                    onPageChanged: (n) {
                      if (n == null) return;
                      setState(() => page = n);
                      widget.object.meta['readingPage'] = n;
                      widget.store.changed();
                    },
                    textSelectionParams: PdfTextSelectionParams(
                      onTextSelectionChange: (s) async {
                        if (!s.isCopyAllowed) return;
                        final text = await s.getSelectedText();
                        final ranges = await s.getSelectedTextRanges();
                        if (mounted)
                          setState(() {
                            selection = text;
                            locator = ranges.isEmpty
                                ? 'p. $page'
                                : 'p. ${ranges.first.pageText.pageNumber}';
                          });
                      },
                    ),
                  ),
                )
              : blocks != null
              ? SelectionArea(
                  onSelectionChanged: (s) => setState(() {
                    selection = s?.plainText ?? '';
                    locator = 'Document passage';
                  }),
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: blocks!
                        .map(
                          (b) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: b.image != null
                                ? Image.memory(
                                    b.image!,
                                    errorBuilder: (_, e, st) => const Text(
                                      '[Embedded image unavailable]',
                                    ),
                                  )
                                : b.cells != null
                                ? Table(
                                    border: TableBorder.all(color: edge),
                                    children: b.cells!
                                        .map(
                                          (r) => TableRow(
                                            children: [
                                              for (
                                                var i = 0;
                                                i <
                                                    b.cells!.fold<int>(
                                                      0,
                                                      (m, r) => r.length > m
                                                          ? r.length
                                                          : m,
                                                    );
                                                i++
                                              )
                                                Padding(
                                                  padding: const EdgeInsets.all(
                                                    8,
                                                  ),
                                                  child: Text(
                                                    i < r.length ? r[i] : '',
                                                  ),
                                                ),
                                            ],
                                          ),
                                        )
                                        .toList(),
                                  )
                                : Text(
                                    b.text,
                                    style: TextStyle(
                                      fontSize: b.heading ? 23 : 16,
                                      fontWeight: b.heading
                                          ? FontWeight.w600
                                          : null,
                                      height: 1.6,
                                    ),
                                  ),
                          ),
                        )
                        .toList(),
                  ),
                )
              : widget.object.meta['file'] == null
              ? SelectionArea(
                  onSelectionChanged: (s) => setState(() {
                    selection = s?.plainText ?? '';
                    locator = 'Source text';
                  }),
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        widget.object.body,
                        style: const TextStyle(fontSize: 16, height: 1.7),
                      ),
                    ],
                  ),
                )
              : [
                  'image',
                  'audio',
                  'video',
                ].contains(widget.object.meta['mediaType'])
              ? MediaPreview(store: widget.store, asset: widget.object)
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      extension == 'doc'
                          ? 'This is a legacy .doc file. Save it as .docx or PDF in Word or LibreOffice, then import that version to read and annotate it here.'
                          : 'This file is stored in your assets. In-app reading supports PDF, DOCX, text, images, audio, and video.',
                    ),
                  ),
                ),
        ),
        if (selection.isNotEmpty)
          Container(
            width: double.infinity,
            color: olive.withValues(alpha: .15),
            padding: const EdgeInsets.all(8),
            child: Text(
              'Selected · $locator · ${selection.length} characters',
              style: const TextStyle(fontSize: 11),
            ),
          ),
      ],
    );
  }
}
