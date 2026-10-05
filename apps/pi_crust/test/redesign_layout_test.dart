import 'dart:io';
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
import 'package:pi_crust/domain/session/session_state.dart';
import 'package:pi_crust/domain/session/agent_status.dart';
import 'package:pi_crust/features/command_palette/command_palette.dart';
import 'package:pi_crust/features/settings/diagnostics.dart';
import 'package:pi_crust/ui/precision.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

// Synthetic data is confined to tests; the product never displays demo sessions.
const sampleSession = SessionState(
  sessionId: 'design-session',
  sessionName: 'Rendere affidabile la riconnessione',
  cwd: 'C:/Projects/pi-crust',
  currentModel: 'claude-sonnet',
  currentThinkingLevel: 'medium',
  entries: [
    SessionEntry(
      id: 'u1',
      role: 'user',
      timestamp: 1,
      text: 'Controlla il flusso di riconnessione. Voglio preservare la cronologia e recuperare gli eventi senza duplicati.',
    ),
    SessionEntry(
      id: 'a1',
      role: 'assistant',
      timestamp: 2,
      thinking: 'Controllo il journal e la sequenza degli eventi prima di modificare il client.',
      toolCalls: [
        ToolExecutionState(
          toolCallId: 't1',
          toolName: 'read',
          args: {'path': 'lib/data/daemon/pcp_client.dart'},
          output: 'Replay cursor verified. No duplicate events.',
          durationMs: 42,
        ),
      ],
      text: 'Il client mantiene il cursore di replay. Possiamo isolare il recupero della connessione senza cambiare la proprietà delle sessioni.\n\n```dart\nfinal cursor = session.lastAppliedSeq;\nawait client.attach(sessionId);\n```\n\nLa cronologia resta gestita da Pi. Il prossimo passo è verificare il comportamento con una disconnessione durante lo streaming.',
    ),
  ],
);

Future<void> capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final output = Platform.environment['PI_CRUST_CAPTURE'];
  if (output == null) return;
  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory(output)..createSync(recursive: true);
    File('${directory.path}/$name.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
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
  for (final size in [
    const Size(1440, 960),
    const Size(1100, 800),
    const Size(390, 844),
  ]) {
    testWidgets('shell remains usable at ${size.width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dark = Platform.environment['PI_CRUST_CAPTURE_DARK'] == '1';
      final json = File('assets/themes/crust-${dark ? 'dark' : 'light'}.json')
          .readAsStringSync();
      final repo = ThemeRepository()
        ..registerThemeJson(json)
        ..setActiveTheme(dark ? 'crust-dark' : 'crust-light');
      addTearDown(repo.dispose);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            diagnosticsFixtureLabelProvider.overrideWithValue(
              'DATI SINTETICI · CAPTURA DI TEST',
            ),
            themeRepositoryProvider.overrideWithValue(repo),
            daemonEndpointProvider.overrideWith((ref) async => null),
            connectionStateProvider.overrideWith(
              (ref) => Stream.value(DaemonConnectionState.connected),
            ),
            sessionListProvider.overrideWith(
              (ref) async => [
                {
                  'id': sampleSession.sessionId,
                  'name': sampleSession.sessionName,
                  'cwd': sampleSession.cwd,
                  'isActive': true,
                  'lastMessagePreview': 'Verifica del journal e del replay',
                },
                {
                  'id': 's2',
                  'name': 'Semplificare il composer',
                  'cwd': sampleSession.cwd,
                  'isActive': false,
                  'lastMessagePreview': 'Gestione delle istruzioni in coda',
                },
                {
                  'id': 's3',
                  'name': 'Esplorare il protocollo PCP',
                  'cwd': 'C:/Projects/pcp',
                  'isActive': false,
                  'lastMessagePreview': 'Contratti e tipi generati',
                },
              ],
            ),
            activeSessionIdProvider.overrideWith(
              (ref) => sampleSession.sessionId,
            ),
            sessionStateFamily(sampleSession.sessionId).overrideWith(
              (ref) =>
                  SessionStateNotifier(sampleSession.sessionId, null)
                    ..state = sampleSession,
            ),
          ],
          child: RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: repo.activeTheme.toThemeData(),
              home: const AppShell(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final layoutError = tester.takeException();
      expect(find.byType(TextField), findsWidgets);
      expect(find.text('PI–CRUST'), findsOneWidget);
      expect(find.byType(CrustMark), findsOneWidget);
      final name = '${dark ? 'dark' : 'light'}-${size.width.toInt()}';
      await capture(tester, boundaryKey, name);
      expect(layoutError, isNull);

      await tester.tap(find.byTooltip('Workspace e modello'));
      await tester.pumpAndSettle();
      if (size.width < 1280) {
        expect(find.text('Area di lavoro'), findsOneWidget);
      }
      expect(find.text('Contesto & Git'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, boundaryKey, '$name-workspace');
      await tester.tap(
        find.byTooltip(
          size.width >= 1280 ? 'Workspace e modello' : 'Chiudi workspace',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Impostazioni'));
      await tester.pumpAndSettle();
      for (final tab in [
        'PI CLI',
        'DAEMON',
        'ASPETTO',
        'PRIVACY',
        'DIAGNOSTICA',
      ]) {
        await tester.ensureVisible(find.text(tab).first);
        await tester.tap(find.text(tab).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$tab at ${size.width}');
        if (tab == 'ASPETTO' || tab == 'DIAGNOSTICA') {
          await capture(tester, boundaryKey, '$name-$tab');
        }
      }
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      container.read(showSettingsProvider.notifier).state = false;
      container
          .read(sessionStateFamily(sampleSession.sessionId).notifier)
          .state = sampleSession.copyWith(
        agentStatus: AgentStatus.working,
      );
      await tester.pump(const Duration(milliseconds: 240));
      expect(find.text('Steer'), findsOneWidget);
      expect(find.text('Follow-up'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, boundaryKey, '$name-streaming');
      container
          .read(sessionStateFamily(sampleSession.sessionId).notifier)
          .state = sampleSession.copyWith(
        readOnly: true,
        readOnlyReason: 'unknown',
      );
      await tester.pump(const Duration(milliseconds: 240));
      expect(find.text('Duplica e continua'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, boundaryKey, '$name-readonly');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalette), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(CommandPalette),
          matching: find.byType(TextField),
        ),
        'Impostazioni',
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Impostazioni Pi-Crust'), findsOneWidget);
      container.read(showSettingsProvider.notifier).state = false;
      container.read(activeSessionIdProvider.notifier).state = null;
      await tester.pumpAndSettle();
      expect(find.text('Nuova\nsessione.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, boundaryKey, '$name-empty');
      await tester.pumpWidget(const SizedBox());
    });
  }
}
