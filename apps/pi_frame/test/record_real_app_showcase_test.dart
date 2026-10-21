import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/app/app_shell.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/data/theme/theme_providers.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/workspace/repository_workspace.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

int _frameCounter = 0;

Directory _resolveOutputDir() {
  final candidate1 = Directory('scratch/real_frames');
  final candidate2 = Directory('../scratch/real_frames');
  final candidate3 = Directory('../../scratch/real_frames');
  if (candidate2.existsSync()) return candidate2;
  if (candidate1.existsSync()) return candidate1;
  if (candidate3.existsSync()) return candidate3;
  candidate2.createSync(recursive: true);
  return candidate2;
}

Future<void> _recordFrames(
  WidgetTester tester,
  GlobalKey boundaryKey,
  int frameCount, {
  Duration step = const Duration(milliseconds: 66),
}) async {
  final outDir = _resolveOutputDir();
  for (var i = 0; i < frameCount; i++) {
    await tester.pump(step);
    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final pad = _frameCounter.toString().padLeft(5, '0');
        File('${outDir.path}/frame_$pad.png')
            .writeAsBytesSync(byteData.buffer.asUint8List());
        _frameCounter++;
      }
      image.dispose();
    });
  }
}

class _VisualWorkspaceClient extends PcpClient {
  _VisualWorkspaceClient() : super(port: 1, token: 'fixture');

  @override
  Future<Map<String, dynamic>> listWorkspaceFiles(String sessionId) async => {
    'data': {
      'rootPath': 'C:/Projects/pi-frame',
      'truncated': false,
      'files': [
        {'path': 'apps/pi_frame/lib/app/app_shell.dart', 'sizeBytes': 4800},
        {
          'path':
              'apps/pi_frame/lib/features/workspace/repository_workspace.dart',
          'sizeBytes': 7200,
        },
        {
          'path': 'apps/pi_frame/lib/ui/code/code_editor_controller.dart',
          'sizeBytes': 3600,
        },
      ],
    },
  };

  @override
  Future<Map<String, dynamic>> readWorkspaceFile(
    String sessionId,
    String path,
  ) async => {
    'data': {
      'rootPath': 'C:/Projects/pi-frame',
      'path': path,
      'content': '''import 'package:flutter/material.dart';
import 'package:pi_frame/ui/precision.dart';

/// PiFrame Bento Triptych AppShell with PiFrameMark 3D icon
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Row(
        children: [
          PiFrameMark(size: 28),
          Text('PiFrame Workspace'),
        ],
      ),
    );
  }
}''',
      'revision': List.filled(64, 'a').join(),
      'sizeBytes': 280,
    },
  };

  @override
  Future<Map<String, dynamic>> refreshWorkspace(
    String sessionId, {
    String? cwd,
  }) async => {
    'data': {
      'isRepository': true,
      'rootPath': 'C:/Projects/pi-frame',
      'branch': 'UI_improvements',
      'files': [
        {
          'path': 'apps/pi_frame/lib/app/app_shell.dart',
          'status': 'modified',
          'staged': false,
          'unstaged': true,
          'additions': 14,
          'deletions': 3,
        },
        {
          'path': 'apps/pi_frame/lib/ui/code/code_editor_controller.dart',
          'status': 'added',
          'staged': true,
          'unstaged': false,
          'additions': 120,
          'deletions': 0,
        },
      ],
    },
  };

  @override
  Future<Map<String, dynamic>> getWorkspaceDiff(
    String sessionId, {
    String? filePath,
  }) async => {
    'data': {
      'filePath': filePath ?? 'apps/pi_frame/lib/app/app_shell.dart',
      'diff': '''--- a/apps/pi_frame/lib/ui/precision.dart
+++ b/apps/pi_frame/lib/ui/precision.dart
@@ -140,6 +140,14 @@
-      child: CustomPaint(painter: _MarkPainter(tokens)),
+      child: Image.asset(
+        isDark ? 'assets/branding/app_icon_dark_512.png' : 'assets/branding/app_icon_light_512.png',
+        width: size,
+        height: size,
+        fit: BoxFit.contain,
+      ),
''',
    },
  };

  @override
  Future<Map<String, dynamic>> saveWorkspaceFile(
    String sessionId,
    Map<String, dynamic> payload,
  ) async => {'data': {'path': payload['path'], 'revision': List.filled(64, 'b').join()}};

  @override
  Future<Map<String, dynamic>> workspaceGitAction(
    String sessionId,
    Map<String, dynamic> payload,
  ) async => {'data': {'status': <String, dynamic>{}}};

  @override
  Future<Map<String, dynamic>> clearQueue(String sessionId) async => {'ok': true};

  @override
  Future<Map<String, dynamic>> sendPrompt(
    String sessionId,
    String text, {
    String? streamingBehavior,
    List<dynamic>? images,
  }) async => {'ok': true};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    for (final font in ['SchibstedGrotesk', 'SourceCodePro']) {
      final loader = FontLoader(font)
        ..addFont(rootBundle.load('assets/fonts/$font.ttf'));
      await loader.load();
    }
    final heading = FontLoader('BarlowCondensed')
      ..addFont(rootBundle.load('assets/fonts/BarlowCondensed-SemiBold.ttf'))
      ..addFont(rootBundle.load('assets/fonts/BarlowCondensed-Bold.ttf'));
    await heading.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  testWidgets('Record live running Flutter application frames', (
    tester,
  ) async {
    const size = Size(1600, 1000);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final darkThemeJson = File('assets/themes/piframe-dark.json').readAsStringSync();
    final lightThemeJson = File('assets/themes/piframe-light.json').readAsStringSync();
    final repo = ThemeRepository()
      ..registerThemeJson(darkThemeJson)
      ..registerThemeJson(lightThemeJson)
      ..setActiveTheme('piframe-dark');
    addTearDown(repo.dispose);

    final client = _VisualWorkspaceClient();
    final boundaryKey = GlobalKey();

    var currentSession = SessionState(
      sessionId: 'demo-live-session',
      sessionName: 'Aggiungere syntax highlighting e Ctrl+F search',
      cwd: 'C:/Projects/pi-frame',
      currentModel: 'claude-3-7-sonnet',
      currentThinkingLevel: 'high',
      sessionStats: const {
        'cost': 0.18,
        'tokens': {'total': 28400},
        'contextUsage': {'tokens': 32000, 'contextWindow': 200000, 'percent': 16.0},
      },
      extensionStatuses: const {'caveman': 'full', 'ponytail': 'full'},
      agentStatus: AgentStatus.working,
      steeringQueue: const ['Verifica che Ctrl+F supporti il cycling dei match avanti e indietro'],
      entries: const [
        SessionEntry(
          id: 'u1',
          role: 'user',
          timestamp: 1,
          text: 'Voglio visualizzare i file del repository con syntax highlighting e una barra di ricerca Ctrl+F rapida.',
        ),
        SessionEntry(
          id: 'a1',
          role: 'assistant',
          timestamp: 2,
          thinking: '1. Creo CodeEditorController integrando SyntaxHighlighter.\n2. Aggiungo overlay con contatore match e navigazione.\n3. Verifico la compatibilità con i token di tema Catppuccin.',
          toolCalls: [
            ToolExecutionState(
              toolCallId: 't1',
              toolName: 'flutter test',
              args: {'filter': 'code_editor'},
              output: '00:04 +5: All tests passed!',
              durationMs: 4100,
            ),
          ],
          text: 'Ho implementato il controller con syntax highlighting per codice multi-linguaggio, overlay di ricerca Ctrl+F con cycling dei match e modifica diretta dei messaggi steer in coda.',
        ),
      ],
    );

    final sessionNotifier = SessionStateNotifier('demo-live-session', client)
      ..state = currentSession;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themeRepositoryProvider.overrideWithValue(repo),
          daemonEndpointProvider.overrideWith((ref) async => null),
          pcpClientProvider.overrideWithValue(client),
          connectionStateProvider.overrideWith(
            (ref) => Stream.value(DaemonConnectionState.connected),
          ),
          sessionListProvider.overrideWith(
            (ref) async => [
              {
                'id': currentSession.sessionId,
                'name': currentSession.sessionName,
                'cwd': currentSession.cwd,
                'isActive': true,
                'lastMessagePreview': 'Ho implementato il controller con syntax highlighting...',
              },
            ],
          ),
          activeSessionIdProvider.overrideWith(
            (ref) => currentSession.sessionId,
          ),
          sessionStateFamily(currentSession.sessionId).overrideWith(
            (ref) => sessionNotifier,
          ),
        ],
        child: RepaintBoundary(
          key: boundaryKey,
          child: Consumer(
            builder: (context, ref, child) {
              final themeData = ref.watch(currentThemeDataProvider);
              return MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: themeData,
                home: const AppShell(),
              );
            },
          ),
        ),
      ),
    );

    // Warm-up 16 render cycles so 3D icon and font assets are fully decoded in GPU texture cache
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final img = await boundary.toImage(pixelRatio: 1.0);
          img.dispose();
        }
      });
    }
    _frameCounter = 0;

    // SCENE 1: Active Bento Triptych with 3D PiFrameMark logo, Chat, Repository & Git (1.5s)
    await _recordFrames(tester, boundaryKey, 25);

    // SCENE 2: Select file in Repository tree to view syntax highlighting (2s)
    final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final repoNotifier = container.read(repositoryStateProvider(currentSession.sessionId).notifier);
    await repoNotifier.loadFiles();
    await repoNotifier.selectFile('apps/pi_frame/lib/app/app_shell.dart');
    await _recordFrames(tester, boundaryKey, 25);

    // SCENE 3: Open in-file search bar (Ctrl+F) and type search query (2s)
    final searchButton = find.byKey(const ValueKey('repository-editor-search-btn'));
    if (searchButton.evaluate().isNotEmpty) {
      await tester.tap(searchButton.first);
      await _recordFrames(tester, boundaryKey, 10);

      final searchInput = find.byKey(const ValueKey('repository-file-search-field'));
      if (searchInput.evaluate().isNotEmpty) {
        await tester.enterText(searchInput, 'PiFrameMark');
        await _recordFrames(tester, boundaryKey, 15);

        // Cycle next match
        final nextBtn = find.byKey(const ValueKey('repository-file-search-next'));
        if (nextBtn.evaluate().isNotEmpty) {
          await tester.tap(nextBtn);
          await _recordFrames(tester, boundaryKey, 15);
        }
      }
    }

    // SCENE 4: Steer Queue modification in Composer (2s)
    final editSteerBtn = find.byTooltip('Modifica messaggio in coda (Steer #1)');
    if (editSteerBtn.evaluate().isNotEmpty) {
      await tester.tap(editSteerBtn.first);
      await _recordFrames(tester, boundaryKey, 15);

      // Dialog is open, tap Annulla to close
      final cancelBtn = find.text('Annulla');
      if (cancelBtn.evaluate().isNotEmpty) {
        await tester.tap(cancelBtn.first);
        await _recordFrames(tester, boundaryKey, 15);
      }
    }

    // SCENE 5: Thinking block toggle animation (1.5s)
    final thinkingHeader = find.byKey(const ValueKey('thinking-header-a1'));
    if (thinkingHeader.evaluate().isNotEmpty) {
      await tester.tap(thinkingHeader.first);
      await _recordFrames(tester, boundaryKey, 15);
      await tester.tap(thinkingHeader.first);
      await _recordFrames(tester, boundaryKey, 15);
    }

    // SCENE 6: Git Changes inspection (2s)
    final gitPane = find.byType(GitChangesPane);
    final changesHeader = find.descendant(of: gitPane, matching: find.textContaining('MODIFICHE (CHANGES)'));
    if (changesHeader.evaluate().isNotEmpty) {
      await tester.tap(changesHeader.first);
      await _recordFrames(tester, boundaryKey, 8);
    }
    final gitFile = find.textContaining('apps/pi_frame/lib');
    if (gitFile.evaluate().isNotEmpty) {
      await tester.tap(gitFile.first);
      await _recordFrames(tester, boundaryKey, 25);

      // Close modal diff
      final closeIcon = find.byIcon(Icons.close);
      if (closeIcon.evaluate().isNotEmpty) {
        await tester.tap(closeIcon.last);
      }
      await _recordFrames(tester, boundaryKey, 10);
    }

    // SCENE 7: Theme Switcher - Catppuccin Latte light mode (2s)
    final lightThemeBtn = find.byIcon(Icons.light_mode_outlined);
    if (lightThemeBtn.evaluate().isNotEmpty) {
      await tester.tap(lightThemeBtn.first);
      await _recordFrames(tester, boundaryKey, 30);
    }

    // SCENE 8: Switch back to Catppuccin dark mode (1.5s)
    final darkThemeBtn = find.byIcon(Icons.dark_mode_outlined);
    if (darkThemeBtn.evaluate().isNotEmpty) {
      await tester.tap(darkThemeBtn.first);
      await _recordFrames(tester, boundaryKey, 25);
    }

    // ignore: avoid_print
    print('CAPTURED REAL APP FRAMES: $_frameCounter');
    expect(_frameCounter, greaterThan(150));
  });
}
