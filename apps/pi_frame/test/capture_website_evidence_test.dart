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
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/command_palette/command_palette.dart';
import 'package:pi_frame/features/settings/theme_editor_dialog.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

Directory _resolveRepoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 5; i++) {
    if (File('${dir.path}/pnpm-workspace.yaml').existsSync() ||
        Directory('${dir.path}/docs/design-evidence').existsSync()) {
      return dir;
    }
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  return Directory.current;
}

void _saveScreenshot(Uint8List bytes, String fileName) {
  final root = _resolveRepoRoot();
  final targetDirs = [
    Directory('${root.path}/docs/design-evidence/recordly-projects'),
    Directory('${root.path}/website/assets/img/ui'),
    Directory('${root.path}/scratch/release_ui_screenshots'),
  ];

  for (final dir in targetDirs) {
    try {
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      File('${dir.path}/$fileName').writeAsBytesSync(bytes);
    } catch (_) {}
  }
}

Future<void> _captureToPng(
  WidgetTester tester,
  GlobalKey key,
  String fileName,
) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.runAsync(() async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      _saveScreenshot(byteData.buffer.asUint8List(), fileName);
    }
    image.dispose();
  });
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
        {
          'path': 'packages/pi_frame_theme/lib/src/theme_tokens.dart',
          'sizeBytes': 5100,
        },
        {'path': 'themes/piframe-dark.json', 'sizeBytes': 1850},
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
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// PiFrame Dark & Light Normative Theme Controller
class ThemeTokensController {
  final FrameTokens tokens;
  const ThemeTokensController(this.tokens);

  Color get background => tokens.background;
  Color get chassis => tokens.chassis;
  Color get surface => tokens.surface;
  Color get accent => tokens.accent;
}
''',
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
      'branch': 'main',
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
          'path': 'themes/piframe-dark.json',
          'status': 'added',
          'staged': true,
          'unstaged': false,
          'additions': 73,
          'deletions': 0,
        },
        {
          'path': 'themes/piframe-light.json',
          'status': 'added',
          'staged': true,
          'unstaged': false,
          'additions': 73,
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
      'diff': '''--- a/apps/pi_frame/lib/app/app_shell.dart
+++ b/apps/pi_frame/lib/app/app_shell.dart
@@ -14,6 +14,9 @@
-    final bg = Color(0xFF303446); // Old Catppuccin
+    // Official PiFrame Dark Theme
+    final bg = FrameTokens.dark.background; // #161c27
+    final accent = FrameTokens.dark.accent; // #5f9fc5
''',
    },
  };

  @override
  Future<Map<String, dynamic>> listSessions({
    String? query,
    int? limit,
  }) async => {
    'data': {
      'sessions': [
        {
          'id': 'sess-main',
          'name': 'Aggiornamento temi predefiniti piframe-dark e piframe-light',
          'cwd': 'C:/Projects/pi-frame',
          'updatedAt': 1729600000000,
          'model': 'claude-3-7-sonnet',
        },
        {
          'id': 'sess-2',
          'name': 'Refactor UI Shell e navigazione pannelli',
          'cwd': 'C:/Projects/pi-frame',
          'updatedAt': 1729599000000,
          'model': 'claude-3-7-sonnet',
        },
      ],
    },
  };

  @override
  Future<List<Map<String, dynamic>>> getSubagents(String sessionId) async => [];
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final uiFont = FontLoader('SchibstedGrotesk')
      ..addFont(rootBundle.load('assets/fonts/SchibstedGrotesk.ttf'));
    await uiFont.load();
    final monoFont = FontLoader('SourceCodePro')
      ..addFont(rootBundle.load('assets/fonts/SourceCodePro.ttf'));
    await monoFont.load();
    final headingFont = FontLoader('BarlowCondensed')
      ..addFont(rootBundle.load('assets/fonts/BarlowCondensed-SemiBold.ttf'))
      ..addFont(rootBundle.load('assets/fonts/BarlowCondensed-Bold.ttf'));
    await headingFont.load();
    final iconsFont = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconsFont.load();
  });

  Widget createHarness({
    required ThemeRepository repo,
    required _VisualWorkspaceClient client,
    required SessionState session,
    required GlobalKey key,
    Widget? customBody,
  }) {
    final notifier = SessionStateNotifier(session.sessionId, client)
      ..state = session;

    return ProviderScope(
      overrides: [
        themeRepositoryProvider.overrideWithValue(repo),
        daemonEndpointProvider.overrideWith((ref) async => null),
        pcpClientProvider.overrideWithValue(client),
        desktopChromeProvider.overrideWithValue(false),
        desktopWindowLifecycleProvider.overrideWithValue(false),
        connectionStateProvider.overrideWith(
          (ref) => Stream.value(DaemonConnectionState.connected),
        ),
        sessionListProvider.overrideWith(
          (ref) async => [
            {
              'id': session.sessionId,
              'name': session.sessionName,
              'cwd': session.cwd,
              'isActive': true,
              'lastMessagePreview': session.entries.isNotEmpty
                  ? session.entries.last.text
                  : 'Nessun messaggio',
            },
          ],
        ),
        activeSessionIdProvider.overrideWith((ref) => session.sessionId),
        sessionStateFamily(session.sessionId).overrideWith((ref) => notifier),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: repo.activeTheme.toThemeData(),
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: customBody ?? const AppShell(),
          ),
        ),
      ),
    );
  }

  // 1. CAPTURE STEER QUEUE
  testWidgets('Capture Steer Queue in PiFrame Dark', (tester) async {
    const size = Size(1600, 1000);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final darkThemeJson = File('assets/themes/piframe-dark.json')
        .readAsStringSync();
    final repo = ThemeRepository()
      ..registerThemeJson(darkThemeJson)
      ..setActiveTheme('piframe-dark');
    addTearDown(repo.dispose);

    final client = _VisualWorkspaceClient();
    final key = GlobalKey();

    final session = SessionState(
      sessionId: 'sess-steer-test',
      sessionName: 'Visual Steering & Queue Re-ordering',
      cwd: 'C:/Projects/pi-frame',
      currentModel: 'claude-3-7-sonnet',
      currentThinkingLevel: 'high',
      sessionStats: const {
        'cost': 0.28,
        'tokens': {'total': 34200},
        'contextUsage': {
          'tokens': 48000,
          'contextWindow': 200000,
          'percent': 24.0,
        },
      },
      extensionStatuses: const {'caveman': 'full', 'ponytail': 'full'},
      agentStatus: AgentStatus.working,
      steeringQueue: const [
        'Verifica che Ctrl+F supporti il cycling dei match avanti e indietro',
        'Aggiungi test per il rollback atomico delle modifiche Git',
        'Controlla il consumo token per file superiori a 100KB',
      ],
      entries: const [
        SessionEntry(
          id: 'u1',
          role: 'user',
          timestamp: 1,
          text: 'Voglio configurare una coda di steering reattiva con token PiFrame Dark.',
        ),
        SessionEntry(
          id: 'a1',
          role: 'assistant',
          timestamp: 2,
          thinking: '1. Verifico la presenza di messaggi steer in coda nel SessionState.\n2. Renderizzo la barra di steering con i controlli di prioritizzazione.\n3. Applico la palette PiFrame Dark (#161c27, #5f9fc5).',
          text: 'Sto elaborando la richiesta. La coda contiene 3 istruzioni pendenti pronte per essere eseguite in sequenza.',
        ),
      ],
    );

    await tester.pumpWidget(
      createHarness(repo: repo, client: client, session: session, key: key),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await _captureToPng(tester, key, 'clip-04-steer-queue.preview.png');
  });

  // 2. CAPTURE REASONING STREAM
  testWidgets('Capture Reasoning Stream in PiFrame Dark', (tester) async {
    const size = Size(1600, 1000);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final darkThemeJson = File('assets/themes/piframe-dark.json')
        .readAsStringSync();
    final repo = ThemeRepository()
      ..registerThemeJson(darkThemeJson)
      ..setActiveTheme('piframe-dark');
    addTearDown(repo.dispose);

    final client = _VisualWorkspaceClient();
    final key = GlobalKey();

    final session = SessionState(
      sessionId: 'sess-reasoning-test',
      sessionName: 'Reasoning Stream & Token Metrics',
      cwd: 'C:/Projects/pi-frame',
      currentModel: 'claude-3-7-sonnet',
      currentThinkingLevel: 'high',
      sessionStats: const {
        'cost': 0.42,
        'tokens': {'total': 52100},
        'contextUsage': {
          'tokens': 72000,
          'contextWindow': 200000,
          'percent': 36.0,
        },
      },
      extensionStatuses: const {'caveman': 'full', 'ponytail': 'full'},
      agentStatus: AgentStatus.working,
      steeringQueue: const [],
      entries: const [
        SessionEntry(
          id: 'u1',
          role: 'user',
          timestamp: 1,
          text: 'Spiega il ciclo di vita della riconnessione automatica del daemon.',
        ),
        SessionEntry(
          id: 'a1',
          role: 'assistant',
          timestamp: 2,
          thinking: '1. Isolo il gestore del protocollo PCP in un modulo separato.\n2. Analizzo gli stream di token per prevenire il blocco del thread UI a 120 FPS.\n3. Verifico che la riconnessione automatica ripristini i cursori di streaming con sequenza monotonica.\n4. La cronologia delle sessioni appartiene a Pi e viene preservata su disco.',
          toolCalls: [
            ToolExecutionState(
              toolCallId: 't1',
              toolName: 'readWorkspaceFile',
              args: {'path': 'apps/pi_frame/lib/data/daemon/pcp_client.dart'},
              output: 'Daemon connection verified on 127.0.0.1. Replay cursor active.',
              durationMs: 48,
            ),
          ],
          text: 'Il demone esegue `pi-agentd` in background su porta loopback locale. Durante la chiusura della finestra, il processo prosegue senza interruzioni.',
        ),
      ],
    );

    await tester.pumpWidget(
      createHarness(repo: repo, client: client, session: session, key: key),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Tap thinking header to ensure expanded state
    final thinkingFinder = find.byKey(const ValueKey('thinking-header-a1'));
    if (thinkingFinder.evaluate().isNotEmpty) {
      await tester.tap(thinkingFinder.first);
      await tester.pump(const Duration(milliseconds: 200));
    }

    await _captureToPng(tester, key, 'clip-06-reasoning-stream.preview.png');
  });

  // 3. CAPTURE GIT STAGING DESK
  testWidgets('Capture Git Staging Desk in PiFrame Dark', (tester) async {
    const size = Size(1600, 1000);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final darkThemeJson = File('assets/themes/piframe-dark.json')
        .readAsStringSync();
    final repo = ThemeRepository()
      ..registerThemeJson(darkThemeJson)
      ..setActiveTheme('piframe-dark');
    addTearDown(repo.dispose);

    final client = _VisualWorkspaceClient();
    final key = GlobalKey();

    final session = SessionState(
      sessionId: 'sess-git-test',
      sessionName: 'Git Changes Review Desk & Diff Staging',
      cwd: 'C:/Projects/pi-frame',
      currentModel: 'claude-3-7-sonnet',
      currentThinkingLevel: 'medium',
      sessionStats: const {
        'cost': 0.15,
        'tokens': {'total': 18900},
        'contextUsage': {
          'tokens': 24000,
          'contextWindow': 200000,
          'percent': 12.0,
        },
      },
      extensionStatuses: const {'caveman': 'full'},
      agentStatus: AgentStatus.settled,
      steeringQueue: const [],
      entries: const [
        SessionEntry(
          id: 'u1',
          role: 'user',
          timestamp: 1,
          text: 'Mostrami le modifiche Git pronte per il commit.',
        ),
        SessionEntry(
          id: 'a1',
          role: 'assistant',
          timestamp: 2,
          text: 'Ecco il quadro delle modifiche: 2 file preparati (staged) e 1 file non preparato con le nuove definizioni del tema PiFrame Dark.',
        ),
      ],
    );

    await tester.pumpWidget(
      createHarness(repo: repo, client: client, session: session, key: key),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Expand Git Changes Pane
    final gitHeader = find.textContaining('GIT CHANGES');
    if (gitHeader.evaluate().isNotEmpty) {
      await tester.tap(gitHeader.first);
      await tester.pump(const Duration(milliseconds: 200));
    }

    final stagedHeader = find.textContaining('MODIFICHE PREPARATE (STAGED)');
    if (stagedHeader.evaluate().isNotEmpty) {
      await tester.tap(stagedHeader.first);
      await tester.pump(const Duration(milliseconds: 200));
    }

    await _captureToPng(tester, key, 'clip-08-git-staging.preview.png');
  });

  // 4. CAPTURE DISCONNECT-SAFE DAEMON
  testWidgets('Capture Disconnect-Safe Daemon in PiFrame Dark', (tester) async {
    const size = Size(1600, 1000);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final darkThemeJson = File('assets/themes/piframe-dark.json')
        .readAsStringSync();
    final repo = ThemeRepository()
      ..registerThemeJson(darkThemeJson)
      ..setActiveTheme('piframe-dark');
    addTearDown(repo.dispose);

    final client = _VisualWorkspaceClient();
    final key = GlobalKey();

    final session = SessionState(
      sessionId: 'sess-daemon-safe',
      sessionName: 'Disconnect-Safe 3-Tier Daemon Session',
      cwd: 'C:/Projects/pi-frame',
      currentModel: 'claude-3-7-sonnet',
      currentThinkingLevel: 'high',
      sessionStats: const {
        'cost': 0.35,
        'tokens': {'total': 44200},
        'contextUsage': {
          'tokens': 58000,
          'contextWindow': 200000,
          'percent': 29.0,
        },
      },
      extensionStatuses: const {'caveman': 'full', 'ponytail': 'full'},
      agentStatus: AgentStatus.working,
      steeringQueue: const [],
      entries: const [
        SessionEntry(
          id: 'u1',
          role: 'user',
          timestamp: 1,
          text: 'Esegui i test di integrazione per il demone in background.',
        ),
        SessionEntry(
          id: 'a1',
          role: 'assistant',
          timestamp: 2,
          toolCalls: [
            ToolExecutionState(
              toolCallId: 't1',
              toolName: 'flutter test',
              args: {'file': 'test/pcp_client_test.dart'},
              output: '00:02 +8: All 8 client tests passed!',
              durationMs: 2150,
            ),
          ],
          text: 'Tutti i test del demone hanno avuto esito positivo. La connessione IPC loopback mantiene la sequenza monotonica.',
        ),
      ],
    );

    await tester.pumpWidget(
      createHarness(repo: repo, client: client, session: session, key: key),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await _captureToPng(tester, key, 'clip-11-disconnect-safe.preview.png');
    await _captureToPng(tester, key, 'clip-01-bento-workspace.preview.png');
    await _captureToPng(tester, key, 'hero-30s-bento-walkthrough.preview.png');
  });

  // 5. CAPTURE THEME EDITOR
  testWidgets('Capture Theme Editor Dialog in PiFrame Dark', (tester) async {
    const size = Size(1300, 850);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final darkThemeJson = File('assets/themes/piframe-dark.json')
        .readAsStringSync();
    final repo = ThemeRepository()
      ..registerThemeJson(darkThemeJson)
      ..setActiveTheme('piframe-dark');
    addTearDown(repo.dispose);

    final key = GlobalKey();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [themeRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: repo.activeTheme.toThemeData(),
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0xFF161C27),
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: const ThemeEditorDialog(),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await _captureToPng(tester, key, '04_theme_editor.png');
    await _captureToPng(tester, key, 'clip-10-catppuccin-themes.preview.png');
  });

  // 6. CAPTURE COMMAND PALETTE
  testWidgets('Capture Command Palette in PiFrame Dark', (tester) async {
    const size = Size(1600, 1000);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final darkThemeJson = File('assets/themes/piframe-dark.json')
        .readAsStringSync();
    final repo = ThemeRepository()
      ..registerThemeJson(darkThemeJson)
      ..setActiveTheme('piframe-dark');
    addTearDown(repo.dispose);

    final key = GlobalKey();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [themeRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: repo.activeTheme.toThemeData(),
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0xFF121721),
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: 680,
                  height: 480,
                  child: const CommandPalette(),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await _captureToPng(tester, key, 'clip-02-command-palette.preview.png');
  });

  // 7. CAPTURE TOOL TIMELINE & CONTEXT ANALYTICS
  testWidgets('Capture Tool Timeline and Context Analytics in PiFrame Dark', (
    tester,
  ) async {
    const size = Size(1600, 1000);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final darkThemeJson = File('assets/themes/piframe-dark.json')
        .readAsStringSync();
    final repo = ThemeRepository()
      ..registerThemeJson(darkThemeJson)
      ..setActiveTheme('piframe-dark');
    addTearDown(repo.dispose);

    final client = _VisualWorkspaceClient();
    final key = GlobalKey();

    final session = SessionState(
      sessionId: 'sess-tools-analytics',
      sessionName: 'PCP Tool Execution Timeline & Context Breakdown',
      cwd: 'C:/Projects/pi-frame',
      currentModel: 'claude-3-7-sonnet',
      currentThinkingLevel: 'high',
      sessionStats: const {
        'cost': 0.48,
        'tokens': {'total': 64100},
        'contextUsage': {
          'tokens': 86400,
          'contextWindow': 200000,
          'percent': 43.2,
        },
      },
      extensionStatuses: const {'caveman': 'full', 'ponytail': 'full'},
      agentStatus: AgentStatus.settled,
      steeringQueue: const [],
      entries: const [
        SessionEntry(
          id: 'u1',
          role: 'user',
          timestamp: 1,
          text: 'Esegui il test delle performance sui token del tema PiFrame Dark.',
        ),
        SessionEntry(
          id: 'a1',
          role: 'assistant',
          timestamp: 2,
          thinking: 'Eseguo il benchmark su 500 componenti UI per accertare il rendering a 120 FPS costanti.',
          toolCalls: [
            ToolExecutionState(
              toolCallId: 't1',
              toolName: 'readWorkspaceFile',
              args: {
                'path': 'packages/pi_frame_theme/lib/src/theme_tokens.dart',
              },
              output: 'FrameTokens loaded: #161c27 base, #5f9fc5 accent.',
              durationMs: 34,
            ),
            ToolExecutionState(
              toolCallId: 't2',
              toolName: 'flutter test',
              args: {'filter': 'design_tokens_test'},
              output: '00:03 +12: All token assertions passed in 18ms!',
              durationMs: 3200,
            ),
            ToolExecutionState(
              toolCallId: 't3',
              toolName: 'benchmarkGpuTextures',
              args: {'sampleFrames': 120},
              output:
                  'Impeller raster cache hit rate: 99.4% (8.2ms frame time)',
              durationMs: 820,
            ),
          ],
          text: 'Il benchmark conferma zero frame drops con i token ufficiali PiFrame Dark. L\'uso del contesto è ottimizzato al 43.2%.',
        ),
      ],
    );

    await tester.pumpWidget(
      createHarness(repo: repo, client: client, session: session, key: key),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await _captureToPng(tester, key, 'clip-07-tool-timeline.preview.png');
    await _captureToPng(tester, key, 'clip-05-context-analytics.preview.png');
    await _captureToPng(tester, key, 'clip-03-code-search.preview.png');

    // Tap to open the session tree drawer for clip-09
    final sessionsBtn = find.byTooltip('Apri sessioni');
    if (sessionsBtn.evaluate().isNotEmpty) {
      await tester.tap(sessionsBtn.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
    await _captureToPng(tester, key, 'clip-09-session-tree.preview.png');
  });
}
