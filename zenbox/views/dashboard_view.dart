import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:zenbox/theme/theme.dart';
import 'package:zenbox/models/zenbox_model.dart';
import 'package:zenbox/theme/zenbox_theme.dart';

class DashboardView extends StatefulWidget {
  const DashboardView({
    super.key,
    required this.store,
    required this.onNavigate,
  });
  final ZenboxStore store;
  final void Function(String mode, {String? courseId, String? noteId})
  onNavigate;

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  ZenboxStore get store => widget.store;

  Future<void> _pickWallpaper() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Dashboard illustration',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Choose a Zenbox illustration or add your own image.',
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final option in bundledDashboardIllustrations)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        setState(() {
                          store.project.layout['dashboardWallpaperAsset'] =
                              option.assetPath;
                          store.project.layout['overviewWallpaperAsset'] =
                              option.assetPath;
                          store.project.layout.remove('dashboardWallpaper');
                          store.project.layout.remove('overviewWallpaper');
                        });
                        studioSettingsNotifier.value =
                            studioSettingsNotifier.value.copyWith(
                          dashboardWallpaperAsset: option.assetPath,
                          clearDashboardWallpaper: true,
                        );
                        store.changed();
                        Navigator.pop(context);
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 120,
                            height: 74,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: (store.project.layout['dashboardWallpaperAsset'] ??
                                            store.project.layout['overviewWallpaperAsset'] ??
                                            studioSettingsNotifier.value.dashboardWallpaperAsset ??
                                            defaultDashboardWallpaperAsset) ==
                                        option.assetPath &&
                                    (store.project.layout['dashboardWallpaper'] == null &&
                                        store.project.layout['overviewWallpaper'] == null &&
                                        studioSettingsNotifier.value.dashboardWallpaper == null)
                                    ? moss
                                    : edge,
                                width: (store.project.layout['dashboardWallpaperAsset'] ??
                                            store.project.layout['overviewWallpaperAsset'] ??
                                            studioSettingsNotifier.value.dashboardWallpaperAsset ??
                                            defaultDashboardWallpaperAsset) ==
                                        option.assetPath &&
                                    (store.project.layout['dashboardWallpaper'] == null &&
                                        store.project.layout['overviewWallpaper'] == null &&
                                        studioSettingsNotifier.value.dashboardWallpaper == null)
                                    ? 2.5
                                    : 1,
                              ),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.asset(option.assetPath, fit: BoxFit.cover),
                                if ((store.project.layout['dashboardWallpaperAsset'] ??
                                            store.project.layout['overviewWallpaperAsset'] ??
                                            studioSettingsNotifier.value.dashboardWallpaperAsset ??
                                            defaultDashboardWallpaperAsset) ==
                                        option.assetPath &&
                                    (store.project.layout['dashboardWallpaper'] == null &&
                                        store.project.layout['overviewWallpaper'] == null &&
                                        studioSettingsNotifier.value.dashboardWallpaper == null))
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: moss,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.check,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: 120,
                            child: Text(
                              option.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add_photo_alternate_outlined),
                title: const Text('Use custom image…'),
                subtitle: const Text('Pick any JPG, PNG, or WEBP from your computer'),
                onTap: () async {
                  final result = await FilePicker.pickFiles(
                    type: FileType.image,
                  );
                  if (result.isEmpty ||
                      result.single.path == null ||
                      !context.mounted) {
                    return;
                  }
                  final pickedPath = result.single.path!;
                  setState(() {
                    store.project.layout['dashboardWallpaper'] = pickedPath;
                    store.project.layout['overviewWallpaper'] = pickedPath;
                    store.project.layout.remove('dashboardWallpaperAsset');
                    store.project.layout.remove('overviewWallpaperAsset');
                  });
                  studioSettingsNotifier.value =
                      studioSettingsNotifier.value.copyWith(
                    dashboardWallpaper: pickedPath,
                    clearDashboardWallpaperAsset: true,
                  );
                  store.changed();
                  if (context.mounted) Navigator.pop(context);
                },
              ),
              if (store.project.layout['dashboardWallpaper'] != null ||
                  store.project.layout['overviewWallpaper'] != null ||
                  store.project.layout['dashboardWallpaperAsset'] != null ||
                  store.project.layout['overviewWallpaperAsset'] != null ||
                  studioSettingsNotifier.value.dashboardWallpaper != null ||
                  studioSettingsNotifier.value.dashboardWallpaperAsset != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.restart_alt),
                  title: const Text('Restore default illustration'),
                  onTap: () {
                    setState(() {
                      store.project.layout.remove('dashboardWallpaper');
                      store.project.layout.remove('overviewWallpaper');
                      store.project.layout.remove('dashboardWallpaperAsset');
                      store.project.layout.remove('overviewWallpaperAsset');
                    });
                    studioSettingsNotifier.value =
                        studioSettingsNotifier.value.copyWith(
                      clearDashboardWallpaper: true,
                      clearDashboardWallpaperAsset: true,
                    );
                    store.changed();
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final customWallpaper =
          store.project.layout['dashboardWallpaper'] as String? ??
          store.project.layout['overviewWallpaper'] as String? ??
          studioSettingsNotifier.value.dashboardWallpaper;
      final assetWallpaper =
          store.project.layout['dashboardWallpaperAsset'] as String? ??
          store.project.layout['overviewWallpaperAsset'] as String? ??
          studioSettingsNotifier.value.dashboardWallpaperAsset ??
          defaultDashboardWallpaperAsset;
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          // Hero Banner
          _HeroBanner(
            dueCount: store.dueCards.length,
            onStudy: () => widget.onNavigate('Review'),
            customWallpaperPath: customWallpaper,
            wallpaperAssetPath: assetWallpaper,
            onChangeWallpaper: _pickWallpaper,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatRow(store: store),
                const SizedBox(height: 36),
                _SectionHeader(
                  icon: Icons.auto_stories_outlined,
                  label: 'Enrolled Courses',
                  illustrationAsset: 'assets/illustrations/dashboard_courses.jpg',
                ),
                const SizedBox(height: 14),
                if (store.courses.isEmpty)
                  _EmptyBanner(
                    icon: Icons.school_outlined,
                    message: 'No courses yet. Add one from the workspace menu.',
                  )
                else
                  ...store.courses.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CourseCard(
                        course: c,
                        onTap: () => widget.onNavigate('Notes', courseId: c.id),
                      ),
                    ),
                  ),
                const SizedBox(height: 36),
                _SectionHeader(
                  icon: Icons.edit_note,
                  label: 'Pick up where you left off',
                ),
                const SizedBox(height: 6),
                if (store.notes.isEmpty)
                  _EmptyBanner(
                    icon: Icons.description_outlined,
                    message: 'No notes yet. Create your first note.',
                  )
                else
                  _RecentNotesList(store: store, onNavigate: widget.onNavigate),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      );
    },
  );
}


// Hero Banner

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.dueCount,
    required this.onStudy,
    required this.onChangeWallpaper,
    this.customWallpaperPath,
    this.wallpaperAssetPath,
  });
  final int dueCount;
  final VoidCallback onStudy;
  final VoidCallback onChangeWallpaper;
  final String? customWallpaperPath;
  final String? wallpaperAssetPath;

  @override
  Widget build(BuildContext context) {
    final assetFallback =
        wallpaperAssetPath ?? defaultDashboardWallpaperAsset;
    return SizedBox(
      height: 250,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background image: custom or bundled asset
          if (customWallpaperPath != null && customWallpaperPath!.isNotEmpty)
            Image.file(
              File(customWallpaperPath!),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Image.asset(
                assetFallback,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: forest),
              ),
            )
          else
            Image.asset(
              assetFallback,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(color: forest),
            ),
          // Dark gradient overlay
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: [Colors.transparent, Color(0xCC1C321A)],
                stops: [0.35, 1.0],
              ),
            ),
          ),
          // Text content
          Positioned(
            left: 32,
            bottom: 32,
            right: 200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'MAKE ROOM FOR UNDERSTANDING',
                  style: TextStyle(
                    color: olive.withValues(alpha: .9),
                    letterSpacing: 1.8,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  dueCount == 0
                      ? 'Your study space is ready'
                      : '$dueCount ideas ready to revisit',
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Georgia',
                    fontSize: 26,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Recall first. A little practice goes a long way.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: onStudy,
                  icon: const Icon(Icons.school_outlined, size: 16),
                  label: const Text('Begin study session'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: .15),
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: .3),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Decorative dot grid
          Positioned(
            top: 16,
            right: 24,
            child: CustomPaint(
              size: const Size(90, 55),
              painter: _DotGridPainter(
                color: Colors.white.withValues(alpha: .18),
              ),
            ),
          ),
          // Wallpaper change button (top-right corner)
          Positioned(
            top: 10,
            right: 10,
            child: Tooltip(
              message: 'Change banner image',
              child: InkWell(
                onTap: onChangeWallpaper,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .28),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.wallpaper_outlined,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


// Dot grid painter

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const cols = 6;
    const rows = 4;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        canvas.drawCircle(
          Offset(c * size.width / (cols - 1), r * size.height / (rows - 1)),
          2.2,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter old) => old.color != color;
}

// Wave painter (decorative)

class _WavePainter extends CustomPainter {
  const _WavePainter({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final path = Path();
    path.moveTo(0, size.height / 2);
    final waveLen = size.width / 4;
    for (var i = 0; i < 4; i++) {
      final x = i * waveLen;
      path.cubicTo(
        x + waveLen * 0.25, 0,
        x + waveLen * 0.75, size.height,
        x + waveLen, size.height / 2,
      );
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.color != color;
}

// Stat row

class _StatRow extends StatelessWidget {
  const _StatRow({required this.store});
  final ZenboxStore store;

  @override
  Widget build(BuildContext context) {
    final stats = [
      (Icons.sticky_note_2_outlined, '${store.notes.length}', 'Notes', moss),
      (
        Icons.travel_explore,
        '${store.sources.length + store.assets.length}',
        'Research & assets',
        bark,
      ),
      (
        Icons.checklist_outlined,
        '${store.tasks.where((t) => !t.isCompleted).length}',
        'Open tasks',
        olive,
      ),
      (
        Icons.timer_outlined,
        '${store.sessions.fold<int>(0, (s, e) => s + e.durationMinutes)} min',
        'Focused study',
        forest,
      ),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: stats
          .map(
            (s) => _StatCard(
              icon: s.$1,
              value: s.$2,
              label: s.$3,
              accent: s.$4,
            ),
          )
          .toList(),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.accent,
  });
  final IconData icon;
  final String value, label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: edge),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: accent),
                ),
                const Spacer(),
                SizedBox(
                  width: 52,
                  height: 18,
                  child: CustomPaint(
                    painter: _WavePainter(
                      color: accent.withValues(alpha: .3),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: forest,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: secondaryInk,
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Section header

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    this.illustrationAsset,
  });
  final IconData icon;
  final String label;
  final String? illustrationAsset;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: moss),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        if (illustrationAsset != null) ...[
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              illustrationAsset!,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ],
      ],
    );
  }
}

// Course card

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course, required this.onTap});
  final Course course;
  final VoidCallback onTap;

  Color _accent() {
    final hue = (course.code.codeUnits.fold(0, (a, b) => a + b) % 6);
    return [
      moss, bark, olive, forest,
      const Color(0xFF7A6B58), secondaryInk,
    ][hue];
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent();
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: edge),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 72,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .1),
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(13),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_stories_outlined, color: accent, size: 20),
                    const SizedBox(height: 4),
                    Text(
                      course.code.length > 4
                          ? course.code.substring(0, 4)
                          : course.code,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        color: accent,
                        letterSpacing: .5,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.code,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        course.title,
                        style: const TextStyle(
                          fontSize: 12, color: secondaryInk,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (course.instructor.isNotEmpty)
                        Text(
                          course.instructor,
                          style: TextStyle(
                            fontSize: 10,
                            color: secondaryInk.withValues(alpha: .7),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Icon(
                  Icons.north_east, size: 16,
                  color: accent.withValues(alpha: .6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Recent notes list

class _RecentNotesList extends StatelessWidget {
  const _RecentNotesList({required this.store, required this.onNavigate});
  final ZenboxStore store;
  final void Function(String, {String? courseId, String? noteId}) onNavigate;

  @override
  Widget build(BuildContext context) {
    final notes = store.notes.take(5).toList();
    return Column(
      children: List.generate(notes.length, (i) {
        final n = notes[i];
        final courseCode = store.getCourse(n.courseId)?.code ?? 'Personal';
        final accent = i.isEven ? moss : olive;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => onNavigate('Notes', noteId: n.id),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: edge),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .1),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            n.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            courseCode,
                            style: const TextStyle(
                              fontSize: 10, color: secondaryInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios, size: 12, color: secondaryInk,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

// Empty banner

class _EmptyBanner extends StatelessWidget {
  const _EmptyBanner({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: edge),
      ),
      child: Row(
        children: [
          Icon(icon, size: 28, color: moss.withValues(alpha: .5)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: secondaryInk, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
