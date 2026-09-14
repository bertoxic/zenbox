import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class StudioPalette {
  const StudioPalette({
    required this.cream,
    required this.sage,
    required this.paleSage,
    required this.gold,
    required this.ink,
    required this.muted,
    required this.line,
    required this.paper,
  });

  final Color cream, sage, paleSage, gold, ink, muted, line, paper;

  factory StudioPalette.forPreset(StudioThemePreset preset) {
    final dark = preset == StudioThemePreset.obsidian;
    final primary = preset.primary;
    final surface = preset.paper;
    final foreground = preset.ink;
    return StudioPalette(
      cream: preset.background,
      sage: primary,
      paleSage: Color.lerp(primary, surface, dark ? .42 : .63)!,
      gold: dark ? const Color(0xFFE2C675) : const Color(0xFFC7A866),
      ink: foreground,
      muted: Color.lerp(foreground, surface, dark ? .44 : .48)!,
      line: Color.lerp(foreground, surface, dark ? .78 : .87)!,
      paper: surface,
    );
  }
}

StudioPalette _activeStudioPalette = StudioPalette.forPreset(
  StudioThemePreset.sage,
);

Color get cream => _activeStudioPalette.cream;
Color get sage => _activeStudioPalette.sage;
Color get paleSage => _activeStudioPalette.paleSage;
Color get gold => _activeStudioPalette.gold;
Color get ink => _activeStudioPalette.ink;
Color get muted => _activeStudioPalette.muted;
Color get line => _activeStudioPalette.line;
Color get paper => _activeStudioPalette.paper;

enum StudioThemePreset {
  sage(
    label: 'Sage',
    description: 'Zenbox natural study palette',
    primary: Color(0xFF42562E),
    background: Color(0xFFF5F5EE),
    ink: Color(0xFF1C321A),
    paper: Color(0xFFFFFEF8),
  ),
  obsidian(
    label: 'Obsidian Slate',
    description: 'A quiet, low-light study space',
    primary: Color(0xFF7A9BB8),
    background: Color(0xFF181C22),
    ink: Color(0xFFE2E7ED),
    paper: Color(0xFF222832),
  ),
  sand(
    label: 'Warm Sand',
    description: 'Warm, comfortable reading',
    primary: Color(0xFFB57A3D),
    background: Color(0xFFFAF6EE),
    ink: Color(0xFF382E25),
    paper: Color(0xFFFFFDF8),
  ),
  cobalt(
    label: 'Deep Cobalt',
    description: 'Clear blue for focused learning',
    primary: Color(0xFF456C9C),
    background: Color(0xFFF2F6FA),
    ink: Color(0xFF1E2B38),
    paper: Color(0xFFFAFCFF),
  ),
  rosewood(
    label: 'Rosewood Velvet',
    description: 'A soft rose study palette',
    primary: Color(0xFFA55A6B),
    background: Color(0xFFFAF2F4),
    ink: Color(0xFF382329),
    paper: Color(0xFFFFF7F9),
  );

  const StudioThemePreset({
    required this.label,
    required this.description,
    required this.primary,
    required this.background,
    required this.ink,
    required this.paper,
  });

  final String label;
  final String description;
  final Color primary;
  final Color background;
  final Color ink;
  final Color paper;
}

class DashboardIllustrationOption {
  final String assetPath;
  final String title;
  final String description;

  const DashboardIllustrationOption({
    required this.assetPath,
    required this.title,
    required this.description,
  });
}

const defaultDashboardWallpaperAsset =
    'assets/illustrations/learning_workspace_hero.png';

const bundledDashboardIllustrations = [
  DashboardIllustrationOption(
    assetPath: 'assets/illustrations/learning_workspace_hero.png',
    title: 'Learning Workspace',
    description: 'Modern focus desk with notes and morning light',
  ),
  DashboardIllustrationOption(
    assetPath: 'assets/illustrations/dashboard_hero.jpg',
    title: 'Hero Library',
    description: 'Warm, classic library reading hall with arches',
  ),
  DashboardIllustrationOption(
    assetPath: 'assets/illustrations/dashboard_study_library.png',
    title: 'Study Library',
    description: 'Quiet archive bookshelf with study desk',
  ),
  DashboardIllustrationOption(
    assetPath: 'assets/illustrations/dashboard_cozy_nook.png',
    title: 'Cozy Nook',
    description: 'Comfortable reading armchair and soft lamplight',
  ),
  DashboardIllustrationOption(
    assetPath: 'assets/illustrations/dashboard_note_arrangement.png',
    title: 'Note Arrangement',
    description: 'Structured index cards, diagrams, and outlines',
  ),
  DashboardIllustrationOption(
    assetPath: 'assets/illustrations/dashboard_courses.jpg',
    title: 'Course Stacks',
    description: 'Academic syllabus textbooks and lecture notes',
  ),
  DashboardIllustrationOption(
    assetPath: 'assets/illustrations/dashboard_concept_map.png',
    title: 'Concept Map',
    description: 'Connected mental models and visual knowledge graphs',
  ),
  DashboardIllustrationOption(
    assetPath: 'assets/illustrations/dashboard_flashcards.png',
    title: 'Flashcards & Recall',
    description: 'Spaced repetition revision cards with timer',
  ),
  DashboardIllustrationOption(
    assetPath: 'assets/illustrations/dashboard_headphones.png',
    title: 'Focus & Audio',
    description: 'Ambient soundscape and headphones study session',
  ),
  DashboardIllustrationOption(
    assetPath: 'assets/illustrations/dashboard_tea_break.png',
    title: 'Tea Break',
    description: 'Mindful pause with herbal tea and open notebook',
  ),
];

class StudioSettings {
  final StudioThemePreset themePreset;
  final String editorFont;
  final double editorLineHeight;
  final int autoSaveSeconds;
  final String aiPersona;
  final bool typewriterEffect;
  final String? dashboardWallpaper;
  final String? dashboardWallpaperAsset;

  const StudioSettings({
    this.themePreset = StudioThemePreset.sage,
    this.editorFont = 'Segoe UI',
    this.editorLineHeight = 1.75,
    this.autoSaveSeconds = 15,
    this.aiPersona = 'Balanced Producer',
    this.typewriterEffect = true,
    this.dashboardWallpaper,
    this.dashboardWallpaperAsset,
  });

  StudioSettings copyWith({
    StudioThemePreset? themePreset,
    String? editorFont,
    double? editorLineHeight,
    int? autoSaveSeconds,
    String? aiPersona,
    bool? typewriterEffect,
    String? dashboardWallpaper,
    bool clearDashboardWallpaper = false,
    String? dashboardWallpaperAsset,
    bool clearDashboardWallpaperAsset = false,
  }) {
    return StudioSettings(
      themePreset: themePreset ?? this.themePreset,
      editorFont: editorFont ?? this.editorFont,
      editorLineHeight: editorLineHeight ?? this.editorLineHeight,
      autoSaveSeconds: autoSaveSeconds ?? this.autoSaveSeconds,
      aiPersona: aiPersona ?? this.aiPersona,
      typewriterEffect: typewriterEffect ?? this.typewriterEffect,
      dashboardWallpaper: clearDashboardWallpaper
          ? null
          : (dashboardWallpaper ?? this.dashboardWallpaper),
      dashboardWallpaperAsset: clearDashboardWallpaperAsset
          ? null
          : (dashboardWallpaperAsset ?? this.dashboardWallpaperAsset),
    );
  }

  Map<String, dynamic> toJson() => {
    'themePreset': themePreset.name,
    'editorFont': editorFont,
    'editorLineHeight': editorLineHeight,
    'autoSaveSeconds': autoSaveSeconds,
    'aiPersona': aiPersona,
    'typewriterEffect': typewriterEffect,
    'dashboardWallpaper': dashboardWallpaper,
    'dashboardWallpaperAsset': dashboardWallpaperAsset,
  };

  factory StudioSettings.fromJson(Map<String, dynamic> j) {
    var preset = StudioThemePreset.sage;
    final presetName = j['themePreset'] as String?;
    if (presetName != null) {
      for (final p in StudioThemePreset.values) {
        if (p.name == presetName) {
          preset = p;
          break;
        }
      }
    }
    return StudioSettings(
      themePreset: preset,
      editorFont: j['editorFont'] as String? ?? 'Segoe UI',
      editorLineHeight: (j['editorLineHeight'] as num?)?.toDouble() ?? 1.75,
      autoSaveSeconds: (j['autoSaveSeconds'] as num?)?.toInt() ?? 15,
      aiPersona: j['aiPersona'] as String? ?? 'Balanced Producer',
      typewriterEffect: j['typewriterEffect'] as bool? ?? true,
      dashboardWallpaper: j['dashboardWallpaper'] as String?,
      dashboardWallpaperAsset: j['dashboardWallpaperAsset'] as String?,
    );
  }
}

File? _cachedSettingsFile;

Future<File> _getSettingsFile() async {
  if (_cachedSettingsFile != null) return _cachedSettingsFile!;
  final support = await getApplicationSupportDirectory();
  final dir = Directory('${support.path}/Zenbox');
  if (!dir.existsSync()) {
    await dir.create(recursive: true);
  }
  _cachedSettingsFile = File('${dir.path}/studio_settings.json');
  return _cachedSettingsFile!;
}

Future<void> saveStudioSettings(StudioSettings settings, {File? file}) async {
  try {
    final targetFile = file ?? await _getSettingsFile();
    final jsonStr = jsonEncode(settings.toJson());
    await targetFile.writeAsString(jsonStr, flush: true);
  } catch (e) {
    debugPrint('Could not save studio settings: $e');
  }
}

Future<StudioSettings> loadStudioSettings({File? file}) async {
  try {
    final targetFile = file ?? await _getSettingsFile();
    if (targetFile.existsSync()) {
      final jsonStr = await targetFile.readAsString();
      if (jsonStr.trim().isNotEmpty) {
        final j = jsonDecode(jsonStr) as Map<String, dynamic>;
        return StudioSettings.fromJson(j);
      }
    }
  } catch (e) {
    debugPrint('Could not load studio settings: $e');
  }
  return const StudioSettings();
}

bool _isAutoSaveInitialized = false;

void initStudioSettingsAutoSave() {
  if (_isAutoSaveInitialized) return;
  _isAutoSaveInitialized = true;
  studioSettingsNotifier.addListener(() {
    saveStudioSettings(studioSettingsNotifier.value);
  });
}

final studioSettingsNotifier = ValueNotifier<StudioSettings>(
  const StudioSettings(),
);

ThemeData studioTheme([StudioSettings? settings]) {
  final s = settings ?? studioSettingsNotifier.value;
  _activeStudioPalette = StudioPalette.forPreset(s.themePreset);
  final isDark = s.themePreset == StudioThemePreset.obsidian;
  final bg = s.themePreset.background;
  final textInk = s.themePreset.ink;
  final prim = s.themePreset.primary;
  final paperBg = s.themePreset.paper;
  final borderColor = isDark ? const Color(0xFF2E3846) : line;

  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Segoe UI',
    brightness: isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: prim,
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: prim,
      secondary: gold,
      surface: paperBg,
      onSurface: textInk,
    ),
    textTheme: TextTheme(
      bodyMedium: TextStyle(fontSize: 13, color: textInk),
      bodySmall: TextStyle(
        fontSize: 11,
        color: isDark ? const Color(0xFF8E9BAA) : muted,
      ),
    ),
    dividerColor: borderColor,
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: paperBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: borderColor),
      ),
      contentPadding: const EdgeInsets.all(13),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: borderColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: isDark ? const Color(0xFF8E9BAA) : muted,
        iconSize: 19,
      ),
    ),
  );
}

class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.color});
  final String label;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: (color ?? paleSage).withValues(alpha: .35),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, color: ink, fontWeight: FontWeight.w600),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState(
    this.icon,
    this.title,
    this.subtitle, {
    super.key,
    this.action,
  });
  final IconData icon;
  final String title, subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: sage),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(fontSize: 21, fontFamily: 'Georgia'),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, height: 1.7),
            ),
            if (action != null) ...[const SizedBox(height: 22), action!],
          ],
        ),
      ),
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(
    this.eyebrow,
    this.title, {
    super.key,
    this.subtitle,
    this.actions = const [],
  });
  final String eyebrow, title;
  final String? subtitle;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
    child: LayoutBuilder(builder: (context, constraints) {
      final heading = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(eyebrow.toUpperCase(), style: TextStyle(color: sage, fontSize: 10,
          letterSpacing: 1.2, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(fontSize: 26,
          fontWeight: FontWeight.w600, letterSpacing: -.6, height: 1.2)),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle!, style: TextStyle(color: muted, fontSize: 12, height: 1.5)),
        ],
      ]);
      if (constraints.maxWidth < 900) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          heading,
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 6, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center,
              children: actions),
          ],
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: heading),
        const SizedBox(width: 12),
        Flexible(
          child: Wrap(
            spacing: 6,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
        ),
      ]);
    }),
  );
}
