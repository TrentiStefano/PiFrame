import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../../data/language/language_settings.dart';
import '../../../data/language/strings_settings.dart';
import '../../../data/metrics/nerd_stats_settings.dart';
import '../../../data/motion/reduced_motion_settings.dart';
import '../../../data/theme/theme_providers.dart';
import '../../../data/transcript/step_grouping_settings.dart';
import '../../../data/composer/composer_settings.dart';
import '../../../domain/session/transcript_grouping.dart';
import '../../../ui/frame_snack_bar.dart';

import 'settings_common.dart';
import '../theme_editor_dialog.dart';

/// Appearance tab: language, theme selection and editor, display toggles.
class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({
    super.key,
    required this.tokens,
    required this.strings,
  });

  final FrameTokens tokens;
  final AppStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTheme = ref.watch(activeThemeSpecProvider);
    final settings = ref.watch(themeSettingsProvider);
    final repo = ref.watch(themeRepositoryProvider);
    final themes = repo.availableThemes;
    final darkThemes = themes.where((t) => t.variant == 'dark').toList();
    final lightThemes = themes.where((t) => t.variant == 'light').toList();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          strings.languageSectionTitle,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          strings.languageSectionSubtitle,
          style: TextStyle(color: tokens.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<AppLanguage>(
              key: const ValueKey('settings-language-dropdown'),
              isExpanded: true,
              value: ref.watch(appLanguageProvider),
              dropdownColor: tokens.surfaceElevated,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 13,
                fontFamily: tokens.uiFontFamily,
              ),
              items: AppLanguage.values.map((lang) {
                return DropdownMenuItem<AppLanguage>(
                  value: lang,
                  child: Row(
                    children: [
                      Text(lang.flag, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 10),
                      Text(lang.label),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (newLang) {
                if (newLang != null) {
                  ref.read(appLanguageProvider.notifier).setLanguage(newLang);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          strings.appearanceTitle,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          strings.appearanceSubtitle,
          style: TextStyle(color: tokens.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.useSystemTheme,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      strings.useSystemThemeSubtitle,
                      style: TextStyle(color: tokens.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Switch(
                key: const ValueKey('settings-theme-system-switch'),
                value: settings.useSystemTheme,
                onChanged: (val) {
                  ref
                      .read(themeSettingsProvider.notifier)
                      .setUseSystemTheme(val);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (!settings.useSystemTheme) ...[
          Text(
            strings.selectActiveTheme,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: tokens.surfaceElevated,
              borderRadius: BorderRadius.circular(tokens.radiusMd),
              border: Border.all(color: tokens.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const ValueKey('settings-theme-dropdown'),
                isExpanded: true,
                borderRadius: BorderRadius.circular(tokens.radiusMd),
                value: activeTheme.id,
                dropdownColor: tokens.surfaceElevated,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 13,
                  fontFamily: tokens.uiFontFamily,
                ),
                items: themes.map((t) {
                  return DropdownMenuItem<String>(
                    value: t.id,
                    child: Text(
                      '${t.name} (${t.variant})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (newId) {
                  if (newId != null) {
                    ref.read(activeThemeSpecProvider.notifier).setTheme(newId);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.defaultDarkTheme,
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: tokens.surfaceElevated,
                      borderRadius: BorderRadius.circular(tokens.radiusMd),
                      border: Border.all(color: tokens.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(tokens.radiusMd),
                        value:
                            darkThemes.any(
                              (t) => t.id == settings.defaultDarkThemeId,
                            )
                            ? settings.defaultDarkThemeId
                            : (darkThemes.isNotEmpty
                                  ? darkThemes.first.id
                                  : null),
                        dropdownColor: tokens.surfaceElevated,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 13,
                          fontFamily: tokens.uiFontFamily,
                        ),
                        items: darkThemes.map((t) {
                          return DropdownMenuItem<String>(
                            value: t.id,
                            child: Text(
                              t.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (newId) {
                          if (newId != null) {
                            ref
                                .read(themeSettingsProvider.notifier)
                                .setDefaultDarkTheme(newId);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.defaultLightTheme,
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: tokens.surfaceElevated,
                      borderRadius: BorderRadius.circular(tokens.radiusMd),
                      border: Border.all(color: tokens.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(tokens.radiusMd),
                        value:
                            lightThemes.any(
                              (t) => t.id == settings.defaultLightThemeId,
                            )
                            ? settings.defaultLightThemeId
                            : (lightThemes.isNotEmpty
                                  ? lightThemes.first.id
                                  : null),
                        dropdownColor: tokens.surfaceElevated,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 13,
                          fontFamily: tokens.uiFontFamily,
                        ),
                        items: lightThemes.map((t) {
                          return DropdownMenuItem<String>(
                            value: t.id,
                            child: Text(
                              t.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (newId) {
                          if (newId != null) {
                            ref
                                .read(themeSettingsProvider.notifier)
                                .setDefaultLightTheme(newId);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('settings-open-theme-editor-btn'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: tokens.accent),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
              ),
              icon: Icon(
                Icons.palette_outlined,
                size: 16,
                color: tokens.accent,
              ),
              label: Text(
                strings.openThemeEditorBtn,
                style: TextStyle(
                  color: tokens.accent,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () {
                ThemeEditorDialog.show(context);
              },
            ),
            OutlinedButton.icon(
              key: const ValueKey('settings-import-theme-btn'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: tokens.borderStrong),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
              ),
              icon: Icon(
                Icons.file_upload_outlined,
                size: 16,
                color: tokens.accent,
              ),
              label: Text(
                strings.importThemeBtn,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () async {
                try {
                  final file = await openFile(
                    acceptedTypeGroups: [
                      XTypeGroup(
                        label: strings.themeJsonFilterLabel,
                        extensions: const ['json'],
                      ),
                    ],
                  );
                  if (file == null || !context.mounted) {
                    return;
                  }
                  final content = await file.readAsString();
                  final importedSpec = await ref
                      .read(activeThemeSpecProvider.notifier)
                      .importThemeFromJson(content);
                  if (context.mounted) {
                    FrameSnackBar.show(
                      context,
                      message: strings.themeImportSuccess(importedSpec.name),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    FrameSnackBar.show(
                      context,
                      message: strings.themeImportError(e),
                    );
                  }
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        buildSettingsInfoCard(tokens, [
          buildSettingsInfoRow(
            tokens,
            strings.labelActiveTheme,
            '${activeTheme.name} (v${activeTheme.version})',
          ),
          buildSettingsInfoRow(
            tokens,
            strings.labelLayoutDensity,
            strings.layoutDensityDefault,
          ),
          buildSettingsInfoRow(
            tokens,
            strings.labelFonts,
            strings.fontsDetail(
              activeTheme.toTokens().uiFontFamily,
              activeTheme.toTokens().monoFontFamily,
            ),
          ),
        ]),
        if (activeTheme.diagnostics.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            strings.themeDiagnosticsHeader,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          ...activeTheme.diagnostics.map(
            (d) => Text(
              '• $d',
              style: TextStyle(color: tokens.textMuted, fontSize: 11),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          strings.composerSectionTitle,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          strings.sendWithEnterSubtitle,
          style: TextStyle(color: tokens.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.border),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: const ValueKey('settings-composer-send-with-enter-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                strings.sendWithEnterTitle,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 13,
                  fontFamily: tokens.uiFontFamily,
                ),
              ),
              activeThumbColor: tokens.accent,
              value: ref.watch(composerSettingsProvider).sendWithEnter,
              onChanged: (val) {
                ref
                    .read(composerSettingsProvider.notifier)
                    .setSendWithEnter(val);
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          strings.reducedMotionSectionTitle,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          strings.reducedMotionSubtitle,
          style: TextStyle(color: tokens.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.border),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: const ValueKey('settings-reduced-motion-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                strings.reducedMotionTitle,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 13,
                  fontFamily: tokens.uiFontFamily,
                ),
              ),
              activeThumbColor: tokens.accent,
              value: ref.watch(reducedMotionSettingsProvider).enabled,
              onChanged: (val) {
                ref
                    .read(reducedMotionSettingsProvider.notifier)
                    .setEnabled(val);
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          strings.nerdStatsSectionTitle,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          strings.nerdStatsSubtitle,
          style: TextStyle(color: tokens.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.border),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: const ValueKey('settings-nerd-stats-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                strings.nerdStatsTitle,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 13,
                  fontFamily: tokens.uiFontFamily,
                ),
              ),
              activeThumbColor: tokens.accent,
              value: ref.watch(nerdStatsSettingsProvider).enabled,
              onChanged: (val) {
                ref.read(nerdStatsSettingsProvider.notifier).setEnabled(val);
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        Builder(
          builder: (context) {
            final stepGroupingSettings = ref.watch(
              stepGroupingSettingsProvider,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.stepGroupingSectionTitle,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  strings.stepGroupingModeDescription(
                    stepGroupingSettings.mode,
                  ),
                  style: TextStyle(color: tokens.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.surfaceElevated,
                    borderRadius: BorderRadius.circular(tokens.radiusMd),
                    border: Border.all(color: tokens.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<StepGroupingMode>(
                      key: const ValueKey(
                        'settings-step-grouping-mode-dropdown',
                      ),
                      isExpanded: true,
                      value: stepGroupingSettings.mode,
                      dropdownColor: tokens.surfaceElevated,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 13,
                        fontFamily: tokens.uiFontFamily,
                      ),
                      items: StepGroupingMode.values.map((mode) {
                        return DropdownMenuItem<StepGroupingMode>(
                          value: mode,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                strings.stepGroupingModeLabel(mode),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                strings.stepGroupingModeDescription(mode),
                                style: TextStyle(
                                  color: tokens.textMuted,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (newMode) {
                        if (newMode != null) {
                          ref
                              .read(stepGroupingSettingsProvider.notifier)
                              .setMode(newMode);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.surfaceElevated,
                    borderRadius: BorderRadius.circular(tokens.radiusMd),
                    border: Border.all(color: tokens.border),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: SwitchListTile(
                      key: const ValueKey(
                        'settings-step-grouping-auto-collapse-switch',
                      ),
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        strings.stepGroupingAutoCollapseTitle,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 13,
                          fontFamily: tokens.uiFontFamily,
                        ),
                      ),
                      subtitle: Text(
                        strings.stepGroupingAutoCollapseSubtitle,
                        style: TextStyle(color: tokens.textMuted, fontSize: 12),
                      ),
                      activeThumbColor: tokens.accent,
                      value: stepGroupingSettings.autoCollapse,
                      onChanged: (val) {
                        ref
                            .read(stepGroupingSettingsProvider.notifier)
                            .setAutoCollapse(val);
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
