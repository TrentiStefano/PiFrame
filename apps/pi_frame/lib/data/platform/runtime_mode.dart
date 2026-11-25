import 'dart:io';

import 'package:flutter/foundation.dart';

/// True when the app runs under `flutter test`. Stores then keep no files, so tests stay hermetic.
bool get isRunningUnderTests => !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

/// True when preference files can live in the user's home directory: not on the web build,
/// and not under the test runner. The web build keeps its preferences in memory instead.
bool get usesHomeDirectoryStorage => !kIsWeb && !isRunningUnderTests;
