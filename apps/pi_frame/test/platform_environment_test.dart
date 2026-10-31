import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/platform/platform_environment.dart';
import 'package:pi_frame/data/pi_install/pi_install_service.dart';

void main() {
  setUp(() {
    PlatformEnvironment.resetCache();
  });

  test('PlatformEnvironment returns search paths including system and home paths', () {
    final paths = PlatformEnvironment.searchPaths;
    expect(paths, isNotEmpty);

    final env = PlatformEnvironment.environment;
    expect(env['PATH'], isNotNull);
    expect(env['PATH']!.isNotEmpty, isTrue);
  });

  test('PlatformEnvironment findExecutable locates standard executables', () {
    // Both Windows and POSIX have cmd/sh or node in standard environments
    final exeName = Platform.isWindows ? 'cmd' : 'sh';
    final found = PlatformEnvironment.findExecutable(exeName);
    expect(found, isNotNull);
    expect(File(found!).existsSync(), isTrue);
  });

  test('PlatformEnvironment findExecutable returns null for non-existent binary', () {
    final found = PlatformEnvironment.findExecutable('non_existent_binary_xyz_123');
    expect(found, isNull);
  });

  test('DefaultPiInstallService isPiInstalled returns a boolean without throwing', () async {
    final service = DefaultPiInstallService();
    final result = await service.isPiInstalled();
    expect(result, isA<bool>());
  });
}

