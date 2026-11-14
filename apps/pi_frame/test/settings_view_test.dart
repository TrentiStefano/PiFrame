import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame/features/settings/settings_view.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/data/theme/theme_providers.dart';
import 'package:pi_frame/data/update/startup_updates_provider.dart';

Map<String, dynamic> _updatedResult({
  String version = '1.0.1',
  String previousVersion = '1.0.0',
}) => {
  'data': {
    'output': 'Done',
    'status': 'updated',
    'previousVersion': previousVersion,
    'version': version,
  },
};

class _PackageUpdateChecker implements StartupUpdateChecker {
  final _PackageClient client;
  _PackageUpdateChecker(this.client);

  @override
  Future<String?> checkCurrentPiVersion() async => '1.5.0';
  @override
  Future<String?> checkLatestPiVersion() async => '1.5.0';
  @override
  Future<List<PackageUpdateInfo>> checkOutdatedPackages() async {
    client.updateChecks++;
    return client.outdatedUpdates;
  }
}

class _PackageClient extends PcpClient {
  _PackageClient() : super(port: 1, token: 'test');
  String? pinnedSource;
  String? pinnedVersion;
  int listRequests = 0;
  final packageCheckRequests = <bool>[];
  int updateChecks = 0;
  List<PackageUpdateInfo> outdatedUpdates = [];
  final updatedSources = <String>[];
  Future<Map<String, dynamic>> Function(String source)? onUpdate;
  Future<Map<String, dynamic>> Function()? onList;
  List<Map<String, dynamic>> packages = [
    {
      'source': 'npm:pi-caveman',
      'name': 'pi-caveman',
      'version': '0.1.15',
      'latestVersion': '1.0.1',
      'pinnedVersion': null,
    },
  ];

  @override
  Future<Map<String, dynamic>> getDaemonConfig() async => {
    'data': {'workerIdleTimeoutMs': 1800000},
  };

  @override
  Future<Map<String, dynamic>> listPiPackages({
    bool checkUpdates = false,
  }) async {
    listRequests++;
    packageCheckRequests.add(checkUpdates);
    if (onList != null) return onList!();
    return {
      'data': {'packages': packages},
    };
  }

  @override
  Future<Map<String, dynamic>> updatePiPackage(String source) async {
    updatedSources.add(source);
    final package = packages.firstWhere(
      (package) => package['source'] == source,
    );
    if (onUpdate != null) {
      final result = await onUpdate!(source);
      final data = result['data'] as Map<String, dynamic>? ?? result;
      final version = data['version'];
      if (version is String &&
          const {'updated', 'current'}.contains(data['status'])) {
        package['version'] = version;
        if (data['status'] == 'current') package['latestVersion'] = version;
      }
      return result;
    }
    if (package['pinnedVersion'] != null) {
      return {
        'data': {
          'status': 'pinned',
          'previousVersion': package['version'],
          'version': package['version'],
        },
      };
    }
    final before = package['version']?.toString() ?? '1.0.0';
    final target = package['latestVersion'];
    if (target is! String) throw StateError('Missing fixture target version');
    package['version'] = target;
    return _updatedResult(previousVersion: before, version: target);
  }

  @override
  Future<Map<String, dynamic>> pinPiPackage(
    String source,
    String version,
  ) async {
    pinnedSource = source;
    pinnedVersion = version;
    final package = packages.firstWhere(
      (package) => package['source'] == source,
    );
    package['source'] = '$source@$version';
    package['version'] = version;
    package['pinnedVersion'] = version;
    return {
      'data': {'source': '$source@$version'},
    };
  }
}

void main() {
  Future<void> pumpPackages(
    WidgetTester tester,
    _PackageClient client, {
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          pcpClientProvider.overrideWithValue(client),
          startupUpdateCheckerProvider.overrideWithValue(
            _PackageUpdateChecker(client),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
          home: Scaffold(
            body: SettingsView(onClose: () {}, initialTabIndex: 1),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> confirmUpdateAll(
    WidgetTester tester, {
    int? expectedCount,
  }) async {
    await tester.tap(find.byKey(const ValueKey('update-all-pi-packages')));
    await tester.pumpAndSettle();
    if (expectedCount != null) {
      expect(
        find.textContaining(
          '$expectedCount pacchetti utente con aggiornamenti disponibili',
        ),
        findsOneWidget,
      );
    }
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Aggiorna tutto'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'update all updates only available sources and reloads the package list',
    (tester) async {
      final client = _PackageClient()
        ..packages = [
          {
            'source': 'npm:pi-caveman',
            'name': 'pi-caveman',
            'version': '1.0.0',
            'latestVersion': '1.0.1',
          },
          {
            'source': 'npm:pi-ranged@^1.0.0',
            'name': 'pi-ranged',
            'version': '1.0.0',
            'latestVersion': '1.2.0',
          },
          {'source': 'git:github.com/example/pi-tools', 'name': 'pi-tools'},
          {
            'source': 'npm:pi-pinned@1.2.3',
            'name': 'pi-pinned',
            'version': '1.2.3',
            'latestVersion': '2.0.0',
            'pinnedVersion': '1.2.3',
          },
          {
            'source': 'npm:pi-current',
            'name': 'pi-current',
            'version': '2.0.0',
            'latestVersion': '2.0.0',
          },
          {
            'source': 'npm:pi-unsupported',
            'name': 'pi-unsupported',
            'version': '1.0.0',
            'latestVersion': '2.0.0',
            'updateError': 'Unsupported platform',
          },
        ];
      await pumpPackages(tester, client);
      await confirmUpdateAll(tester, expectedCount: 2);

      expect(client.updatedSources, ['npm:pi-caveman', 'npm:pi-ranged@^1.0.0']);
      expect(client.listRequests, 2);
      expect(client.packageCheckRequests, [true, true]);
      expect(
        find.textContaining('Tutti i 2 pacchetti sono stati aggiornati.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('update-all-pi-packages')),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('cancelling update all does not update any package', (
    tester,
  ) async {
    final client = _PackageClient();
    await pumpPackages(tester, client);
    await tester.tap(find.byKey(const ValueKey('update-all-pi-packages')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Annulla'),
      ),
    );
    await tester.pumpAndSettle();
    expect(client.updatedSources, isEmpty);
    expect(client.listRequests, 1);
  });

  testWidgets('updates are sequential and package controls stay disabled', (
    tester,
  ) async {
    final first = Completer<Map<String, dynamic>>();
    final second = Completer<Map<String, dynamic>>();
    final client = _PackageClient()
      ..packages = [
        {
          'source': 'npm:first',
          'name': 'first',
          'version': '1.0.0',
          'latestVersion': '1.0.1',
        },
        {
          'source': 'npm:second',
          'name': 'second',
          'version': '1.0.0',
          'latestVersion': '1.0.1',
        },
      ]
      ..onUpdate = (source) =>
          source == 'npm:first' ? first.future : second.future;
    await pumpPackages(tester, client);
    await confirmUpdateAll(tester);

    expect(client.updatedSources, ['npm:first']);
    expect(find.text('Aggiornamento...'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('update-all-pi-packages')),
          )
          .onPressed,
      isNull,
    );
    for (final tooltip in [
      'Aggiorna first',
      'Blocca versione first',
      'Rimuovi first',
    ]) {
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == tooltip,
              ),
            )
            .onPressed,
        isNull,
      );
    }

    first.complete(_updatedResult());
    await tester.pumpAndSettle();
    expect(client.updatedSources, ['npm:first', 'npm:second']);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.5,
    );
    second.complete(_updatedResult());
    await tester.pumpAndSettle();
    expect(find.text('Aggiorna tutto'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Aggiorna first',
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('one failed update does not prevent the remaining updates', (
    tester,
  ) async {
    final client = _PackageClient()
      ..packages = [
        {
          'source': 'npm:broken',
          'name': 'broken',
          'version': '1.0.0',
          'latestVersion': '1.0.1',
        },
        {
          'source': 'npm:working',
          'name': 'working',
          'version': '1.0.0',
          'latestVersion': '1.0.1',
        },
      ]
      ..onUpdate = (source) async {
        if (source == 'npm:broken') throw StateError('Package download failed');
        return _updatedResult();
      };
    await pumpPackages(tester, client);
    await confirmUpdateAll(tester);
    expect(client.updatedSources, ['npm:broken', 'npm:working']);
    expect(client.listRequests, 2);
    final error = tester
        .widget<Text>(find.byKey(const ValueKey('pi-package-update-error')))
        .data!;
    expect(error, contains('Pacchetti aggiornati: 1.'));
    expect(error, contains('Aggiornamenti non riusciti: 1.'));
    expect(error, contains('npm:broken: Operazione non riuscita'));
    expect(error, isNot(contains('Package download failed')));
    expect(
      find.textContaining('Tutti i 2 pacchetti sono stati aggiornati.'),
      findsNothing,
    );
  });

  testWidgets(
    'an update that becomes current is not counted as newly updated',
    (tester) async {
      final client = _PackageClient()
        ..onUpdate = (_) async => {
          'data': {'status': 'current', 'version': '0.1.15'},
        };
      await pumpPackages(tester, client);
      await confirmUpdateAll(tester);
      expect(
        find.textContaining(
          'Pacchetti aggiornati: 0. Già aggiornati: 1. Versione bloccata: 0.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Riavvia Pi per applicare le modifiche.'),
        findsNothing,
      );
      expect(client.updateChecks, 1);
    },
  );

  testWidgets('an unverified command result never produces a success message', (
    tester,
  ) async {
    final client = _PackageClient()
      ..onUpdate = (_) async => {
        'data': {'output': 'Command finished'},
      };
    await pumpPackages(tester, client);
    await confirmUpdateAll(tester);
    final error = tester
        .widget<Text>(find.byKey(const ValueKey('pi-package-update-error')))
        .data!;
    expect(
      error,
      contains('Il daemon non ha verificato la versione installata'),
    );
    expect(error, contains('Aggiornamenti non riusciti: 1.'));
    expect(
      find.textContaining('Tutti i 1 pacchetti sono stati aggiornati.'),
      findsNothing,
    );
  });

  testWidgets(
    'an updated npm result without an installed version is rejected',
    (tester) async {
      final client = _PackageClient()
        ..onUpdate = (_) async => {
          'data': {'status': 'updated'},
        };
      await pumpPackages(tester, client);
      await confirmUpdateAll(tester);
      final error = tester
          .widget<Text>(find.byKey(const ValueKey('pi-package-update-error')))
          .data!;
      expect(
        error,
        contains('Il daemon non ha verificato la versione installata'),
      );
    },
  );

  testWidgets(
    'installed updates clear the startup notice and display the new version',
    (tester) async {
      final client = _PackageClient()
        ..outdatedUpdates = const [
          PackageUpdateInfo(
            name: 'pi-caveman',
            currentVersion: '0.1.15',
            latestVersion: '1.2.0',
          ),
        ];
      client.packages.first['latestVersion'] = '1.2.0';
      client.onUpdate = (_) async {
        client.packages.first['version'] = '1.2.0';
        client.outdatedUpdates = [];
        return _updatedResult(previousVersion: '0.1.15', version: '1.2.0');
      };
      await pumpPackages(tester, client);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsView)),
      );
      await container.read(startupUpdatesProvider.notifier).checkUpdates();
      expect(container.read(startupUpdatesProvider).shouldShowBanner, isTrue);
      await confirmUpdateAll(tester);
      expect(container.read(startupUpdatesProvider).shouldShowBanner, isFalse);
      expect(container.read(startupUpdatesProvider).outdatedPackages, isEmpty);
      expect(client.updateChecks, 2);
      expect(find.textContaining('1.2.0 · npm:pi-caveman'), findsOneWidget);
    },
  );

  testWidgets(
    'single-package update failures remain visible and recheck notices',
    (tester) async {
      final client = _PackageClient()
        ..onUpdate = (_) async =>
            throw StateError('installed 0.1.15, expected 1.2.0');
      await pumpPackages(tester, client);
      await tester.tap(find.byTooltip('Aggiorna pi-caveman'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Aggiorna'),
        ),
      );
      await tester.pumpAndSettle();
      final error = tester
          .widget<Text>(find.byKey(const ValueKey('pi-package-update-error')))
          .data!;
      // Raw daemon text is not shown inline; the generic title is.
      expect(error, contains('npm:pi-caveman: Operazione non riuscita'));
      expect(error, isNot(contains('installed 0.1.15')));
      expect(client.updateChecks, 1);
      expect(client.listRequests, 2);
    },
  );

  testWidgets(
    'incompatible update reasons are visible beside the installed package',
    (tester) async {
      final client = _PackageClient();
      await pumpPackages(tester, client);
      client.packages.first.addAll({
        'latestVersion': '1.2.0',
        'updateError': 'Required dependency only supports macOS and Linux.',
      });
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsView)),
      );
      await container.read(startupUpdatesProvider.notifier).checkUpdates();
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Aggiornamento 1.2.0 non compatibile con questa piattaforma.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Required dependency only supports macOS and Linux.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('update all is disabled when no packages are installed', (
    tester,
  ) async {
    final client = _PackageClient()..packages = [];
    await pumpPackages(tester, client);
    expect(find.text('Nessun pacchetto Pi utente installato.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('update-all-pi-packages')),
          )
          .onPressed,
      isNull,
    );
  });

  for (final entry in const <String, Map<String, dynamic>>{
    'current versions': {'latestVersion': '1.0.0'},
    'newer installed versions': {'version': '3.0.0'},
    'pinned versions': {'source': 'npm:tested@1.0.0', 'pinnedVersion': '1.0.0'},
    'incompatible updates': {'updateError': 'Unsupported platform'},
    'unknown available versions': {'latestVersion': null},
    'unknown installed versions': {'version': null},
    'invalid versions': {'latestVersion': 'invalid'},
  }.entries) {
    testWidgets('update buttons remain disabled for ${entry.key}', (
      tester,
    ) async {
      final client = _PackageClient()
        ..packages = [
          {
            'source': 'npm:tested',
            'name': 'tested',
            'version': '1.0.0',
            'latestVersion': '2.0.0',
            ...entry.value,
          },
        ];
      await pumpPackages(tester, client);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Aggiorna tested',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('update-all-pi-packages')),
            )
            .onPressed,
        isNull,
      );
      expect(client.updatedSources, isEmpty);
      expect(client.packageCheckRequests, [true]);
    });
  }

  testWidgets('update controls wait for verified availability', (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    final client = _PackageClient()..onList = () => pending.future;
    await pumpPackages(tester, client, settle: false);
    expect(find.byKey(const ValueKey('update-all-pi-packages')), findsNothing);
    expect(client.updatedSources, isEmpty);
    pending.complete({
      'data': {'packages': client.packages},
    });
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('update-all-pi-packages')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton &&
                  widget.tooltip == 'Aggiorna pi-caveman',
            ),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'a fresh check enables buttons when an update becomes available',
    (tester) async {
      final client = _PackageClient();
      client.packages.first['latestVersion'] = '0.1.15';
      await pumpPackages(tester, client);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('update-all-pi-packages')),
            )
            .onPressed,
        isNull,
      );
      client.packages.first['latestVersion'] = '1.0.1';
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsView)),
      );
      await container.read(startupUpdatesProvider.notifier).refreshPackages();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('update-all-pi-packages')),
            )
            .onPressed,
        isNotNull,
      );
      expect(client.packageCheckRequests, [true, true]);
    },
  );

  testWidgets('a stale list cannot re-enable buttons after a newer check', (
    tester,
  ) async {
    final first = Completer<Map<String, dynamic>>();
    var requests = 0;
    final client = _PackageClient()
      ..onList = () => ++requests == 1
          ? first.future
          : Future.value({
              'data': {
                'packages': [
                  {
                    'source': 'npm:pi-caveman',
                    'name': 'pi-caveman',
                    'version': '2.0.0',
                    'latestVersion': '2.0.0',
                  },
                ],
              },
            });
    await pumpPackages(tester, client, settle: false);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsView)),
    );
    await container.read(startupUpdatesProvider.notifier).refreshPackages();
    await tester.pumpAndSettle();
    first.complete({
      'data': {
        'packages': [
          {
            'source': 'npm:pi-caveman',
            'name': 'pi-caveman',
            'version': '1.0.0',
            'latestVersion': '2.0.0',
          },
        ],
      },
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('2.0.0 · npm:pi-caveman'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('update-all-pi-packages')),
          )
          .onPressed,
      isNull,
    );
    expect(client.updatedSources, isEmpty);
  });

  testWidgets('a single update disables controls once the package is current', (
    tester,
  ) async {
    final client = _PackageClient();
    await pumpPackages(tester, client);
    await tester.tap(find.byTooltip('Aggiorna pi-caveman'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Aggiorna'),
      ),
    );
    await tester.pumpAndSettle();
    expect(client.updatedSources, ['npm:pi-caveman']);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton &&
                  widget.tooltip == 'Aggiorna pi-caveman',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('update-all-pi-packages')),
          )
          .onPressed,
      isNull,
    );
  });

  for (final bulk in [false, true]) {
    testWidgets(
      'an expired ${bulk ? 'bulk' : 'single'} confirmation cannot update a current package',
      (tester) async {
        final client = _PackageClient();
        await pumpPackages(tester, client);
        await tester.tap(
          bulk
              ? find.byKey(const ValueKey('update-all-pi-packages'))
              : find.byTooltip('Aggiorna pi-caveman'),
        );
        await tester.pumpAndSettle();
        client.packages = [
          {...client.packages.first, 'version': '1.0.1'},
        ];
        final container = ProviderScope.containerOf(
          tester.element(find.byType(SettingsView)),
        );
        await container.read(startupUpdatesProvider.notifier).refreshPackages();
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(
              FilledButton,
              bulk ? 'Aggiorna tutto' : 'Aggiorna',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(client.updatedSources, isEmpty);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('update-all-pi-packages')),
              )
              .onPressed,
          isNull,
        );
      },
    );
  }

  testWidgets('package update header fits a narrow viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpPackages(tester, _PackageClient());
    expect(find.text('Pacchetti Pi installati'), findsOneWidget);
    expect(find.text('Aggiorna tutto'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('Packages loading, timeout and error states', () {
    testWidgets('loading shows a labelled skeleton instead of a spinner', (
      tester,
    ) async {
      final pending = Completer<Map<String, dynamic>>();
      final client = _PackageClient()..onList = () => pending.future;
      await pumpPackages(tester, client, settle: false);

      expect(find.text('Caricamento pacchetti…'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('packages-skeleton-row')),
        findsNWidgets(4),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('packages-loading')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('packages-load-retry')), findsNothing);

      await tester.pump(const Duration(seconds: 9));
      expect(find.byKey(const ValueKey('packages-loading-slow')), findsNothing);

      pending.complete({
        'data': {'packages': client.packages},
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('packages-loading')), findsNothing);
    });

    testWidgets('timeout keeps the skeleton and retry re-requests the list', (
      tester,
    ) async {
      final pending = Completer<Map<String, dynamic>>();
      final client = _PackageClient();
      client.onList = () {
        if (client.listRequests == 1) return pending.future;
        return Future.value({
          'data': {
            'packages': [
              {
                'source': 'npm:pi-caveman',
                'name': 'pi-caveman',
                'version': '0.1.15',
              },
            ],
          },
        });
      };
      await pumpPackages(tester, client, settle: false);

      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(
        find.text('Il caricamento richiede più tempo del previsto'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('packages-skeleton-row')),
        findsNWidgets(4),
      );
      expect(find.byKey(const ValueKey('packages-load-retry')), findsOneWidget);
      expect(client.listRequests, 1);

      await tester.tap(find.byKey(const ValueKey('packages-load-retry')));
      await tester.pumpAndSettle();

      expect(client.listRequests, 2);
      expect(find.byKey(const ValueKey('packages-loading-slow')), findsNothing);
      expect(find.text('pi-caveman'), findsOneWidget);
    });

    testWidgets('error shows a callout with raw details behind Dettagli', (
      tester,
    ) async {
      final client = _PackageClient()
        ..onList = () async => throw StateError('daemon refused boom-42');
      await pumpPackages(tester, client);

      expect(find.byKey(const ValueKey('packages-load-error')), findsOneWidget);
      expect(find.text('Impossibile caricare i pacchetti'), findsOneWidget);
      expect(find.byKey(const ValueKey('packages-load-retry')), findsOneWidget);
      expect(find.text('Dettagli'), findsOneWidget);
      expect(find.byKey(const ValueKey('packages-load-details')), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('packages-load-details-toggle')),
      );
      await tester.pumpAndSettle();

      final details = tester.widget<SelectableText>(
        find.byKey(const ValueKey('packages-load-details')),
      );
      expect(details.data, contains('boom-42'));
    });

    testWidgets('retry from the error callout re-requests the list', (
      tester,
    ) async {
      final client = _PackageClient();
      client.onList = () async {
        if (client.listRequests == 1) throw StateError('first call failed');
        return {
          'data': {'packages': client.packages},
        };
      };
      await pumpPackages(tester, client);

      expect(find.byKey(const ValueKey('packages-load-error')), findsOneWidget);
      expect(client.listRequests, 1);

      await tester.tap(find.byKey(const ValueKey('packages-load-retry')));
      await tester.pumpAndSettle();

      expect(client.listRequests, 2);
      expect(find.byKey(const ValueKey('packages-load-error')), findsNothing);
      expect(find.text('pi-caveman'), findsOneWidget);
    });

    testWidgets('leaving settings while loading cancels the slow timer', (
      tester,
    ) async {
      final pending = Completer<Map<String, dynamic>>();
      final client = _PackageClient()..onList = () => pending.future;
      await pumpPackages(tester, client, settle: false);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 15));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('closing settings during update does not interrupt the batch', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    final client = _PackageClient()
      ..packages = [
        {
          'source': 'npm:first',
          'name': 'first',
          'version': '1.0.0',
          'latestVersion': '1.0.1',
        },
        {
          'source': 'npm:second',
          'name': 'second',
          'version': '1.0.0',
          'latestVersion': '1.0.1',
        },
      ]
      ..onUpdate = (source) async {
        if (source == 'npm:first') return pending.future;
        return _updatedResult();
      };
    await pumpPackages(tester, client);
    await confirmUpdateAll(tester);
    await tester.pumpWidget(const SizedBox());
    pending.complete(_updatedResult());
    await tester.pumpAndSettle();
    expect(client.updatedSources, ['npm:first', 'npm:second']);
    expect(client.listRequests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SettingsView exposes package list and version pin workflow', (
    tester,
  ) async {
    final client = _PackageClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          pcpClientProvider.overrideWithValue(client),
          startupUpdateCheckerProvider.overrideWithValue(
            _PackageUpdateChecker(client),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
          home: Scaffold(body: SettingsView(onClose: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('PACCHETTI'));
    await tester.pumpAndSettle();

    expect(find.text('pi-caveman'), findsOneWidget);
    expect(find.textContaining('0.1.15'), findsOneWidget);
    await tester.tap(find.byTooltip('Blocca versione pi-caveman'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '0.1.16');
    await tester.tap(find.text('Blocca'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blocca versione'));
    await tester.pumpAndSettle();

    expect(client.pinnedSource, 'npm:pi-caveman');
    expect(client.pinnedVersion, '0.1.16');
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton &&
                  widget.tooltip == 'Aggiorna pi-caveman',
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('theme selector changes MaterialApp to the Catppuccin asset', (
    tester,
  ) async {
    final repository = ThemeRepository();
    addTearDown(repository.dispose);
    for (final flavor in ['light', 'dark']) {
      repository.registerThemeJson(
        File('assets/themes/piframe-$flavor.json').readAsStringSync(),
      );
    }
    repository.setActiveTheme('piframe-light');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          themeRepositoryProvider.overrideWithValue(repository),
          themeStorageProvider.overrideWithValue(
            MemoryThemeStorage('piframe-light'),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: ref.watch(currentThemeDataProvider),
            home: Scaffold(
              body: Column(
                children: [
                  Builder(
                    builder: (context) => Text(
                      Theme.of(context).scaffoldBackgroundColor
                          .toARGB32()
                          .toString(),
                      key: const ValueKey('theme-background'),
                    ),
                  ),
                  Expanded(child: SettingsView(onClose: () {})),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(const Color(0xFFF1F3F7).toARGB32().toString()),
      findsOneWidget,
    );

    await tester.tap(find.text('ASPETTO'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-theme-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PiFrame Dark (dark)').last);
    await tester.pumpAndSettle();

    expect(
      find.text(const Color(0xFF161C27).toARGB32().toString()),
      findsOneWidget,
    );
  });

  testWidgets(
    'SettingsView renders all settings tabs including terminal and remote',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [daemonEndpointProvider.overrideWith((ref) async => null)],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
            home: Scaffold(body: SettingsView(onClose: () {})),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final tab in [
        'PI CLI',
        'PACCHETTI',
        'DAEMON',
        'ASPETTO',
        'PRIVACY',
        'DIAGNOSTICA',
        'AGGIORNAMENTI',
        'TERMINALE',
        'ACCESSO REMOTO',
        'AGENTI',
      ]) {
        await tester.ensureVisible(find.text(tab).first);
        expect(find.text(tab), findsOneWidget);
      }
    },
  );

  testWidgets(
    'SettingsView enforces D16 Zero Remote Telemetry in Privacy tab',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [daemonEndpointProvider.overrideWith((ref) async => null)],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
            home: Scaffold(
              body: SettingsView(onClose: () {}, initialTabIndex: 4),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'PiFrame non invia alcun dato di utilizzo a server remoti.',
        ),
        findsOneWidget,
      );
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(Radio), findsNothing);
      expect(find.textContaining('Invia statistiche'), findsNothing);
      expect(find.textContaining('Abilita telemetria'), findsNothing);
      expect(find.textContaining('Abilita analytics'), findsNothing);
    },
  );

  testWidgets('SettingsView toggles Nerd stats switch in Appearance tab', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [daemonEndpointProvider.overrideWith((ref) async => null)],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
          home: Scaffold(
            body: SettingsView(onClose: () {}, initialTabIndex: 3),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var i = 0; i < 5; i++) {
      if (find
          .byKey(const ValueKey('settings-nerd-stats-switch'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pumpAndSettle();
    }

    final switchFinder = find.byKey(
      const ValueKey('settings-nerd-stats-switch'),
    );
    expect(switchFinder, findsOneWidget);

    final switchWidget = tester.widget<SwitchListTile>(switchFinder);
    expect(switchWidget.value, isFalse);

    // Built but below the 600 px test viewport: bring it on screen so the tap hits it.
    await tester.ensureVisible(switchFinder);
    await tester.pumpAndSettle();
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    final updatedSwitch = tester.widget<SwitchListTile>(switchFinder);
    expect(updatedSwitch.value, isTrue);
  });

  testWidgets('SettingsView configures step grouping in Appearance tab', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [daemonEndpointProvider.overrideWith((ref) async => null)],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
          home: Scaffold(
            body: SettingsView(onClose: () {}, initialTabIndex: 3),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var i = 0; i < 6; i++) {
      if (find
          .byKey(const ValueKey('settings-step-grouping-auto-collapse-switch'))
          .evaluate()
          .isNotEmpty) {
        // Drag a bit further to bring it fully into center of viewport
        await tester.drag(find.byType(ListView).first, const Offset(0, -150));
        await tester.pumpAndSettle();
        break;
      }
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pumpAndSettle();
    }

    final dropdownFinder = find.byKey(
      const ValueKey('settings-step-grouping-mode-dropdown'),
    );
    expect(dropdownFinder, findsOneWidget);

    final autoCollapseFinder = find.byKey(
      const ValueKey('settings-step-grouping-auto-collapse-switch'),
    );
    expect(autoCollapseFinder, findsOneWidget);

    final switchWidget = tester.widget<SwitchListTile>(autoCollapseFinder);
    expect(switchWidget.value, isTrue); // default is true

    await tester.ensureVisible(autoCollapseFinder);
    await tester.pumpAndSettle();
    await tester.tap(autoCollapseFinder);
    await tester.pumpAndSettle();

    final updatedSwitch = tester.widget<SwitchListTile>(autoCollapseFinder);
    expect(updatedSwitch.value, isFalse);
  });

  testWidgets(
    'SettingsView exposes an accessible back action and Escape closes it',
    (tester) async {
      var closed = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [daemonEndpointProvider.overrideWith((ref) async => null)],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
            home: Scaffold(body: SettingsView(onClose: () => closed = true)),
          ),
        ),
      );
      await tester.pump();

      final backButton = find.byKey(const ValueKey('settings-back-button'));
      expect(backButton, findsOneWidget);
      expect(
        tester.widget<IconButton>(backButton).tooltip,
        'Torna all\'area di lavoro',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(closed, isTrue);
    },
  );
}
