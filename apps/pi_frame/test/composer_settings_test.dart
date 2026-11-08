import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/composer/composer_settings.dart';

void main() {
  group('ComposerSettings model', () {
    test('defaults to sendWithEnter == false', () {
      const settings = ComposerSettings();
      expect(settings.sendWithEnter, isFalse);
    });

    test('roundtrips toJson and fromJson for both true and false', () {
      const sTrue = ComposerSettings(sendWithEnter: true);
      final jsonTrue = sTrue.toJson();
      expect(jsonTrue['sendWithEnter'], isTrue);
      final loadedTrue = ComposerSettings.fromJson(jsonTrue);
      expect(loadedTrue.sendWithEnter, isTrue);
      expect(loadedTrue, equals(sTrue));

      const sFalse = ComposerSettings(sendWithEnter: false);
      final jsonFalse = sFalse.toJson();
      expect(jsonFalse['sendWithEnter'], isFalse);
      final loadedFalse = ComposerSettings.fromJson(jsonFalse);
      expect(loadedFalse.sendWithEnter, isFalse);
      expect(loadedFalse, equals(sFalse));
    });

    test('tolerant to missing, null, and invalid json fields', () {
      expect(ComposerSettings.fromJson(null).sendWithEnter, isFalse);
      expect(ComposerSettings.fromJson({}).sendWithEnter, isFalse);
      expect(ComposerSettings.fromJson({'sendWithEnter': null}).sendWithEnter, isFalse);
      expect(ComposerSettings.fromJson({'sendWithEnter': 'true'}).sendWithEnter, isFalse);
      expect(ComposerSettings.fromJson({'sendWithEnter': 1}).sendWithEnter, isFalse);
      expect(ComposerSettings.fromJson({'sendWithEnter': 0}).sendWithEnter, isFalse);
      expect(ComposerSettings.fromJson({'sendWithEnter': []}).sendWithEnter, isFalse);
      expect(ComposerSettings.fromJson({'sendWithEnter': {}}).sendWithEnter, isFalse);
      expect(ComposerSettings.fromJson({'otherKey': 'val'}).sendWithEnter, isFalse);
    });

    test('copyWith works correctly', () {
      const s = ComposerSettings(sendWithEnter: false);
      expect(s.copyWith(sendWithEnter: true).sendWithEnter, isTrue);
      expect(s.copyWith().sendWithEnter, isFalse);
    });
  });

  group('ComposerSettingsNotifier persistence', () {
    late Directory tempDir;
    late File testStorageFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('composer_settings_test_');
      testStorageFile = File('${tempDir.path}/composer_settings.json');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('persists state changes to injected storage file', () {
      final notifier = ComposerSettingsNotifier(storageFile: testStorageFile);
      expect(notifier.state.sendWithEnter, isFalse);

      notifier.setSendWithEnter(true);
      expect(notifier.state.sendWithEnter, isTrue);
      expect(testStorageFile.existsSync(), isTrue);

      final decoded = jsonDecode(testStorageFile.readAsStringSync()) as Map<String, dynamic>;
      expect(decoded['sendWithEnter'], isTrue);

      // Reloading from same file preserves true
      final reloadedNotifier = ComposerSettingsNotifier(storageFile: testStorageFile);
      expect(reloadedNotifier.state.sendWithEnter, isTrue);

      // Flipping back saves false
      reloadedNotifier.setSendWithEnter(false);
      expect(reloadedNotifier.state.sendWithEnter, isFalse);
      final decoded2 = jsonDecode(testStorageFile.readAsStringSync()) as Map<String, dynamic>;
      expect(decoded2['sendWithEnter'], isFalse);
    });

    test('gracefully falls back to default on corrupted storage file', () {
      testStorageFile.writeAsStringSync('{{{ not valid json !!!');
      final notifier = ComposerSettingsNotifier(storageFile: testStorageFile);
      expect(notifier.state.sendWithEnter, isFalse);
    });
  });
}
