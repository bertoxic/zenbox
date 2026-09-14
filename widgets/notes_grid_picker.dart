import 'package:flutter/material.dart';
import 'package:zenbox/models/model.dart';
import 'package:zenbox/theme/theme.dart';

/// A floating modal dialog showing a responsive grid of notes/documents,
/// with real-time search filtering, kind badges, and body excerpts.
class NotesGridPickerModal extends StatefulWidget {
  const NotesGridPickerModal({
    super.key,
    required this.sources,
    this.initialSelection,
    this.title = 'Select Note or Document',
    this.isPdf,
  });

  final List<CreativeObject> sources;
  final CreativeObject? initialSelection;
  final String title;
  final bool Function(CreativeObject? o)? isPdf;

  @override
  State<NotesGridPickerModal> createState() => _NotesGridPickerModalState();
}

class _NotesGridPickerModalState extends State<NotesGridPickerModal> {
  final TextEditingController _searchController = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _checkIsPdf(CreativeObject? o) {
    if (widget.isPdf != null) return widget.isPdf!(o);
    if (o == null) return false;
    final ext = o.meta['file']?.toString().split('.').last.toLowerCase() ?? '';
    return ext == 'pdf';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.sources.where((s) {
      if (_filter.isEmpty) return true;
      final q = _filter.toLowerCase();
      return s.title.toLowerCase().contains(q) ||
          s.body.toLowerCase().contains(q) ||
          s.kind.toLowerCase().contains(q);
    }).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: paper,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.notes_rounded, size: 22, color: sage),
                  const SizedBox(width: 10),
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: ink,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '(${widget.sources.length} available)',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, size: 19),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Filter by title, content, or kind…',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  filled: true,
                  fillColor: cream,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: line),
                  ),
                  suffixIcon: _filter.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _filter = '');
                          },
                        )
                      : null,
                ),
                onChanged: (v) => setState(() => _filter = v.trim()),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          _filter.isEmpty
                              ? 'No notes or documents found.'
                              : 'No matching notes for "$_filter"',
                          style: TextStyle(color: muted, fontSize: 13),
                        ),
                      )
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 260,
                          mainAxisExtent: 145,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final o = filtered[index];
                          final isSelected =
                              widget.initialSelection?.id == o.id;
                          final isPdf = _checkIsPdf(o);
                          final icon = isPdf
                              ? Icons.picture_as_pdf_outlined
                              : [
                                  'concept',
                                  'definition',
                                  'formula',
                                ].contains(o.kind)
                              ? Icons.lightbulb_outline
                              : Icons.description_outlined;

                          return Material(
                            color: isSelected
                                ? sage.withValues(alpha: .12)
                                : cream,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => Navigator.pop(context, o),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected ? sage : line,
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          icon,
                                          size: 16,
                                          color: isSelected ? sage : gold,
                                        ),
                                        const SizedBox(width: 6),
                                        Tag(
                                          o.kind,
                                          color:
                                              isSelected ? sage : paleSage,
                                        ),
                                        const Spacer(),
                                        if (isSelected)
                                          Icon(
                                            Icons.check_circle,
                                            size: 16,
                                            color: sage,
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      o.title.isEmpty
                                          ? 'Untitled ${o.kind}'
                                          : o.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Expanded(
                                      child: Text(
                                        o.body.trim().isEmpty
                                            ? 'No content written yet.'
                                            : o.body.trim(),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: muted,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
