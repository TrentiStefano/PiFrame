import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pi_frame/app/app_shell.dart';
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

class _ShowcaseClient extends PcpClient {
  _ShowcaseClient() : super(port: 1, token: 'showcase-token');

  @override
  Future<Map<String, dynamic>> listWorkspaceFiles(String sessionId) async => {
    'data': {
      'rootPath': 'C:/Projects/piframe-demo',
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
  Future<Map<String, dynamic>> readWorkspaceFile(String sessionId, String path) async => {
    'data': {
      'rootPath': 'C:/Projects/piframe-demo',
      'path': path,
      'content': '''import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    // Official PiFrame Dark Theme Normative Tokens
    final bg = FrameTokens.dark.background; // #161c27
    final chassis = FrameTokens.dark.chassis; // #121721
    final accent = FrameTokens.dark.accent; // #5f9fc5
    final thinking = FrameTokens.dark.thinking; // #81b2cf

    return Scaffold(
      backgroundColor: bg,
      body: BentoTriptychWorkspace(
        chat: TranscriptView(),
        diffReview: ReviewFileDiffViewer(),
      ),
    );
  }
}
''',
    },
  };

  @override
  Future<Map<String, dynamic>> refreshWorkspace(String sessionId, {String? cwd}) async => {
    'data': {
      'isRepository': true,
      'rootPath': 'C:/Projects/piframe-demo',
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
  Future<Map<String, dynamic>> getWorkspaceDiff(String sessionId, {String? filePath}) async => {
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
  Future<Map<String, dynamic>> listSessions({String? query, int? limit}) async => {
    'data': {
      'sessions': [
        {
          'id': 'sess-showcase',
          'name': 'Refactor Token System & Bento Ergonomics',
          'cwd': 'C:/Projects/piframe-demo',
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

void main() {
  testWidgets('Capture Full App Clip 1 & Clip 2 States in PiFrame Dark', (tester) async {
    const size = Size(1600, 900);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final darkJson = File('assets/themes/piframe-dark.json').readAsStringSync();
    final repo = ThemeRepository()
      ..registerThemeJson(darkJson)
      ..setActiveTheme('piframe-dark');
    addTearDown(repo.dispose);

    final client = _ShowcaseClient();
    final key = GlobalKey();

    // ==========================================
    // CLIP 1: AGENT QUESTIONS IN FULL APPSHELL
    // ==========================================

    final sessionQuestion = SessionState(
      sessionId: 'sess-showcase',
      sessionName: 'Refactor Token System & Bento Ergonomics',
      cwd: 'C:/Projects/piframe-demo',
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
          'requestId': 'req_cache_choice',
          'method': 'select',
          'title': '[Architettura] Quale approccio di caching preferisci?',
          'options': [
            '1. In-memory LRU cache con invalidazione TTL',
            '2. Monotonic SQLite event journal (Consigliato)',
            '3. Redis remote connection su bridge IPC',
          ],
          'multiSelect': false,
        },
      ],
      entries: const [
        SessionEntry(
          id: 'u1',
          role: 'user',
          timestamp: 1,
          text: 'Ispeziona l\'architettura e proponi le opzioni di caching per il refactor.',
        ),
        SessionEntry(
          id: 'a1',
          role: 'assistant',
          timestamp: 2,
          thinking: '1. Valuto i vincoli di persistenza locale.\n2. Preparo le opzioni architetturali per la decisione utente.',
          text: 'Ho preparato le 3 alternative per la gestione del cache state.',
        ),
      ],
    );

    final notifier1 = SessionStateNotifier('sess-showcase', client)..state = sessionQuestion;
    final pinnedNotifier = PinnedSessionsNotifier()..state = {'sess-showcase'};

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themeRepositoryProvider.overrideWithValue(repo),
          daemonEndpointProvider.overrideWith((ref) async => null),
          pcpClientProvider.overrideWithValue(client),
          activeSessionIdProvider.overrideWith((ref) => 'sess-showcase'),
          sessionStateFamily('sess-showcase').overrideWith((ref) => notifier1),
          pinnedSessionsProvider.overrideWith((ref) => pinnedNotifier),
          isReviewingChangesProvider.overrideWith((ref) => false),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: repo.activeTheme.toThemeData(),
          home: Scaffold(
            backgroundColor: const Color(0xFF161C27),
            body: RepaintBoundary(key: key, child: const AppShell()),
          ),
        ),
      ),
    );

    // Frame 1A: Question dialog active in full AppShell (Option 1 initial)
    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, key, 'scratch/full_app_clip1_state1.png');

    // Frame 1B: Tap Option 2 (Monotonic SQLite)
    final opt2Finder = find.textContaining('Monotonic SQLite');
    if (opt2Finder.evaluate().isNotEmpty) {
      await tester.tap(opt2Finder.first);
      await tester.pump(const Duration(milliseconds: 200));
    }
    await _capture(tester, key, 'scratch/full_app_clip1_state2.png');

    // Frame 1C: Question resolved into transcript
    final sessionAnswered = SessionState(
      sessionId: 'sess-showcase',
      sessionName: 'Refactor Token System & Bento Ergonomics',
      cwd: 'C:/Projects/piframe-demo',
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
          text: 'Ispeziona l\'architettura e proponi le opzioni di caching per il refactor.',
        ),
        SessionEntry(
          id: 'a1',
          role: 'assistant',
          timestamp: 2,
          thinking: '1. Valuto i vincoli di persistenza locale.\n2. Preparo le opzioni architetturali per la decisione utente.',
          text: 'Ho preparato le 3 alternative per la gestione del cache state.',
        ),
        SessionEntry(
          id: 'u2',
          role: 'user',
          timestamp: 3,
          text: 'Scelta effettuata: 2. Monotonic SQLite event journal (Consigliato)',
        ),
        SessionEntry(
          id: 'a2',
          role: 'assistant',
          timestamp: 4,
          thinking: 'Configuro il controller SQLite e aggiorno i file di persistenza.',
          text: 'Approccio confermato: procedo con l\'implementazione del Monotonic SQLite journal e delle policy di retention.',
        ),
      ],
    );

    notifier1.state = sessionAnswered;
    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, key, 'scratch/full_app_clip1_state3.png');

    // ==========================================
    // CLIP 2: REVIEW CHANGES IN FULL APPSHELL
    // ==========================================

    final sessionWithModified = sessionAnswered.copyWith(
      sessionStats: {
        'cost': 0.052,
        'tokens': {'total': 28900},
        'contextUsage': {
          'tokens': 44500,
          'contextWindow': 200000,
          'percent': 22.2,
        },
      },
    );

    // Turn ON isReviewingChangesProvider -> right compartment opens Review Changes
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themeRepositoryProvider.overrideWithValue(repo),
          daemonEndpointProvider.overrideWith((ref) async => null),
          pcpClientProvider.overrideWithValue(client),
          activeSessionIdProvider.overrideWith((ref) => 'sess-showcase'),
          sessionStateFamily('sess-showcase').overrideWith((ref) => notifier1..state = sessionWithModified),
          pinnedSessionsProvider.overrideWith((ref) => pinnedNotifier),
          isReviewingChangesProvider.overrideWith((ref) => true),
          diffViewModeProvider.overrideWith((ref) => DiffViewMode.twoColumn),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: repo.activeTheme.toThemeData(),
          home: Scaffold(
            backgroundColor: const Color(0xFF161C27),
            body: RepaintBoundary(key: key, child: const AppShell()),
          ),
        ),
      ),
    );

    // Frame 2B: Full AppShell with Review Changes desk open (collapsed diff)
    await tester.pump(const Duration(milliseconds: 300));
    await _capture(tester, key, 'scratch/full_app_clip2_desk_open.png');

    // Frame 2C: Expand diff on lib/app_shell.dart
    final fileRowFinder = find.textContaining('app_shell.dart');
    if (fileRowFinder.evaluate().isNotEmpty) {
      await tester.tap(fileRowFinder.first);
      await tester.pump(const Duration(milliseconds: 300));
    }
    await _capture(tester, key, 'scratch/full_app_clip2_diff_expanded.png');
  });
}
