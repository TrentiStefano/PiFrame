import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:pi_frame/data/window/window_state_service.dart';
import 'package:pi_frame/ui/startup_audio.dart';
import 'package:pi_frame/ui/startup_assemble_animation.dart';

void main() {
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
      const customState = WindowState(
        width: 1440,
        height: 900,
        x: 120,
        y: 80,
        isFullScreen: true,
        isMaximized: false,
      );

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

    test('StartupAudio play methods do not crash in test environment', () {
      expect(() => StartupAudio.playCiak(), returnsNormally);
      expect(() => StartupAudio.playHum(), returnsNormally);
      expect(() => StartupAudio.dispose(), returnsNormally);
    });
  });

  group('StartupAssembleOverlay tests', () {
    Widget wrapWithTheme(Widget child) {
      return MaterialApp(
        theme: ThemeData.dark().copyWith(
          extensions: const [FrameTokens.dark],
        ),
        home: Scaffold(body: child),
      );
    }

    testWidgets('renders child and finishes immediately in test mode or on tap', (tester) async {
      var completed = false;

      await tester.pumpWidget(
        wrapWithTheme(
          StartupAssembleOverlay(
            autoStart: true,
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

    testWidgets('can be tapped to dismiss overlay', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          StartupAssembleOverlay(
            autoStart: false,
            child: const Text('App Ready'),
          ),
        ),
      );
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
