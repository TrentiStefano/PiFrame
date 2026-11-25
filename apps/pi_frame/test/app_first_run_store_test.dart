import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/first_run/app_first_run_store.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pi_frame_first_run_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('without a storage file the intro plays once per launch outside tests (web behaviour)', () {
    // Regression: the web build has no preference file, and returning false there
    // silenced the startup intro that the web build played before.
    final store = AppFirstRunStore.forTesting(underTests: false);

    expect(store.consumeIntro(), isTrue);
    expect(store.consumeIntro(), isFalse);
  });

  test('under tests the intro never plays, even without a storage file', () {
    final store = AppFirstRunStore.forTesting(underTests: true);

    expect(store.consumeIntro(), isFalse);
    expect(store.consumeIntro(), isFalse);
  });

  test('with a storage file the intro plays once and the played state persists', () {
    final file = File('${tempDir.path}/app_first_run.json');
    final store = AppFirstRunStore.forTesting(underTests: false)..setStorageFileForTesting(file);

    expect(store.consumeIntro(), isTrue);
    expect(file.existsSync(), isTrue);

    final nextLaunch = AppFirstRunStore.forTesting(underTests: false)..setStorageFileForTesting(file);
    expect(nextLaunch.consumeIntro(), isFalse);
  });
}
