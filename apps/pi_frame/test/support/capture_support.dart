import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the app's typefaces and its icon font, so a test renders text the way the app does.
Future<void> loadAppFonts() async {
  for (final font in ['SchibstedGrotesk', 'SourceCodePro']) {
    await (FontLoader(font)..addFont(rootBundle.load('assets/fonts/$font.ttf'))).load();
  }
  await (FontLoader('BarlowCondensed')
        ..addFont(rootBundle.load('assets/fonts/BarlowCondensed-SemiBold.ttf'))
        ..addFont(rootBundle.load('assets/fonts/BarlowCondensed-Bold.ttf')))
      .load();
  await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

/// A temporary folder for the captures a test writes when the tracked evidence is not refreshed. It is created on first
/// use; [deleteOnTearDownAll] removes it when the file's tests finish, so a plain `flutter test` leaves nothing behind.
class TemporaryCaptureFolder {
  TemporaryCaptureFolder(this._prefix);

  final String _prefix;
  Directory? _created;

  Directory get directory => _created ??= Directory.systemTemp.createTempSync(_prefix);

  /// Registers the cleanup; call it from `main`.
  void deleteOnTearDownAll() {
    tearDownAll(() {
      _created?.deleteSync(recursive: true);
      _created = null;
    });
  }
}
