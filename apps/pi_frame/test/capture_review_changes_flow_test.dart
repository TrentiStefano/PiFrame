import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pi_frame/features/session_changes/review_file_diff_viewer.dart';
import 'package:pi_frame/features/session_changes/session_changes_provider.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  testWidgets('Capture Review Changes Flow', (tester) async {
    const size = Size(1100, 750);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final darkJson = File('assets/themes/piframe-dark.json').readAsStringSync();
    final repo = ThemeRepository()
      ..registerThemeJson(darkJson)
      ..setActiveTheme('piframe-dark');
    addTearDown(repo.dispose);

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

    final key = GlobalKey();

    // 1. Unexpanded file list
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: repo.activeTheme.toThemeData(),
        home: Scaffold(
          backgroundColor: const Color(0xFF161C27),
          body: Center(
            child: SizedBox(
              width: 1000,
              height: 680,
              child: RepaintBoundary(
                key: key,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C2432),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2E3C53)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.rate_review,
                                color: Color(0xFF5F9FC5),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Revisione modifiche (Review Changes)',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2E3C53),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '1 file',
                                  style: TextStyle(
                                    color: Color(0xFF5F9FC5),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF161C27),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFF2E3C53),
                              ),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.vertical_split,
                                  size: 14,
                                  color: Color(0xFF5F9FC5),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  '50/50 Split Diff',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161C27),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF475A77)),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.keyboard_arrow_right,
                              color: Color(0xFF5F9FC5),
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Icon(
                              Icons.description_outlined,
                              color: Color(0xFFA3B2C5),
                              size: 16,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'lib/app/app_shell.dart',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontFamily: 'SourceCodePro',
                              ),
                            ),
                            Spacer(),
                            Text(
                              '+14',
                              style: TextStyle(
                                color: Color(0xFFA1D9B0),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              '-3',
                              style: TextStyle(
                                color: Color(0xFFF1887A),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
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
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final img = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        if (bytes != null) {
          File('../../scratch/review_frame_collapsed.png')
              .writeAsBytesSync(bytes.buffer.asUint8List());
        }
      }
    });

    // 2. Expanded 50/50 split diff view
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: repo.activeTheme.toThemeData(),
        home: Scaffold(
          backgroundColor: const Color(0xFF161C27),
          body: Center(
            child: SizedBox(
              width: 1000,
              height: 680,
              child: RepaintBoundary(
                key: key,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C2432),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2E3C53)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.rate_review,
                                color: Color(0xFF5F9FC5),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Revisione modifiche (Review Changes)',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2E3C53),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '1 file',
                                  style: TextStyle(
                                    color: Color(0xFF5F9FC5),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF161C27),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFF5F9FC5),
                              ),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.vertical_split,
                                  size: 14,
                                  color: Color(0xFF5F9FC5),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  '50/50 Split Diff',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF242E40),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8),
                          ),
                          border: Border.all(color: const Color(0xFF5F9FC5)),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.keyboard_arrow_down,
                              color: Color(0xFF5F9FC5),
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Icon(
                              Icons.description_outlined,
                              color: Color(0xFF5F9FC5),
                              size: 16,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'lib/app/app_shell.dart',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontFamily: 'SourceCodePro',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Spacer(),
                            Text(
                              '+14',
                              style: TextStyle(
                                color: Color(0xFFA1D9B0),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              '-3',
                              style: TextStyle(
                                color: Color(0xFFF1887A),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFF5F9FC5)),
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(8),
                            ),
                          ),
                          child: ReviewFileDiffViewer(
                            file: changedFile,
                            mode: DiffViewMode.twoColumn,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final img = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        if (bytes != null) {
          File('../../scratch/review_frame_expanded.png')
              .writeAsBytesSync(bytes.buffer.asUint8List());
        }
      }
    });
  });
}
