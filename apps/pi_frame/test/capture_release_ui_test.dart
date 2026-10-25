import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/app/app_shell.dart';
import 'package:pi_frame/app/desktop_chrome.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/data/theme/theme_providers.dart';
import 'package:pi_frame/features/sessions_sidebar/instruction_file_dialog.dart';
import 'package:pi_frame/features/settings/theme_editor_dialog.dart';
import 'package:pi_frame/features/settings/settings_view.dart';
import 'package:pi_frame/ui/startup_assemble_animation.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

Directory _getOutputDir() {
  final out = Directory('c:/Personale/Repos/pi-crust/pi-crust/scratch/release_ui_screenshots');
  if (!out.existsSync()) {
    out.createSync(recursive: true);
  }
  return out;
}

Future<void> _captureToPng(
  WidgetTester tester,
  GlobalKey key,
  String fileName,
) async {
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      final outDir = _getOutputDir();
      File('${outDir.path}/$fileName').writeAsBytesSync(byteData.buffer.asUint8List());
    }
    image.dispose();
  });
}

class _MockPcpClient extends PcpClient {
  _MockPcpClient() : super(port: 1, token: 'mock');

  @override
  Future<Map<String, dynamic>> listSessions({String? query, int? limit}) async => {
        'data': {
          'sessions': [
            {
              'id': 'sess-1',
              'name': 'Audit Dart consumers e integrazione grafica Linux',
              'cwd': 'C:/Personale/Repos/pi-crust',
              'updatedAt': 1729586000000,
              'model': 'claude-3-7-sonnet',
            },
            {
              'id': 'sess-2',
              'name': 'Refactor UI Shell e navigazione pannelli',
              'cwd': 'C:/Personale/Repos/pi-crust',
              'updatedAt': 1729585000000,
              'model': 'claude-3-7-sonnet',
            },
            {
              'id': 'sess-3',
              'name': 'Aggiungere syntax highlighting e Ctrl+F search',
              'cwd': 'C:/Personale/Repos/pi-crust',
              'updatedAt': 1729584000000,
              'model': 'gpt-4o',
            },
            {
              'id': 'sess-4',
              'name': 'Ottimizzazione protocollo PCP e streaming token',
              'cwd': 'C:/Personale/Repos/pi-crust',
              'updatedAt': 1729583000000,
              'model': 'claude-3-7-sonnet',
            },
            {
              'id': 'sess-5',
              'name': 'Aggiornamento dipendenze e audit SAIF',
              'cwd': 'C:/Personale/Repos/pi-crust',
              'updatedAt': 1729582000000,
              'model': 'claude-3-5-sonnet',
            },
          ]
        }
      };
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final ui = FontLoader('SchibstedGrotesk')
      ..addFont(rootBundle.load('assets/fonts/SchibstedGrotesk.ttf'));
    await ui.load();
    final mono = FontLoader('SourceCodePro')
      ..addFont(rootBundle.load('assets/fonts/SourceCodePro.ttf'));
    await mono.load();
    final heading = FontLoader('BarlowCondensed')
      ..addFont(rootBundle.load('assets/fonts/BarlowCondensed-Bold.ttf'));
    await heading.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  testWidgets('Capture 1: Landing page with Quick Launch for 5 Recent Sessions', (tester) async {
    const size = Size(1400, 900);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final darkThemeJson = File('assets/themes/piframe-dark.json').readAsStringSync();
    final repo = ThemeRepository()
      ..registerThemeJson(darkThemeJson)
      ..setActiveTheme('piframe-dark');
    addTearDown(repo.dispose);

    final boundaryKey = GlobalKey();
    final mockClient = _MockPcpClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themeRepositoryProvider.overrideWithValue(repo),
          pcpClientProvider.overrideWithValue(mockClient),
          desktopChromeProvider.overrideWithValue(false),
          desktopWindowLifecycleProvider.overrideWithValue(false),
          connectionStateProvider.overrideWith(
            (ref) => Stream.value(DaemonConnectionState.connected),
          ),
          sessionListProvider.overrideWith(
            (ref) => Future.value([
              {
                'id': 'sess-1',
                'name': 'Audit Dart consumers e grafica Linux',
                'cwd': 'C:/Personale/Repos/pi-crust',
                'updatedAt': 1729586000000,
              },
              {
                'id': 'sess-2',
                'name': 'Refactor UI Shell e navigazione pannelli',
                'cwd': 'C:/Personale/Repos/pi-crust',
                'updatedAt': 1729585000000,
              },
              {
                'id': 'sess-3',
                'name': 'Aggiungere syntax highlighting e Ctrl+F search',
                'cwd': 'C:/Personale/Repos/pi-crust',
                'updatedAt': 1729584000000,
              },
              {
                'id': 'sess-4',
                'name': 'Ottimizzazione protocollo PCP e streaming token',
                'cwd': 'C:/Personale/Repos/pi-crust',
                'updatedAt': 1729583000000,
              },
              {
                'id': 'sess-5',
                'name': 'Aggiornamento dipendenze e audit SAIF',
                'cwd': 'C:/Personale/Repos/pi-crust',
                'updatedAt': 1729582000000,
              },
            ]),
          ),
          activeSessionIdProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp(
          theme: repo.activeTheme.toThemeData(),
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: RepaintBoundary(
              key: boundaryKey,
              child: const AppShell(),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Sessioni recenti'), findsOneWidget);
    expect(find.text('Audit Dart consumers e grafica Linux'), findsOneWidget);

    await _captureToPng(tester, boundaryKey, '01_landing_quick_launch.png');
  });

  testWidgets('Capture 2: Instruction File Dialog with Genera con Pi', (tester) async {
    const size = Size(1200, 800);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final darkThemeJson = File('assets/themes/piframe-dark.json').readAsStringSync();
    final repo = ThemeRepository()
      ..registerThemeJson(darkThemeJson)
      ..setActiveTheme('piframe-dark');
    addTearDown(repo.dispose);

    final boundaryKey = GlobalKey();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themeRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: repo.activeTheme.toThemeData(),
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0xFF0F172A),
            body: Center(
              child: RepaintBoundary(
                key: boundaryKey,
                child: const InstructionFileDialog(folder: 'C:/Personale/Repos/pi-crust'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Tap "Genera con Pi" button
    final generateBtn = find.byKey(const ValueKey('instruction-generate-pi-btn'));
    expect(generateBtn, findsOneWidget);
    await tester.tap(generateBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await _captureToPng(tester, boundaryKey, '02_instruction_dialog.png');
  });

  testWidgets('Capture 3: Startup Assemble Overlay with framed logo', (tester) async {
    const size = Size(1200, 800);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final darkThemeJson = File('assets/themes/piframe-dark.json').readAsStringSync();
    final repo = ThemeRepository()
      ..registerThemeJson(darkThemeJson)
      ..setActiveTheme('piframe-dark');
    addTearDown(repo.dispose);

    final boundaryKey = GlobalKey();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themeRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: repo.activeTheme.toThemeData(),
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0xFF0D1117),
            body: RepaintBoundary(
              key: boundaryKey,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomPaint(
                      size: const Size(140, 140),
                      painter: StartupAssembleOverlay.createAssemblePainter(
                        progress: 0.68,
                        tokens: FrameTokens.dark,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'PIFRAME',
                      style: TextStyle(
                        color: FrameTokens.dark.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 4.0,
                        fontFamily: FrameTokens.dark.headingFontFamily,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'PRECISION AGENT DESKTOP',
                      style: TextStyle(
                        color: FrameTokens.dark.textMuted,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2.2,
                        fontFamily: FrameTokens.dark.monoFontFamily,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await _captureToPng(tester, boundaryKey, '03_startup_assemble_animation.png');
  });

  testWidgets('Capture 4: Theme Editor Dialog with custom theme preview', (tester) async {
    const size = Size(1300, 850);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final darkThemeJson = File('assets/themes/piframe-dark.json').readAsStringSync();
    final repo = ThemeRepository()
      ..registerThemeJson(darkThemeJson)
      ..setActiveTheme('piframe-dark');
    addTearDown(repo.dispose);

    final boundaryKey = GlobalKey();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themeRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: repo.activeTheme.toThemeData(),
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0xFF0F172A),
            body: Center(
              child: RepaintBoundary(
                key: boundaryKey,
                child: const ThemeEditorDialog(),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await _captureToPng(tester, boundaryKey, '04_theme_editor.png');
  });

  testWidgets('Capture 5: Appearance Settings with Language Dropdown', (tester) async {
    const size = Size(1300, 850);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final darkThemeJson = File('assets/themes/piframe-dark.json').readAsStringSync();
    final repo = ThemeRepository()
      ..registerThemeJson(darkThemeJson)
      ..setActiveTheme('piframe-dark');
    addTearDown(repo.dispose);

    final boundaryKey = GlobalKey();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themeRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: repo.activeTheme.toThemeData(),
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: RepaintBoundary(
              key: boundaryKey,
              child: SettingsView(
                onClose: () {},
                initialTabIndex: 3,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Lingua dell\'Applicazione'), findsOneWidget);

    await _captureToPng(tester, boundaryKey, '05_appearance_settings.png');
  });
}
