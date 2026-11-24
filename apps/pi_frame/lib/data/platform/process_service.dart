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

/// A child process that stays alive: output arrives as byte streams and input
/// is written to its standard input.
abstract class RunningProcess {
  Stream<List<int>> get stdout;

  Stream<List<int>> get stderr;

  /// Completes with the exit code when the process ends.
  Future<int> get exitCode;

  /// Writes [bytes] to the process's standard input.
  void writeBytes(List<int> bytes);

  /// Writes [line] followed by a newline to the process's standard input.
  void writeLine(String line);

  /// Asks the process to stop. Returns false when it had already ended.
  bool kill();
}

/// Runs child processes (CLI tools) to completion, or starts one that stays alive.
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

  /// Starts [executable] and returns without waiting for it to finish.
  Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell = false,
  });
}

class IoRunningProcess implements RunningProcess {
  final Process _process;

  IoRunningProcess(this._process);

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void writeBytes(List<int> bytes) => _process.stdin.add(bytes);

  @override
  void writeLine(String line) => _process.stdin.writeln(line);

  @override
  bool kill() => _process.kill();
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

  @override
  Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell = false,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: runInShell,
    );
    return IoRunningProcess(process);
  }
}

final processServiceProvider = Provider<ProcessService>((ref) => const IoProcessService());
