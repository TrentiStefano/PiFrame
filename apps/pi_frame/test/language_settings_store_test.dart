import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/language/language_settings.dart';

/// The default-language rule (#56): new installs start in English, existing
/// users whose saved settings have no language keep Italian, an explicit
/// choice always wins.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('piframe_language_'));
  tearDown(() => dir.deleteSync(recursive: true));

  LanguageSettingsStore store() => LanguageSettingsStore(directory: dir);

  void writeJson(String name, Object value) => File('${dir.path}/$name').writeAsStringSync(jsonEncode(value));

  test('no saved settings: English', () {
    expect(store().load(), AppLanguage.en);
  });

  test('a missing settings directory counts as no saved settings: English', () {
    dir.deleteSync(recursive: true);
    expect(store().load(), AppLanguage.en);
    dir.createSync();
  });

  test('saved settings without a language: Italian (existing users)', () {
    writeJson('theme_settings.json', {'activeThemeId': 'piframe-dark'});
    expect(store().load(), AppLanguage.it);
  });

  test('a new install with an unrelated JSON file in the folder still gets English', () {
    writeJson('notes.json', {'todo': 'try PiFrame'});
    expect(store().load(), AppLanguage.en);
  });

  test('every known PiFrame settings file marks an existing user', () {
    expect(LanguageSettingsStore.knownSettingsFiles, contains('theme_settings.json'));
    for (final name in LanguageSettingsStore.knownSettingsFiles) {
      for (final file in dir.listSync()) {
        file.deleteSync();
      }
      writeJson(name, <String, Object>{});
      expect(store().load(), AppLanguage.it, reason: name);
    }
  });

  test('a language file without a language entry: Italian', () {
    writeJson('language_settings.json', <String, Object>{});
    expect(store().load(), AppLanguage.it);
  });

  test('explicit English wins over other saved settings', () {
    writeJson('theme_settings.json', {'activeThemeId': 'piframe-dark'});
    writeJson('language_settings.json', {'language': 'en'});
    expect(store().load(), AppLanguage.en);
  });

  test('explicit Italian wins', () {
    writeJson('language_settings.json', {'language': 'it'});
    expect(store().load(), AppLanguage.it);
  });

  test('the first resolution is saved, so files written later do not change it', () {
    expect(store().load(), AppLanguage.en);
    writeJson('window_state.json', {'width': 1200});
    expect(store().load(), AppLanguage.en);
  });

  test('a saved choice round-trips', () {
    store().save(AppLanguage.it);
    expect(store().load(), AppLanguage.it);
    store().save(AppLanguage.en);
    expect(store().load(), AppLanguage.en);
  });

  test('the notifier starts from the store and saves choices to it', () {
    writeJson('theme_settings.json', {'activeThemeId': 'piframe-dark'});
    final notifier = AppLanguageNotifier(store: store());
    expect(notifier.state, AppLanguage.it);
    notifier.setLanguage(AppLanguage.en);
    expect(store().load(), AppLanguage.en);
  });

  group('web client', () {
    test('with no saved choice, an Italian browser starts in Italian', () {
      expect(webLanguage(saved: null, browser: 'it-IT'), AppLanguage.it);
      expect(webLanguage(saved: null, browser: 'it'), AppLanguage.it);
    });

    test('with no saved choice, an English browser starts in English', () {
      expect(webLanguage(saved: null, browser: 'en-GB'), AppLanguage.en);
    });

    test('with no saved choice, any other or unknown browser language starts in English', () {
      expect(webLanguage(saved: null, browser: 'fr-FR'), AppLanguage.en);
      expect(webLanguage(saved: null, browser: 'italic'), AppLanguage.en);
      expect(webLanguage(saved: null, browser: null), AppLanguage.en);
    });

    test('a saved choice wins over the browser language', () {
      expect(webLanguage(saved: 'en', browser: 'it-IT'), AppLanguage.en);
      expect(webLanguage(saved: 'it', browser: 'en-US'), AppLanguage.it);
    });
  });

  test('without storage (tests, no home directory) the app starts in English', () {
    expect(AppLanguageNotifier(store: const LanguageSettingsStore(directory: null)).state, AppLanguage.en);
  });
}
