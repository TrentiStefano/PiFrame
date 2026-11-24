import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/data/language/strings_settings.dart';
import 'package:pi_frame/data/platform/file_dialog_service.dart';
import 'package:pi_frame/data/platform/file_system_service.dart';
import 'package:pi_frame/data/terminal/terminal_settings.dart';
import 'package:pi_frame/features/settings/sections/appearance_section.dart';
import 'package:pi_frame/features/settings/sections/terminal_section.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'support/fake_platform_services.dart';

/// Records the custom path the section asks for, without writing the user's terminal settings file.
class _RecordingTerminalSettings extends TerminalSettingsNotifier {
  _RecordingTerminalSettings() {
    state = state.copyWith(mode: TerminalMode.native, nativeApp: NativeTerminalApp.custom);
  }

  final List<String> customPaths = [];

  @override
  void setCustomPath(String path) {
    customPaths.add(path);
    state = state.copyWith(customPath: path);
  }
}

void main() {
  const strings = AppStrings(AppLanguage.defaultLanguage);

  testWidgets('importing a theme asks for one JSON file and reads the chosen file through the file service', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final dialogs = FakeFileDialogService()..files = [fakePickedFile('/themes/broken.json')];
    final files = FakeFileSystemService()..files['/themes/broken.json'] = 'not a theme';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fileDialogServiceProvider.overrideWithValue(dialogs),
          fileSystemServiceProvider.overrideWithValue(files),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: const Scaffold(
            body: AppearanceSection(tokens: FrameTokens.dark, strings: strings),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(strings.importThemeBtn));
    await tester.tap(find.text(strings.importThemeBtn));
    await tester.pumpAndSettle();

    expect(dialogs.fileRequestedExtensions, [
      ['json'],
    ]);
    expect(dialogs.fileRequestedMultiple, [false]);
    // The content was read from the chosen path, so the broken theme is reported as an import error.
    expect(find.textContaining('Error importing theme'), findsOneWidget);
  });

  testWidgets('browsing for a terminal executable asks for one file and uses its path', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final dialogs = FakeFileDialogService()..files = [fakePickedFile('/opt/term/alacritty')];
    final terminal = _RecordingTerminalSettings();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fileDialogServiceProvider.overrideWithValue(dialogs),
          terminalSettingsProvider.overrideWith((ref) => terminal),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: const Scaffold(
            body: TerminalSection(tokens: FrameTokens.dark, strings: strings),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(strings.terminalBrowseBtn).first);
    await tester.tap(find.text(strings.terminalBrowseBtn).first);
    await tester.pumpAndSettle();

    expect(dialogs.fileRequestedMultiple, [false]);
    expect(terminal.customPaths, ['/opt/term/alacritty']);
  });
}
