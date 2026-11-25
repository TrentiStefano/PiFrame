import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/platform/process_service.dart';

List<String> _printEnvCommand(String name) =>
    Platform.isWindows ? ['cmd', '/c', 'echo %$name%'] : ['sh', '-c', 'printf "%s" "\$$name"'];

void main() {
  test('IoProcessService.start defaults the child environment to the augmented environment', () async {
    // Regression: start() passed a null environment, so a child started by the settings
    // CLI section did not get the augmented PATH (Homebrew and user bin directories on macOS).
    final service = IoProcessService(
      defaultEnvironment: () => {...Platform.environment, 'PIFRAME_DEFAULT_MARK': 'augmented-default'},
    );
    final command = _printEnvCommand('PIFRAME_DEFAULT_MARK');

    final process = await service.start(command.first, command.sublist(1));
    final stdout = await utf8.decodeStream(process.stdout);
    await process.exitCode;

    expect(stdout, contains('augmented-default'));
  });

  test('IoProcessService.start passes an explicit environment instead of the default', () async {
    final service = IoProcessService(
      defaultEnvironment: () => {...Platform.environment, 'PIFRAME_DEFAULT_MARK': 'augmented-default'},
    );
    final command = _printEnvCommand('PIFRAME_DEFAULT_MARK');

    final process = await service.start(
      command.first,
      command.sublist(1),
      environment: {...Platform.environment, 'PIFRAME_DEFAULT_MARK': 'explicit-value'},
    );
    final stdout = await utf8.decodeStream(process.stdout);
    await process.exitCode;

    expect(stdout, contains('explicit-value'));
    expect(stdout, isNot(contains('augmented-default')));
  });
}
