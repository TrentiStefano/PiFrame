import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../../data/language/language_settings.dart';
import '../../../data/language/strings_settings.dart';
import '../../../data/platform/file_dialog_service.dart';
import '../../../data/platform/file_system_service.dart';
import '../../../data/platform/host_environment_service.dart';
import '../../../data/terminal/terminal_settings.dart';
import '../../../ui/frame_section.dart';
import '../../../ui/frame_snack_bar.dart';
import '../../../ui/precision.dart';

/// Terminal tab: preferred execution mode and native terminal app.
/// Each choice group is one [FrameSection]; the radio rows sit in a
/// transparent [Material] so their ink is not hidden by a background.
class TerminalSection extends ConsumerWidget {
  const TerminalSection({super.key, required this.tokens, required this.strings});

  final FrameTokens tokens;
  final AppStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = FrameText.of(context);
    final termSettings = ref.watch(terminalSettingsProvider);
    final notifier = ref.read(terminalSettingsProvider.notifier);
    final isWindows = ref.watch(hostEnvironmentServiceProvider).isWindows;
    final nativeEnabled = termSettings.mode == TerminalMode.native;
    final rowTitleStyle = text.body.copyWith(color: tokens.textPrimary, fontWeight: FontWeight.w600);
    final rowSubtitleStyle = text.caption.copyWith(color: tokens.textMuted);
    final rowStyle = text.body.copyWith(color: tokens.textPrimary);

    return ListView(
      padding: const EdgeInsets.all(FrameSpace.x6),
      children: [
        FrameSection(
          title: strings.terminalTabTitle,
          description: strings.terminalTabSubtitle,
          child: Material(
            type: MaterialType.transparency,
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
                    contentPadding: EdgeInsets.zero,
                    title: Text(strings.terminalIntegratedTitle, style: rowTitleStyle),
                    subtitle: Text(strings.terminalIntegratedSubtitle, style: rowSubtitleStyle),
                  ),
                  Divider(color: tokens.border, height: 1),
                  RadioListTile<TerminalMode>(
                    value: TerminalMode.native,
                    activeColor: tokens.accent,
                    contentPadding: EdgeInsets.zero,
                    title: Text(strings.terminalNativeTitle, style: rowTitleStyle),
                    subtitle: Text(strings.terminalNativeSubtitle, style: rowSubtitleStyle),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: FrameSpace.x8),
        FrameSection(
          key: const ValueKey('settings-native-app-section'),
          title: strings.terminalNativeAppHeader,
          // Progressive disclosure: the native app list is inert until
          // "Terminale nativo" is the chosen mode.
          child: IgnorePointer(
            ignoring: !nativeEnabled,
            child: Opacity(
              opacity: nativeEnabled ? 1 : 0.5,
              child: Material(
                type: MaterialType.transparency,
                child: RadioGroup<NativeTerminalApp>(
                  groupValue: termSettings.nativeApp,
                  onChanged: (app) {
                    if (app != null && nativeEnabled) {
                      notifier.setNativeApp(app);
                    }
                  },
                  child: Column(
                    children: [
                      RadioListTile<NativeTerminalApp>(
                        value: NativeTerminalApp.systemDefault,
                        activeColor: tokens.accent,
                        contentPadding: EdgeInsets.zero,
                        title: Text(strings.terminalNativeAppDefault(isWindows), style: rowStyle),
                      ),
                      if (isWindows) ...[
                        Divider(color: tokens.border, height: 1),
                        RadioListTile<NativeTerminalApp>(
                          value: NativeTerminalApp.powershell,
                          activeColor: tokens.accent,
                          contentPadding: EdgeInsets.zero,
                          title: Text(strings.terminalPowershell, style: rowStyle),
                        ),
                        Divider(color: tokens.border, height: 1),
                        RadioListTile<NativeTerminalApp>(
                          value: NativeTerminalApp.cmd,
                          activeColor: tokens.accent,
                          contentPadding: EdgeInsets.zero,
                          title: Text(strings.terminalCmd, style: rowStyle),
                        ),
                        Divider(color: tokens.border, height: 1),
                        RadioListTile<NativeTerminalApp>(
                          value: NativeTerminalApp.wsl,
                          activeColor: tokens.accent,
                          contentPadding: EdgeInsets.zero,
                          title: Text(strings.terminalWsl, style: rowStyle),
                        ),
                      ],
                      Divider(color: tokens.border, height: 1),
                      RadioListTile<NativeTerminalApp>(
                        value: NativeTerminalApp.custom,
                        activeColor: tokens.accent,
                        contentPadding: EdgeInsets.zero,
                        title: Text(strings.terminalCustomApp, style: rowStyle),
                        subtitle: termSettings.nativeApp == NativeTerminalApp.custom
                            ? Padding(
                                padding: const EdgeInsets.only(top: FrameSpace.x2),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: TextEditingController(text: termSettings.customPath)
                                          ..selection = TextSelection.collapsed(offset: termSettings.customPath.length),
                                        style: text.mono.copyWith(color: tokens.textPrimary),
                                        decoration: InputDecoration(
                                          hintText: isWindows ? 'C:\\Path\\To\\terminal.exe' : '/usr/bin/alacritty',
                                          isDense: true,
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(tokens.radiusSm),
                                          ),
                                        ),
                                        onSubmitted: (val) => notifier.setCustomPath(val.trim()),
                                      ),
                                    ),
                                    const SizedBox(width: FrameSpace.x2),
                                    PressFeedback(
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.folder_open_outlined, size: FrameSize.icon),
                                        label: Text(strings.terminalBrowseBtn),
                                        onPressed: () async {
                                          final picked = await ref
                                              .read(fileDialogServiceProvider)
                                              .pickFiles(
                                                label: strings.terminalExecutableFilterLabel,
                                                extensions: const ['exe', 'bat', 'cmd', 'sh'],
                                                multiple: false,
                                              );
                                          if (picked.isNotEmpty) {
                                            notifier.setCustomPath(picked.first);
                                          }
                                        },
                                      ),
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
            ),
          ),
        ),
        const SizedBox(height: FrameSpace.x6),
        Align(
          alignment: Alignment.centerLeft,
          child: PressFeedback(
            child: FilledButton.icon(
              key: const ValueKey('settings-terminal-test-btn'),
              style: FilledButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: tokens.surface,
                minimumSize: const Size(0, FrameSize.rowForm),
              ),
              icon: const Icon(Icons.open_in_new_outlined, size: FrameSize.icon),
              label: Text(strings.terminalTestBtn),
              onPressed: () async {
                final launched = await launchNativeTerminal(
                  cwd: ref.read(fileSystemServiceProvider).currentDirectory,
                  nativeApp: termSettings.nativeApp,
                  customPath: termSettings.customPath,
                );
                if (context.mounted) {
                  FrameSnackBar.show(
                    context,
                    message: launched ? strings.terminalTestSuccess : strings.terminalTestFailed,
                    isError: !launched,
                  );
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}
