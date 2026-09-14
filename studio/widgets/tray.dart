// ignore_for_file: invalid_use_of_protected_member
part of '../../studio.dart';

extension _StudioTray on _StudioState {
  Widget tray() => DragTarget<CreativeObject>(
    onAcceptWithDetails: (d) {
      d.data.meta['tray'] = true;
      store.changed();
    },
    builder: (context, candidates, rejected) {
      final trayItems = project.objects
          .where((o) => o.meta['tray'] == true)
          .toList();
      return Container(
        height: 84,
        decoration: BoxDecoration(
          color: candidates.isNotEmpty ? paleSage : cream,
          border: Border(top: BorderSide(color: line)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.inventory_2_outlined, size: 17, color: muted),
                const SizedBox(height: 4),
                Text(
                  'TEMPORARY TRAY',
                  style: TextStyle(fontSize: 8, color: muted, letterSpacing: 1),
                ),
                Text(
                  '${trayItems.length} pinned',
                  style: TextStyle(
                    fontSize: 8,
                    color: sage,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            if (trayItems.isNotEmpty)
              IconButton(
                tooltip: 'Scroll left',
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: () {
                  if (_trayScrollController.hasClients) {
                    _trayScrollController.animateTo(
                      (_trayScrollController.offset - 260).clamp(
                        0.0,
                        _trayScrollController.position.maxScrollExtent,
                      ),
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  }
                },
              ),
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                    PointerDeviceKind.stylus,
                  },
                ),
                child: Scrollbar(
                  controller: _trayScrollController,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _trayScrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 14,
                    ),
                    itemCount: trayItems.length,
                    itemBuilder: (context, index) {
                      final o = trayItems[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: drag(
                          o,
                          Container(
                            width: 230,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: paper,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: line),
                            ),
                            child: Row(
                              children: [
                                if (o.kind == 'asset' &&
                                    o.meta['mediaType'] == 'image')
                                  Container(
                                    width: 34,
                                    height: 34,
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: line),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: AssetThumbnail(
                                        store: store,
                                        asset: o,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  )
                                else if (o.kind == 'asset')
                                  Container(
                                    width: 34,
                                    height: 34,
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      color: paleSage.withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Icon(
                                      o.meta['mediaType'] == 'video'
                                          ? Icons.videocam_outlined
                                          : Icons.attachment,
                                      size: 17,
                                      color: sage,
                                    ),
                                  )
                                else
                                  Container(
                                    width: 34,
                                    height: 34,
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      color: cream,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Icon(
                                      o.kind == 'quiz'
                                          ? Icons.quiz_outlined
                                          : (o.kind == 'card'
                                                ? Icons.flip_to_back_outlined
                                                : (o.kind == 'script'
                                                      ? Icons.movie_outlined
                                                      : (o.kind == 'research'
                                                            ? Icons
                                                                  .travel_explore
                                                            : Icons
                                                                  .note_outlined))),
                                      size: 17,
                                      color: sage,
                                    ),
                                  ),
                                Expanded(
                                  child: InkWell(
                                    onTap: () => open(o),
                                    child: Text(
                                      o.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Float in overlay (PIP)',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                  onPressed: () => openFloatingVideo(o),
                                  icon: const Icon(
                                    Icons.picture_in_picture_alt,
                                    size: 14,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remove from tray',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 20,
                                    minHeight: 20,
                                  ),
                                  onPressed: () {
                                    o.meta['tray'] = false;
                                    store.changed();
                                  },
                                  icon: const Icon(Icons.close, size: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            if (trayItems.isNotEmpty)
              IconButton(
                tooltip: 'Scroll right',
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: () {
                  if (_trayScrollController.hasClients) {
                    _trayScrollController.animateTo(
                      (_trayScrollController.offset + 260).clamp(
                        0.0,
                        _trayScrollController.position.maxScrollExtent,
                      ),
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  }
                },
              ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Capture a thought',
              onPressed: quickCapture,
              icon: const Icon(Icons.add, size: 18),
            ),
            const SizedBox(width: 8),
          ],
        ),
      );
    },
  );
}
