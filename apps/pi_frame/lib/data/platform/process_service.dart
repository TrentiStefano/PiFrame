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

/// A child process that is still running. Its output arrives while it runs, and
/// input can be written to its standard input.
abstract class RunningProcess {
  Stream<List<int>> get stdout;

  Stream<List<int>> get stderr;

  /// Completes with the exit code when the process ends.
  Future<int> get exitCode;

  /// Writes [bytes] to the process's standard input.
  void writeBytes(List<int> bytes);

  /// Writes [line] followed by a newline to the process's standard input.
  void writeLine(String line);

  /// Stops the process. Returns false when it had already exited.
  bool kill();
}

/// Runs child processes (CLI tools) on the host.
abstract class ProcessService {
  /// Runs [executable] with [arguments] to completion. The environment defaults to the
  /// augmented PATH from [PlatformEnvironment].
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration? timeout,
    String? workingDirectory,
    bool runInShell = false,
    Map<String, String>? environment,
  });

  /// Starts [executable] and returns at once, so the caller can read its output and kill it.
  /// The process runs in [workingDirectory] when given, else in the app's directory.
  Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell = false,
    Map<String, String>? environment,
  });
}

class IoRunningProcess implements RunningProcess {
  IoRunningProcess(this._process);

  final Process _process;

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
    String? workingDirectory,
    bool runInShell = false,
    Map<String, String>? environment,
  }) async {
    final future = Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
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
    Map<String, String>? environment,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: runInShell,
    );
    return IoRunningProcess(process);
  }
}

final processServiceProvider = Provider<ProcessService>((ref) => const IoProcessService());
