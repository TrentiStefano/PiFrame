import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'platform_environment.dart';

/// The result of a finished child process.
class ProcessOutput {
  final int exitCode;
  final String stdout;
  final String stderr;

  const ProcessOutput({required this.exitCode, this.stdout = '', this.stderr = ''});

  bool get succeeded => exitCode == 0;
}

/// Runs short child processes (CLI tools) to completion.
abstract class ProcessService {
  /// Runs [executable] with [arguments]. The environment defaults to the
  /// augmented PATH from [PlatformEnvironment].
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration? timeout,
    bool runInShell = false,
    Map<String, String>? environment,
  });
}

class IoProcessService implements ProcessService {
  const IoProcessService();

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration? timeout,
    bool runInShell = false,
    Map<String, String>? environment,
  }) async {
    final future = Process.run(
      executable,
      arguments,
      environment: environment ?? PlatformEnvironment.environment,
      runInShell: runInShell,
    );
    final result = await (timeout == null ? future : future.timeout(timeout));
    return ProcessOutput(exitCode: result.exitCode, stdout: '${result.stdout}', stderr: '${result.stderr}');
  }
}

final processServiceProvider = Provider<ProcessService>((ref) => const IoProcessService());
