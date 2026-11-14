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
import '../../../ui/frame_section.dart';
import '../../../ui/frame_snack_bar.dart';

import 'settings_common.dart';
import '../theme_editor_dialog.dart';

/// Appearance tab: language, theme selection and editor, display toggles.
/// Each block is one [FrameSection]; fields sit at the form row height.
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
    final text = FrameText.of(context);
    final activeTheme = ref.watch(activeThemeSpecProvider);
    final settings = ref.watch(themeSettingsProvider);
    final repo = ref.watch(themeRepositoryProvider);
    final themes = repo.availableThemes;
    final darkThemes = themes.where((t) => t.variant == 'dark').toList();
    final lightThemes = themes.where((t) => t.variant == 'light').toList();
    final fieldLabelStyle = text.label.copyWith(color: tokens.textSecondary);

    return ListView(
      padding: const EdgeInsets.all(FrameSpace.x6),
      children: [
        FrameSection(
          title: strings.languageSectionTitle,
          description: strings.languageSectionSubtitle,
          child: buildSettingsFieldBox(
            tokens,
            DropdownButtonHideUnderline(
              child: DropdownButton<AppLanguage>(
                key: const ValueKey('settings-language-dropdown'),
                isExpanded: true,
                isDense: true,
                value: ref.watch(appLanguageProvider),
                dropdownColor: tokens.surfaceElevated,
                style: text.body.copyWith(color: tokens.textPrimary),
                items: AppLanguage.values.map((lang) {
                  return DropdownMenuItem<AppLanguage>(
                    value: lang,
                    child: Row(
                      children: [
                        Text(
                          lang.flag,
                          style: text.bodyLarge,
                        ),
                        const SizedBox(width: FrameSpace.x2),
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
        ),
        const SizedBox(height: FrameSpace.x8),
        FrameSection(
          title: strings.appearanceTitle,
          description: strings.appearanceSubtitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.useSystemTheme,
                          style: text.bodyLarge.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: FrameSpace.x1),
                        Text(
                          strings.useSystemThemeSubtitle,
                          style: text.caption.copyWith(
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    key: const ValueKey('settings-theme-system-switch'),
                    value: settings.useSystemTheme,
                    activeThumbColor: tokens.accent,
                    onChanged: (val) {
                      ref
                          .read(themeSettingsProvider.notifier)
                          .setUseSystemTheme(val);
                    },
                  ),
                ],
              ),
              const SizedBox(height: FrameSpace.x4),
              if (!settings.useSystemTheme) ...[
                Text(strings.selectActiveTheme, style: fieldLabelStyle),
                const SizedBox(height: FrameSpace.x1),
                buildSettingsFieldBox(
                  tokens,
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      key: const ValueKey('settings-theme-dropdown'),
                      isExpanded: true,
                      isDense: true,
                      borderRadius: BorderRadius.circular(tokens.radiusMd),
                      value: activeTheme.id,
                      dropdownColor: tokens.surfaceElevated,
                      style: text.body.copyWith(color: tokens.textPrimary),
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
                          ref
                              .read(activeThemeSpecProvider.notifier)
                              .setTheme(newId);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: FrameSpace.x4),
              ],
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(strings.defaultDarkTheme, style: fieldLabelStyle),
                        const SizedBox(height: FrameSpace.x1),
                        buildSettingsFieldBox(
                          tokens,
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              isDense: true,
                              borderRadius: BorderRadius.circular(
                                tokens.radiusMd,
                              ),
                              value:
                                  darkThemes.any(
                                    (t) => t.id == settings.defaultDarkThemeId,
                                  )
                                  ? settings.defaultDarkThemeId
                                  : (darkThemes.isNotEmpty
                                        ? darkThemes.first.id
                                        : null),
                              dropdownColor: tokens.surfaceElevated,
                              style: text.body.copyWith(
                                color: tokens.textPrimary,
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
                  const SizedBox(width: FrameSpace.x4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(strings.defaultLightTheme, style: fieldLabelStyle),
                        const SizedBox(height: FrameSpace.x1),
                        buildSettingsFieldBox(
                          tokens,
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              isDense: true,
                              borderRadius: BorderRadius.circular(
                                tokens.radiusMd,
                              ),
                              value:
                                  lightThemes.any(
                                    (t) =>
                                        t.id == settings.defaultLightThemeId,
                                  )
                                  ? settings.defaultLightThemeId
                                  : (lightThemes.isNotEmpty
                                        ? lightThemes.first.id
                                        : null),
                              dropdownColor: tokens.surfaceElevated,
                              style: text.body.copyWith(
                                color: tokens.textPrimary,
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
              const SizedBox(height: FrameSpace.x3),
              Wrap(
                spacing: FrameSpace.x3,
                runSpacing: FrameSpace.x2,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('settings-open-theme-editor-btn'),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: tokens.accent),
                      minimumSize: const Size(0, FrameSize.rowForm),
                      padding: const EdgeInsets.symmetric(
                        horizontal: FrameSpace.x4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                      ),
                    ),
                    icon: Icon(
                      Icons.palette_outlined,
                      size: FrameSize.icon,
                      color: tokens.accent,
                    ),
                    label: Text(
                      strings.openThemeEditorBtn,
                      style: text.label.copyWith(color: tokens.accent),
                    ),
                    onPressed: () {
                      ThemeEditorDialog.show(context);
                    },
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('settings-import-theme-btn'),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: tokens.borderStrong),
                      minimumSize: const Size(0, FrameSize.rowForm),
                      padding: const EdgeInsets.symmetric(
                        horizontal: FrameSpace.x4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                      ),
                    ),
                    icon: Icon(
                      Icons.file_upload_outlined,
                      size: FrameSize.icon,
                      color: tokens.accent,
                    ),
                    label: Text(
                      strings.importThemeBtn,
                      style: text.label.copyWith(color: tokens.textPrimary),
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
                            message: strings.themeImportSuccess(
                              importedSpec.name,
                            ),
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
              const SizedBox(height: FrameSpace.x4),
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
                const SizedBox(height: FrameSpace.x4),
                Text(
                  strings.themeDiagnosticsHeader,
                  style: text.label.copyWith(color: tokens.textPrimary),
                ),
                const SizedBox(height: FrameSpace.x1),
                ...activeTheme.diagnostics.map(
                  (d) => Text(
                    '• $d',
                    style: text.caption.copyWith(color: tokens.textMuted),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: FrameSpace.x8),
        FrameSection(
          title: strings.composerSectionTitle,
          description: strings.sendWithEnterSubtitle,
          child: Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: const ValueKey('settings-composer-send-with-enter-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                strings.sendWithEnterTitle,
                style: text.body.copyWith(color: tokens.textPrimary),
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
        const SizedBox(height: FrameSpace.x8),
        FrameSection(
          title: strings.reducedMotionSectionTitle,
          description: strings.reducedMotionSubtitle,
          child: Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: const ValueKey('settings-reduced-motion-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                strings.reducedMotionTitle,
                style: text.body.copyWith(color: tokens.textPrimary),
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
        const SizedBox(height: FrameSpace.x8),
        FrameSection(
          title: strings.nerdStatsSectionTitle,
          description: strings.nerdStatsSubtitle,
          child: Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: const ValueKey('settings-nerd-stats-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                strings.nerdStatsTitle,
                style: text.body.copyWith(color: tokens.textPrimary),
              ),
              activeThumbColor: tokens.accent,
              value: ref.watch(nerdStatsSettingsProvider).enabled,
              onChanged: (val) {
                ref.read(nerdStatsSettingsProvider.notifier).setEnabled(val);
              },
            ),
          ),
        ),
        const SizedBox(height: FrameSpace.x8),
        Builder(
          builder: (context) {
            final stepGroupingSettings = ref.watch(
              stepGroupingSettingsProvider,
            );
            return FrameSection(
              title: strings.stepGroupingSectionTitle,
              description: strings.stepGroupingModeDescription(
                stepGroupingSettings.mode,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildSettingsFieldBox(
                    tokens,
                    DropdownButtonHideUnderline(
                      child: DropdownButton<StepGroupingMode>(
                        key: const ValueKey(
                          'settings-step-grouping-mode-dropdown',
                        ),
                        isExpanded: true,
                        isDense: true,
                        value: stepGroupingSettings.mode,
                        dropdownColor: tokens.surfaceElevated,
                        style: text.body.copyWith(color: tokens.textPrimary),
                        // The closed field is one line tall; the menu keeps
                        // the two-line label and description.
                        selectedItemBuilder: (context) => [
                          for (final mode in StepGroupingMode.values)
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                strings.stepGroupingModeLabel(mode),
                                style: text.body.copyWith(
                                  color: tokens.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        items: StepGroupingMode.values.map((mode) {
                          return DropdownMenuItem<StepGroupingMode>(
                            value: mode,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  strings.stepGroupingModeLabel(mode),
                                  style: text.label,
                                ),
                                Text(
                                  strings.stepGroupingModeDescription(mode),
                                  style: text.caption.copyWith(
                                    color: tokens.textMuted,
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
                  const SizedBox(height: FrameSpace.x2),
                  Material(
                    type: MaterialType.transparency,
                    child: SwitchListTile(
                      key: const ValueKey(
                        'settings-step-grouping-auto-collapse-switch',
                      ),
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        strings.stepGroupingAutoCollapseTitle,
                        style: text.body.copyWith(color: tokens.textPrimary),
                      ),
                      subtitle: Text(
                        strings.stepGroupingAutoCollapseSubtitle,
                        style: text.caption.copyWith(color: tokens.textMuted),
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
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
