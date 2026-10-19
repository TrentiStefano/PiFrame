import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_crust/app/app_shell.dart';
import 'package:pi_crust/data/daemon/daemon_providers.dart';
import 'package:pi_crust/data/daemon/pcp_client.dart';
import 'package:pi_crust/data/theme/theme_providers.dart';
import 'package:pi_crust/domain/session/agent_status.dart';
import 'package:pi_crust/domain/session/session_state.dart';
import 'package:pi_crust/features/command_palette/command_palette.dart';
import 'package:pi_crust/features/composer/composer.dart';
import 'package:pi_crust/features/session_tree/session_tree_dialog.dart';
import 'package:pi_crust/features/tool_timeline/tool_card.dart';
import 'package:pi_crust/features/transcript/thinking_block.dart';
import 'package:pi_crust/features/workspace/repository_workspace.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

final Map<String, int> _frameCounters = {};

Directory _resolveScenarioDir(String scenario, {bool clean = false}) {
  Directory root;
  if (Directory('scratch').existsSync()) {
    root = Directory('scratch/real_frames/$scenario');
  } else if (Directory('../../scratch').existsSync()) {
    root = Directory('../../scratch/real_frames/$scenario');
  } else if (Directory('../scratch').existsSync()) {
    root = Directory('../scratch/real_frames/$scenario');
  } else {
    root = Directory('../../scratch/real_frames/$scenario');
  }
  if (!root.existsSync()) {
    root.createSync(recursive: true);
  } else if (clean) {
    for (final f in root.listSync()) {
      if (f is File && f.path.endsWith('.png')) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
  }
  return root;
}

// ---------------------------------------------------------------------------
// Easing helpers – cubic-bezier approximations matching CSS ease-in-out.
// t ∈ [0,1] → eased t ∈ [0,1].
// ---------------------------------------------------------------------------
double _easeInOutCubic(double t) {
  // Attempt to match Recordly's cubic-bezier(0.25, 1, 0.5, 1) feel.
  // Smoothstep³ provides a pleasant glide that decelerates near the end.
  return t < 0.5
      ? 4.0 * t * t * t
      : 1.0 - math.pow(-2.0 * t + 2.0, 3) / 2.0;
}


class ShowcaseController extends ChangeNotifier {
  double zoomScale = 1.0;
  Alignment zoomAlignment = Alignment.center;
  Offset? cursorPosition;
  bool cursorClicking = false;
  String? activeToast;

  void setZoom({double scale = 1.0, Alignment alignment = Alignment.center}) {
    zoomScale = scale;
    zoomAlignment = alignment;
    notifyListeners();
  }

  void setCursor(Offset? pos, {bool clicking = false}) {
    cursorPosition = pos;
    cursorClicking = clicking;
    notifyListeners();
  }

  void setToast(String? toast) {
    activeToast = toast;
    notifyListeners();
  }
}

/// Records [frameCount] frames of the current stage, optionally animating:
///   • cursor from its current position to [targetCursor]
///   • zoom from current scale/alignment to [targetZoomScale]/[targetZoomAlignment]
///
/// All interpolation uses ease-in-out-cubic for fluid, non-linear motion.
/// [step] should be ~33 ms for 30 fps playback.
Future<void> _recordFrames(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String scenario,
  int frameCount, {
  Duration step = const Duration(milliseconds: 33), // ≈ 30 fps
  Offset? targetCursor,
  bool clickAtEnd = false,
  ShowcaseController? controller,
  // Optional zoom animation targets (smooth animated zoom during segment)
  double? targetZoomScale,
  Alignment? targetZoomAlignment,
}) async {
  final outDir = _resolveScenarioDir(scenario);
  _frameCounters.putIfAbsent(scenario, () => 0);

  final startCursor = controller?.cursorPosition ?? targetCursor;
  final startZoomScale = controller?.zoomScale ?? 1.0;
  final startZoomAlignment = controller?.zoomAlignment ?? Alignment.center;
  final endZoomScale = targetZoomScale ?? startZoomScale;
  final endZoomAlignment = targetZoomAlignment ?? startZoomAlignment;

  for (var i = 0; i < frameCount; i++) {
    final rawT = frameCount > 1 ? (i + 1) / frameCount : 1.0;
    final easedT = _easeInOutCubic(rawT);

    // Animate cursor position with eased interpolation
    if (controller != null && targetCursor != null && startCursor != null) {
      final curX = ui.lerpDouble(startCursor.dx, targetCursor.dx, easedT)!;
      final curY = ui.lerpDouble(startCursor.dy, targetCursor.dy, easedT)!;
      // Click ripple shows during the last 6 frames for a smooth pulse
      final isClicking = clickAtEnd && (i >= frameCount - 6);
      controller.setCursor(Offset(curX, curY), clicking: isClicking);
    }

    // Animate zoom scale and alignment with eased interpolation
    if (controller != null &&
        (targetZoomScale != null || targetZoomAlignment != null)) {
      final s = ui.lerpDouble(startZoomScale, endZoomScale, easedT)!;
      final ax = ui.lerpDouble(
        startZoomAlignment.x,
        endZoomAlignment.x,
        easedT,
      )!;
      final ay = ui.lerpDouble(
        startZoomAlignment.y,
        endZoomAlignment.y,
        easedT,
      )!;
      controller.setZoom(scale: s, alignment: Alignment(ax, ay));
    }

    await tester.pump(step);
    await tester.runAsync(() async {
      final boundary = boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final pad = _frameCounters[scenario]!.toString().padLeft(5, '0');
        File('${outDir.path}/frame_$pad.png')
            .writeAsBytesSync(byteData.buffer.asUint8List());
        _frameCounters[scenario] = _frameCounters[scenario]! + 1;
      }
      image.dispose();
    });
  }
}

/// Convenience: record a hold/dwell segment (no cursor or zoom change, just
/// time passing so the UI feels alive rather than frozen).
Future<void> _recordDwell(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String scenario,
  int frameCount, {
  ShowcaseController? controller,
}) async {
  await _recordFrames(
    tester,
    boundaryKey,
    scenario,
    frameCount,
    controller: controller,
  );
}

class _VisualWorkspaceClient extends PcpClient {
  _VisualWorkspaceClient() : super(port: 1, token: 'fixture');

  @override
  Future<Map<String, dynamic>> listWorkspaceFiles(String sessionId) async => {
    'data': {
      'rootPath': 'C:/Projects/pi-crust',
      'truncated': false,
      'files': [
        {'path': 'apps/pi_crust/lib/app/app_shell.dart', 'sizeBytes': 4800},
        {
          'path':
              'apps/pi_crust/lib/features/workspace/repository_workspace.dart',
          'sizeBytes': 7200,
        },
        {
          'path': 'apps/pi_crust/lib/ui/code/code_editor_controller.dart',
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
      'rootPath': 'C:/Projects/pi-crust',
      'path': path,
      'content': '''import 'package:flutter/material.dart';
import 'package:pi_crust/ui/precision.dart';

/// Pi-Crust Bento Triptych AppShell with CrustMark 3D icon
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Row(
        children: [
          CrustMark(size: 28),
          Text('Pi-Crust Workspace'),
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
      'rootPath': 'C:/Projects/pi-crust',
      'branch': 'UI_improvements',
      'files': [
        {
          'path': 'apps/pi_crust/lib/app/app_shell.dart',
          'status': 'modified',
          'staged': false,
          'unstaged': true,
          'additions': 14,
          'deletions': 3,
        },
        {
          'path': 'apps/pi_crust/lib/ui/code/code_editor_controller.dart',
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
      'filePath': filePath ?? 'apps/pi_crust/lib/app/app_shell.dart',
      'diff': '''--- a/apps/pi_crust/lib/ui/precision.dart
+++ b/apps/pi_crust/lib/ui/precision.dart
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

  @override
  Future<Map<String, dynamic>> getAvailableModels(String sessionId) async => {
    'data': [
      {'id': 'claude-3-7-sonnet', 'name': 'Claude 3.7 Sonnet'},
      {'id': 'gpt-4o', 'name': 'GPT-4o'},
      {'id': 'gemini-2-flash', 'name': 'Gemini 2.0 Flash'},
    ],
  };

  @override
  Future<Map<String, dynamic>> getAvailableThinkingLevels(String sessionId) async => {
    'data': ['off', 'low', 'medium', 'high'],
  };

  @override
  Future<Map<String, dynamic>> getSessionTree(String sessionId) async => {
    'data': {
      'tree': [
        {
          'id': 'root-user-1',
          'role': 'user',
          'summary': 'Voglio visualizzare i file con syntax highlighting e Ctrl+F',
          'isLeaf': false,
          'isActive': true,
        },
        {
          'id': 'root-assistant-1',
          'role': 'assistant',
          'summary': 'Ho implementato il controller con syntax highlighting',
          'isLeaf': false,
          'isActive': true,
        },
        {
          'id': 'fork-node-2',
          'role': 'fork',
          'summary': 'Ramo alternativo: Prova con LSP integrato',
          'isLeaf': true,
          'isActive': false,
        },
      ],
    },
  };
}

class RecordlyCanvas extends StatelessWidget {
  final Widget child;
  final ShowcaseController controller;

  const RecordlyCanvas({
    super.key,
    required this.child,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          width: 1920,
          height: 1080,
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.0, -0.2),
              radius: 1.15,
              colors: [
                Color(0xFF292C3C), // Catppuccin Frappé chassis
                Color(0xFF1E2030), // Deep tone
                Color(0xFF181926), // Dark edge
              ],
            ),
          ),
          child: Stack(
            children: [
              // Centered Application Window Frame
              Center(
                child: Transform.scale(
                  scale: controller.zoomScale,
                  alignment: controller.zoomAlignment,
                  child: Container(
                    width: 1680,
                    height: 980,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0x33B4BEFE),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.55),
                          blurRadius: 48,
                          spreadRadius: 2,
                          offset: const Offset(0, 24),
                        ),
                        BoxShadow(
                          color: const Color(0xFF8CAAEE).withOpacity(0.08),
                          blurRadius: 80,
                          spreadRadius: -10,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        // Recordly Desktop Window Chrome Titlebar
                        Container(
                          height: 36,
                          color: const Color(0xFF232634),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFED8796),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFE5C890),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFA6D189),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 18),
                              const Expanded(
                                child: Center(
                                  child: Text(
                                    'Pi-Crust — Bento Triptych Workspace',
                                    style: TextStyle(
                                      color: Color(0xFF838BA7),
                                      fontSize: 13,
                                      fontFamily: 'BarlowCondensed',
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 60),
                            ],
                          ),
                        ),
                        // The Actual Flutter Application
                        Expanded(child: child),
                      ],
                    ),
                  ),
                ),
              ),
              // Recordly Notification Toast
              if (controller.activeToast != null)
                Positioned(
                  top: 36,
                  right: 48,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF303446).withOpacity(0.96),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF8CAAEE).withOpacity(0.4),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          color: Color(0xFFA6D189),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          controller.activeToast!,
                          style: const TextStyle(
                            color: Color(0xFFC6D0F5),
                            fontSize: 13,
                            fontFamily: 'SchibstedGrotesk',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Recordly Virtual Mouse Cursor
              if (controller.cursorPosition != null)
                Positioned(
                  left: controller.cursorPosition!.dx,
                  top: controller.cursorPosition!.dy,
                  child: _RecordlyCursor(isClicking: controller.cursorClicking),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RecordlyCursor extends StatelessWidget {
  final bool isClicking;

  const _RecordlyCursor({required this.isClicking});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (isClicking)
          Positioned(
            left: -14,
            top: -14,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF8CAAEE), width: 3),
              ),
            ),
          ),
        CustomPaint(
          size: const Size(22, 28),
          painter: _CursorPainter(),
        ),
      ],
    );
  }
}

class _CursorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, 22)
      ..lineTo(5.5, 17)
      ..lineTo(10, 26)
      ..lineTo(14, 24)
      ..lineTo(9.5, 15)
      ..lineTo(16, 15)
      ..close();

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawPath(path.shift(const Offset(1, 2)), shadowPaint);

    final fillPaint = Paint()
      ..color = const Color(0xFFC6D0F5)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final strokePaint = Paint()
      ..color = const Color(0xFF1E1E2E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

  testWidgets('Record live running Flutter application with Recordly aesthetics', (
    tester,
  ) async {
    const size = Size(1920, 1080);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final darkThemeJson = File('assets/themes/crust-dark.json').readAsStringSync();
    final lightThemeJson = File('assets/themes/crust-light.json').readAsStringSync();
    final repo = ThemeRepository()
      ..registerThemeJson(darkThemeJson)
      ..registerThemeJson(lightThemeJson)
      ..setActiveTheme('crust-dark');
    addTearDown(repo.dispose);

    final client = _VisualWorkspaceClient();
    final boundaryKey = GlobalKey();
    final controller = ShowcaseController();

    var currentSession = SessionState(
      sessionId: 'demo-live-session',
      sessionName: 'Aggiungere syntax highlighting e Ctrl+F search',
      cwd: 'C:/Projects/pi-crust',
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
                home: RecordlyCanvas(
                  controller: controller,
                  child: const AppShell(),
                ),
              );
            },
          ),
        ),
      ),
    );

    // Warm-up GPU texture cache — pump enough frames for all widgets to settle
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 33));
      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final img = await boundary.toImage(pixelRatio: 1.0);
          img.dispose();
        }
      });
    }

    // =================================================================
    // CLIP 1: Bento Triptych Workspace (3 co-visible areas)
    //  - Full overview, no zoom — show the ergonomic Bento layout.
    //  - 90 frames @ 30fps = 3s → smooth gentle cursor glide
    // =================================================================
    _resolveScenarioDir('bento', clean: true);
    controller.setZoom(scale: 1.0, alignment: Alignment.center);
    controller.setCursor(const Offset(200, 300));
    // Gentle drift across workspace: left panel → center → right panel
    await _recordFrames(
      tester,
      boundaryKey,
      'bento',
      45,
      targetCursor: const Offset(840, 400),
      controller: controller,
    );
    // Continue drifting right toward Git Changes pane
    await _recordFrames(
      tester,
      boundaryKey,
      'bento',
      45,
      targetCursor: const Offset(1500, 350),
      controller: controller,
    );
    // Dwell at rest so the viewer absorbs the layout
    await _recordDwell(tester, boundaryKey, 'bento', 30, controller: controller);

    // =================================================================
    // CLIP: Command Palette (Ctrl+K Quick Actions)
    // =================================================================
    _resolveScenarioDir('palette', clean: true);
    controller.setZoom(scale: 1.0, alignment: Alignment.center);
    final comandiBtn = find.text('Comandi');
    if (comandiBtn.evaluate().isNotEmpty) {
      await _recordFrames(
        tester,
        boundaryKey,
        'palette',
        20,
        controller: controller,
        targetZoomScale: 1.06,
        targetZoomAlignment: const Alignment(0.40, -0.80),
      );
      await _recordFrames(
        tester,
        boundaryKey,
        'palette',
        24,
        targetCursor: tester.getCenter(comandiBtn.first),
        clickAtEnd: true,
        controller: controller,
      );
      await tester.tap(comandiBtn.first, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      await _recordFrames(
        tester,
        boundaryKey,
        'palette',
        20,
        controller: controller,
        targetZoomScale: 1.04,
        targetZoomAlignment: Alignment.center,
      );

      final paletteInput = find.byType(TextField);
      if (paletteInput.evaluate().isNotEmpty) {
        await tester.enterText(paletteInput.first, 'git');
        await tester.pump();
        await _recordFrames(
          tester,
          boundaryKey,
          'palette',
          24,
          targetCursor: tester.getCenter(paletteInput.first),
          controller: controller,
        );
      }
      await _recordDwell(tester, boundaryKey, 'palette', 30, controller: controller);

      final closeFinder = find.byType(CommandPalette);
      if (closeFinder.evaluate().isNotEmpty) {
        Navigator.of(tester.element(closeFinder.first)).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      }
    } else {
      await _recordDwell(tester, boundaryKey, 'palette', 60, controller: controller);
    }
    await _recordFrames(
      tester,
      boundaryKey,
      'palette',
      18,
      controller: controller,
      targetZoomScale: 1.0,
      targetZoomAlignment: Alignment.center,
    );

    // =================================================================
    // CLIP 2: In-File Code Search & Syntax Highlighting
    //  - Zoom gently into the repository pane to see code + search overlay.
    //  - Reduced zoom (1.22x) and centered alignment to avoid clipping.
    // =================================================================
    _resolveScenarioDir('search', clean: true);
    final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final repoNotifier = container.read(repositoryStateProvider(currentSession.sessionId).notifier);
    await repoNotifier.loadFiles();
    await repoNotifier.selectFile('apps/pi_crust/lib/app/app_shell.dart');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Start at full view and animate zoom IN over 30 frames
    controller.setZoom(scale: 1.0, alignment: Alignment.center);
    controller.setCursor(const Offset(520, 300));
    await _recordFrames(
      tester,
      boundaryKey,
      'search',
      30,
      targetCursor: const Offset(480, 260),
      controller: controller,
      targetZoomScale: 1.22,
      targetZoomAlignment: const Alignment(-0.35, -0.15),
    );

    // Tap search button
    final searchButton = find.byKey(const ValueKey('repository-editor-search-btn'));
    if (searchButton.evaluate().isNotEmpty) {
      // Glide cursor toward search button and click
      await _recordFrames(
        tester,
        boundaryKey,
        'search',
        24,
        targetCursor: tester.getCenter(searchButton.first),
        clickAtEnd: true,
        controller: controller,
      );
      await tester.tap(searchButton.first, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Enter search query — dwell on input field while text appears
      final searchInput = find.byKey(const ValueKey('repository-file-search-field'));
      if (searchInput.evaluate().isNotEmpty) {
        await tester.enterText(searchInput, 'CrustMark');
        await _recordFrames(
          tester,
          boundaryKey,
          'search',
          36,
          targetCursor: tester.getCenter(searchInput.first),
          controller: controller,
        );

        // Cycle next match
        final nextBtn = find.byKey(const ValueKey('repository-file-search-next'));
        if (nextBtn.evaluate().isNotEmpty) {
          await _recordFrames(
            tester,
            boundaryKey,
            'search',
            24,
            targetCursor: tester.getCenter(nextBtn.first),
            clickAtEnd: true,
            controller: controller,
          );
          await tester.tap(nextBtn, warnIfMissed: false);
          // Hold a beat so the match highlight registers visually
          await _recordDwell(tester, boundaryKey, 'search', 24, controller: controller);
        }
      }
    }
    // Zoom back out smoothly
    await _recordFrames(
      tester,
      boundaryKey,
      'search',
      20,
      controller: controller,
      targetZoomScale: 1.0,
      targetZoomAlignment: Alignment.center,
    );

    // =================================================================
    // CLIP 3: In-Flight Steer Queue Editing
    //  - Gentle zoom into the composer area at the bottom.
    // =================================================================
    _resolveScenarioDir('steer', clean: true);
    controller.setZoom(scale: 1.0, alignment: Alignment.center);
    // Smooth zoom into composer zone
    await _recordFrames(
      tester,
      boundaryKey,
      'steer',
      24,
      controller: controller,
      targetZoomScale: 1.10,
      targetZoomAlignment: const Alignment(0.0, 0.12),
    );

    // Tap composer to expand
    final composerMinBar = find.byKey(const ValueKey('composer-minimized-bar'));
    final composerBox = find.byType(Composer);
    final targetToTap = composerMinBar.evaluate().isNotEmpty ? composerMinBar.first : composerBox.first;
    await tester.tap(targetToTap, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final editSteerBtn = find.byKey(const ValueKey('edit-steer-btn-0'));
    if (editSteerBtn.evaluate().isNotEmpty) {
      // Glide to the edit button
      await _recordFrames(
        tester,
        boundaryKey,
        'steer',
        30,
        targetCursor: tester.getCenter(editSteerBtn.first),
        clickAtEnd: true,
        controller: controller,
      );
      await tester.tap(editSteerBtn.first, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Edit text in modal dialog
      final dialogField = find.byKey(const ValueKey('edit-steer-dialog-field'));
      if (dialogField.evaluate().isNotEmpty) {
        await tester.enterText(
          dialogField.first,
          'Verifica che Ctrl+F supporti il cycling rapido avanti/indietro',
        );
        // Dwell on the edited text
        await _recordFrames(
          tester,
          boundaryKey,
          'steer',
          36,
          targetCursor: tester.getCenter(dialogField.first),
          controller: controller,
        );

        final saveBtn = find.byKey(const ValueKey('edit-steer-dialog-save'));
        if (saveBtn.evaluate().isNotEmpty) {
          await _recordFrames(
            tester,
            boundaryKey,
            'steer',
            24,
            targetCursor: tester.getCenter(saveBtn.first),
            clickAtEnd: true,
            controller: controller,
          );
          await tester.tap(saveBtn.first, warnIfMissed: false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          // Result dwell
          await _recordDwell(tester, boundaryKey, 'steer', 20, controller: controller);
        }
      }
    } else {
      // Record graceful frames of the composer area
      await _recordDwell(tester, boundaryKey, 'steer', 60, controller: controller);
    }
    // Zoom back out
    await _recordFrames(
      tester,
      boundaryKey,
      'steer',
      18,
      controller: controller,
      targetZoomScale: 1.0,
      targetZoomAlignment: Alignment.center,
    );

    // =================================================================
    // CLIP: Context Window & Cost Analytics (ContextPanel)
    // =================================================================
    _resolveScenarioDir('context', clean: true);
    controller.setZoom(scale: 1.0, alignment: Alignment.center);
    final tuneBtn = find.byTooltip('Modello e azioni sessione');
    if (tuneBtn.evaluate().isNotEmpty) {
      await _recordFrames(
        tester,
        boundaryKey,
        'context',
        20,
        controller: controller,
        targetZoomScale: 1.08,
        targetZoomAlignment: const Alignment(0.55, -0.60),
      );
      await _recordFrames(
        tester,
        boundaryKey,
        'context',
        24,
        targetCursor: tester.getCenter(tuneBtn.first),
        clickAtEnd: true,
        controller: controller,
      );
      await tester.tap(tuneBtn.first, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await _recordFrames(
        tester,
        boundaryKey,
        'context',
        24,
        controller: controller,
        targetZoomScale: 1.12,
        targetZoomAlignment: const Alignment(0.50, 0.0),
      );
      await _recordDwell(tester, boundaryKey, 'context', 45, controller: controller);

      final closeDrawer = find.byTooltip('Chiudi workspace');
      if (closeDrawer.evaluate().isNotEmpty) {
        await tester.tap(closeDrawer.first, warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
      }
    } else {
      await _recordDwell(tester, boundaryKey, 'context', 60, controller: controller);
    }
    await _recordFrames(
      tester,
      boundaryKey,
      'context',
      18,
      controller: controller,
      targetZoomScale: 1.0,
      targetZoomAlignment: Alignment.center,
    );

    // =================================================================
    // CLIP 4: Collapsible Deep Reasoning Streams
    //  - Zoom into the chat transcript area showing the thinking block.
    // =================================================================
    _resolveScenarioDir('reasoning', clean: true);
    controller.setZoom(scale: 1.0, alignment: Alignment.center);
    // Animate zoom into transcript area
    await _recordFrames(
      tester,
      boundaryKey,
      'reasoning',
      24,
      controller: controller,
      targetZoomScale: 1.20,
      targetZoomAlignment: const Alignment(0.10, -0.10),
    );
    final thinkingWidget = find.byType(ThinkingBlock);
    if (thinkingWidget.evaluate().isNotEmpty) {
      // Glide to thinking block and tap to collapse
      await _recordFrames(
        tester,
        boundaryKey,
        'reasoning',
        30,
        targetCursor: tester.getCenter(thinkingWidget.first),
        clickAtEnd: true,
        controller: controller,
      );
      await tester.tap(thinkingWidget.first, warnIfMissed: false);
      await tester.pump();
      // Dwell so the collapsed state is visible
      await _recordDwell(tester, boundaryKey, 'reasoning', 30, controller: controller);

      // Re-expand by tapping again
      await tester.tap(thinkingWidget.first, warnIfMissed: false);
      await tester.pump();
      await _recordDwell(tester, boundaryKey, 'reasoning', 30, controller: controller);
    } else {
      await _recordDwell(tester, boundaryKey, 'reasoning', 60, controller: controller);
    }
    // Zoom back out
    await _recordFrames(
      tester,
      boundaryKey,
      'reasoning',
      18,
      controller: controller,
      targetZoomScale: 1.0,
      targetZoomAlignment: Alignment.center,
    );

    // =================================================================
    // CLIP: Tool Execution Timeline & Autonomous Test Output
    // =================================================================
    _resolveScenarioDir('tools', clean: true);
    controller.setZoom(scale: 1.0, alignment: Alignment.center);
    final toolCard = find.byType(ToolCard);
    if (toolCard.evaluate().isNotEmpty) {
      await _recordFrames(
        tester,
        boundaryKey,
        'tools',
        24,
        controller: controller,
        targetZoomScale: 1.20,
        targetZoomAlignment: const Alignment(0.12, -0.15),
      );
      await _recordFrames(
        tester,
        boundaryKey,
        'tools',
        26,
        targetCursor: tester.getCenter(toolCard.first),
        clickAtEnd: true,
        controller: controller,
      );
      await tester.tap(toolCard.first, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      await _recordDwell(tester, boundaryKey, 'tools', 40, controller: controller);

      // Collapse back
      await tester.tap(toolCard.first, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    } else {
      await _recordDwell(tester, boundaryKey, 'tools', 60, controller: controller);
    }
    await _recordFrames(
      tester,
      boundaryKey,
      'tools',
      18,
      controller: controller,
      targetZoomScale: 1.0,
      targetZoomAlignment: Alignment.center,
    );

    // =================================================================
    // CLIP 5: Live Git Changes & Staging
    //  - Zoom into the Git Changes pane (right side), but with a
    //    conservative scale (1.18x) so the pane doesn't get clipped.
    // =================================================================
    _resolveScenarioDir('git', clean: true);
    controller.setZoom(scale: 1.0, alignment: Alignment.center);
    // Animate zoom toward git pane
    await _recordFrames(
      tester,
      boundaryKey,
      'git',
      24,
      controller: controller,
      targetZoomScale: 1.18,
      targetZoomAlignment: const Alignment(0.55, -0.05),
    );
    final gitPane = find.byType(GitChangesPane);
    final changesHeader = find.descendant(
      of: gitPane,
      matching: find.textContaining('MODIFICHE (CHANGES)'),
    );
    if (changesHeader.evaluate().isNotEmpty) {
      await tester.tap(changesHeader.first, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }
    final gitListTile = find.descendant(of: gitPane, matching: find.byType(ListTile));
    if (gitListTile.evaluate().isNotEmpty) {
      // Glide to the list tile
      await _recordFrames(
        tester,
        boundaryKey,
        'git',
        30,
        targetCursor: tester.getCenter(gitListTile.first),
        clickAtEnd: true,
        controller: controller,
      );
      await tester.tap(gitListTile.first, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // Unified Diff modal is now visible – zoom out slightly to show it
      await _recordFrames(
        tester,
        boundaryKey,
        'git',
        24,
        controller: controller,
        targetZoomScale: 1.08,
        targetZoomAlignment: Alignment.center,
      );
      // Dwell on the diff
      await _recordDwell(tester, boundaryKey, 'git', 36, controller: controller);

      // Close diff modal
      final closeIcon = find.descendant(
        of: find.byType(Dialog),
        matching: find.byIcon(Icons.close),
      );
      if (closeIcon.evaluate().isNotEmpty) {
        await tester.tap(closeIcon.first, warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await _recordDwell(tester, boundaryKey, 'git', 18, controller: controller);
      }
    }
    // Zoom back out
    await _recordFrames(
      tester,
      boundaryKey,
      'git',
      18,
      controller: controller,
      targetZoomScale: 1.0,
      targetZoomAlignment: Alignment.center,
    );

    // =================================================================
    // CLIP: Conversation Branching & Session Tree
    // =================================================================
    _resolveScenarioDir('tree', clean: true);
    controller.setZoom(scale: 1.0, alignment: Alignment.center);
    final appShellFinder = find.byType(AppShell);
    if (appShellFinder.evaluate().isNotEmpty) {
      final contextElement = tester.element(appShellFinder.first);
      SessionTreeDialog.show(contextElement, sessionId: currentSession.sessionId);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      await _recordFrames(
        tester,
        boundaryKey,
        'tree',
        24,
        controller: controller,
        targetZoomScale: 1.06,
        targetZoomAlignment: Alignment.center,
      );
      await _recordFrames(
        tester,
        boundaryKey,
        'tree',
        28,
        targetCursor: const Offset(960, 520),
        controller: controller,
      );
      await _recordDwell(tester, boundaryKey, 'tree', 40, controller: controller);

      final closeBtn = find.text('Chiudi');
      if (closeBtn.evaluate().isNotEmpty) {
        await tester.tap(closeBtn.first, warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      }
    } else {
      await _recordDwell(tester, boundaryKey, 'tree', 60, controller: controller);
    }
    await _recordFrames(
      tester,
      boundaryKey,
      'tree',
      18,
      controller: controller,
      targetZoomScale: 1.0,
      targetZoomAlignment: Alignment.center,
    );

    // =================================================================
    // CLIP 6: Catppuccin Theme Switcher (Frappé ↔ Latte)
    //  - Gentle zoom, theme toggle, dwell, toggle back.
    // =================================================================
    _resolveScenarioDir('theme', clean: true);
    controller.setZoom(scale: 1.0, alignment: Alignment.center);
    // Very gentle zoom so the full-window theme change is visible
    await _recordFrames(
      tester,
      boundaryKey,
      'theme',
      18,
      controller: controller,
      targetZoomScale: 1.04,
      targetZoomAlignment: Alignment.center,
    );
    final lightBtn = find.byTooltip('Tema chiaro');
    if (lightBtn.evaluate().isNotEmpty) {
      // Glide to button
      await _recordFrames(
        tester,
        boundaryKey,
        'theme',
        24,
        targetCursor: tester.getCenter(lightBtn.first),
        clickAtEnd: true,
        controller: controller,
      );
      await tester.tap(lightBtn.first, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Dwell on the light theme
      await _recordDwell(tester, boundaryKey, 'theme', 45, controller: controller);

      // Switch back to dark mode
      final darkBtn = find.byTooltip('Tema scuro');
      if (darkBtn.evaluate().isNotEmpty) {
        await _recordFrames(
          tester,
          boundaryKey,
          'theme',
          24,
          targetCursor: tester.getCenter(darkBtn.first),
          clickAtEnd: true,
          controller: controller,
        );
        await tester.tap(darkBtn.first, warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        // Dwell on restored dark theme
        await _recordDwell(tester, boundaryKey, 'theme', 36, controller: controller);
      }
    }
    // Zoom back to 1.0
    await _recordFrames(
      tester,
      boundaryKey,
      'theme',
      15,
      controller: controller,
      targetZoomScale: 1.0,
      targetZoomAlignment: Alignment.center,
    );

    // =================================================================
    // CLIP 7: Disconnect-Safe Daemon & Notifications
    //  - Show the "Pi locale" badge and notification toast.
    // =================================================================
    _resolveScenarioDir('disconnect', clean: true);
    controller.setZoom(scale: 1.0, alignment: Alignment.center);
    controller.setToast('Sessione sincronizzata (100% locale, zero telemetria)');
    // Animate zoom into top-left where the daemon badge lives
    await _recordFrames(
      tester,
      boundaryKey,
      'disconnect',
      24,
      controller: controller,
      targetCursor: const Offset(420, 160),
      targetZoomScale: 1.10,
      targetZoomAlignment: const Alignment(-0.45, -0.55),
    );
    // Dwell to let the toast read
    await _recordDwell(tester, boundaryKey, 'disconnect', 60, controller: controller);
    // Zoom back out and dismiss toast
    controller.setToast(null);
    await _recordFrames(
      tester,
      boundaryKey,
      'disconnect',
      18,
      controller: controller,
      targetZoomScale: 1.0,
      targetZoomAlignment: Alignment.center,
    );

    // =================================================================
    // HERO: 30s Master Walkthrough
    // Copy/assemble frames across scenarios into the hero folder
    // =================================================================
    final heroDir = _resolveScenarioDir('hero', clean: true);
    var heroFrameIndex = 0;
    final heroScenarios = [
      'bento',
      'palette',
      'search',
      'steer',
      'context',
      'reasoning',
      'tools',
      'git',
      'tree',
      'theme',
      'disconnect',
    ];
    for (final sc in heroScenarios) {
      final scDir = _resolveScenarioDir(sc, clean: false);
      final frames = scDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final f in frames) {
        final pad = heroFrameIndex.toString().padLeft(5, '0');
        f.copySync('${heroDir.path}/frame_$pad.png');
        heroFrameIndex++;
      }
    }
    _frameCounters['hero'] = heroFrameIndex;

    // ignore: avoid_print
    print('RECORDED SCENARIOS SUMMARY:');
    _frameCounters.forEach((k, v) {
      // ignore: avoid_print
      print('  Scenario "$k": $v frames');
    });
    expect(_frameCounters['hero'] ?? 0, greaterThan(300));
  });
}
