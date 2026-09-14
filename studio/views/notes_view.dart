// ignore_for_file: invalid_use_of_protected_member, unused_element
part of '../../studio.dart';

extension _StudioNotesView on _StudioState {
  Widget writing([String? requestedMode]) {
    final documents = project.objects
        .where((o) => o.kind == 'script' || o.kind == 'manuscript')
        .toList();
    final isNoteKind =
        selected?.kind == 'script' || selected?.kind == 'manuscript';
    final current = isNoteKind ? selected : documents.firstOrNull;
    if (current == null) {
      return EmptyState(
        Icons.edit_outlined,
        'Start with a topic you want to understand.',
        'Create a study note or guide to begin.',
        action: FilledButton.icon(
          onPressed: () => create('script'),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Create note'),
        ),
      );
    }
    return Column(
      children: [
        studyActions(current),
        Expanded(
          child: DocumentEditor(
            key: ValueKey(current.id),
            store: store,
            object: current,
            siblingDocuments: documents,
            onSwitchDocument: (document) {
              setState(() => selectedId = document.id);
              saveLayout();
            },
            onNewDocument: () => create('script'),
            onInspect: () {
              setState(() {
                dock = 'Inspector';
                showDock = true;
              });
            },
            onExport: () => run(() => exportPdf(current)),
            onAskAi: (req) {
              lastSelection = req;
              setState(() {
                dock = 'AI';
                showDock = true;
              });
              ai.ask('Regarding "${req.text}":\n${req.action}');
            },
            onPreview: preview,
            onDelete: () => remove(current),
          ),
        ),
      ],
    );
  }

  Widget scratchpadWorkspace() => conceptBankWorkspace();
  Widget scratchpadGridCard(CreativeObject note) => conceptBankGridCard(note);

  Widget documentViewerWorkspace() {
    if (activeDocument == null) {
      return const Center(child: Text('No document selected'));
    }
    final doc = activeDocument!;
    return Column(
      children: [
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: paper,
            border: Border(bottom: BorderSide(color: line)),
          ),
          child: Row(
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                onPressed: () {
                  setState(() {
                    mode = previousModeBeforeDocument ?? 'Media library';
                    activeDocument = null;
                  });
                },
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('Back', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 14),
              Icon(Icons.description, size: 18, color: sage),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  doc.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TextButton.icon(
                onPressed: () => run(() async {
                  final result = await FilePicker.saveFile(
                    fileName: safeName(doc.title),
                    bytes: await File(store.mediaPath(doc)).readAsBytes(),
                  );
                  if (result != null) toast('Original exported');
                }),
                icon: const Icon(Icons.download, size: 16),
                label: const Text(
                  'Export original',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: sage,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                onPressed: () => openQuizGenerator(source: doc),
                icon: const Icon(Icons.quiz_outlined, size: 16),
                label: const Text(
                  'Quiz or cards',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Pop out in floating window',
                onPressed: () => openFloatingVideo(doc),
                icon: const Icon(Icons.picture_in_picture_alt, size: 19),
              ),
            ],
          ),
        ),
        Expanded(
          child: MediaPreview(
            key: ValueKey(doc.id),
            store: store,
            asset: doc,
            autoplay: true,
            compactDocumentHeader: true,
          ),
        ),
      ],
    );
  }

}
