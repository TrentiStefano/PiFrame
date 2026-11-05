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
import 'package:pi_frame/features/session_changes/session_changes_provider.dart';
import 'package:pi_frame/features/sessions_sidebar/pinned_sessions_provider.dart';
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
  String relativePath,
) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.runAsync(() async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      _saveScreenshot(byteData.buffer.asUint8List(), relativePath);
    }
    image.dispose();
  });
}

class _PerfectShowcaseClient extends PcpClient {
  _PerfectShowcaseClient() : super(port: 1, token: 'showcase-token');

  @override
  Future<Map<String, dynamic>> listWorkspaceFiles(String sessionId) async => {
    'data': {
      'rootPath': 'C:/Projects/piframe-mock',
      'truncated': false,
      'files': [
        {'path': 'lib/main.dart', 'sizeBytes': 1200},
        {'path': 'lib/app_shell.dart', 'sizeBytes': 5400},
        {'path': 'lib/theme_tokens.dart', 'sizeBytes': 3200},
        {'path': 'README.md', 'sizeBytes': 2800},
      ],
    },
  };

  @override
  Future<Map<String, dynamic>> readWorkspaceFile(
    String sessionId,
    String path,
  ) async => {
    'data': {
      'rootPath': 'C:/Projects/piframe-mock',
      'path': path,
      'content': '''import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final bg = FrameTokens.dark.background;
    return Scaffold(backgroundColor: bg, body: const Text('App'));
  }
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
      'rootPath': 'C:/Projects/piframe-mock',
      'branch': 'main',
      'files': [
        {
          'path': 'lib/app_shell.dart',
          'status': 'modified',
          'staged': false,
          'unstaged': true,
          'additions': 14,
          'deletions': 3,
        },
      ],
      'totalAdditions': 14,
      'totalDeletions': 3,
    },
  };

  @override
  Future<Map<String, dynamic>> getWorkspaceDiff(
    String sessionId, {
    String? filePath,
  }) async => {
    'data': {
      'filePath': filePath ?? 'lib/app_shell.dart',
      'diff': '''--- a/lib/app_shell.dart
+++ b/lib/app_shell.dart
@@ -14,8 +14,14 @@
-    final bg = Color(0xFF232634); // Legacy Catppuccin
-    final accent = Color(0xFFCA9EE6);
+    // Official PiFrame Dark Theme Normative Tokens
+    final bg = FrameTokens.dark.background; // #161c27
+    final chassis = FrameTokens.dark.chassis; // #121721
+    final accent = FrameTokens.dark.accent; // #5f9fc5
+    final thinking = FrameTokens.dark.thinking; // #81b2cf
@@ -32,6 +38,10 @@
-    return Container(child: chatView);
+    return BentoTriptychWorkspace(
+      chat: chatView,
+      diffReview: splitDiffReview,
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
          'id': 'sess-showcase',
          'name': 'Refactor Token System & Bento Ergonomics',
          'cwd': 'C:/Projects/piframe-mock',
          'updatedAt': 1729605000000,
          'model': 'claude-3-7-sonnet',
          'isPinned': true,
          'isActive': true,
        },
      ],
    },
  };

  @override
  Future<List<Map<String, dynamic>>> getSubagents(String sessionId) async => [];
}

const String kOfficialDiffText = '''--- a/lib/app_shell.dart
+++ b/lib/app_shell.dart
@@ -14,8 +14,14 @@
-    final bg = Color(0xFF232634); // Legacy Catppuccin
-    final accent = Color(0xFFCA9EE6);
+    // Official PiFrame Dark Theme Normative Tokens
+    final bg = FrameTokens.dark.background; // #161c27
+    final chassis = FrameTokens.dark.chassis; // #121721
+    final accent = FrameTokens.dark.accent; // #5f9fc5
+    final thinking = FrameTokens.dark.thinking; // #81b2cf
@@ -32,6 +38,10 @@
-    return Container(child: chatView);
+    return BentoTriptychWorkspace(
+      chat: chatView,
+      diffReview: splitDiffReview,
+    );
''';

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
      final headingFont = FontLoader('BarlowCondensed')
        ..addFont(rootBundle.load('assets/fonts/BarlowCondensed-SemiBold.ttf'))
        ..addFont(rootBundle.load('assets/fonts/BarlowCondensed-Bold.ttf'));
      await headingFont.load();
      final iconsFont = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await iconsFont.load();
    } catch (_) {}
  });

  testWidgets(
    'Render Perfect Showcase Frames for Clip 1 and Clip 2 in 1920x1080',
    (tester) async {
      const size = Size(1920, 1080);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      final darkJson = File('assets/themes/piframe-dark.json')
          .readAsStringSync();
      final repo = ThemeRepository()
        ..registerThemeJson(darkJson)
        ..setActiveTheme('piframe-dark');
      addTearDown(repo.dispose);

      final client = _PerfectShowcaseClient();
      final key = GlobalKey();

      // 1. CLIP 1 SESSION STATE (Question Dialog Active)
      final sessionQuestion = SessionState(
        sessionId: 'sess-showcase',
        sessionName: 'Refactor Token System & Bento Ergonomics',
        cwd: 'C:/Projects/piframe-mock',
        currentModel: 'claude-3-7-sonnet',
        currentThinkingLevel: 'high',
        contextWindowOverride: 128000,
        sessionStats: const {
          'cost': 0.042,
          'tokens': {'total': 24800},
          'contextUsage': {
            'tokens': 38200,
            'contextWindow': 200000,
            'percent': 19.1,
          },
        },
        extensionStatuses: const {'caveman': 'full', 'ponytail': 'full'},
        agentStatus: AgentStatus.awaitingUser,
        pendingUiRequests: const [
          {
            'requestId': 'req_lib_choice',
            'method': 'select',
            'title': '[Libreria] Quale libreria preferisci utilizzare?',
            'options': [
              '1. Axios — Leggero e performante',
              '2. Native Fetch — Standard browser, zero dipendenze',
              '3. TanStack Query — Query hook e caching automatico',
              '4. Type something.',
            ],
            'multiSelect': false,
          },
        ],
        entries: const [
          SessionEntry(
            id: 'u1',
            role: 'user',
            timestamp: 1,
            text: 'chiedi all utente con ask_user_question quale libreria preferisce',
          ),
          SessionEntry(
            id: 'a1',
            role: 'assistant',
            timestamp: 2,
            thinking: '1. Valuto i vincoli di progetto (zero dipendenze esterne).\n2. Formulo il questionario decisionale con le opzioni disponibili.',
            text:
                'Ho preparato le opzioni per la selezione della libreria HTTP.',
          ),
        ],
      );

      final sessionNotifier = SessionStateNotifier('sess-showcase', client)
        ..state = sessionQuestion;
      final pinnedNotifier = PinnedSessionsNotifier()
        ..state = {'sess-showcase'};

      final changesWithFile = SessionChangesState(
        isLoading: false,
        files: const [
          SessionChangedFile(
            path: 'lib/app_shell.dart',
            filename: 'app_shell.dart',
            directory: 'lib',
            additions: 14,
            deletions: 3,
            status: 'modified',
            diff: kOfficialDiffText,
          ),
        ],
        totalAdditions: 14,
        totalDeletions: 3,
      );

      Widget buildApp({
        required bool isReviewing,
        Set<String> expandedFiles = const {},
      }) {
        return ProviderScope(
          overrides: [
            themeRepositoryProvider.overrideWithValue(repo),
            daemonEndpointProvider.overrideWith((ref) async => null),
            pcpClientProvider.overrideWithValue(client),
            connectionStateProvider.overrideWith(
              (ref) => Stream.value(DaemonConnectionState.connected),
            ),
            desktopChromeProvider.overrideWithValue(false),
            desktopWindowLifecycleProvider.overrideWithValue(false),
            activeSessionIdProvider.overrideWith((ref) => 'sess-showcase'),
            sessionStateFamily('sess-showcase')
                .overrideWith((ref) => sessionNotifier),
            pinnedSessionsProvider.overrideWith((ref) => pinnedNotifier),
            isReviewingChangesProvider.overrideWith((ref) => isReviewing),
            diffViewModeProvider.overrideWith((ref) => DiffViewMode.twoColumn),
            sessionChangesProvider('sess-showcase').overrideWith(
              (ref) =>
                  SessionChangesNotifier(ref, 'sess-showcase')
                    ..state = changesWithFile,
            ),
            expandedReviewFilesProvider('sess-showcase')
                .overrideWith((ref) => expandedFiles),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: repo.activeTheme.toThemeData(),
            home: Scaffold(
              backgroundColor: const Color(0xFF161C27),
              body: RepaintBoundary(key: key, child: const AppShell()),
            ),
          ),
        );
      }

      // 1A. Capture Clip 1 State A (Option 1 checked initial)
      await tester.pumpWidget(buildApp(isReviewing: false));
      await tester.pump(const Duration(milliseconds: 250));
      await _capture(tester, key, 'scratch/real_full_c1_stateA.png');

      // 1B. Tap Option 2 (Native Fetch) -> State B
      final opt2 = find.textContaining('Native Fetch');
      if (opt2.evaluate().isNotEmpty) {
        await tester.tap(opt2.first);
        await tester.pump(const Duration(milliseconds: 200));
      }
      await _capture(tester, key, 'scratch/real_full_c1_stateB.png');

      // 1C. State C: Answered in transcript
      final sessionAnswered = SessionState(
        sessionId: 'sess-showcase',
        sessionName: 'Refactor Token System & Bento Ergonomics',
        cwd: 'C:/Projects/piframe-mock',
        currentModel: 'claude-3-7-sonnet',
        currentThinkingLevel: 'high',
        contextWindowOverride: 128000,
        sessionStats: const {
          'cost': 0.048,
          'tokens': {'total': 26400},
          'contextUsage': {
            'tokens': 41200,
            'contextWindow': 200000,
            'percent': 20.6,
          },
        },
        extensionStatuses: const {'caveman': 'full', 'ponytail': 'full'},
        agentStatus: AgentStatus.settled,
        entries: const [
          SessionEntry(
            id: 'u1',
            role: 'user',
            timestamp: 1,
            text: 'chiedi all utente con ask_user_question quale libreria preferisce',
          ),
          SessionEntry(
            id: 'a1',
            role: 'assistant',
            timestamp: 2,
            thinking: '1. Valuto i vincoli di progetto.\n2. Formulo il questionario decisionale.',
            text:
                'Ho preparato le opzioni per la selezione della libreria HTTP.',
          ),
          SessionEntry(
            id: 'u2',
            role: 'user',
            timestamp: 3,
            text: 'Scelta effettuata: 2. Native Fetch — Standard browser, zero dipendenze',
          ),
          SessionEntry(
            id: 'a2',
            role: 'assistant',
            timestamp: 4,
            thinking: 'Configuro il client HTTP con Native Fetch per garantire zero dipendenze esterne.',
            text: 'Utente selezionato: Native Fetch.\nNessun pacchetto npm aggiuntivo; procedo con l\'implementazione nativa.',
          ),
        ],
      );

      sessionNotifier.state = sessionAnswered;
      await tester.pump(const Duration(milliseconds: 250));
      await _capture(tester, key, 'scratch/real_full_c1_stateC.png');

      // ==========================================
      // CAPTURE CLIP 2: REVIEW CHANGES & 50/50 DIFF
      // ==========================================

      // State 2A: Full App with Review Changes desk open (collapsed file row)
      await tester.pumpWidget(buildApp(isReviewing: true, expandedFiles: {}));
      await tester.pump(const Duration(milliseconds: 250));
      await _capture(tester, key, 'scratch/real_full_c2_desk_open.png');

      // State 2B: Expanded 50/50 split diff on lib/app_shell.dart
      await tester.pumpWidget(
        buildApp(isReviewing: true, expandedFiles: {'lib/app_shell.dart'}),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await _capture(tester, key, 'scratch/real_full_c2_diff_expanded.png');

      // Drain timers cleanly
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));
    },
  );
}
