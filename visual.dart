import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'model.dart';
import 'quiz_model.dart';
import 'quiz_view.dart';
import 'zenbox/reader.dart';
import 'notification_service.dart';
import 'theme.dart';
import 'markdown_view.dart';

class AssetThumbnail extends StatefulWidget {
  const AssetThumbnail({
    super.key,
    required this.store,
    required this.asset,
    this.fit = BoxFit.cover,
  });
  final StudioStore store;
  final CreativeObject asset;
  final BoxFit fit;
  @override
  State<AssetThumbnail> createState() => _AssetThumbnailState();
}

class _AssetThumbnailState extends State<AssetThumbnail> {
  bool _loadingPoster = false;

  @override
  void initState() {
    super.initState();
    _loadPoster();
  }

  @override
  void didUpdateWidget(covariant AssetThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.id != widget.asset.id) _loadPoster();
  }

  void _loadPoster() {
    if (widget.asset.meta['mediaType'] != 'video' ||
        widget.asset.meta['thumbnail'] != null ||
        _loadingPoster)
      return;
    _loadingPoster = true;
    widget.store.ensureVideoThumbnail(widget.asset).whenComplete(() {
      if (mounted) setState(() => _loadingPoster = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    final store = widget.store;
    final fit = widget.fit;
    if (asset.meta['mediaType'] == 'image') {
      return Image.file(
        File(store.mediaPath(asset)),
        fit: fit,
        errorBuilder: (_, _, _) =>
            Center(child: Icon(Icons.broken_image_outlined, color: muted)),
      );
    }
    if (asset.meta['mediaType'] == 'video' && asset.meta['thumbnail'] != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(store.thumbnailPath(asset)),
            fit: fit,
            errorBuilder: (_, _, _) => _fallback(asset),
          ),
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .48),
                shape: BoxShape.circle,
              ),
              child: const Padding(
                padding: EdgeInsets.all(7),
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 25,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return _fallback(asset);
  }

  Widget _fallback(CreativeObject asset) {
    return ColoredBox(
      color: paleSage.withValues(alpha: .4),
      child: Center(
        child: Icon(
          asset.meta['mediaType'] == 'video'
              ? Icons.play_circle_outline
              : asset.meta['mediaType'] == 'audio'
              ? Icons.graphic_eq
              : Icons.insert_drive_file_outlined,
          size: 40,
          color: sage,
        ),
      ),
    );
  }
}

class MediaPreview extends StatefulWidget {
  const MediaPreview({
    super.key,
    required this.store,
    required this.asset,
    this.autoplay = false,
    this.compactDocumentHeader = false,
  });
  final StudioStore store;
  final CreativeObject asset;
  final bool autoplay;
  final bool compactDocumentHeader;
  @override
  State<MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<MediaPreview> {
  Player? player;
  VideoController? controller;
  StreamSubscription<String>? errors;
  String? error;
  @override
  void initState() {
    super.initState();
    if (['video', 'audio'].contains(widget.asset.meta['mediaType'])) {
      player = Player();
      controller = VideoController(player!);
      errors = player!.stream.error.listen((e) {
        if (mounted) setState(() => error = e);
      });
      player!
          .open(
            Media(widget.store.mediaPath(widget.asset)),
            play: widget.autoplay,
          )
          .catchError((Object e) {
            if (mounted) setState(() => error = '$e');
          });
    }
  }

  @override
  void dispose() {
    errors?.cancel();
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return EmptyState(
        Icons.error_outline,
        'Unable to play this file',
        error!,
      );
    }
    if (controller != null) return Video(controller: controller!);
    if (widget.asset.meta['mediaType'] == 'image') {
      return InteractiveViewer(
        minScale: .2,
        maxScale: 8,
        child: AssetThumbnail(
          store: widget.store,
          asset: widget.asset,
          fit: BoxFit.contain,
        ),
      );
    }
    final docExt =
        widget.asset.meta['file']?.toString().split('.').last.toLowerCase() ??
        '';
    final isDoc =
        [
          'pdf',
          'docx',
          'doc',
          'txt',
          'md',
          'csv',
          'json',
          'log',
        ].contains(docExt) ||
        widget.asset.meta['mediaType'] == 'document' ||
        widget.asset.kind == 'source';
    if (isDoc) {
      return SourceReader(
        store: widget.store,
        object: widget.asset,
        showTitle: !widget.compactDocumentHeader,
        onCapture: (quote, locator) {
          final note = CreativeObject(
            kind: 'note',
            title: 'Quote: ${widget.asset.title}',
            body: '"$quote"\n— $locator',
            links: [widget.asset.id],
          );
          widget.store.project.objects.add(note);
          widget.store.changed();
          TopNotification.show(
            context,
            'Saved quotation to Notes',
            icon: Icons.bookmark_added_outlined,
          );
        },
        onAsk: (prompt) {
          Clipboard.setData(ClipboardData(text: prompt));
          TopNotification.show(
            context,
            'Prompt copied for AI Companion',
            icon: Icons.copy_all_outlined,
          );
        },
      );
    }
    return EmptyState(
      Icons.insert_drive_file_outlined,
      widget.asset.title,
      'This attachment is stored in your project. Use Export original to open it in another application.',
    );
  }
}

class ConceptCategory {
  const ConceptCategory({
    required this.id,
    required this.name,
    required this.accentColor,
    required this.bgColor,
    required this.icon,
  });

  final String id;
  final String name;
  final Color accentColor;
  final Color bgColor;
  final IconData icon;
}

const conceptCategories = [
  ConceptCategory(
    id: 'concept',
    name: 'Concept',
    accentColor: Color(0xFF4C7B5D),
    bgColor: Color(0xFFF0F5F1),
    icon: Icons.lightbulb_outline,
  ),
  ConceptCategory(
    id: 'definition',
    name: 'Definition',
    accentColor: Color(0xFF2E6B80),
    bgColor: Color(0xFFEBF3F6),
    icon: Icons.menu_book_outlined,
  ),
  ConceptCategory(
    id: 'formula',
    name: 'Formula',
    accentColor: Color(0xFFB5701B),
    bgColor: Color(0xFFFBF4E8),
    icon: Icons.functions_outlined,
  ),
  ConceptCategory(
    id: 'question',
    name: 'Question',
    accentColor: Color(0xFFB54536),
    bgColor: Color(0xFFFAECEB),
    icon: Icons.help_outline,
  ),
  ConceptCategory(
    id: 'summary',
    name: 'Summary',
    accentColor: Color(0xFF5B6E32),
    bgColor: Color(0xFFF3F5EA),
    icon: Icons.summarize_outlined,
  ),
  ConceptCategory(
    id: 'takeaway',
    name: 'Key Point',
    accentColor: Color(0xFF55528A),
    bgColor: Color(0xFFF0EFF8),
    icon: Icons.stars_outlined,
  ),
];

ConceptCategory getCategoryFor(CreativeObject o) {
  final catId = o.meta['category'] as String?;
  if (catId != null) {
    for (final c in conceptCategories) {
      if (c.id == catId) return c;
    }
  }
  final colorIdx = (o.meta['color'] as int? ?? 0) % conceptCategories.length;
  return conceptCategories[colorIdx];
}

class CanvasWorkspace extends StatefulWidget {
  const CanvasWorkspace({
    super.key,
    required this.store,
    required this.edit,
    required this.remove,
    required this.select,
  });
  final StudioStore store;
  final void Function(CreativeObject) edit, select;
  final FutureOr<void> Function(CreativeObject) remove;
  @override
  State<CanvasWorkspace> createState() => _CanvasWorkspaceState();
}

class _CanvasWorkspaceState extends State<CanvasWorkspace> {
  final transform = TransformationController();
  String? selected;
  String? editing;
  bool connecting = false;
  Offset? mouseScenePoint;
  String searchQuery = '';

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  List<CreativeObject> get nodes => widget.store.project.of('board').toList();

  void add({CreativeObject? source, Offset? point, String? categoryId}) {
    final defaultCat = categoryId ?? 'concept';
    final o = CreativeObject(
      kind: 'board',
      title: source?.title ?? 'New Concept',
      body:
          source?.body ??
          'Double-click to expand this thought, add formulas, or connect to related ideas.',
      links: source == null ? [] : [source.id],
      meta: {
        'x': point?.dx ?? 150.0 + (nodes.length % 5) * 60,
        'y': point?.dy ?? 150.0 + (nodes.length % 5) * 60,
        'color': nodes.length % conceptCategories.length,
        'category': defaultCat,
      },
    );
    widget.store.add(o);
    setState(() {
      selected = o.id;
    });
    widget.select(o);
  }

  void _startConnecting(String sourceId) {
    setState(() {
      selected = sourceId;
      connecting = true;
    });
  }

  void _completeConnecting(String targetId) {
    if (selected != null && selected != targetId) {
      final source = widget.store.project.object(selected);
      if (source != null && !source.links.contains(targetId)) {
        source.links.add(targetId);
        widget.store.changed();
      }
    }
    setState(() {
      connecting = false;
    });
  }

  void _removeConnection(CreativeObject source, String targetId) {
    setState(() {
      source.links.remove(targetId);
      widget.store.changed();
    });
  }

  void _cycleCategory(CreativeObject o) {
    final currentCat = getCategoryFor(o);
    final nextIdx =
        (conceptCategories.indexWhere((c) => c.id == currentCat.id) + 1) %
        conceptCategories.length;
    setState(() {
      o.meta['category'] = conceptCategories[nextIdx].id;
      o.meta['color'] = nextIdx;
      widget.store.changed();
    });
  }

  void _setCategory(CreativeObject o, String categoryId) {
    final idx = conceptCategories.indexWhere((c) => c.id == categoryId);
    setState(() {
      o.meta['category'] = categoryId;
      if (idx != -1) o.meta['color'] = idx;
      widget.store.changed();
    });
  }

  void _autoArrange() {
    final allNodes = nodes;
    if (allNodes.isEmpty) return;

    final inDegree = <String, int>{};
    for (final n in allNodes) {
      inDegree[n.id] = 0;
    }
    for (final n in allNodes) {
      for (final link in n.links) {
        if (inDegree.containsKey(link)) {
          inDegree[link] = (inDegree[link] ?? 0) + 1;
        }
      }
    }

    final levels = <int, List<CreativeObject>>{};
    final visited = <String>{};

    var currentLevel = allNodes
        .where((n) => (inDegree[n.id] ?? 0) == 0)
        .toList();
    if (currentLevel.isEmpty) currentLevel = [allNodes.first];

    int levelIndex = 0;
    while (currentLevel.isNotEmpty) {
      levels[levelIndex] = [];
      final nextLevel = <CreativeObject>[];
      for (final n in currentLevel) {
        if (visited.contains(n.id)) continue;
        visited.add(n.id);
        levels[levelIndex]!.add(n);
        for (final targetId in n.links) {
          final target = allNodes.firstWhere(
            (item) => item.id == targetId,
            orElse: () => n,
          );
          if (target != n &&
              !visited.contains(target.id) &&
              !nextLevel.contains(target)) {
            nextLevel.add(target);
          }
        }
      }
      currentLevel = nextLevel;
      levelIndex++;
    }

    final unvisited = allNodes.where((n) => !visited.contains(n.id)).toList();
    if (unvisited.isNotEmpty) {
      levels[levelIndex] = unvisited;
    }

    levels.forEach((col, colNodes) {
      final startY = 160.0;
      final gapY = 270.0;
      final startX = 140.0 + col * 370.0;
      for (int r = 0; r < colNodes.length; r++) {
        final node = colNodes[r];
        node.meta['x'] = startX.clamp(50.0, 2700.0);
        node.meta['y'] = (startY + r * gapY).clamp(50.0, 1750.0);
      }
    });

    widget.store.changed();
    setState(() {});
  }

  void _fitView() {
    if (nodes.isEmpty) {
      transform.value = Matrix4.identity();
      return;
    }
    double minX = 999999, minY = 999999, maxX = -999999, maxY = -999999;
    for (final n in nodes) {
      final x = (n.meta['x'] as num?)?.toDouble() ?? 100;
      final y = (n.meta['y'] as num?)?.toDouble() ?? 100;
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x + 280);
      maxY = math.max(maxY, y + 200);
    }
    final contentW = maxX - minX + 240;
    final contentH = maxY - minY + 240;
    final scale = (900 / math.max(contentW, contentH * 1.3)).clamp(0.4, 1.2);
    final tx = -minX * scale + 80;
    final ty = -minY * scale + 60;
    transform.value = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(scale);
    setState(() {});
  }

  void _zoom(double factor) {
    final currentScale = transform.value.getMaxScaleOnAxis();
    final newScale = (currentScale * factor).clamp(0.3, 2.5);
    final scaleChange = newScale / currentScale;
    transform.value = transform.value.scaled(scaleChange);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SectionHeading(
        'Visual concept workspace',
        'Mind Map & Concept Board',
        subtitle:
            'Connect ideas across topics · Drag cards to arrange · Double-click canvas to add · Double-click card to edit',
        actions: [
          SizedBox(
            width: 140,
            height: 30,
            child: TextField(
              style: const TextStyle(fontSize: 11),
              decoration: InputDecoration(
                hintText: 'Search board...',
                hintStyle: TextStyle(fontSize: 10, color: muted),
                prefixIcon: const Icon(Icons.search, size: 14),
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                isDense: true,
              ),
              onChanged: (v) =>
                  setState(() => searchQuery = v.trim().toLowerCase()),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Auto arrange into concept tree',
            onPressed: _autoArrange,
            icon: const Icon(Icons.auto_awesome_mosaic_outlined),
          ),
          IconButton(
            tooltip: 'Fit all concepts in view',
            onPressed: _fitView,
            icon: const Icon(Icons.fit_screen_outlined),
          ),
          IconButton(
            tooltip: 'Zoom in',
            onPressed: () => _zoom(1.2),
            icon: const Icon(Icons.zoom_in, size: 19),
          ),
          IconButton(
            tooltip: 'Zoom out',
            onPressed: () => _zoom(0.83),
            icon: const Icon(Icons.zoom_out, size: 19),
          ),
          IconButton(
            tooltip: connecting ? 'Cancel linking' : 'Connect selected card',
            onPressed: selected == null
                ? null
                : () => setState(() => connecting = !connecting),
            icon: Icon(Icons.hub_outlined, color: connecting ? gold : muted),
          ),
          IconButton(
            tooltip: 'Delete selected card',
            onPressed: selected == null
                ? null
                : () {
                    final object = widget.store.project.object(selected);
                    if (object != null) widget.remove(object);
                  },
            icon: const Icon(Icons.delete_outline, color: Color(0xFFA54141)),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            onPressed: () => add(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add card'),
          ),
        ],
      ),
      if (connecting)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: gold.withValues(alpha: 0.15),
          child: Row(
            children: [
              Icon(Icons.hub, size: 16, color: gold),
              const SizedBox(width: 8),
              Text(
                'Linking Mode Active: Click any target card to connect from selected card',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
              const Spacer(),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => setState(() => connecting = false),
                child: const Text(
                  'Cancel Linking',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      Expanded(
        child: ClipRect(
          child: LayoutBuilder(
            builder: (context, constraints) => DragTarget<CreativeObject>(
              onAcceptWithDetails: (details) {
                final box = context.findRenderObject() as RenderBox;
                final point = transform.toScene(
                  box.globalToLocal(details.offset),
                );
                add(
                  source: details.data,
                  point: Offset(
                    point.dx.clamp(50, 2700),
                    point.dy.clamp(50, 1750),
                  ),
                );
              },
              builder: (context, candidates, rejected) => Container(
                color: candidates.isNotEmpty
                    ? paleSage.withValues(alpha: .5)
                    : const Color(0xFFF3F3EC),
                child: MouseRegion(
                  onHover: (event) {
                    if (connecting) {
                      setState(() {
                        mouseScenePoint = transform.toScene(
                          event.localPosition,
                        );
                      });
                    }
                  },
                  child: GestureDetector(
                    onDoubleTapDown: (details) {
                      final box = context.findRenderObject() as RenderBox;
                      final localPos = box.globalToLocal(
                        details.globalPosition,
                      );
                      final scenePos = transform.toScene(localPos);
                      add(
                        point: Offset(
                          scenePos.dx.clamp(50, 2700),
                          scenePos.dy.clamp(50, 1750),
                        ),
                      );
                    },
                    onTap: () {
                      if (connecting) {
                        setState(() => connecting = false);
                      }
                    },
                    child: InteractiveViewer(
                      transformationController: transform,
                      constrained: false,
                      boundaryMargin: const EdgeInsets.all(500),
                      minScale: .25,
                      maxScale: 2.5,
                      child: SizedBox(
                        width: 3200,
                        height: 2200,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: BoardPainter(
                                  nodes: nodes,
                                  selectedId: selected,
                                  connecting: connecting,
                                  connectingSourceId: selected,
                                  mousePoint: mouseScenePoint,
                                ),
                              ),
                            ),
                            for (final o in nodes) _buildNodeCard(o),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _buildNodeCard(CreativeObject o) {
    final cat = getCategoryFor(o);
    final isSelected = selected == o.id;
    final isMatch =
        searchQuery.isEmpty ||
        o.title.toLowerCase().contains(searchQuery) ||
        o.body.toLowerCase().contains(searchQuery);

    final linkedObjects = o.links
        .map((id) => widget.store.project.object(id))
        .whereType<CreativeObject>()
        .toList();

    return Positioned(
      left: (o.meta['x'] as num?)?.toDouble() ?? 100,
      top: (o.meta['y'] as num?)?.toDouble() ?? 100,
      child: Opacity(
        opacity: isMatch ? 1.0 : 0.35,
        child: GestureDetector(
          onTap: () {
            if (connecting && selected != null && selected != o.id) {
              _completeConnecting(o.id);
            } else {
              setState(() => selected = o.id);
              widget.select(o);
            }
          },
          onDoubleTap: () {
            setState(() {
              selected = o.id;
              editing = o.id;
            });
            widget.select(o);
          },
          onPanUpdate: editing == o.id
              ? null
              : (details) {
                  final scale = transform.value.getMaxScaleOnAxis();
                  setState(() {
                    o.meta['x'] =
                        (((o.meta['x'] as num?)?.toDouble() ?? 100) +
                                details.delta.dx / scale)
                            .clamp(50.0, 2900.0);
                    o.meta['y'] =
                        (((o.meta['y'] as num?)?.toDouble() ?? 100) +
                                details.delta.dy / scale)
                            .clamp(50.0, 1900.0);
                  });
                  widget.store.changed();
                },
          child: Container(
            width: 280,
            decoration: BoxDecoration(
              color: cat.bgColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? (connecting ? gold : cat.accentColor)
                    : line,
                width: isSelected ? 2.5 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? cat.accentColor.withValues(alpha: 0.25)
                      : Colors.black.withValues(alpha: 0.06),
                  offset: const Offset(0, 4),
                  blurRadius: isSelected ? 14 : 8,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Card Header: Category Chip & Actions
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: cat.accentColor.withValues(alpha: 0.08),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                    border: Border(
                      bottom: BorderSide(color: line.withValues(alpha: 0.6)),
                    ),
                  ),
                  child: Row(
                    children: [
                      PopupMenuButton<String>(
                        tooltip: 'Change category',
                        onSelected: (val) => _setCategory(o, val),
                        itemBuilder: (context) => conceptCategories.map((c) {
                          return PopupMenuItem<String>(
                            value: c.id,
                            child: Row(
                              children: [
                                Icon(c.icon, size: 15, color: c.accentColor),
                                const SizedBox(width: 8),
                                Text(
                                  c.name,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: cat.accentColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(cat.icon, size: 12, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                cat.name.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(
                                Icons.arrow_drop_down,
                                size: 12,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: editing == o.id
                            ? 'Finish editing'
                            : 'Edit card text',
                        iconSize: 15,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 22,
                          minHeight: 22,
                        ),
                        color: editing == o.id ? cat.accentColor : muted,
                        onPressed: () {
                          setState(() {
                            selected = o.id;
                            editing = editing == o.id ? null : o.id;
                          });
                          widget.select(o);
                        },
                        icon: Icon(
                          editing == o.id
                              ? Icons.check_rounded
                              : Icons.edit_outlined,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Connect to another card',
                        iconSize: 15,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 22,
                          minHeight: 22,
                        ),
                        color: connecting && selected == o.id ? gold : muted,
                        onPressed: () => _startConnecting(o.id),
                        icon: const Icon(Icons.hub_outlined),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Delete card',
                        iconSize: 15,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 22,
                          minHeight: 22,
                        ),
                        color: const Color(0xFFA54141),
                        onPressed: () => widget.remove(o),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),

                // Card Body
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Attached image thumbnails if linked
                      for (final linked in linkedObjects)
                        if (linked.kind == 'asset' &&
                            linked.meta['mediaType'] == 'image') ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              height: 120,
                              width: double.infinity,
                              child: AssetThumbnail(
                                store: widget.store,
                                asset: linked,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],

                      // Card text only becomes interactive after pressing edit.
                      if (editing == o.id)
                        TextFormField(
                          key: ValueKey('${o.id}-title-editor'),
                          initialValue: o.title,
                          autofocus: true,
                          style: TextStyle(
                            fontFamily: 'Georgia',
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                            color: ink,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Concept title…',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 4),
                            border: UnderlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFF6E8B76)),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: Color(0xFF6E8B76),
                                width: 1.5,
                              ),
                            ),
                          ),
                          onChanged: (val) {
                            o.title = val;
                            widget.store.changed();
                          },
                        )
                      else
                        Text(
                          o.title,
                          style: TextStyle(
                            fontFamily: 'Georgia',
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                            color: ink,
                          ),
                        ),
                      const SizedBox(height: 6),

                      if (editing == o.id)
                        TextFormField(
                          key: ValueKey('${o.id}-body-editor'),
                          initialValue: o.body,
                          maxLines: null,
                          minLines: 2,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.55,
                            color: ink.withValues(alpha: 0.85),
                          ),
                          decoration: InputDecoration(
                            hintText:
                                'Write idea, formula, or concept details…',
                            hintStyle: TextStyle(
                              fontSize: 11,
                              color: muted.withValues(alpha: 0.7),
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 4,
                            ),
                            border: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFF6E8B76)),
                            ),
                            focusedBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: Color(0xFF6E8B76),
                                width: 1.2,
                              ),
                            ),
                          ),
                          onChanged: (val) {
                            o.body = val;
                            widget.store.changed();
                          },
                        )
                      else
                        Text(
                          o.body.isEmpty
                              ? 'No details yet — choose edit to add some.'
                              : o.body,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.55,
                            color: o.body.isEmpty
                                ? muted.withValues(alpha: .7)
                                : ink.withValues(alpha: 0.85),
                            fontStyle: o.body.isEmpty ? FontStyle.italic : null,
                          ),
                        ),
                      const SizedBox(height: 10),

                      // Footer with link connections pill
                      Row(
                        children: [
                          if (o.links.isNotEmpty)
                            PopupMenuButton<String>(
                              tooltip: 'Manage connections',
                              onSelected: (targetId) =>
                                  _removeConnection(o, targetId),
                              itemBuilder: (context) => o.links.map((id) {
                                final target = widget.store.project.object(id);
                                final title = target?.title ?? 'Unknown';
                                return PopupMenuItem<String>(
                                  value: id,
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.link_off,
                                        size: 14,
                                        color: Color(0xFFA54141),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Unlink: $title',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: paper,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: line),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.hub,
                                      size: 11,
                                      color: cat.accentColor,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${o.links.length} ${o.links.length == 1 ? 'link' : 'links'}',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        color: ink,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            Text(
                              'No connections',
                              style: TextStyle(
                                fontSize: 9,
                                color: muted.withValues(alpha: 0.6),
                              ),
                            ),
                          const Spacer(),
                          Text(
                            '#${nodes.indexOf(o) + 1}',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BoardPainter extends CustomPainter {
  BoardPainter({
    required this.nodes,
    this.selectedId,
    this.connecting = false,
    this.connectingSourceId,
    this.mousePoint,
  });

  final List<CreativeObject> nodes;
  final String? selectedId;
  final bool connecting;
  final String? connectingSourceId;
  final Offset? mousePoint;

  static const double cardWidth = 280.0;
  static const double cardHeight = 180.0;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Subtle dotted background grid
    final dotPaint = Paint()
      ..color = const Color(0xFF5B6E32).withValues(alpha: 0.2);
    for (double x = 0; x < size.width; x += 28) {
      for (double y = 0; y < size.height; y += 28) {
        canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
      }
    }

    // 2. Connections with cubic Beziers and directional arrows
    for (final o in nodes) {
      final ox = (o.meta['x'] as num?)?.toDouble() ?? 100.0;
      final oy = (o.meta['y'] as num?)?.toDouble() ?? 100.0;
      final oCat = getCategoryFor(o);

      for (final linkId in o.links) {
        final targets = nodes.where((n) => n.id == linkId);
        if (targets.isEmpty) continue;
        final target = targets.first;
        final tx = (target.meta['x'] as num?)?.toDouble() ?? 100.0;
        final ty = (target.meta['y'] as num?)?.toDouble() ?? 100.0;

        final isHighlighted = selectedId == o.id || selectedId == target.id;
        _drawSmartConnection(
          canvas,
          startRect: Rect.fromLTWH(ox, oy, cardWidth, cardHeight),
          endRect: Rect.fromLTWH(tx, ty, cardWidth, cardHeight),
          color: isHighlighted
              ? const Color(0xFFC07D2B)
              : oCat.accentColor.withValues(alpha: 0.85),
          isHighlighted: isHighlighted,
        );
      }
    }

    // 3. Live connecting line to mouse pointer
    if (connecting && connectingSourceId != null && mousePoint != null) {
      final source = nodes.where((n) => n.id == connectingSourceId).firstOrNull;
      if (source != null) {
        final sx = (source.meta['x'] as num?)?.toDouble() ?? 100.0;
        final sy = (source.meta['y'] as num?)?.toDouble() ?? 100.0;
        final sCenter = Offset(sx + cardWidth / 2, sy + cardHeight / 2);

        final previewPaint = Paint()
          ..color = const Color(0xFFC07D2B)
          ..strokeWidth = 2.4
          ..style = PaintingStyle.stroke;

        final cp = Offset(
          (sCenter.dx + mousePoint!.dx) / 2,
          (sCenter.dy + mousePoint!.dy) / 2 - 25,
        );
        final path = Path()
          ..moveTo(sCenter.dx, sCenter.dy)
          ..quadraticBezierTo(cp.dx, cp.dy, mousePoint!.dx, mousePoint!.dy);

        canvas.drawPath(path, previewPaint);
        canvas.drawCircle(
          mousePoint!,
          5,
          Paint()..color = const Color(0xFFC07D2B),
        );
      }
    }
  }

  void _drawSmartConnection(
    Canvas canvas, {
    required Rect startRect,
    required Rect endRect,
    required Color color,
    required bool isHighlighted,
  }) {
    final startCenter = startRect.center;
    final endCenter = endRect.center;
    final dx = endCenter.dx - startCenter.dx;
    final dy = endCenter.dy - startCenter.dy;

    Offset anchorA, anchorB;
    Offset cpA, cpB;

    if (dx.abs() >= dy.abs()) {
      if (dx >= 0) {
        anchorA = Offset(startRect.right, startRect.center.dy);
        anchorB = Offset(endRect.left, endRect.center.dy);
        final dist = (anchorB.dx - anchorA.dx).abs() * 0.45 + 35;
        cpA = Offset(anchorA.dx + dist, anchorA.dy);
        cpB = Offset(anchorB.dx - dist, anchorB.dy);
      } else {
        anchorA = Offset(startRect.left, startRect.center.dy);
        anchorB = Offset(endRect.right, endRect.center.dy);
        final dist = (anchorA.dx - anchorB.dx).abs() * 0.45 + 35;
        cpA = Offset(anchorA.dx - dist, anchorA.dy);
        cpB = Offset(anchorB.dx + dist, anchorB.dy);
      }
    } else {
      if (dy >= 0) {
        anchorA = Offset(startRect.center.dx, startRect.bottom);
        anchorB = Offset(endRect.center.dx, endRect.top);
        final dist = (anchorB.dy - anchorA.dy).abs() * 0.45 + 35;
        cpA = Offset(anchorA.dx, anchorA.dy + dist);
        cpB = Offset(anchorB.dx, anchorB.dy - dist);
      } else {
        anchorA = Offset(startRect.center.dx, startRect.top);
        anchorB = Offset(endRect.center.dx, endRect.bottom);
        final dist = (anchorA.dy - anchorB.dy).abs() * 0.45 + 35;
        cpA = Offset(anchorA.dx, anchorA.dy - dist);
        cpB = Offset(anchorB.dx, anchorB.dy + dist);
      }
    }

    final path = Path()
      ..moveTo(anchorA.dx, anchorA.dy)
      ..cubicTo(cpA.dx, cpA.dy, cpB.dx, cpB.dy, anchorB.dx, anchorB.dy);

    if (isHighlighted) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.3)
        ..strokeWidth = 6.0
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, glowPaint);
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = isHighlighted ? 2.8 : 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = color;
    canvas.drawCircle(anchorA, isHighlighted ? 4.5 : 3.5, dotPaint);

    final angle = math.atan2(anchorB.dy - cpB.dy, anchorB.dx - cpB.dx);
    const arrowSize = 10.0;
    final p1 = anchorB;
    final p2 = Offset(
      anchorB.dx - arrowSize * math.cos(angle - math.pi / 7),
      anchorB.dy - arrowSize * math.sin(angle - math.pi / 7),
    );
    final p3 = Offset(
      anchorB.dx - arrowSize * math.cos(angle + math.pi / 7),
      anchorB.dy - arrowSize * math.sin(angle + math.pi / 7),
    );
    final arrowPath = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    canvas.drawPath(arrowPath, dotPaint);
  }

  @override
  bool shouldRepaint(BoardPainter oldDelegate) => true;
}

class FloatingItemOverlay extends StatefulWidget {
  const FloatingItemOverlay({
    super.key,
    required this.store,
    required this.asset,
    required this.onClose,
    this.initialPosition,
  });

  final StudioStore store;
  final CreativeObject asset;
  final VoidCallback onClose;
  final Offset? initialPosition;

  @override
  State<FloatingItemOverlay> createState() => _FloatingItemOverlayState();
}

typedef FloatingVideoPlayer = FloatingItemOverlay;

class _FloatingItemOverlayState extends State<FloatingItemOverlay> {
  Player? player;
  VideoController? controller;
  StreamSubscription<String>? errors;
  StreamSubscription<Duration>? positionSub;
  StreamSubscription<Duration>? durationSub;
  StreamSubscription<bool>? playingSub;

  late TextEditingController noteController;
  final TransformationController imageTransformController =
      TransformationController();

  String? error;
  double width = 430;
  double height = 290;
  late double posX;
  late double posY;
  bool minimized = false;
  bool markdownPreview = false;
  bool isPlaying = true;
  Duration currentPos = Duration.zero;
  Duration totalDuration = Duration.zero;

  bool get isVideo =>
      widget.asset.kind == 'asset' && widget.asset.meta['mediaType'] == 'video';
  bool get isAudio =>
      widget.asset.kind == 'asset' && widget.asset.meta['mediaType'] == 'audio';
  bool get isImage =>
      widget.asset.kind == 'asset' && widget.asset.meta['mediaType'] == 'image';
  bool get isDocument {
    final ext =
        widget.asset.meta['file']?.toString().split('.').last.toLowerCase() ??
        '';
    return [
          'pdf',
          'docx',
          'doc',
          'txt',
          'md',
          'csv',
          'json',
          'log',
        ].contains(ext) ||
        widget.asset.meta['mediaType'] == 'document' ||
        widget.asset.kind == 'source';
  }

  bool get isQuiz => widget.asset.kind == 'quiz';
  bool get isFlashcard => widget.asset.kind == 'card';
  bool get isNote =>
      !isVideo &&
      !isAudio &&
      !isImage &&
      !isDocument &&
      !isQuiz &&
      !isFlashcard;
  bool get isLightSurface => isNote || isQuiz || isFlashcard;

  @override
  void initState() {
    super.initState();
    posX = widget.initialPosition?.dx ?? 120;
    posY = widget.initialPosition?.dy ?? 100;
    noteController = TextEditingController(text: widget.asset.body);

    if (isQuiz) {
      width = 460;
      height = 420;
    } else if (isFlashcard) {
      width = 380;
      height = 280;
    } else if (isDocument) {
      width = 520;
      height = 640;
    } else if (isNote) {
      width = 380;
      height = 320;
    } else if (isImage) {
      width = 460;
      height = 340;
    }

    if (isVideo || isAudio) {
      player = Player();
      controller = VideoController(player!);
      errors = player!.stream.error.listen((e) {
        if (mounted) setState(() => error = e);
      });
      positionSub = player!.stream.position.listen((p) {
        if (mounted) setState(() => currentPos = p);
      });
      durationSub = player!.stream.duration.listen((d) {
        if (mounted) setState(() => totalDuration = d);
      });
      playingSub = player!.stream.playing.listen((p) {
        if (mounted) setState(() => isPlaying = p);
      });

      player!
          .open(Media(widget.store.mediaPath(widget.asset)), play: true)
          .catchError((Object e) {
            if (mounted) setState(() => error = '$e');
          });
    }
  }

  @override
  void dispose() {
    errors?.cancel();
    positionSub?.cancel();
    durationSub?.cancel();
    playingSub?.cancel();
    player?.dispose();
    noteController.dispose();
    imageTransformController.dispose();
    super.dispose();
  }

  String formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    posX = posX.clamp(0.0, math.max(0.0, screenSize.width - width));
    posY = posY.clamp(
      0.0,
      math.max(0.0, screenSize.height - (minimized ? 46.0 : height)),
    );

    final headerIcon = isQuiz
        ? Icons.quiz_outlined
        : isFlashcard
        ? Icons.flip_to_back_outlined
        : isVideo
        ? Icons.movie_outlined
        : isAudio
        ? Icons.audiotrack_outlined
        : isImage
        ? Icons.image_outlined
        : isDocument
        ? Icons.menu_book_outlined
        : Icons.sticky_note_2_outlined;

    return Positioned(
      left: posX,
      top: posY,
      child: Material(
        elevation: 16,
        shadowColor: ink.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(10),
        color: isLightSurface ? paper : ink,
        child: SizedBox(
          width: width,
          height: minimized ? 46 : height,
          child: Stack(
            children: [
              Container(
                width: width,
                height: minimized ? 46 : height,
                decoration: BoxDecoration(
                  color: isLightSurface ? paper : ink,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: sage.withValues(alpha: .7),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    GestureDetector(
                      onPanUpdate: (d) {
                        setState(() {
                          posX += d.delta.dx;
                          posY += d.delta.dy;
                        });
                      },
                      child: Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isLightSurface
                              ? cream
                              : Color.lerp(ink, Colors.black, .35)!,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(8),
                            topRight: Radius.circular(8),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              headerIcon,
                              size: 15,
                              color: isLightSurface ? sage : paleSage,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.asset.title,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isLightSurface ? ink : cream,
                                ),
                              ),
                            ),
                            Tag(
                              widget.asset.kind.toUpperCase(),
                              color: isLightSurface ? paleSage : ink,
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: markdownPreview
                                  ? 'Edit markdown'
                                  : 'Preview markdown',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              onPressed: isNote
                                  ? () => setState(
                                      () => markdownPreview = !markdownPreview,
                                    )
                                  : null,
                              icon: Icon(
                                markdownPreview
                                    ? Icons.edit_outlined
                                    : Icons.preview_outlined,
                                size: 15,
                                color: isLightSurface ? muted : paleSage,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Small (320px)',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              onPressed: () => setState(() {
                                width = 320;
                                height = isQuiz
                                    ? 340
                                    : (isFlashcard
                                          ? 240
                                          : (isDocument
                                                ? 420
                                                : (isNote ? 260 : 210)));
                                minimized = false;
                              }),
                              icon: Text(
                                'S',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isLightSurface ? muted : paleSage,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Medium (460px)',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              onPressed: () => setState(() {
                                width = 460;
                                height = isQuiz
                                    ? 440
                                    : (isFlashcard
                                          ? 320
                                          : (isDocument
                                                ? 580
                                                : (isNote ? 340 : 300)));
                                minimized = false;
                              }),
                              icon: Text(
                                'M',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isLightSurface ? muted : paleSage,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Large (640px)',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              onPressed: () => setState(() {
                                width = 640;
                                height = isQuiz
                                    ? 560
                                    : (isFlashcard
                                          ? 400
                                          : (isDocument
                                                ? 720
                                                : (isNote ? 440 : 400)));
                                minimized = false;
                              }),
                              icon: Text(
                                'L',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isLightSurface ? muted : paleSage,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: minimized
                                  ? 'Expand window'
                                  : 'Minimize to bar',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 26,
                                minHeight: 26,
                              ),
                              onPressed: () =>
                                  setState(() => minimized = !minimized),
                              icon: Icon(
                                minimized
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 16,
                                color: isLightSurface ? ink : paleSage,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close window',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 26,
                                minHeight: 26,
                              ),
                              onPressed: widget.onClose,
                              icon: Icon(
                                Icons.close,
                                size: 16,
                                color: isLightSurface ? ink : cream,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!minimized) ...[
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: isVideo || isAudio
                                  ? (controller != null
                                        ? Video(controller: controller!)
                                        : AssetThumbnail(
                                            store: widget.store,
                                            asset: widget.asset,
                                            fit: BoxFit.contain,
                                          ))
                                  : isImage
                                  ? Container(
                                      color: ink,
                                      child: InteractiveViewer(
                                        transformationController:
                                            imageTransformController,
                                        minScale: 0.5,
                                        maxScale: 4.0,
                                        child: Center(
                                          child: AssetThumbnail(
                                            store: widget.store,
                                            asset: widget.asset,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    )
                                  : isQuiz
                                  ? _buildFloatingQuiz()
                                  : isFlashcard
                                  ? FlashcardFlipWidget(
                                      card: widget.asset,
                                      compact: width < 420,
                                    )
                                  : isDocument
                                  ? SourceReader(
                                      store: widget.store,
                                      object: widget.asset,
                                      onCapture: (_, _) {},
                                      onAsk: (_) {},
                                    )
                                  : Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        children: [
                                          TextFormField(
                                            initialValue: widget.asset.title,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: ink,
                                            ),
                                            decoration: const InputDecoration(
                                              border: InputBorder.none,
                                              hintText: 'Title',
                                            ),
                                            onChanged: (v) {
                                              widget.asset.title = v;
                                              widget.store.changed();
                                            },
                                          ),
                                          const Divider(height: 12),
                                          Expanded(
                                            child: markdownPreview
                                                ? SingleChildScrollView(
                                                    child: MarkdownView(
                                                      data: widget.asset.body,
                                                      selectable: true,
                                                      compact: true,
                                                    ),
                                                  )
                                                : TextField(
                                                    controller: noteController,
                                                    maxLines: null,
                                                    expands: true,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      height: 1.6,
                                                      color: ink,
                                                    ),
                                                    decoration:
                                                        const InputDecoration(
                                                          border:
                                                              InputBorder.none,
                                                          hintText:
                                                              'Notes or thoughts…',
                                                        ),
                                                    onChanged: (v) {
                                                      widget.asset.body = v;
                                                      widget.store.changed();
                                                    },
                                                  ),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                            if (error != null)
                              Container(
                                color: Colors.black54,
                                padding: const EdgeInsets.all(16),
                                child: Center(
                                  child: Text(
                                    error!,
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        color: isLightSurface
                            ? line.withValues(alpha: .45)
                            : Color.lerp(ink, Colors.black, .35)!,
                        child: Row(
                          children: [
                            if (isVideo || isAudio) ...[
                              IconButton(
                                tooltip: isPlaying ? 'Pause' : 'Play',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                onPressed: () {
                                  if (player != null) player!.playOrPause();
                                },
                                icon: Icon(
                                  isPlaying ? Icons.pause : Icons.play_arrow,
                                  size: 18,
                                  color: cream,
                                ),
                              ),
                              Text(
                                formatDuration(currentPos),
                                style: TextStyle(fontSize: 10, color: paleSage),
                              ),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderThemeData(
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 5,
                                    ),
                                    trackHeight: 3,
                                    activeTrackColor: gold,
                                    inactiveTrackColor: Colors.white24,
                                    thumbColor: cream,
                                  ),
                                  child: Slider(
                                    value: currentPos.inMilliseconds
                                        .toDouble()
                                        .clamp(
                                          0.0,
                                          math.max(
                                            1.0,
                                            totalDuration.inMilliseconds
                                                .toDouble(),
                                          ),
                                        ),
                                    max: math.max(
                                      1.0,
                                      totalDuration.inMilliseconds.toDouble(),
                                    ),
                                    onChanged: (v) {
                                      player?.seek(
                                        Duration(milliseconds: v.toInt()),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              Text(
                                formatDuration(totalDuration),
                                style: TextStyle(fontSize: 10, color: paleSage),
                              ),
                            ] else if (isImage) ...[
                              TextButton.icon(
                                onPressed: () {
                                  imageTransformController.value =
                                      Matrix4.identity();
                                },
                                icon: Icon(
                                  Icons.restart_alt,
                                  size: 13,
                                  color: paleSage,
                                ),
                                label: Text(
                                  'Reset zoom',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: paleSage,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: 'Copy image title',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: widget.asset.title),
                                  );
                                },
                                icon: Icon(
                                  Icons.copy,
                                  size: 14,
                                  color: paleSage,
                                ),
                              ),
                            ] else if (isQuiz) ...[
                              Expanded(
                                child: Text(
                                  widget.asset.title,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 10, color: muted),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Tag('QUIZ', color: paleSage),
                            ] else if (isFlashcard) ...[
                              Expanded(
                                child: Text(
                                  widget.asset.title,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 10, color: muted),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Tag('CARD', color: paleSage),
                            ] else if (isDocument) ...[
                              Expanded(
                                child: Text(
                                  widget.asset.title,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 10, color: muted),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Tag('DOCUMENT', color: paleSage),
                            ] else ...[
                              Text(
                                '${widget.asset.body.trim().isEmpty ? 0 : widget.asset.body.trim().split(RegExp(r'\s+')).length} words',
                                style: TextStyle(fontSize: 10, color: muted),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: 'Copy note',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: widget.asset.body),
                                  );
                                },
                                icon: Icon(Icons.copy, size: 14, color: ink),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!minimized) ...[
                // Right edge
                Positioned(
                  right: 0,
                  top: 10,
                  bottom: 10,
                  width: 8,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: (d) {
                        setState(() {
                          width = (width + d.delta.dx).clamp(240.0, 1200.0);
                        });
                      },
                    ),
                  ),
                ),
                // Left edge
                Positioned(
                  left: 0,
                  top: 10,
                  bottom: 10,
                  width: 8,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: (d) {
                        setState(() {
                          final newW = (width - d.delta.dx).clamp(
                            240.0,
                            1200.0,
                          );
                          posX += (width - newW);
                          width = newW;
                        });
                      },
                    ),
                  ),
                ),
                // Bottom edge
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 0,
                  height: 8,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpDown,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onVerticalDragUpdate: (d) {
                        setState(() {
                          height = (height + d.delta.dy).clamp(140.0, 900.0);
                        });
                      },
                    ),
                  ),
                ),
                // Top edge
                Positioned(
                  left: 10,
                  right: 10,
                  top: 0,
                  height: 8,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpDown,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onVerticalDragUpdate: (d) {
                        setState(() {
                          final newH = (height - d.delta.dy).clamp(
                            140.0,
                            900.0,
                          );
                          posY += (height - newH);
                          height = newH;
                        });
                      },
                    ),
                  ),
                ),
                // Top-left corner
                Positioned(
                  left: 0,
                  top: 0,
                  width: 14,
                  height: 14,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpLeftDownRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (d) {
                        setState(() {
                          final newW = (width - d.delta.dx).clamp(
                            240.0,
                            1200.0,
                          );
                          final newH = (height - d.delta.dy).clamp(
                            140.0,
                            900.0,
                          );
                          posX += (width - newW);
                          posY += (height - newH);
                          width = newW;
                          height = newH;
                        });
                      },
                    ),
                  ),
                ),
                // Top-right corner
                Positioned(
                  right: 0,
                  top: 0,
                  width: 14,
                  height: 14,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpRightDownLeft,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (d) {
                        setState(() {
                          final newW = (width + d.delta.dx).clamp(
                            240.0,
                            1200.0,
                          );
                          final newH = (height - d.delta.dy).clamp(
                            140.0,
                            900.0,
                          );
                          posY += (height - newH);
                          width = newW;
                          height = newH;
                        });
                      },
                    ),
                  ),
                ),
                // Bottom-left corner
                Positioned(
                  left: 0,
                  bottom: 0,
                  width: 14,
                  height: 14,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpRightDownLeft,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (d) {
                        setState(() {
                          final newW = (width - d.delta.dx).clamp(
                            240.0,
                            1200.0,
                          );
                          final newH = (height + d.delta.dy).clamp(
                            140.0,
                            900.0,
                          );
                          posX += (width - newW);
                          width = newW;
                          height = newH;
                        });
                      },
                    ),
                  ),
                ),
                // Bottom-right corner
                Positioned(
                  right: 0,
                  bottom: 0,
                  width: 16,
                  height: 16,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpLeftDownRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (d) {
                        setState(() {
                          width = (width + d.delta.dx).clamp(240.0, 1200.0);
                          height = (height + d.delta.dy).clamp(140.0, 900.0);
                        });
                      },
                      child: Container(
                        alignment: Alignment.bottomRight,
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.south_east,
                          size: 11,
                          color: isLightSurface ? muted : paleSage,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingQuiz() {
    try {
      final decoded = jsonDecode(widget.asset.body);
      final quiz = QuizData.fromJson(Map<String, dynamic>.from(decoded));
      return QuizPlayerWidget(
        quiz: quiz,
        store: widget.store,
        compact: width < 420,
        onClose: widget.onClose,
      );
    } catch (_) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.quiz_outlined, size: 32, color: muted),
              const SizedBox(height: 8),
              Text(
                'Could not load quiz data.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
        ),
      );
    }
  }
}

class StoryboardCard extends StatelessWidget {
  const StoryboardCard({
    super.key,
    required this.store,
    required this.shot,
    required this.index,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onPlayVideo,
    required this.onDelete,
    this.isGrid = false,
  });

  final StudioStore store;
  final CreativeObject shot;
  final int index;
  final bool selected;
  final VoidCallback onTap, onEdit, onDelete;
  final void Function(CreativeObject videoAsset) onPlayVideo;
  final bool isGrid;

  CreativeObject? get mediaAsset {
    final assets = shot.links
        .map(store.project.object)
        .whereType<CreativeObject>()
        .where((o) => o.kind == 'asset')
        .toList();
    return assets.where((o) => o.meta['mediaType'] == 'video').firstOrNull ??
        assets.where((o) => o.meta['mediaType'] == 'image').firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final asset = mediaAsset;
    final isVideo = asset?.meta['mediaType'] == 'video';
    final duration = (shot.meta['duration'] as num? ?? 5.0).toDouble();
    final camera = shot.meta['camera'] as String? ?? 'Explanation';

    return DragTarget<CreativeObject>(
      onAcceptWithDetails: (d) {
        if (d.data.id != shot.id && !shot.links.contains(d.data.id)) {
          shot.links.add(d.data.id);
          store.changed();
        }
      },
      builder: (context, candidates, rejected) => Material(
        color: candidates.isNotEmpty ? paleSage.withValues(alpha: .5) : paper,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          onDoubleTap: onEdit,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? sage : line,
                width: selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(9),
              boxShadow: [
                BoxShadow(
                  color: ink.withValues(alpha: .04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    Container(
                      height: isGrid ? 170 : 130,
                      width: double.infinity,
                      clipBehavior: Clip.antiAlias,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE2E6DD),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(8),
                        ),
                      ),
                      child: asset != null
                          ? AssetThumbnail(
                              store: store,
                              asset: asset,
                              fit: BoxFit.cover,
                            )
                          : Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.panorama_outlined,
                                    size: 28,
                                    color: sage,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Drop image or video here',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: ink.withValues(alpha: .8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${index + 1}'.padLeft(2, '0'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: cream,
                          ),
                        ),
                      ),
                    ),
                    if (isVideo)
                      Positioned(
                        right: 10,
                        top: 10,
                        child: InkWell(
                          onTap: () => onPlayVideo(asset!),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: gold,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.play_arrow, size: 14, color: ink),
                                const SizedBox(width: 4),
                                Text(
                                  'POP OUT VIDEO',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 10,
                      bottom: 8,
                      child: Tag(
                        '${duration.toStringAsFixed(1)}s',
                        color: paper,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              shot.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Georgia',
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Segment options',
                            onSelected: (v) {
                              if (v == 'edit') onEdit();
                              if (v == 'delete') onDelete();
                              if (v == 'video' && isVideo) onPlayVideo(asset!);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit lesson segment'),
                              ),
                              if (isVideo)
                                const PopupMenuItem(
                                  value: 'video',
                                  child: Text('Play video in PIP player'),
                                ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete segment'),
                              ),
                            ],
                            icon: const Icon(Icons.more_vert, size: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        shot.body.isNotEmpty
                            ? shot.body
                            : 'No action or visual description written.',
                        maxLines: isGrid ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: muted,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Tag(camera, color: paleSage),
                          const Spacer(),
                          Text(
                            '${shot.links.length} links',
                            style: TextStyle(fontSize: 9, color: muted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
