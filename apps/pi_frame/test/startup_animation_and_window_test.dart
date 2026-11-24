import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame/data/first_run/app_first_run_store.dart';
import 'package:pi_frame/data/motion/startup_animation_settings.dart';
import 'package:pi_frame/data/window/window_state_service.dart';
import 'package:pi_frame/ui/startup_audio.dart';
import 'package:pi_frame/ui/startup_assemble_animation.dart';

void main() {
  group('Startup intro gating (task 7.8)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('pi_frame_intro_test_');
    });

    tearDown(() {
      AppFirstRunStore.instance.setStorageFileForTesting(null);
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('first run flag is true exactly once per install', () {
      final file = File('${tempDir.path}/app_first_run.json');
      AppFirstRunStore.instance.setStorageFileForTesting(file);

      expect(AppFirstRunStore.instance.consumeIntro(), isTrue);
      expect(AppFirstRunStore.instance.consumeIntro(), isFalse);
      expect(file.existsSync(), isTrue);
    });

    test('settings default to off and round-trip through JSON', () {
      const defaults = StartupAnimationSettings();
      expect(defaults.enabled, isFalse);
      expect(StartupAnimationSettings.fromJson(const StartupAnimationSettings(enabled: true).toJson()).enabled, isTrue);
      expect(StartupAnimationSettings.fromJson({'enabled': 'yes'}).enabled, isFalse);
    });

    test('intro plays on the first run, or every launch when the setting is on', () {
      ProviderContainer makeContainer({required bool firstRun, required bool settingOn}) {
        final container = ProviderContainer(
          overrides: [
            appIntroFirstRunProvider.overrideWithValue(firstRun),
            startupAnimationSettingsProvider.overrideWith(
              (ref) =>
                  StartupAnimationSettingsNotifier(storageFile: File('${tempDir.path}/startup_animation_settings.json'))
                    ..setEnabled(settingOn),
            ),
          ],
        );
        addTearDown(container.dispose);
        return container;
      }

      expect(makeContainer(firstRun: false, settingOn: false).read(startupIntroPlaysProvider), isFalse);
      expect(makeContainer(firstRun: true, settingOn: false).read(startupIntroPlaysProvider), isTrue);
      expect(makeContainer(firstRun: false, settingOn: true).read(startupIntroPlaysProvider), isTrue);
    });

    test('toggling the setting persists it to the storage file', () {
      final file = File('${tempDir.path}/startup_animation_settings.json');
      final notifier = StartupAnimationSettingsNotifier(storageFile: file);

      notifier.setEnabled(true);
      expect(file.existsSync(), isTrue);
      expect(StartupAnimationSettingsNotifier(storageFile: file).state.enabled, isTrue);
    });
  });

  group('WindowStateService tests', () {
    late Directory tempDir;
    late File stateFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('pi_frame_window_test_');
      stateFile = File('${tempDir.path}/window_state.json');
      WindowStateService.instance.setStorageFileForTesting(stateFile);
    });

    tearDown(() {
      WindowStateService.instance.setStorageFileForTesting(null);
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('default window state is non-fullscreen with default dimensions', () async {
      final state = await WindowStateService.instance.loadState();
      expect(state.isFullScreen, isFalse);
      expect(state.isMaximized, isFalse);
      expect(state.width, 1100);
      expect(state.height, 720);
    });

    test('persists custom window state and restores correctly', () async {
      const customState = WindowState(width: 1440, height: 900, x: 120, y: 80, isFullScreen: true, isMaximized: false);

      await WindowStateService.instance.saveState(customState);
      expect(stateFile.existsSync(), isTrue);

      final reloaded = await WindowStateService.instance.loadState();
      expect(reloaded.width, 1440);
      expect(reloaded.height, 900);
      expect(reloaded.x, 120);
      expect(reloaded.y, 80);
      expect(reloaded.isFullScreen, isTrue);
      expect(reloaded.isMaximized, isFalse);
    });
  });

  group('StartupAudio synthesis tests', () {
    test('generateCiakWav produces valid 16-bit PCM RIFF WAVE header', () {
      final bytes = StartupAudio.generateCiakWav();
      expect(bytes.length, greaterThan(44));

      // Check RIFF header magic bytes
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(bytes.sublist(12, 16)), 'fmt ');
      expect(String.fromCharCodes(bytes.sublist(36, 40)), 'data');
    });

    test('generateHumWav produces valid 16-bit PCM RIFF WAVE header', () {
      final bytes = StartupAudio.generateHumWav();
      expect(bytes.length, greaterThan(44));

      // Check RIFF header magic bytes
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(bytes.sublist(12, 16)), 'fmt ');
      expect(String.fromCharCodes(bytes.sublist(36, 40)), 'data');
    });

    test('wavFor returns the clip of each startup sound', () {
      expect(StartupAudio.wavFor(StartupSound.ciak), StartupAudio.generateCiakWav());
      expect(StartupAudio.wavFor(StartupSound.hum), StartupAudio.generateHumWav());
    });
  });

  group('StartupAssembleOverlay tests', () {
    Widget wrapWithTheme(Widget child) {
      return MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: Scaffold(body: child),
      );
    }

    testWidgets('renders child and finishes immediately when the intro is skipped', (tester) async {
      var completed = false;

      await tester.pumpWidget(
        wrapWithTheme(
          StartupAssembleOverlay(
            autoStart: true,
            skipIntro: true,
            onAnimationComplete: () => completed = true,
            child: const Text('Main App Content'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The main content is always in the tree
      expect(find.text('Main App Content'), findsOneWidget);
      expect(completed, isTrue);
    });

    testWidgets('reports the ciak and hum cues to onSound as the intro plays', (tester) async {
      final sounds = <StartupSound>[];

      await tester.pumpWidget(
        wrapWithTheme(StartupAssembleOverlay(onSound: sounds.add, child: const Text('Main App Content'))),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      expect(sounds, [StartupSound.ciak, StartupSound.hum]);
    });

    testWidgets('can be tapped to dismiss overlay', (tester) async {
      await tester.pumpWidget(wrapWithTheme(StartupAssembleOverlay(autoStart: false, child: const Text('App Ready'))));
      await tester.pump();

      // Overlay should be present when autoStart is false and not completed
      final overlayFinder = find.byKey(const ValueKey('startup-assemble-overlay'));
      expect(overlayFinder, findsOneWidget);
      expect(find.text('PIFRAME'), findsOneWidget);

      // Tap to dismiss
      await tester.tap(overlayFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // After dismissal, overlay is gone and app content remains
      expect(find.byKey(const ValueKey('startup-assemble-overlay')), findsNothing);
      expect(find.text('App Ready'), findsOneWidget);
    });
  });
}
