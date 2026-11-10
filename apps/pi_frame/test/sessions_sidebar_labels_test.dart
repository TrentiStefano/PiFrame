import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/features/sessions_sidebar/pinned_sessions_provider.dart';
import 'package:pi_frame/features/sessions_sidebar/sessions_sidebar.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _PinnedNotifier extends PinnedSessionsNotifier {
  // Built from a list: in memory only, so the test never rewrites the user's real pins file.
  _PinnedNotifier() : super(['one', 'two']);
}

void main() {
  testWidgets('folders and pinned sessions retain context after filtering', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pcpClientProvider.overrideWithValue(null),
          pinnedSessionsProvider.overrideWith((ref) => _PinnedNotifier()),
          sessionListProvider.overrideWith(
            (ref) async => [
              {
                'id': 'one',
                'name': 'PiFrame',
                'cwd': r'C:\versions\v1\PiFrame',
              },
              {
                'id': 'two',
                'name': 'PiFrame',
                'cwd': r'C:\versions\v2\PiFrame',
              },
            ],
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: const Scaffold(body: SessionsSidebar()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('v1 / PiFrame'), findsNWidgets(2));
    expect(find.text('v2 / PiFrame'), findsNWidgets(2));

    await tester.tap(
      find.byKey(const ValueKey(r'session-folder:C:\versions\v1\PiFrame')),
    );
    await tester.pumpAndSettle();
    expect(find.text('v1 / PiFrame'), findsNWidgets(3));

    await tester.enterText(find.byType(TextField), 'one');
    await tester.pumpAndSettle();
    expect(find.text('v1 / PiFrame'), findsNWidgets(2));
    expect(find.text('v2 / PiFrame'), findsNothing);
    expect(find.text('PiFrame'), findsNothing);

    await tester.tap(find.byTooltip('Azioni sessione'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rinomina'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.text, 'PiFrame');
  });
}
