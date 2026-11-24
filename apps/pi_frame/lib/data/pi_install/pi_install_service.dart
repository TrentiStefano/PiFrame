import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/platform_environment.dart';
import '../platform/runtime_mode.dart';

abstract class PiInstallService {
  Future<bool> isFirstRun();
  Future<void> markFirstRunCompleted();
  Future<bool> isPiInstalled();
  Stream<String> installPiAgent();
}

class DefaultPiInstallService implements PiInstallService {
  final File? _customConfigFile;

  DefaultPiInstallService([this._customConfigFile]);

  File? _resolveFirstRunFile() {
    if (_customConfigFile != null) return _customConfigFile;
    if (kIsWeb) return null;
    try {
      final env = Platform.environment;
      final home = Platform.isWindows ? (env['USERPROFILE'] ?? 'C:\\Users\\Default') : (env['HOME'] ?? '/tmp');
      final dir = Directory('$home/.piframe');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return File('${dir.path}/first_run.json');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> isFirstRun() async {
    // The browser never installs the Pi CLI: dart:io Platform throws there.
    if (kIsWeb) return false;
    // Avoid showing first-run dialog automatically in automated test environments unless overridden
    if (isRunningUnderTests) {
      return false;
    }
    final file = _resolveFirstRunFile();
    if (file == null) return false;
    if (!file.existsSync()) {
      return true;
    }
    try {
      final content = await file.readAsString();
      final json = jsonDecode(content);
      if (json is Map<String, dynamic>) {
        return json['firstRunCompleted'] != true;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<void> markFirstRunCompleted() async {
    final file = _resolveFirstRunFile();
    if (file == null) return;
    try {
      final data = {'firstRunCompleted': true, 'timestamp': DateTime.now().toIso8601String()};
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  @override
  Future<bool> isPiInstalled() async {
    // A remote browser cannot probe the host shell; the daemon already reports
    // Pi capabilities through PCP.
    if (kIsWeb) return true;
    try {
      final piExe = PlatformEnvironment.findExecutable('pi');
      final target = piExe ?? 'pi';
      final ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run(
          'cmd.exe',
          ['/c', target, '--version'],
          environment: PlatformEnvironment.environment,
          runInShell: true,
        ).timeout(const Duration(seconds: 5));
      } else {
        result = await Process.run(
          target,
          ['--version'],
          environment: PlatformEnvironment.environment,
          runInShell: piExe == null,
        ).timeout(const Duration(seconds: 5));
      }
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<String> installPiAgent() async* {
    if (kIsWeb) {
      yield 'Installing the Pi CLI is only available on desktop.\n';
      return;
    }
    yield 'Starting the official Pi Coding Agent install...\n';
    final controller = StreamController<String>();

    try {
      final Process process;
      if (Platform.isWindows) {
        yield 'Running the official Windows command: irm https://pi.dev/install.ps1 | iex\n\n';
        process = await Process.start(
          'powershell.exe',
          ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', 'irm https://pi.dev/install.ps1 | iex'],
          environment: PlatformEnvironment.environment,
          runInShell: true,
        );
      } else {
        yield 'Running the official command: curl -fsSL https://pi.dev/install.sh | sh\n';
        yield 'Checking system prerequisites...\n\n';

        final nodePath = PlatformEnvironment.findExecutable('node');
        final npmPath = PlatformEnvironment.findExecutable('npm');
        final brewPath = PlatformEnvironment.findExecutable('brew');

        final String script;
        if (nodePath == null || npmPath == null) {
          if (brewPath != null) {
            script = 'echo "Installing the Node.js prerequisite with Homebrew..."; brew install node && curl -fsSL https://pi.dev/install.sh | sh';
          } else {
            // Standalone Node.js bootstrap into ~/.local/share/pi-node/current
            script = '''
ARCH=\$(uname -m)
case "\$ARCH" in
  arm64|aarch64) N_ARCH="arm64" ;;
  *) N_ARCH="x64" ;;
esac
OS=\$(uname -s | tr '[:upper:]' '[:lower:]')
NODE_BASE="\$HOME/.local/share/pi-node"
mkdir -p "\$NODE_BASE"
echo "Downloading the standalone Node.js runtime for \$OS-\$N_ARCH..."
curl -fsSL "https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt" -o "\$NODE_BASE/SHASUMS.txt" 2>/dev/null || true
TAR_NAME=\$(grep "node-v.*-\$OS-\$N_ARCH\\.tar\\.gz" "\$NODE_BASE/SHASUMS.txt" 2>/dev/null | awk '{print \$2}' | head -n 1)
if [ -n "\$TAR_NAME" ]; then
  curl -fsSL "https://nodejs.org/dist/latest-v22.x/\$TAR_NAME" | tar -xz -C "\$NODE_BASE"
  DIR_NAME="\${TAR_NAME%.tar.gz}"
  rm -rf "\$NODE_BASE/current"
  ln -sfn "\$NODE_BASE/\$DIR_NAME" "\$NODE_BASE/current"
  export PATH="\$NODE_BASE/current/bin:\$PATH"
  echo "Node.js set up in \$NODE_BASE/current/bin"
fi
curl -fsSL https://pi.dev/install.sh | sh
''';
          }
        } else {
          script = 'curl -fsSL https://pi.dev/install.sh | sh';
        }

        process = await Process.start(
          '/bin/sh',
          ['-c', script],
          environment: PlatformEnvironment.environment,
          runInShell: false,
        );
      }

      process.stdout.listen((bytes) {
        controller.add(utf8.decode(bytes, allowMalformed: true));
      });

      process.stderr.listen((bytes) {
        controller.add(utf8.decode(bytes, allowMalformed: true));
      });

      unawaited(
        process.exitCode
            .then((code) {
              PlatformEnvironment.resetCache();
              if (code == 0) {
                controller.add('\n[SUCCESS] Pi Coding Agent installed successfully!\n');
              } else {
                controller.add('\n[ERROR] Install process exited with code: $code\n');
              }
              unawaited(controller.close());
            })
            .catchError((err) {
              controller.add('\n[ERROR] $err\n');
              unawaited(controller.close());
            }),
      );

      yield* controller.stream;
    } catch (e) {
      yield '\n[ERROR] Could not start the install process: $e\n';
    }
  }
}

final piInstallServiceProvider = Provider<PiInstallService>((ref) {
  return DefaultPiInstallService();
});
