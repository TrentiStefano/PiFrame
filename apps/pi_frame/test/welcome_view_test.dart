import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/data/first_run/app_first_run_store.dart';
import 'package:pi_frame/features/welcome/welcome_view.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _MockPcpClient extends PcpClient {
  _MockPcpClient() : super(port: 1, token: 'test');

  @override
  Stream<PcpEvent> events(String sessionId) => const Stream.empty();

  @override
  Stream<PcpSnapshot> snapshots(String sessionId) => const Stream.empty();

  @override
  Future<Map<String, dynamic>> sendCommand(PcpCommand command) async => {'status': 'ok', 'data': {}};
}

Map<String, dynamic> _session(String id, String cwd, int updatedAt) => {
  'id': id,
  'name': 'Session $id',
  'cwd': cwd,
  'updatedAt': updatedAt,
};

Future<void> _pumpWelcome(
  WidgetTester tester, {
  required List<Map<String, dynamic>> sessions,
  PcpClient? client,
  bool narrow = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pcpClientProvider.overrideWithValue(client),
        connectionStateProvider.overrideWith((ref) => Stream.value(DaemonConnectionState.connected)),
        sessionListProvider.overrideWith((ref) async => sessions),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: Scaffold(
          body: WelcomeView(narrow: narrow, connected: true, onOpenSessionsDrawer: () {}, onOpenCommandPalette: () {}),
        ),
      ),
    ),
  );
}

void _useSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  final storeFile = File(
    '${Directory.systemTemp.createTempSync('piframe_welcome_').path}'
    '${Platform.pathSeparator}app_first_run.json',
  );

  setUp(() {
    if (storeFile.existsSync()) storeFile.deleteSync();
    // Mark the intro as played so tests that do not cover it show the final state.
    storeFile.writeAsStringSync('{"introPlayed": true}');
    AppFirstRunStore.instance.setStorageFileForTesting(storeFile);
  });

  tearDown(() {
    AppFirstRunStore.instance.setStorageFileForTesting(null);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('lists recent sessions grouped by repository, without subagents, at most eight', (tester) async {
    _useSize(tester, const Size(1280, 900));
    await _pumpWelcome(
      tester,
      sessions: [
        for (var i = 0; i < 6; i++) _session('a$i', '/work/alpha', 1000 - i),
        _session('sub', '/work/alpha', 2000)..['isSubsession'] = true,
        for (var i = 0; i < 4; i++) _session('b$i', '/work/beta', 900 - i),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Resume your work'), findsOneWidget);
    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-launch-session-a5')), findsOneWidget);
    // Eight most recent: a0..a5 and b0, b1. b2 and b3 fall outside.
    expect(find.byKey(const ValueKey('quick-launch-session-b1')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-launch-session-b2')), findsNothing);
    expect(find.byKey(const ValueKey('quick-launch-session-sub')), findsNothing);
  });

  testWidgets('tapping a recent session makes it active', (tester) async {
    _useSize(tester, const Size(1280, 900));
    final container = ProviderContainer(
      overrides: [
        pcpClientProvider.overrideWithValue(_MockPcpClient()),
        connectionStateProvider.overrideWith((ref) => Stream.value(DaemonConnectionState.connected)),
        sessionListProvider.overrideWith((ref) async => [_session('one', '/work/alpha', 10)]),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: const Scaffold(
            body: WelcomeView(narrow: false, connected: true, onOpenSessionsDrawer: _noop, onOpenCommandPalette: _noop),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('quick-launch-session-one')));
    await tester.pumpAndSettle();
    expect(container.read(activeSessionIdProvider), 'one');
  });

  testWidgets('keyboard shortcut hint is hidden on touch platforms', (tester) async {
    _useSize(tester, const Size(1280, 900));
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await _pumpWelcome(tester, sessions: const []);
    await tester.pumpAndSettle();
    expect(find.text('Ctrl / Cmd + K · Commands'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('keyboard shortcut hint is shown with a desktop platform', (tester) async {
    _useSize(tester, const Size(1280, 900));
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await _pumpWelcome(tester, sessions: const []);
    await tester.pumpAndSettle();
    expect(find.text('Ctrl / Cmd + K · Commands'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('first run staggers the title in and later launches do not', (tester) async {
    _useSize(tester, const Size(1280, 900));
    storeFile.deleteSync();

    await _pumpWelcome(tester, sessions: const []);
    // First frame: the title is still transparent.
    final titleOpacity = find.ancestor(of: find.text('Resume your work'), matching: find.byType(Opacity));
    expect(tester.widget<Opacity>(titleOpacity.first).opacity, lessThan(1));

    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(titleOpacity.first).opacity, 1);
    expect(storeFile.readAsStringSync(), contains('introPlayed'));

    // Second launch: the intro is already recorded, so the title is visible at once.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpWelcome(tester, sessions: const []);
    final again = find.ancestor(of: find.text('Resume your work'), matching: find.byType(Opacity));
    for (final element in again.evaluate()) {
      expect((element.widget as Opacity).opacity, 1);
    }
    expect(find.text('Resume your work'), findsOneWidget);
  });
}

void _noop() {}
