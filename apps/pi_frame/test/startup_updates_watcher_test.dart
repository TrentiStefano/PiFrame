import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/data/update/startup_updates_provider.dart';
import 'package:pi_frame/data/platform/host_environment_service.dart';
import 'package:pi_frame/features/updates/startup_updates_watcher.dart';

import 'support/fake_platform_services.dart';

/// Records the update checks the watcher asks for instead of running them.
class _RecordingUpdatesNotifier extends StartupUpdatesNotifier {
  _RecordingUpdatesNotifier(super.ref);

  int checks = 0;

  @override
  Future<void> checkUpdates() async {
    checks++;
  }
}

void main() {
  late StreamController<DaemonConnectionState> connection;
  _RecordingUpdatesNotifier? notifier;

  setUp(() {
    connection = StreamController<DaemonConnectionState>.broadcast();
    notifier = null;
  });

  tearDown(() async {
    await connection.close();
  });

  Future<void> pumpWatcher(WidgetTester tester, HostEnvironmentService host) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hostEnvironmentServiceProvider.overrideWithValue(host),
          connectionStateProvider.overrideWith((ref) => connection.stream),
          startupUpdatesProvider.overrideWith((ref) => notifier = _RecordingUpdatesNotifier(ref)),
        ],
        child: const MaterialApp(home: Scaffold(body: StartupUpdatesWatcher())),
      ),
    );
    await tester.pump();
  }

  testWidgets('asks for an update check once the daemon is connected', (tester) async {
    await pumpWatcher(tester, FakeHostEnvironmentService());
    expect(notifier?.checks ?? 0, 0);

    connection.add(DaemonConnectionState.connected);
    await tester.pump();
    await tester.pump();

    expect(notifier!.checks, 1);
  });

  testWidgets('asks again after a reconnect, but not twice for one connection', (tester) async {
    await pumpWatcher(tester, FakeHostEnvironmentService());

    connection.add(DaemonConnectionState.connected);
    await tester.pump();
    await tester.pump();
    connection.add(DaemonConnectionState.connected);
    await tester.pump();
    await tester.pump();
    connection.add(DaemonConnectionState.reconnecting);
    await tester.pump();
    connection.add(DaemonConnectionState.connected);
    await tester.pump();
    await tester.pump();

    expect(notifier!.checks, 2);
  });

  testWidgets('never asks in a Flutter test run', (tester) async {
    await pumpWatcher(tester, FakeHostEnvironmentService(variables: const {'FLUTTER_TEST': 'true'}));

    connection.add(DaemonConnectionState.connected);
    await tester.pump();
    await tester.pump();

    expect(notifier?.checks ?? 0, 0);
  });

  testWidgets('never asks on the web build', (tester) async {
    await pumpWatcher(tester, FakeHostEnvironmentService(isWeb: true));

    connection.add(DaemonConnectionState.connected);
    await tester.pump();
    await tester.pump();

    expect(notifier?.checks ?? 0, 0);
  });
}
