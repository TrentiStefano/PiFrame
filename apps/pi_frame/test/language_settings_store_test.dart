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

  test('without storage (tests, no home directory) the app starts in English', () {
    expect(AppLanguageNotifier(store: const LanguageSettingsStore(directory: null)).state, AppLanguage.en);
  });
}
