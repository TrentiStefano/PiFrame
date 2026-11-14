import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../../data/language/language_settings.dart';
import '../../../data/language/strings_settings.dart';
import '../../../data/terminal/terminal_settings.dart';
import '../../../ui/frame_snack_bar.dart';
import 'settings_common.dart';

/// Terminal tab: preferred execution mode and native terminal app.
class TerminalSection extends ConsumerWidget {
  const TerminalSection({
    super.key,
    required this.tokens,
    required this.strings,
  });

  final FrameTokens tokens;
  final AppStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final termSettings = ref.watch(terminalSettingsProvider);
    final notifier = ref.read(terminalSettingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          strings.terminalTabTitle,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          strings.terminalTabSubtitle,
          style: TextStyle(color: tokens.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 20),

        // Section 1: Modalità di esecuzione
        Text(
          strings.terminalPreferredModeHeader,
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: tokens.border),
          ),
          child: RadioGroup<TerminalMode>(
            groupValue: termSettings.mode,
            onChanged: (mode) {
              if (mode != null) notifier.setMode(mode);
            },
            child: Column(
              children: [
                RadioListTile<TerminalMode>(
                  value: TerminalMode.integrated,
                  activeColor: tokens.accent,
                  title: Text(
                    strings.terminalIntegratedTitle,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    strings.terminalIntegratedSubtitle,
                    style: TextStyle(color: tokens.textMuted, fontSize: 11),
                  ),
                ),
                Divider(color: tokens.border, height: 1),
                RadioListTile<TerminalMode>(
                  value: TerminalMode.native,
                  activeColor: tokens.accent,
                  title: Text(
                    strings.terminalNativeTitle,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    strings.terminalNativeSubtitle,
                    style: TextStyle(color: tokens.textMuted, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Section 2: Scelta applicazione terminale nativo
        Text(
          strings.terminalNativeAppHeader,
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: tokens.border),
          ),
          child: RadioGroup<NativeTerminalApp>(
            groupValue: termSettings.nativeApp,
            onChanged: (app) {
              if (app != null) notifier.setNativeApp(app);
            },
            child: Column(
              children: [
                RadioListTile<NativeTerminalApp>(
                  value: NativeTerminalApp.systemDefault,
                  activeColor: tokens.accent,
                  title: Text(
                    strings.terminalNativeAppDefault(isWindowsOs),
                    style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                  ),
                ),
                if (isWindowsOs) ...[
                  Divider(color: tokens.border, height: 1),
                  RadioListTile<NativeTerminalApp>(
                    value: NativeTerminalApp.powershell,
                    activeColor: tokens.accent,
                    title: Text(
                      strings.terminalPowershell,
                      style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                    ),
                  ),
                  Divider(color: tokens.border, height: 1),
                  RadioListTile<NativeTerminalApp>(
                    value: NativeTerminalApp.cmd,
                    activeColor: tokens.accent,
                    title: Text(
                      strings.terminalCmd,
                      style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                    ),
                  ),
                  Divider(color: tokens.border, height: 1),
                  RadioListTile<NativeTerminalApp>(
                    value: NativeTerminalApp.wsl,
                    activeColor: tokens.accent,
                    title: Text(
                      strings.terminalWsl,
                      style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                    ),
                  ),
                ],
                Divider(color: tokens.border, height: 1),
                RadioListTile<NativeTerminalApp>(
                  value: NativeTerminalApp.custom,
                  activeColor: tokens.accent,
                  title: Text(
                    strings.terminalCustomApp,
                    style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                  ),
                  subtitle: termSettings.nativeApp == NativeTerminalApp.custom
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller:
                                      TextEditingController(
                                          text: termSettings.customPath,
                                        )
                                        ..selection = TextSelection.collapsed(
                                          offset:
                                              termSettings.customPath.length,
                                        ),
                                  style: TextStyle(
                                    color: tokens.textPrimary,
                                    fontSize: 12,
                                    fontFamily: tokens.monoFontFamily,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: isWindowsOs
                                        ? 'C:\\Percorso\\A\\terminal.exe'
                                        : '/usr/bin/alacritty',
                                    isDense: true,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                        tokens.radiusSm,
                                      ),
                                    ),
                                  ),
                                  onSubmitted: (val) =>
                                      notifier.setCustomPath(val.trim()),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.folder_open, size: 14),
                                label: Text(strings.terminalBrowseBtn),
                                onPressed: () async {
                                  final file = await openFile(
                                    acceptedTypeGroups: [
                                      XTypeGroup(
                                        label: strings
                                            .terminalExecutableFilterLabel,
                                        extensions: const [
                                          'exe',
                                          'bat',
                                          'cmd',
                                          'sh',
                                        ],
                                      ),
                                    ],
                                  );
                                  if (file != null) {
                                    notifier.setCustomPath(file.path);
                                  }
                                },
                              ),
                            ],
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Test action button
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: tokens.accent,
              foregroundColor: tokens.surface,
            ),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(strings.terminalTestBtn),
            onPressed: () async {
              final launched = await launchNativeTerminal(
                cwd: Directory.current.path,
                nativeApp: termSettings.nativeApp,
                customPath: termSettings.customPath,
              );
              if (context.mounted) {
                FrameSnackBar.show(
                  context,
                  message: launched
                      ? strings.terminalTestSuccess
                      : strings.terminalTestFailed,
                );
              }
            },
          ),
        ),
      ],
    );
  }
}
