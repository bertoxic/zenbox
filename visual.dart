import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'model.dart';
import 'theme.dart';

class AssetThumbnail extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (asset.meta['mediaType'] == 'image') {
      return Image.file(
        File(store.mediaPath(asset)),
        fit: fit,
        errorBuilder: (_, _, _) => Center(
          child: Icon(Icons.broken_image_outlined, color: muted),
        ),
      );
    }
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
  });
  final StudioStore store;
  final CreativeObject asset;
  final bool autoplay;
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
    return EmptyState(
      Icons.insert_drive_file_outlined,
      widget.asset.title,
      'This attachment is stored in your project. Use Export original to open it in another application.',
    );
  }
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
  bool connecting = false;
  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  List<CreativeObject> get nodes => widget.store.project.of('board').toList();
  void add([CreativeObject? source, Offset? point]) {
    final o = CreativeObject(
      kind: 'board',
      title: source?.title ?? 'Untitled thought',
      body: source?.body ?? 'Double-click to develop this idea.',
      links: source == null ? [] : [source.id],
      meta: {
        'x': point?.dx ?? 150.0 + nodes.length * 35,
        'y': point?.dy ?? 150.0 + nodes.length * 35,
        'color': nodes.length % 3,
      },
    );
    widget.store.add(o);
    selected = o.id;
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SectionHeading(
        'Make room for ideas',
        'The canvas',
        subtitle:
            'Drag cards to arrange · scroll to zoom · double-click to edit',
        actions: [
          IconButton(
            tooltip: 'Reset view',
            onPressed: () => transform.value = Matrix4.identity(),
            icon: const Icon(Icons.fit_screen),
          ),
          IconButton(
            tooltip: connecting
                ? 'Cancel connection'
                : 'Connect selected card to another card',
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
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: add,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add card'),
          ),
        ],
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
                  details.data,
                  Offset(point.dx.clamp(0, 2700), point.dy.clamp(0, 1750)),
                );
              },
              builder: (context, candidates, rejected) => Container(
                color: candidates.isNotEmpty
                    ? paleSage.withValues(alpha: .5)
                    : const Color(0xFFEFEFE5),
                child: InteractiveViewer(
                  transformationController: transform,
                  constrained: false,
                  boundaryMargin: const EdgeInsets.all(400),
                  minScale: .3,
                  maxScale: 2.5,
                  child: SizedBox(
                    width: 3000,
                    height: 2000,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(painter: BoardPainter(nodes)),
                        ),
                        for (final o in nodes)
                          Positioned(
                            left: (o.meta['x'] as num?)?.toDouble() ?? 100,
                            top: (o.meta['y'] as num?)?.toDouble() ?? 100,
                            child: GestureDetector(
                              onTap: () {
                                if (connecting && selected != o.id) {
                                  final source = widget.store.project.object(
                                    selected,
                                  );
                                  if (source != null &&
                                      !source.links.contains(o.id)) {
                                    source.links.add(o.id);
                                  }
                                  connecting = false;
                                  widget.store.changed();
                                }
                                setState(() => selected = o.id);
                                widget.select(o);
                              },
                              onDoubleTap: () => widget.edit(o),
                              onPanUpdate: (details) {
                                o.meta['x'] =
                                    (((o.meta['x'] as num?)?.toDouble() ??
                                                100) +
                                            details.delta.dx /
                                                transform.value
                                                    .getMaxScaleOnAxis())
                                        .clamp(0, 2700);
                                o.meta['y'] =
                                    (((o.meta['y'] as num?)?.toDouble() ??
                                                100) +
                                            details.delta.dy /
                                                transform.value
                                                    .getMaxScaleOnAxis())
                                        .clamp(0, 1750);
                                widget.store.changed();
                              },
                              child: Container(
                                width: 270,
                                padding: const EdgeInsets.all(22),
                                decoration: BoxDecoration(
                                  color: [
                                    paper,
                                    const Color(0xFFD9E2D1),
                                    const Color(0xFFEDE1C5),
                                  ][(o.meta['color'] as int? ?? 0) % 3],
                                  border: Border.all(
                                    color: selected == o.id ? sage : line,
                                    width: selected == o.id ? 2 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: ink.withValues(alpha: .07),
                                      offset: const Offset(0, 5),
                                      blurRadius: 16,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.drag_indicator,
                                          color: muted,
                                          size: 15,
                                        ),
                                        const Spacer(),
                                        IconButton(
                                          tooltip: 'Delete card',
                                          iconSize: 16,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 24,
                                            minHeight: 24,
                                          ),
                                          color: const Color(0xFFA54141),
                                          onPressed: () => widget.remove(o),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '${nodes.indexOf(o) + 1}'.padLeft(
                                            2,
                                            '0',
                                          ),
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    for (final id in o.links)
                                      if (widget.store.project
                                                  .object(id)
                                                  ?.kind ==
                                              'asset' &&
                                          widget.store.project
                                                  .object(id)
                                                  ?.meta['mediaType'] ==
                                              'image') ...[
                                        SizedBox(
                                          height: 130,
                                          width: double.infinity,
                                          child: AssetThumbnail(
                                            store: widget.store,
                                            asset: widget.store.project.object(
                                              id,
                                            )!,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                      ],
                                    Text(
                                      o.title,
                                      style: const TextStyle(
                                        fontFamily: 'Georgia',
                                        fontSize: 20,
                                        height: 1.3,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      o.body,
                                      maxLines: 6,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        height: 1.7,
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    Text(
                                      'IDEA / REFERENCE',
                                      style: TextStyle(
                                        fontSize: 8,
                                        letterSpacing: 1.5,
                                        color: muted,
                                      ),
                                    ),
                                  ],
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
          ),
        ),
      ),
    ],
  );
}

class BoardPainter extends CustomPainter {
  BoardPainter(this.nodes);
  final List<CreativeObject> nodes;
  @override
  void paint(Canvas canvas, Size size) {
    final dots = Paint()..color = sage.withValues(alpha: .25);
    for (double x = 0; x < size.width; x += 24) {
      for (double y = 0; y < size.height; y += 24) {
        canvas.drawCircle(Offset(x, y), 1, dots);
      }
    }
    final pen = Paint()
      ..color = sage
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final o in nodes) {
      for (final id in o.links) {
        final targets = nodes.where((n) => n.id == id);
        if (targets.isEmpty) continue;
        final target = targets.first;
        final a = Offset(
          (o.meta['x'] as num).toDouble() + 270,
          (o.meta['y'] as num).toDouble() + 100,
        );
        final b = Offset(
          (target.meta['x'] as num).toDouble(),
          (target.meta['y'] as num).toDouble() + 100,
        );
        canvas.drawPath(
          Path()
            ..moveTo(a.dx, a.dy)
            ..cubicTo(a.dx + 80, a.dy, b.dx - 80, b.dy, b.dx, b.dy),
          pen,
        );
      }
    }
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
  bool isPlaying = true;
  Duration currentPos = Duration.zero;
  Duration totalDuration = Duration.zero;

  bool get isVideo =>
      widget.asset.kind == 'asset' && widget.asset.meta['mediaType'] == 'video';
  bool get isAudio =>
      widget.asset.kind == 'asset' && widget.asset.meta['mediaType'] == 'audio';
  bool get isImage =>
      widget.asset.kind == 'asset' && widget.asset.meta['mediaType'] == 'image';
  bool get isNote => !isVideo && !isAudio && !isImage;

  @override
  void initState() {
    super.initState();
    posX = widget.initialPosition?.dx ?? 120;
    posY = widget.initialPosition?.dy ?? 100;
    noteController = TextEditingController(text: widget.asset.body);

    if (isNote) {
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

    final headerIcon = isVideo
        ? Icons.movie_outlined
        : isAudio
        ? Icons.audiotrack_outlined
        : isImage
        ? Icons.image_outlined
        : Icons.sticky_note_2_outlined;

    return Positioned(
      left: posX,
      top: posY,
      child: Material(
        elevation: 16,
        shadowColor: ink.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(10),
        color: isNote ? paper : ink,
        child: SizedBox(
          width: width,
          height: minimized ? 46 : height,
          child: Stack(
            children: [
              Container(
                width: width,
                height: minimized ? 46 : height,
                decoration: BoxDecoration(
                  color: isNote ? paper : ink,
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
                          color: isNote
                              ? const Color(0xFFE4E7DC)
                              : const Color(0xFF222923),
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
                              color: isNote ? sage : paleSage,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.asset.title,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isNote ? ink : cream,
                                ),
                              ),
                            ),
                            Tag(
                              widget.asset.kind.toUpperCase(),
                              color: isNote ? paleSage : ink,
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: 'Small (320px)',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              onPressed: () => setState(() {
                                width = 320;
                                height = isNote ? 260 : 210;
                                minimized = false;
                              }),
                              icon: Text(
                                'S',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isNote ? muted : paleSage,
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
                                height = isNote ? 340 : 300;
                                minimized = false;
                              }),
                              icon: Text(
                                'M',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isNote ? muted : paleSage,
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
                                height = isNote ? 440 : 400;
                                minimized = false;
                              }),
                              icon: Text(
                                'L',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isNote ? muted : paleSage,
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
                                color: isNote ? ink : paleSage,
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
                                color: isNote ? ink : cream,
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
                                  : Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: TextField(
                                        controller: noteController,
                                        maxLines: null,
                                        expands: true,
                                        style: TextStyle(
                                          fontSize: 12,
                                          height: 1.6,
                                          color: ink,
                                        ),
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          hintText: 'Notes or thoughts…',
                                        ),
                                        onChanged: (v) {
                                          widget.asset.body = v;
                                          widget.store.changed();
                                        },
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
                        color: isNote
                            ? const Color(0xFFEDEFE5)
                            : const Color(0xFF1B211C),
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
                          color: isNote ? muted : paleSage,
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
    final camera = shot.meta['camera'] as String? ?? 'Medium Shot';

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
                            tooltip: 'Shot options',
                            onSelected: (v) {
                              if (v == 'edit') onEdit();
                              if (v == 'delete') onDelete();
                              if (v == 'video' && isVideo) onPlayVideo(asset!);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit shot details'),
                              ),
                              if (isVideo)
                                const PopupMenuItem(
                                  value: 'video',
                                  child: Text('Play video in PIP player'),
                                ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete shot'),
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
