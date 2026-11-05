import 'dart:async';
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
import 'package:pi_frame/data/update/github_update_client.dart';
import 'package:pi_frame/data/update/update_providers.dart';
import 'package:pi_frame/data/update/update_storage.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/domain/session/attachment_model.dart';
import 'package:pi_frame/domain/update/update_models.dart';
import 'package:pi_frame/features/browser/web_browser_pane.dart';
import 'package:pi_frame/features/context_panel/context_panel.dart';
import 'package:pi_frame/features/composer/attachment_chips.dart';
import 'package:pi_frame/features/dialogs/extension_ui_dialog.dart';
import 'package:pi_frame/features/session_changes/review_file_diff_viewer.dart';
import 'package:pi_frame/features/session_changes/session_changes_pane.dart';
import 'package:pi_frame/features/session_changes/session_changes_provider.dart';
import 'package:pi_frame/features/sessions_sidebar/instruction_file_dialog.dart';
import 'package:pi_frame/features/sessions_sidebar/pinned_sessions_provider.dart';
import 'package:pi_frame/features/sessions_sidebar/sessions_sidebar.dart';
import 'package:pi_frame/features/settings/pi_cli_section.dart';
import 'package:pi_frame/features/settings/remote_section.dart';
import 'package:pi_frame/features/settings/updates_section.dart';
import 'package:pi_frame/features/transcript/rich_content.dart';
import 'package:pi_frame/features/updates/startup_update_banner.dart';
import 'package:pi_frame/features/workspace/integrated_terminal.dart';
import 'package:pi_frame/features/workspace/repository_workspace.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

Directory _resolveRepoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 5; i++) {
    if (File('${dir.path}/pnpm-workspace.yaml').existsSync() ||
        Directory('${dir.path}/website').existsSync()) {
      return dir;
    }
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  return Directory.current;
}

void _saveScreenshot(Uint8List bytes, String relativePath) {
  final root = _resolveRepoRoot();
  final target = File('${root.path}/$relativePath');
  if (!target.parent.existsSync()) {
    target.parent.createSync(recursive: true);
  }
  target.writeAsBytesSync(bytes);
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey key,
  String relativePath, {
  double ratio = 2.0,
}) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.runAsync(() async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: ratio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      _saveScreenshot(byteData.buffer.asUint8List(), relativePath);
    }
    image.dispose();
  });
}

class _MockShowcaseClient extends PcpClient {
  _MockShowcaseClient() : super(port: 1, token: 'showcase-fixture');

  @override
  Future<Map<String, dynamic>> listWorkspaceFiles(String sessionId) async => {
    'data': {
      'rootPath': 'C:/Projects/pi-frame',
      'truncated': false,
      'files': [
        {'path': 'apps/pi_frame/lib/app/app_shell.dart', 'sizeBytes': 5200},
        {
          'path': 'packages/pi_frame_theme/lib/src/theme_tokens.dart',
          'sizeBytes': 6200,
        },
        {'path': 'themes/piframe-dark.json', 'sizeBytes': 2100},
        {'path': 'docs/DESIGN.md', 'sizeBytes': 9800},
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

/// PiFrame Dark & Light Theme Tokens Controller
class ThemeTokensController {
  final FrameTokens tokens;
  const ThemeTokensController(this.tokens);

  Color get background => tokens.background;
  Color get chassis => tokens.chassis;
  Color get surface => tokens.surface;
  Color get accent => tokens.accent;
  Color get thinking => tokens.thinking;
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
          'additions': 18,
          'deletions': 4,
        },
        {
          'path': 'packages/pi_frame_theme/lib/src/theme_tokens.dart',
          'status': 'modified',
          'staged': true,
          'unstaged': false,
          'additions': 32,
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
      'diff': '''--- a/lib/app/app_shell.dart
+++ b/lib/app/app_shell.dart
@@ -14,8 +14,14 @@
-    final background = Color(0xFF232634); // Legacy Catppuccin
-    final accent = Color(0xFFCA9EE6);
+    // Official PiFrame Dark Theme Normative Tokens
+    final background = FrameTokens.dark.background; // #161c27
+    final chassis = FrameTokens.dark.chassis;       // #121721
+    final accent = FrameTokens.dark.accent;         // #5f9fc5
+    final thinking = FrameTokens.dark.thinking;     // #81b2cf
@@ -40,6 +46,10 @@
-    return Container(child: chatView);
+    return BentoTriptychWorkspace(
+      chat: chatView,
+      diffReview: splitDiffReview,
+      terminal: hardwareTerminal,
+    );
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
          'id': 'sess-pinned-1',
          'name': 'Refactor Token System & Bento Grid Ergonomics',
          'cwd': 'C:/Projects/pi-frame',
          'updatedAt': 1729605000000,
          'model': 'claude-3-7-sonnet',
          'isPinned': true,
          'isActive': false,
        },
        {
          'id': 'sess-main',
          'name': 'Integrazione Browser Web e Terminale Hardware',
          'cwd': 'C:/Projects/pi-frame',
          'updatedAt': 1729600000000,
          'model': 'claude-3-7-sonnet',
          'isPinned': false,
          'isActive': true,
        },
      ],
    },
  };

  @override
  Future<List<Map<String, dynamic>>> getSubagents(String sessionId) async => [];

  @override
  Future<Map<String, dynamic>> getRemoteStatus() async => {
    'data': {
      'enabled': true,
      'state': 'running',
      'url': 'https://node-piframe.tailscale.net',
      'tunnelProvider': 'tailscale',
      'pairingUrl': 'https://node-piframe.tailscale.net?token=showcase_pairing',
      'devices': [
        {
          'id': 'dev_iphone16',
          'name': 'iPhone 16 Pro (Stefano)',
          'mode': 'view',
          'lastSeen': 1729606000000,
        },
      ],
      'tailscale': {
        'installed': true,
        'running': true,
        'hostname': 'node-piframe',
        'domain': 'tailnet.ts.net',
      },
    },
  };
}

class _FakeUpdateClient implements UpdateClient {
  @override
  Future<AppRelease?> fetchLatestRelease() async => AppRelease(
    tagName: 'v1.1.0',
    name: 'PiFrame v1.1.0 — 120fps Native Release',
    body: '• Motore grafico Impeller a 120 FPS\n• Integrazione browser web per test live\n• Gestione server MCP e version pinning',
    htmlUrl: 'https://github.com/TrentiStefano/piframe/releases/tag/v1.1.0',
    assets: const [
      ReleaseAsset(
        name: 'PiFrame-Setup-x64.exe',
        downloadUrl: 'https://github.com/...',
        size: 48000000,
        contentType: 'application/octet-stream',
      ),
    ],
  );

  @override
  Stream<DownloadProgress> downloadAsset({
    required ReleaseAsset asset,
    required String destinationPath,
    Future<void>? cancelSignal,
  }) async* {
    yield const DownloadProgress(
      downloadedBytes: 100,
      totalBytes: 100,
      fraction: 1.0,
    );
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    try {
      final uiFont = FontLoader('SchibstedGrotesk')
        ..addFont(rootBundle.load('assets/fonts/SchibstedGrotesk.ttf'));
      await uiFont.load();
      final monoFont = FontLoader('SourceCodePro')
        ..addFont(rootBundle.load('assets/fonts/SourceCodePro.ttf'));
      await monoFont.load();
    } catch (_) {}
  });

  Widget wrapHarness({
    required Widget child,
    bool isDark = true,
    GlobalKey? key,
    List<Override> extraOverrides = const [],
  }) {
    final darkJson = File('assets/themes/piframe-dark.json').readAsStringSync();
    final lightJson = File('assets/themes/piframe-light.json')
        .readAsStringSync();
    final repo = ThemeRepository()
      ..registerThemeJson(darkJson)
      ..registerThemeJson(lightJson)
      ..setActiveTheme(isDark ? 'piframe-dark' : 'piframe-light');

    final client = _MockShowcaseClient();
    final session = SessionState(
      sessionId: 'sess-showcase',
      sessionName: 'PiFrame Native Feature Showcase',
      cwd: 'C:/Projects/pi-frame',
      currentModel: 'claude-3-7-sonnet',
      currentThinkingLevel: 'high',
      contextWindowOverride: 128000,
      sessionStats: const {
        'cost': 0.38,
        'tokens': {'total': 52400},
        'contextUsage': {
          'tokens': 78000,
          'contextWindow': 200000,
          'percent': 39.0,
        },
      },
      extensionStatuses: const {'caveman': 'full', 'ponytail': 'full'},
      agentStatus: AgentStatus.settled,
      entries: const [
        SessionEntry(
          id: 'u1',
          role: 'user',
          timestamp: 1,
          text: 'Ispeziona i file di configurazione e prepara la diff di revisione.',
        ),
        SessionEntry(
          id: 'a1',
          role: 'assistant',
          timestamp: 2,
          thinking: 'Analizzo le dipendenze in lib/app/app_shell.dart e verifico lo stato di staging.',
          text: 'Ho esaminato i file modificati. Puoi aprire direttamente lib/app/app_shell.dart o verificare le modifiche nel pannello Git Changes.',
        ),
      ],
    );

    final notifier = SessionStateNotifier(session.sessionId, client)
      ..state = session;
    final pinnedNotifier = PinnedSessionsNotifier()..state = {'sess-pinned-1'};
    final updateClient = _FakeUpdateClient();
    final updateStorage = MemoryUpdateStorage();

    final tokens = isDark ? FrameTokens.dark : FrameTokens.light;

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
        activeSessionIdProvider.overrideWith((ref) => session.sessionId),
        sessionStateFamily(session.sessionId).overrideWith((ref) => notifier),
        pinnedSessionsProvider.overrideWith((ref) => pinnedNotifier),
        updateClientProvider.overrideWithValue(updateClient),
        updateStorageProvider.overrideWithValue(updateStorage),
        ...extraOverrides,
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: isDark ? Brightness.dark : Brightness.light,
          scaffoldBackgroundColor: tokens.background,
          fontFamily: 'SchibstedGrotesk',
          extensions: [tokens],
        ),
        home: Scaffold(
          backgroundColor: tokens.background,
          body: RepaintBoundary(key: key, child: child),
        ),
      ),
    );
  }

  // 1. FEATURE 01: AGENT QUESTIONS TO USER (MULTI-FRAME RECORDING)
  testWidgets('Capture Feature 01: Agent Questions Dialog', (tester) async {
    const size = Size(900, 600);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final key = GlobalKey();
    final request = {
      'method': 'select',
      'prompt':
          'Quale architettura di caching preferisci per il refactor dei token?',
      'options': [
        '1. In-memory LRU cache con invalidazione TTL (Consigliato)',
        '2. Monotonic SQLite event journal con retention a 7 giorni',
        '3. Connessione remota su Redis tramite bridge IPC',
      ],
      'multiSelect': false,
    };

    await tester.pumpWidget(
      wrapHarness(
        key: key,
        child: Center(
          child: SizedBox(
            width: 720,
            child: ExtensionUiDialog(
              sessionId: 'sess-showcase',
              request: request,
              isCard: false,
            ),
          ),
        ),
      ),
    );

    // Frame 1: Resting state with questions
    await tester.pump(const Duration(milliseconds: 100));
    await _capture(tester, key, 'scratch/showcase_frames/f01_01.png');

    // Frame 2: Select option 1
    final option1 = find.textContaining('LRU cache');
    if (option1.evaluate().isNotEmpty) {
      await tester.tap(option1.first);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _capture(tester, key, 'scratch/showcase_frames/f01_02.png');
    await _capture(
      tester,
      key,
      'website/assets/img/ui/feature-01-agent-questions.png',
    );
  });

  // 2. FEATURE 03: WORK AREA CONTEXT & COMPACTION LIMITS
  testWidgets('Capture Feature 03: Work Area Context Limits', (tester) async {
    const size = Size(800, 650);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final key = GlobalKey();

    await tester.pumpWidget(
      wrapHarness(
        key: key,
        child: Center(
          child: SizedBox(
            width: 720,
            height: 560,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1C2432),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E3C53)),
              ),
              child: const SingleChildScrollView(
                child: ContextPanel(sessionId: 'sess-showcase'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));
    await _capture(
      tester,
      key,
      'website/assets/img/ui/feature-03-workarea-context-limits.png',
    );
  });

  // 3. FEATURE 04: CHAT DRAG AND DROP & ATTACH CHIPS
  testWidgets('Capture Feature 04: File Drag & Drop Target', (tester) async {
    const size = Size(900, 600);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final key = GlobalKey();

    final testAttachments = [
      const ChatAttachment(
        id: 'att_1',
        name: 'app_shell.dart',
        type: AttachmentType.externalFile,
        pathOrUrl: 'lib/app/app_shell.dart',
      ),
      const ChatAttachment(
        id: 'att_2',
        name: 'design_tokens.json',
        type: AttachmentType.externalFile,
        pathOrUrl: 'themes/design_tokens.json',
      ),
    ];

    await tester.pumpWidget(
      wrapHarness(
        key: key,
        child: Center(
          child: SizedBox(
            width: 820,
            height: 520,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1C2432),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E3C53)),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF161C27),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF5F9FC5),
                          width: 2,
                          strokeAlign: BorderSide.strokeAlignInside,
                        ),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.file_download_outlined,
                              size: 48,
                              color: Color(0xFF5F9FC5),
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Rilascia i file qui per allegarli alla chat',
                              style: TextStyle(
                                color: Color(0xFFF8FAFC),
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Supporta immagini, file sorgente Dart/TS e cartelle di progetto',
                              style: TextStyle(
                                color: Color(0xFFA3B2C5),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161C27),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2E3C53)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.attach_file,
                          size: 18,
                          color: Color(0xFF81B2CF),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AttachmentListBar(
                            attachments: testAttachments,
                            onRemove: (_) {},
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 150));
    await _capture(tester, key, 'scratch/showcase_frames/f04_01.png');
    await _capture(
      tester,
      key,
      'website/assets/img/ui/feature-04-file-drag-drop-attach.png',
    );
  });

  // 4. FEATURE 05: REVIEW CHANGES 50/50 SPLIT DIFF
  testWidgets('Capture Feature 05: 50/50 Split Diff Review', (tester) async {
    const size = Size(1200, 750);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final key = GlobalKey();

    const diffText = '''--- a/lib/app/app_shell.dart
+++ b/lib/app/app_shell.dart
@@ -14,8 +14,14 @@
-    final background = Color(0xFF232634); // Legacy Catppuccin
-    final accent = Color(0xFFCA9EE6);
+    // Official PiFrame Dark Theme Normative Tokens
+    final background = FrameTokens.dark.background; // #161c27
+    final chassis = FrameTokens.dark.chassis;       // #121721
+    final accent = FrameTokens.dark.accent;         // #5f9fc5
+    final thinking = FrameTokens.dark.thinking;     // #81b2cf
@@ -40,6 +46,10 @@
-    return Container(child: chatView);
+    return BentoTriptychWorkspace(
+      chat: chatView,
+      diffReview: splitDiffReview,
+      terminal: hardwareTerminal,
+    );
''';

    final changedFile = SessionChangedFile(
      path: 'lib/app/app_shell.dart',
      filename: 'app_shell.dart',
      directory: 'lib/app',
      additions: 14,
      deletions: 3,
      status: 'modified',
      diff: diffText,
    );

    await tester.pumpWidget(
      wrapHarness(
        key: key,
        child: Center(
          child: SizedBox(
            width: 1120,
            height: 660,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1C2432),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E3C53)),
              ),
              child: ReviewFileDiffViewer(
                file: changedFile,
                mode: DiffViewMode.twoColumn,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 150));
    await _capture(tester, key, 'scratch/showcase_frames/f05_01.png');
    await _capture(
      tester,
      key,
      'website/assets/img/ui/feature-05-review-changes-50-50-diff.png',
    );
  });

  // 5. FEATURE 06: GIT CHANGES & STAGING PANE
  testWidgets('Capture Feature 06: Git Changes Desk & Staging', (tester) async {
    const size = Size(500, 750);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final key = GlobalKey();

    await tester.pumpWidget(
      wrapHarness(
        key: key,
        child: Center(
          child: SizedBox(
            width: 440,
            height: 680,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1C2432),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E3C53)),
              ),
              child: const SessionChangesPane(sessionId: 'sess-showcase'),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, key, 'scratch/showcase_frames/f06_01.png');
    await _capture(
      tester,
      key,
      'website/assets/img/ui/feature-06-git-changes-staging.png',
    );
  });

  // 6. FEATURE 07: INTEGRATED WEB BROWSER
  testWidgets('Capture Feature 07: Integrated Web Browser Pane', (
    tester,
  ) async {
    const size = Size(900, 700);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final key = GlobalKey();

    await tester.pumpWidget(
      wrapHarness(
        key: key,
        child: Center(
          child: SizedBox(
            width: 820,
            height: 620,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1C2432),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E3C53)),
              ),
              child: const WebBrowserPane(sessionId: 'sess-showcase'),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, key, 'scratch/showcase_frames/f07_01.png');
    await _capture(
      tester,
      key,
      'website/assets/img/ui/feature-07-web-browser-pane.png',
    );
  });

  // 7. FEATURE 08: REPOSITORY SEARCH & ADD TO CHAT
  testWidgets('Capture Feature 08: Repository Workspace & Add to Chat', (
    tester,
  ) async {
    const size = Size(1000, 750);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final key = GlobalKey();

    await tester.pumpWidget(
      wrapHarness(
        key: key,
        child: Center(
          child: SizedBox(
            width: 920,
            height: 680,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1C2432),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E3C53)),
              ),
              child: const RepositoryPane(sessionId: 'sess-showcase'),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, key, 'scratch/showcase_frames/f08_01.png');
    await _capture(
      tester,
      key,
      'website/assets/img/ui/feature-08-repo-search-add-to-chat.png',
    );
  });

  // 8. FEATURE 09: PANE RESIZE & INTEGRATED TERMINAL
  testWidgets('Capture Feature 09: Integrated Terminal Panel', (tester) async {
    const size = Size(900, 600);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final key = GlobalKey();

    await tester.pumpWidget(
      wrapHarness(
        key: key,
        child: Center(
          child: SizedBox(
            width: 820,
            height: 500,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1C2432),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E3C53)),
              ),
              child: IntegratedTerminalPanel(
                cwd: 'C:/Projects/pi-frame',
                tokens: FrameTokens.dark,
                onCollapseDownward: () {},
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, key, 'scratch/showcase_frames/f09_01.png');
    await _capture(
      tester,
      key,
      'website/assets/img/ui/feature-09-pane-resize-and-terminal.png',
    );
  });

  // 9. FEATURE 10: SESSION RENAMING & PINNING
  testWidgets('Capture Feature 10: Session Renaming & Pinning', (tester) async {
    const size = Size(400, 700);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final key = GlobalKey();

    await tester.pumpWidget(
      wrapHarness(
        key: key,
        child: Center(
          child: SizedBox(
            width: 340,
            height: 640,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1C2432),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E3C53)),
              ),
              child: const SessionsSidebar(),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, key, 'scratch/showcase_frames/f10_01.png');
    await _capture(
      tester,
      key,
      'website/assets/img/ui/feature-10-rename-and-pin-session.png',
    );
  });

  // 10. FEATURE 11: LIGHT MODE SWITCH & PANE CHECKLIST
  testWidgets('Capture Feature 11: Light Mode & Pane Visibility', (
    tester,
  ) async {
    const size = Size(1200, 750);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final key = GlobalKey();

    await tester.pumpWidget(
      wrapHarness(isDark: false, key: key, child: const AppShell()),
    );

    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, key, 'scratch/showcase_frames/f11_01.png');
    await _capture(
      tester,
      key,
      'website/assets/img/ui/feature-11-light-mode-pane-checklist.png',
    );
  });

  // 11. FEATURE 12: IN-APP UPDATE FLOW
  testWidgets('Capture Feature 12: In-App Updates', (tester) async {
    const size = Size(800, 600);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final key = GlobalKey();

    await tester.pumpWidget(
      wrapHarness(
        key: key,
        child: Center(
          child: SizedBox(
            width: 680,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1C2432),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E3C53)),
              ),
              child: const SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StartupUpdateBanner(),
                    SizedBox(height: 16),
                    UpdatesSection(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));
    await _capture(
      tester,
      key,
      'website/assets/img/ui/feature-12-in-app-update-flow.png',
    );
  });

  // 12. FEATURE 14: REMOTE TAILSCALE & PHONE QR
  testWidgets('Capture Feature 14: Remote Tailscale & Phone QR', (
    tester,
  ) async {
    const size = Size(900, 800);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final key = GlobalKey();

    await tester.pumpWidget(
      wrapHarness(
        key: key,
        child: Center(
          child: SizedBox(
            width: 760,
            height: 720,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1C2432),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E3C53)),
              ),
              child: const SingleChildScrollView(child: RemoteSection()),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 300));
    await _capture(
      tester,
      key,
      'website/assets/img/ui/feature-14-tailscale-remote-phone.png',
    );
  });

  // 13. FEATURE 15 & 17: PI CLI SETTINGS & PACKAGES
  testWidgets('Capture Feature 15 & 17: Pi CLI & Packages', (tester) async {
    const size = Size(900, 850);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final key = GlobalKey();

    await tester.pumpWidget(
      wrapHarness(
        key: key,
        child: Center(
          child: SizedBox(
            width: 760,
            height: 760,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1C2432),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E3C53)),
              ),
              child: const SingleChildScrollView(
                child: PiCliSection(tokens: FrameTokens.dark),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));
    await _capture(
      tester,
      key,
      'website/assets/img/ui/feature-15-pi-cli-settings-update.png',
    );
    await _capture(
      tester,
      key,
      'website/assets/img/ui/feature-17-packages-version-pinning.png',
    );
  });

  // 14. FEATURE 18: IN-CHAT FILE JUMP TO OS EXPLORER
  testWidgets('Capture Feature 18: File Mention Click Explorer', (
    tester,
  ) async {
    const size = Size(800, 450);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final key = GlobalKey();

    const textWithLink = '''Ho aggiornato il controller del tema:
• `lib/app/app_shell.dart:45` (Bento Triptych split layout)
• `packages/pi_frame_theme/lib/src/theme_tokens.dart:18` (Normative Dark tokens)

Puoi cliccare direttamente sui file per aprirli nell'Explorer del sistema operativo.''';

    await tester.pumpWidget(
      wrapHarness(
        key: key,
        child: Center(
          child: SizedBox(
            width: 720,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1C2432),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E3C53)),
              ),
              child: const RichContent(
                text: textWithLink,
                cwd: 'C:/Projects/pi-frame',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, key, 'scratch/showcase_frames/f18_01.png');
    await _capture(
      tester,
      key,
      'website/assets/img/ui/feature-18-click-file-open-explorer.png',
    );
  });

  // 15. FEATURE 20: INSTRUCTION FILE DIALOG (AGENTS.MD)
  testWidgets('Capture Feature 20: Instruction File Dialog', (tester) async {
    const size = Size(900, 750);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final key = GlobalKey();

    await tester.pumpWidget(
      wrapHarness(
        key: key,
        child: const Center(
          child: SizedBox(
            width: 780,
            height: 660,
            child: InstructionFileDialog(
              folder: 'C:/Projects/pi-frame',
              sessionId: 'sess-showcase',
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, key, 'scratch/showcase_frames/f20_01.png');
    await _capture(
      tester,
      key,
      'website/assets/img/ui/feature-20-generate-repo-instructions.png',
    );
  });
}
