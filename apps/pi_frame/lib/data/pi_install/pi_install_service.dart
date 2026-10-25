import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      final home = Platform.isWindows
          ? (env['USERPROFILE'] ?? 'C:\\Users\\Default')
          : (env['HOME'] ?? '/tmp');
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
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
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
      final data = {
        'firstRunCompleted': true,
        'timestamp': DateTime.now().toIso8601String(),
      };
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  @override
  Future<bool> isPiInstalled() async {
    // A remote browser cannot probe the host shell; the daemon already reports
    // Pi capabilities through PCP.
    if (kIsWeb) return true;
    try {
      final ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run(
          'cmd.exe',
          ['/c', 'pi', '--version'],
          runInShell: true,
        ).timeout(const Duration(seconds: 5));
      } else {
        result = await Process.run(
          'pi',
          ['--version'],
          runInShell: true,
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
      yield 'L\'installazione della CLI Pi è disponibile solo su desktop.\n';
      return;
    }
    yield 'Inizializzazione installazione di @earendil-works/pi-coding-agent...\n';
    final controller = StreamController<String>();

    try {
      final Process process;
      if (Platform.isWindows) {
        process = await Process.start(
          'cmd.exe',
          ['/c', 'npm', 'install', '-g', '@earendil-works/pi-coding-agent'],
          runInShell: true,
        );
      } else {
        process = await Process.start(
          'npm',
          ['install', '-g', '@earendil-works/pi-coding-agent'],
          runInShell: true,
        );
      }

      process.stdout.listen((bytes) {
        controller.add(utf8.decode(bytes, allowMalformed: true));
      });

      process.stderr.listen((bytes) {
        controller.add(utf8.decode(bytes, allowMalformed: true));
      });

      process.exitCode.then((code) {
        if (code == 0) {
          controller.add('\n[SUCCESSO] @earendil-works/pi-coding-agent installato con successo!\n');
        } else {
          controller.add('\n[ERRORE] Processo di installazione terminato con codice: $code\n');
        }
        controller.close();
      }).catchError((err) {
        controller.add('\n[ERRORE] $err\n');
        controller.close();
      });

      yield* controller.stream;
    } catch (e) {
      yield '\n[ERRORE] Impossibile avviare il processo di installazione: $e\n';
    }
  }
}

final piInstallServiceProvider = Provider<PiInstallService>((ref) {
  return DefaultPiInstallService();
});
