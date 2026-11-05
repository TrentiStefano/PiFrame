import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/metrics/nerd_stats_settings.dart';

void main() {
  group('NerdStatsSettings model', () {
    test('defaults to enabled == false', () {
      const settings = NerdStatsSettings();
      expect(settings.enabled, isFalse);
    });

    test('roundtrips toJson and fromJson for both true and false', () {
      const sTrue = NerdStatsSettings(enabled: true);
      final jsonTrue = sTrue.toJson();
      expect(jsonTrue['enabled'], isTrue);
      final loadedTrue = NerdStatsSettings.fromJson(jsonTrue);
      expect(loadedTrue.enabled, isTrue);
      expect(loadedTrue, equals(sTrue));

      const sFalse = NerdStatsSettings(enabled: false);
      final jsonFalse = sFalse.toJson();
      expect(jsonFalse['enabled'], isFalse);
      final loadedFalse = NerdStatsSettings.fromJson(jsonFalse);
      expect(loadedFalse.enabled, isFalse);
      expect(loadedFalse, equals(sFalse));
    });

    test('tolerant to missing, null, and invalid json fields', () {
      expect(NerdStatsSettings.fromJson(null).enabled, isFalse);
      expect(NerdStatsSettings.fromJson({}).enabled, isFalse);
      expect(NerdStatsSettings.fromJson({'enabled': null}).enabled, isFalse);
      expect(NerdStatsSettings.fromJson({'enabled': 'true'}).enabled, isFalse);
      expect(NerdStatsSettings.fromJson({'enabled': 1}).enabled, isFalse);
      expect(NerdStatsSettings.fromJson({'enabled': 0}).enabled, isFalse);
      expect(NerdStatsSettings.fromJson({'enabled': []}).enabled, isFalse);
      expect(NerdStatsSettings.fromJson({'enabled': {}}).enabled, isFalse);
      expect(NerdStatsSettings.fromJson({'otherKey': 'val'}).enabled, isFalse);
    });

    test('copyWith works correctly', () {
      const s = NerdStatsSettings(enabled: false);
      expect(s.copyWith(enabled: true).enabled, isTrue);
      expect(s.copyWith().enabled, isFalse);
    });

    test('equality and toString work properly', () {
      const a = NerdStatsSettings(enabled: true);
      const b = NerdStatsSettings(enabled: true);
      const c = NerdStatsSettings(enabled: false);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a.toString(), contains('enabled: true'));
    });
  });

  group('NerdStatsSettingsNotifier persistence', () {
    late Directory tempDir;
    late File testStorageFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('nerd_stats_settings_test_');
      testStorageFile = File('${tempDir.path}/nerd_stats_settings.json');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('persists state changes to injected storage file', () {
      final notifier = NerdStatsSettingsNotifier(storageFile: testStorageFile);
      expect(notifier.state.enabled, isFalse);

      notifier.setEnabled(true);
      expect(notifier.state.enabled, isTrue);
      expect(testStorageFile.existsSync(), isTrue);

      final content = testStorageFile.readAsStringSync();
      final map = jsonDecode(content) as Map<String, dynamic>;
      expect(map['enabled'], isTrue);

      notifier.setEnabled(false);
      expect(notifier.state.enabled, isFalse);
      final updatedContent = testStorageFile.readAsStringSync();
      final updatedMap = jsonDecode(updatedContent) as Map<String, dynamic>;
      expect(updatedMap['enabled'], isFalse);
    });

    test('loads persisted state from disk on initialization', () {
      testStorageFile.writeAsStringSync(jsonEncode({'enabled': true}));
      final notifier = NerdStatsSettingsNotifier(storageFile: testStorageFile);
      expect(notifier.state.enabled, isTrue);
    });
  });
}
