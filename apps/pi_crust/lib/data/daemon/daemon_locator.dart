import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class DaemonEndpoint {
  final int port;
  final String token;

  const DaemonEndpoint({required this.port, required this.token});
}

class DaemonLocator {
  static String get _homeDir {
    final env = Platform.environment;
    if (Platform.isWindows) {
      return env['USERPROFILE'] ?? 'C:\\Users\\Default';
    }
    return env['HOME'] ?? '/tmp';
  }

  static String get _runtimeDir {
    final custom = Platform.environment['PI_CRUST_HOME'];
    if (custom != null && custom.isNotEmpty) {
      return '$custom/runtime';
    }
    return '$_homeDir/.pi-crust/runtime';
  }

  static Future<DaemonEndpoint?> locateOrProbe({bool autoSpawn = true}) async {
    if (kIsWeb) {
      // Browsers cannot inspect native runtime files. Use daemon-hosted same-origin bootstrap.
      final base = Uri.base;
      if (base.host != '127.0.0.1' && base.host != 'localhost') return null;
      try {
        final response = await http.get(base.resolve('/api/session-bootstrap'))
            .timeout(const Duration(seconds: 3));
        if (response.statusCode != 200) return null;
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final token = data['token'] as String?;
        if (token == null || token.isEmpty) return null;
        return DaemonEndpoint(port: base.port, token: token);
      } catch (_) {
        return null;
      }
    }
    // 1. Try reading existing runtime files and health probe
    var endpoint = await _probeActiveDaemon();
    if (endpoint != null) {
      return endpoint;
    }

    if (!autoSpawn) return null;

    // 2. On-demand launch of sidecar daemon (D8)
    final launched = await _spawnSidecarDaemon();
    if (!launched) return null;

    // 3. Poll for readiness (100ms interval, up to 10s timeout)
    const timeout = Duration(seconds: 10);
    final stopwatch = Stopwatch()..start();

    while (stopwatch.elapsed < timeout) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      endpoint = await _probeActiveDaemon();
      if (endpoint != null) {
        return endpoint;
      }
    }

    return null;
  }

  static Future<DaemonEndpoint?> _probeActiveDaemon() async {
    final jsonFile = File('$_runtimeDir/daemon.json');
    final tokenFile = File('$_runtimeDir/daemon.token');

    if (await jsonFile.exists() && await tokenFile.exists()) {
      try {
        final jsonContent = await jsonFile.readAsString();
        final token = (await tokenFile.readAsString()).trim();
        final data = jsonDecode(jsonContent) as Map<String, dynamic>;
        final port = data['port'] as int;

        final healthUri = Uri.parse('http://127.0.0.1:$port/api/health');
        final resp = await http.get(healthUri).timeout(const Duration(milliseconds: 800));
        if (resp.statusCode == 200) {
          return DaemonEndpoint(port: port, token: token);
        }
      } catch (_) {
        // Stale or unreachable
      }
    }
    return null;
  }

  static Future<bool> _spawnSidecarDaemon() async {
    try {
      final envBin = Platform.environment['PI_CRUST_DAEMON_BIN'];
      if (envBin != null && await File(envBin).exists()) {
        final isScript = RegExp(r'\.(c?js|mjs)$', caseSensitive: false).hasMatch(envBin);
        await Process.start(
          isScript ? 'node' : envBin,
          isScript ? [File(envBin).absolute.path] : [],
          mode: ProcessStartMode.detached,
        );
        return true;
      }

      // Check next to executable (bundle sidecar)
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final bundledExeName = Platform.isWindows ? 'pi-agentd.exe' : 'pi-agentd';
      final bundledSidecar = File('$exeDir/$bundledExeName');
      if (await bundledSidecar.exists()) {
        await Process.start(
          bundledSidecar.path,
          [],
          mode: ProcessStartMode.detached,
        );
        return true;
      }

      // Development fallbacks: check repository paths
      final devPaths = [
        '$exeDir/pi-agentd.cjs',
        '$exeDir/dist/pi-agentd.cjs',
        '../agentd/dist/pi-agentd.cjs',
        '../agentd/dist/main.js',
        'apps/agentd/dist/pi-agentd.cjs',
        'apps/agentd/dist/main.js',
        '../../apps/agentd/dist/pi-agentd.cjs',
        '../../apps/agentd/dist/main.js',
      ];

      for (final p in devPaths) {
        final file = File(p);
        if (await file.exists()) {
          await Process.start(
            'node',
            [file.absolute.path],
            mode: ProcessStartMode.detached,
          );
          return true;
        }
      }
    } catch (_) {
      // Spawn error handled gracefully
    }
    return false;
  }
}
