import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_crust/app/app_shell.dart';
import 'package:pi_crust/data/daemon/daemon_providers.dart';
import 'package:pi_crust/data/daemon/pcp_client.dart';
import 'package:pi_crust/data/theme/theme_providers.dart';
import 'package:pi_crust/domain/session/session_state.dart';
import 'package:pi_crust/features/transcript/rich_content.dart';
import 'package:pi_crust/features/settings/settings_view.dart';
import 'package:pi_crust/ui/code/code_block.dart';
import 'package:pi_crust/ui/code/diff_block.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrapApp(Widget child, {Size size = const Size(1200, 800), bool dark = true}) {
    final json = File('assets/themes/crust-${dark ? 'dark' : 'light'}.json').readAsStringSync();
    final repo = ThemeRepository()
      ..registerThemeJson(json)
      ..setActiveTheme(dark ? 'crust-dark' : 'crust-light');
    return ProviderScope(
      overrides: [
        themeRepositoryProvider.overrideWithValue(repo),
        daemonEndpointProvider.overrideWith((ref) async => null),
        connectionStateProvider.overrideWith((ref) => Stream.value(DaemonConnectionState.connected)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: repo.activeTheme.toThemeData(),
        home: child,
      ),
    );
  }

  group('UI Hardening - Extreme Screen Dimensions & Overflow Checks', () {
    testWidgets('AppShell renders at narrow width 320px without RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(wrapApp(const AppShell(), size: const Size(320, 600)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('AppShell renders with active session at narrow width 320px without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const worstSession = SessionState(
        sessionId: 'worst-case-session-id-with-extreme-length-123456789',
        sessionName: 'SuperLongSessionNameThatMightOverflowAnyConstrainedRowOrHeaderInTheInterface🚀',
        cwd: 'C:/Extremely/Long/Path/That/Exceeds/Normal/Width/Bounds/Repository/Testing/Pi/Crust',
        currentModel: 'custom-enterprise-deployment-claude-3-7-sonnet-long-model-name',
        currentThinkingLevel: 'extreme-extended-depth-level-3',
        sessionStats: {
          'cost': 123.4567,
          'contextUsage': {
            'tokens': 1950000,
            'contextWindow': 2000000,
            'percent': 97.5,
          },
        },
        extensionStatuses: {
          'very-long-extension-name-alpha': 'full-active-streaming-mode',
          'another-very-long-extension-name-beta': 'standby-awaiting-trigger',
        },
        entries: [
          SessionEntry(
            id: 'e1',
            role: 'user',
            timestamp: 1,
            text: 'Test entry',
          ),
        ],
      );

      final json = File('assets/themes/crust-dark.json').readAsStringSync();
      final repo = ThemeRepository()
        ..registerThemeJson(json)
        ..setActiveTheme('crust-dark');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            themeRepositoryProvider.overrideWithValue(repo),
            daemonEndpointProvider.overrideWith((ref) async => null),
            connectionStateProvider.overrideWith((ref) => Stream.value(DaemonConnectionState.connected)),
            activeSessionIdProvider.overrideWith((ref) => worstSession.sessionId),
            sessionStateFamily(worstSession.sessionId).overrideWith(
              (ref) => SessionStateNotifier(worstSession.sessionId, null)..state = worstSession,
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: repo.activeTheme.toThemeData(),
            home: const AppShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('AppShell renders at short screen height 380px without overflow', (tester) async {
      tester.view.physicalSize = const Size(800, 380);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(wrapApp(const AppShell(), size: const Size(800, 380)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('UI Hardening - Stress Testing & Worst-Case Data', () {
    testWidgets('RichContent handles worst-case markdown and unclosed fences gracefully', (tester) async {
      const worstMarkdown = '''
# Titolo con emoji 🚀 e caratteri speciali: <test> & "quotes"
Testo normale con `un_pezzo_di_codice_inline_estremamente_lungo_senza_spazi_che_potrebbe_rompere_il_layout_del_widget_span_se_non_gestito`
Altro testo con **grassetto non chiuso...
```unrecognized_lang_xyz
line 1 of code
line 2 of code
''';

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [CrustTokens.dark],
          ),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: RichContent(text: worstMarkdown),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(RichContent), findsOneWidget);
    });

    testWidgets('CodeBlock handles 1000 lines without crashing or freezing', (tester) async {
      final thousandLines = List.generate(1000, (i) => 'final var_$i = "test string $i"; // comment $i').join('\n');

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [CrustTokens.dark],
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CodeBlock(code: thousandLines, language: 'dart'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(CodeBlock), findsOneWidget);
    });

    testWidgets('DiffBlock handles massive diffs without IntrinsicWidth failure', (tester) async {
      final diffLines = [
        '@@ -1,500 +1,500 @@',
        ...List.generate(300, (i) => '+added line $i with some significant length to test horizontal rendering'),
        ...List.generate(300, (i) => '-removed line $i with some significant length to test horizontal rendering'),
      ].join('\n');

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [CrustTokens.dark],
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: DiffBlock(diffText: diffLines, filename: 'massive_file.dart'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('+300'), findsOneWidget);
      expect(find.text('-300'), findsOneWidget);
    });
  });

  group('UI Stability - Resource & Lifecycle Management', () {
    testWidgets('SettingsView can be mounted and unmounted repeatedly without ticker leaks', (tester) async {
      final json = File('assets/themes/crust-dark.json').readAsStringSync();
      final repo = ThemeRepository()
        ..registerThemeJson(json)
        ..setActiveTheme('crust-dark');

      for (var i = 0; i < 3; i++) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              themeRepositoryProvider.overrideWithValue(repo),
              daemonEndpointProvider.overrideWith((ref) async => null),
            ],
            child: MaterialApp(
              theme: repo.activeTheme.toThemeData(),
              home: Scaffold(
                body: SettingsView(onClose: () {}),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Unmount SettingsView
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              themeRepositoryProvider.overrideWithValue(repo),
              daemonEndpointProvider.overrideWith((ref) async => null),
            ],
            child: const MaterialApp(
              home: Scaffold(body: SizedBox.shrink()),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      expect(tester.takeException(), isNull);
    });
  });
}
