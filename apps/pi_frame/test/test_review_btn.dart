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

class _Client extends PcpClient {
  _Client() : super(port: 1, token: 'token');

  @override
  Future<Map<String, dynamic>> listWorkspaceFiles(String sessionId) async => {
    'data': {
      'rootPath': 'C:/Projects/piframe-mock',
      'truncated': false,
      'files': [
        {'path': 'lib/app_shell.dart', 'sizeBytes': 5400},
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
      'content': 'code',
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
      'filePath': 'lib/app_shell.dart',
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
          'id': 'sess-1',
          'name': 'Refactor Token System',
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
      final iconsFont = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await iconsFont.load();
    } catch (_) {}
  });

  testWidgets('Test Tapping review-changes-btn', (tester) async {
    const size = Size(1920, 1080);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final darkJson = File('assets/themes/piframe-dark.json').readAsStringSync();
    final repo = ThemeRepository()
      ..registerThemeJson(darkJson)
      ..setActiveTheme('piframe-dark');
    addTearDown(repo.dispose);

    final client = _Client();
    final key = GlobalKey();

    final session = SessionState(
      sessionId: 'sess-1',
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
          text: 'Esegui il refactor dei token.',
        ),
      ],
    );

    final notifier = SessionStateNotifier('sess-1', client)..state = session;
    final pinnedNotifier = PinnedSessionsNotifier()..state = {'sess-1'};

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themeRepositoryProvider.overrideWithValue(repo),
          daemonEndpointProvider.overrideWith((ref) async => null),
          pcpClientProvider.overrideWithValue(client),
          connectionStateProvider.overrideWith(
            (ref) => Stream.value(DaemonConnectionState.connected),
          ),
          desktopChromeProvider.overrideWithValue(false),
          desktopWindowLifecycleProvider.overrideWithValue(false),
          activeSessionIdProvider.overrideWith((ref) => 'sess-1'),
          sessionStateFamily('sess-1').overrideWith((ref) => notifier),
          pinnedSessionsProvider.overrideWith((ref) => pinnedNotifier),
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

    await tester.pump(const Duration(milliseconds: 300));

    // Tap review-changes-btn
    final btn = find.byKey(const ValueKey('review-changes-btn'));
    expect(btn, findsOneWidget);
    await tester.tap(btn);
    await tester.pump(const Duration(milliseconds: 300));

    // Capture screen after tapping review-changes-btn
    await tester.runAsync(() async {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final img = await boundary.toImage(pixelRatio: 1.0);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        if (bytes != null) {
          File('../../scratch/real_review_btn_tapped.png')
              .writeAsBytesSync(bytes.buffer.asUint8List());
        }
      }
    });

    // Expand the file diff
    final fileRow = find.byKey(
      const ValueKey('review-file-lib/app_shell.dart'),
    );
    expect(fileRow, findsOneWidget);
    await tester.tap(fileRow);
    await tester.pump(const Duration(milliseconds: 300));

    // Capture screen after expanding diff!
    await tester.runAsync(() async {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final img = await boundary.toImage(pixelRatio: 1.0);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        if (bytes != null) {
          File('../../scratch/real_diff_50_50_expanded.png')
              .writeAsBytesSync(bytes.buffer.asUint8List());
        }
      }
    });

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
