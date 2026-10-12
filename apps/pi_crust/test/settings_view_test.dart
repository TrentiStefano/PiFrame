import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust/features/settings/settings_view.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import 'package:pi_crust/data/daemon/daemon_providers.dart';
import 'package:pi_crust/data/daemon/pcp_client.dart';
import 'package:pi_crust/data/theme/theme_providers.dart';

class _PackageClient extends PcpClient {
  _PackageClient() : super(port: 1, token: 'test');
  String? pinnedSource;
  String? pinnedVersion;

  @override
  Future<Map<String, dynamic>> getDaemonConfig() async => {
    'data': {'workerIdleTimeoutMs': 1800000},
  };

  @override
  Future<Map<String, dynamic>> listPiPackages() async => {
    'data': {
      'packages': [
        {
          'source': 'npm:pi-caveman',
          'name': 'pi-caveman',
          'version': '0.1.15',
          'pinnedVersion': null,
        },
      ],
    },
  };

  @override
  Future<Map<String, dynamic>> pinPiPackage(
    String source,
    String version,
  ) async {
    pinnedSource = source;
    pinnedVersion = version;
    return {
      'data': {'source': '$source@$version'},
    };
  }
}

void main() {
  testWidgets('SettingsView exposes package list and version pin workflow', (
    tester,
  ) async {
    final client = _PackageClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          pcpClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [CrustTokens.dark]),
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
  });

  testWidgets('theme selector changes MaterialApp to the Catppuccin asset', (
    tester,
  ) async {
    final repository = ThemeRepository();
    addTearDown(repository.dispose);
    for (final flavor in ['light', 'dark']) {
      repository.registerThemeJson(
        File('assets/themes/crust-$flavor.json').readAsStringSync(),
      );
    }
    repository.setActiveTheme('crust-light');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          themeRepositoryProvider.overrideWithValue(repository),
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
      find.text(const Color(0xFFEFF1F5).toARGB32().toString()),
      findsOneWidget,
    );

    await tester.tap(find.text('ASPETTO'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Catppuccin Frappé (dark)').last);
    await tester.pumpAndSettle();

    expect(
      find.text(const Color(0xFF303446).toARGB32().toString()),
      findsOneWidget,
    );
  });

  testWidgets('SettingsView renders six settings tabs', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [daemonEndpointProvider.overrideWith((ref) async => null)],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [CrustTokens.dark]),
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
    ]) {
      await tester.ensureVisible(find.text(tab).first);
      expect(find.text(tab), findsOneWidget);
    }
  });

  testWidgets(
    'SettingsView enforces D16 Zero Remote Telemetry in Privacy tab',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [daemonEndpointProvider.overrideWith((ref) async => null)],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: [CrustTokens.dark]),
            home: Scaffold(
              body: SettingsView(onClose: () {}, initialTabIndex: 4),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Pi-Crust non invia alcun dato di utilizzo a server remoti.',
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
}
