// ignore_for_file: invalid_use_of_protected_member
part of '../../studio.dart';

extension _StudioSettingsDialog on _StudioState {
  Future<void> settings() async {
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final currentSettings = studioSettingsNotifier.value;
          return AlertDialog(
            title: const Text('Study preferences'),
            content: SizedBox(
              width: 580,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'THEME & PALETTE',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: StudioThemePreset.values.map((preset) {
                        final isSelected =
                            currentSettings.themePreset == preset;
                        return InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            final updated = currentSettings.copyWith(
                              themePreset: preset,
                            );
                            studioSettingsNotifier.value = updated;
                            setDialogState(() {});
                            setState(() {});
                          },
                          child: Container(
                            width: 170,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: preset.paper,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected ? preset.primary : line,
                                width: isSelected ? 2 : 1,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: preset.primary.withValues(
                                          alpha: 0.2,
                                        ),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: preset.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: preset.background,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: line),
                                      ),
                                    ),
                                    const Spacer(),
                                    if (isSelected)
                                      Icon(
                                        Icons.check_circle,
                                        size: 16,
                                        color: preset.primary,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  preset.label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: preset.ink,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  preset.description,
                                  style: TextStyle(fontSize: 10, color: muted),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'DASHBOARD BANNER & ILLUSTRATION',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Choose a bundled Zenbox artwork or select a custom image from your device.',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                    const SizedBox(height: 12),
                    () {
                      final customWallpaper =
                          project.layout['overviewWallpaper'] as String? ??
                          project.layout['dashboardWallpaper'] as String? ??
                          currentSettings.dashboardWallpaper;
                      final currentAsset =
                          project.layout['overviewWallpaperAsset'] as String? ??
                          project.layout['dashboardWallpaperAsset'] as String? ??
                          currentSettings.dashboardWallpaperAsset ??
                          defaultDashboardWallpaperAsset;
                      final isCustom =
                          customWallpaper != null && customWallpaper.isNotEmpty;

                      final activeOption = bundledDashboardIllustrations.firstWhere(
                        (o) => o.assetPath == currentAsset,
                        orElse: () => bundledDashboardIllustrations.first,
                      );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: sage.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: line),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    width: 110,
                                    height: 66,
                                    child: isCustom
                                        ? Image.file(
                                            File(customWallpaper),
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                Image.asset(
                                              currentAsset,
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        : Image.asset(
                                            currentAsset,
                                            fit: BoxFit.cover,
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: (isCustom
                                                      ? Colors.teal
                                                      : sage)
                                                  .withValues(alpha: 0.2),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              isCustom
                                                  ? 'CUSTOM IMAGE'
                                                  : 'BUNDLED ARTWORK',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 0.8,
                                                color: isCustom
                                                    ? Colors.teal.shade800
                                                    : sage,
                                              ),
                                            ),
                                          ),
                                          const Spacer(),
                                          if (isCustom ||
                                              currentAsset !=
                                                  defaultDashboardWallpaperAsset)
                                            TextButton.icon(
                                              style: TextButton.styleFrom(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                ),
                                              ),
                                              onPressed: () {
                                                setState(() {
                                                  project.layout.remove(
                                                    'overviewWallpaper',
                                                  );
                                                  project.layout.remove(
                                                    'dashboardWallpaper',
                                                  );
                                                  project.layout.remove(
                                                    'overviewWallpaperAsset',
                                                  );
                                                  project.layout.remove(
                                                    'dashboardWallpaperAsset',
                                                  );
                                                });
                                                studioSettingsNotifier.value =
                                                    currentSettings.copyWith(
                                                  clearDashboardWallpaper: true,
                                                  clearDashboardWallpaperAsset:
                                                      true,
                                                );
                                                saveLayout();
                                                store.changed();
                                                setDialogState(() {});
                                              },
                                              icon: const Icon(
                                                Icons.restart_alt,
                                                size: 14,
                                              ),
                                              label: const Text(
                                                'Reset',
                                                style: TextStyle(fontSize: 11),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        isCustom
                                            ? File(customWallpaper)
                                                    .uri
                                                    .pathSegments
                                                    .isNotEmpty
                                                ? File(customWallpaper)
                                                    .uri
                                                    .pathSegments
                                                    .last
                                                : customWallpaper
                                            : activeOption.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        isCustom
                                            ? customWallpaper
                                            : activeOption.description,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'BUNDLED ILLUSTRATIONS',
                            style: TextStyle(
                              fontSize: 9,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w600,
                              color: muted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: bundledDashboardIllustrations.map((option) {
                              final isSelected = !isCustom &&
                                  currentAsset == option.assetPath;
                              return InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  setState(() {
                                    project.layout['overviewWallpaperAsset'] =
                                        option.assetPath;
                                    project.layout['dashboardWallpaperAsset'] =
                                        option.assetPath;
                                    project.layout.remove('overviewWallpaper');
                                    project.layout.remove('dashboardWallpaper');
                                  });
                                  studioSettingsNotifier.value =
                                      currentSettings.copyWith(
                                    dashboardWallpaperAsset: option.assetPath,
                                    clearDashboardWallpaper: true,
                                  );
                                  saveLayout();
                                  store.changed();
                                  setDialogState(() {});
                                },
                                child: Container(
                                  width: 102,
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected ? sage : line,
                                      width: isSelected ? 2 : 1,
                                    ),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: sage.withValues(
                                                alpha: 0.2,
                                              ),
                                              blurRadius: 4,
                                              offset: const Offset(0, 1),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: SizedBox(
                                          width: 94,
                                          height: 56,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              Image.asset(
                                                option.assetPath,
                                                fit: BoxFit.cover,
                                              ),
                                              if (isSelected)
                                                Positioned(
                                                  top: 3,
                                                  right: 3,
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.all(2),
                                                    decoration: BoxDecoration(
                                                      color: sage,
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(
                                                      Icons.check,
                                                      size: 11,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        option.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: isSelected ? ink : muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final result =
                                      await FilePicker.pickFiles(
                                    type: FileType.image,
                                  );
                                  if (result.isEmpty ||
                                      result.single.path == null) {
                                    return;
                                  }
                                  final pickedPath = result.single.path!;
                                  setState(() {
                                    project.layout['overviewWallpaper'] =
                                        pickedPath;
                                    project.layout['dashboardWallpaper'] =
                                        pickedPath;
                                    project.layout.remove(
                                      'overviewWallpaperAsset',
                                    );
                                    project.layout.remove(
                                      'dashboardWallpaperAsset',
                                    );
                                  });
                                  studioSettingsNotifier.value =
                                      currentSettings.copyWith(
                                    dashboardWallpaper: pickedPath,
                                    clearDashboardWallpaperAsset: true,
                                  );
                                  saveLayout();
                                  store.changed();
                                  setDialogState(() {});
                                },
                                icon: const Icon(
                                  Icons.add_photo_alternate_outlined,
                                  size: 16,
                                ),
                                label: Text(
                                  isCustom
                                      ? 'Change custom image…'
                                      : 'Choose custom image…',
                                ),
                              ),
                              if (isCustom) ...[
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      project.layout.remove('overviewWallpaper');
                                      project.layout.remove('dashboardWallpaper');
                                    });
                                    studioSettingsNotifier.value =
                                        currentSettings.copyWith(
                                      clearDashboardWallpaper: true,
                                    );
                                    saveLayout();
                                    store.changed();
                                    setDialogState(() {});
                                  },
                                  icon: const Icon(Icons.close, size: 14),
                                  label: const Text(
                                    'Remove custom image',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      );
                    }(),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'EDITOR & TYPOGRAPHY',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: currentSettings.editorFont,
                            decoration: const InputDecoration(
                              labelText: 'Primary Font',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'Georgia',
                                child: Text('Georgia (Serif)'),
                              ),
                              DropdownMenuItem(
                                value: 'Segoe UI',
                                child: Text('Segoe UI (Clean Sans)'),
                              ),
                              DropdownMenuItem(
                                value: 'Courier New',
                                child: Text('Courier New (Monospace / Code)'),
                              ),
                              DropdownMenuItem(
                                value: 'Consolas',
                                child: Text('Consolas (Monospace)'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                studioSettingsNotifier.value = currentSettings
                                    .copyWith(editorFont: val);
                                setDialogState(() {});
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: DropdownButtonFormField<double>(
                            isExpanded: true,
                            initialValue: currentSettings.editorLineHeight,
                            decoration: const InputDecoration(
                              labelText: 'Line Spacing',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 1.5,
                                child: Text('1.5x (Compact)'),
                              ),
                              DropdownMenuItem(
                                value: 1.75,
                                child: Text('1.75x (Standard)'),
                              ),
                              DropdownMenuItem(
                                value: 2.0,
                                child: Text('2.0x (Relaxed)'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                studioSettingsNotifier.value = currentSettings
                                    .copyWith(editorLineHeight: val);
                                setDialogState(() {});
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: currentSettings.autoSaveSeconds,
                      decoration: const InputDecoration(
                        labelText: 'Autosave Cadence',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 5,
                          child: Text('Every 5 seconds (Real-time)'),
                        ),
                        DropdownMenuItem(
                          value: 15,
                          child: Text('Every 15 seconds (Standard)'),
                        ),
                        DropdownMenuItem(
                          value: 30,
                          child: Text('Every 30 seconds'),
                        ),
                        DropdownMenuItem(
                          value: 60,
                          child: Text('Every 60 seconds'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          studioSettingsNotifier.value = currentSettings
                              .copyWith(autoSaveSeconds: val);
                          setDialogState(() {});
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'AI ASSISTANT CUSTOMIZATION',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: currentSettings.aiPersona,
                      decoration: const InputDecoration(
                        labelText: 'Learning assistant style',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Balanced Producer',
                          child: Text('Study Tutor & Academic Mentor'),
                        ),
                        DropdownMenuItem(
                          value: 'Critique & Polish',
                          child: Text('Socratic Tutor (Active recall)'),
                        ),
                        DropdownMenuItem(
                          value: 'Creative Outliner',
                          child: Text(
                            'Summary Specialist (High-yield synthesis)',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Screenplay Specialist',
                          child: Text(
                            'Detailed Researcher (Citations & evidence)',
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          studioSettingsNotifier.value = currentSettings
                              .copyWith(aiPersona: val);
                          setDialogState(() {});
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: Colors.transparent,
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Token Typewriter Animation',
                          style: TextStyle(fontSize: 13),
                        ),
                        subtitle: const Text(
                          'Render generated AI responses text-by-text with live cursor',
                          style: TextStyle(fontSize: 11),
                        ),
                        value: currentSettings.typewriterEffect,
                        onChanged: (val) {
                          studioSettingsNotifier.value = currentSettings
                              .copyWith(typewriterEffect: val);
                          setDialogState(() {});
                        },
                      ),
                    ),
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.auto_awesome_outlined),
                        title: const Text(
                          'AI providers & API keys',
                          style: TextStyle(fontSize: 13),
                        ),
                        subtitle: const Text(
                          'Configure Gemini, OpenAI, Claude, or local Ollama endpoints',
                          style: TextStyle(fontSize: 11),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.pop(context);
                          showAiSettings(this.context, store, ai);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'PROJECT DETAILS',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: project.title,
                      decoration: const InputDecoration(
                        labelText: 'Project name',
                      ),
                      onChanged: (v) {
                        if (v.trim().isNotEmpty) {
                          project.title = v;
                          store.changed();
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: project.description,
                      decoration: const InputDecoration(
                        labelText: 'Creative intention & logline',
                      ),
                      maxLines: 2,
                      onChanged: (v) {
                        project.description = v;
                        store.changed();
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              manageProjectsDialog();
                            },
                            icon: const Icon(Icons.tune, size: 15),
                            label: const Text(
                              'Manage workspaces',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: store.projects.length > 1
                                ? () {
                                    Navigator.pop(context);
                                    deleteProjectDialog(project);
                                  }
                                : null,
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 15,
                              color: Color(0xFFA54141),
                            ),
                            label: Text(
                              'Delete workspace',
                              style: TextStyle(
                                fontSize: 11,
                                color: store.projects.length > 1
                                    ? const Color(0xFFA54141)
                                    : muted,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'KEYBOARD SHORTCUTS',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Ctrl K     Search & commands\nCtrl S     Save now\nCtrl B     Focus mode\nCtrl Shift Space     Quick capture\nCtrl Z / Ctrl Y     Undo / redo in editor',
                      style: TextStyle(fontSize: 12, height: 1.9),
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'LOCAL PROJECT STORAGE',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SelectableText(
                      store.directory.path,
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your work autosaves locally on this computer. Export a portable project bundle to back it up or transfer.',
                      style: TextStyle(fontSize: 11, height: 1.6, color: muted),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () => run(importProject),
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: const Text('Import a portable project'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }
}
