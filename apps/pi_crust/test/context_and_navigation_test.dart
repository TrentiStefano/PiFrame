import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import 'package:pi_crust/features/sessions_sidebar/sessions_sidebar.dart';
import 'package:pi_crust/features/session_tree/session_tree_dialog.dart';
import 'package:pi_crust/data/daemon/daemon_providers.dart';

void main() {
  Widget wrapWithThemeAndScope(Widget child, {List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(
          extensions: const [CrustTokens.dark],
        ),
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('SessionsSidebar displays search field, filter chips, and filters sessions', (tester) async {
    final mockSessions = [
      {
        'id': 'sess_1',
        'name': 'Feature Branch A',
        'cwd': '/projects/pi-crust',
        'isActive': true,
        'lastMessagePreview': 'Implementing git diff viewer',
      },
      {
        'id': 'sess_2',
        'name': 'Bugfix Session B',
        'cwd': '/projects/other-repo',
        'isActive': false,
        'lastMessagePreview': 'Fixing stream buffer overflow',
      },
    ];

    await tester.pumpWidget(
      wrapWithThemeAndScope(
        const SessionsSidebar(),
        overrides: [
          sessionListProvider.overrideWith((ref) => Future.value(mockSessions)),
          activeSessionIdProvider.overrideWith((ref) => 'sess_1'),
        ],
      ),
    );

    await tester.pumpAndSettle();

    // Verify header and search field
    expect(find.text('Sessioni'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Tutte'), findsOneWidget);
    expect(find.text('Attive'), findsOneWidget);
    expect(find.text('Questo repo'), findsOneWidget);

    // Both sessions should initially be visible
    expect(find.text('Feature Branch A'), findsOneWidget);
    expect(find.text('Bugfix Session B'), findsOneWidget);

    // Filter by search query
    await tester.enterText(find.byType(TextField), 'diff viewer');
    await tester.pumpAndSettle();

    expect(find.text('Feature Branch A'), findsOneWidget);
    expect(find.text('Bugfix Session B'), findsNothing);

    // Clear search
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    // Filter by "Attive" chip
    await tester.tap(find.text('Attive'));
    await tester.pumpAndSettle();

    expect(find.text('Feature Branch A'), findsOneWidget);
    expect(find.text('Bugfix Session B'), findsNothing);
  });

  testWidgets('SessionTreeDialog renders properly in empty state', (tester) async {
    await tester.pumpWidget(
      wrapWithThemeAndScope(
        const SessionTreeDialog(sessionId: 'sess_test'),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Albero della Sessione'), findsOneWidget);
    expect(find.text('Sessione: sess_test'), findsOneWidget);
    expect(find.text('Chiudi'), findsOneWidget);
  });
}
