import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_crust/data/update/github_update_client.dart';
import 'package:pi_crust/data/update/installer_launcher.dart';
import 'package:pi_crust/data/update/update_providers.dart';
import 'package:pi_crust/data/update/update_storage.dart';
import 'package:pi_crust/domain/update/update_models.dart';
import 'package:pi_crust/features/settings/updates_section.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

class _FakeUpdateClient implements UpdateClient {
  AppRelease? nextRelease;

  @override
  Future<AppRelease?> fetchLatestRelease() async => nextRelease;

  @override
  Stream<DownloadProgress> downloadAsset({
    required ReleaseAsset asset,
    required String destinationPath,
    Future<void>? cancelSignal,
  }) async* {
    yield const DownloadProgress(downloadedBytes: 100, totalBytes: 100, fraction: 1.0);
  }
}

class _FakeInstallerLauncher implements InstallerLauncher {
  bool launched = false;
  String? openedUrl;

  @override
  Future<void> launchInstaller(String filePath, {required AppRelease release}) async {
    launched = true;
  }

  @override
  Future<void> openReleasePage(String url) async {
    openedUrl = url;
  }
}

void main() {
  testWidgets('UpdatesSection renders current version and check button', (
    tester,
  ) async {
    final client = _FakeUpdateClient();
    final storage = MemoryUpdateStorage();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateClientProvider.overrideWithValue(client),
          updateStorageProvider.overrideWithValue(storage),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [CrustTokens.dark]),
          home: const Scaffold(body: UpdatesSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aggiornamenti Pi-Crust'), findsOneWidget);
    expect(find.textContaining('Versione installata:'), findsOneWidget);
    expect(find.byKey(const ValueKey('check_for_updates_button')), findsOneWidget);

    // Initial opt-in state: unchecked by default
    final checkbox = tester.widget<Switch>(find.byType(Switch));
    expect(checkbox.value, isFalse);
    expect(find.text('Frequenza di controllo:'), findsNothing);
  });

  testWidgets('opt-in checkbox toggles and reveals frequency dropdown', (
    tester,
  ) async {
    final client = _FakeUpdateClient();
    final storage = MemoryUpdateStorage();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateClientProvider.overrideWithValue(client),
          updateStorageProvider.overrideWithValue(storage),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [CrustTokens.dark]),
          home: const Scaffold(body: UpdatesSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Toggle switch on
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    // Now frequency dropdown should be visible
    expect(find.text('Frequenza di controllo:'), findsOneWidget);
    expect(find.text('Ogni settimana (consigliato)'), findsOneWidget);

    // Tap dropdown and change to 'Ogni giorno'
    await tester.tap(find.text('Ogni settimana (consigliato)'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ogni giorno').last);
    await tester.pumpAndSettle();

    expect(find.text('Ogni giorno'), findsOneWidget);
  });

  testWidgets('displays up-to-date card when check returns no newer release', (
    tester,
  ) async {
    final client = _FakeUpdateClient();
    client.nextRelease = AppRelease(
      tagName: 'v1.3.0',
      name: 'v1.3.0',
      body: 'Current version',
      htmlUrl: 'https://github.com/TrentiStefano/pi-crust/releases/tag/v1.3.0',
      assets: const [],
    );
    final storage = MemoryUpdateStorage();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateClientProvider.overrideWithValue(client),
          updateStorageProvider.overrideWithValue(storage),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [CrustTokens.dark]),
          home: const Scaffold(body: UpdatesSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('check_for_updates_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Pi-Crust è aggiornato all\'ultima versione disponibile'),
      findsOneWidget,
    );
  });

  testWidgets('displays update available card, download, and install dialog', (
    tester,
  ) async {
    final client = _FakeUpdateClient();
    final launcher = _FakeInstallerLauncher();
    client.nextRelease = AppRelease(
      tagName: 'v1.4.0',
      name: 'Pi-Crust v1.4.0',
      body: 'Nuova versione con supporto ad aggiornamenti automatici!',
      htmlUrl: 'https://github.com/TrentiStefano/pi-crust/releases/tag/v1.4.0',
      assets: [
        const ReleaseAsset(
          name: 'Pi-Crust-Setup-1.4.0-windows-x64.exe',
          downloadUrl: 'https://github.com/TrentiStefano/pi-crust/releases/download/v1.4.0/Pi-Crust-Setup-1.4.0-windows-x64.exe',
          size: 52428800,
          contentType: 'application/octet-stream',
        ),
      ],
    );
    final storage = MemoryUpdateStorage();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateClientProvider.overrideWithValue(client),
          installerLauncherProvider.overrideWithValue(launcher),
          updateStorageProvider.overrideWithValue(storage),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [CrustTokens.dark]),
          home: const Scaffold(body: UpdatesSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap check for updates
    await tester.tap(find.byKey(const ValueKey('check_for_updates_button')));
    await tester.pumpAndSettle();

    expect(find.text('Pi-Crust v1.4.0'), findsOneWidget);
    expect(find.textContaining('Nuova versione con supporto ad aggiornamenti automatici!'), findsOneWidget);
    expect(find.text('Scarica aggiornamento'), findsOneWidget);

    // Tap download
    await tester.tap(find.text('Scarica aggiornamento'));
    await tester.pumpAndSettle();

    // Now ready to install
    expect(find.text('Installa e Riavvia'), findsOneWidget);
    expect(find.text('Pronto per l\'installazione'), findsOneWidget);

    // Tap install button -> confirmation dialog should open
    await tester.tap(find.text('Installa e Riavvia'));
    await tester.pumpAndSettle();

    expect(find.text('Confermare installazione?'), findsOneWidget);
    // Confirm install in dialog
    await tester.tap(find.text('Installa e Riavvia').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(launcher.launched, isTrue);
  });
}
