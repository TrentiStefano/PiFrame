import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../../app/app_version.dart';
import '../../domain/update/semver.dart';
import 'web_token_stub.dart' if (dart.library.html) 'web_token_html.dart';

class DaemonEndpoint {
  final String host;
  final int port;
  final String token;
  final bool isSecure;

  const DaemonEndpoint({
    this.host = '127.0.0.1',
    required this.port,
    required this.token,
    this.isSecure = false,
  });
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
    final custom = Platform.environment['PI_FRAME_HOME'];
    if (custom != null && custom.isNotEmpty) {
      return '$custom/runtime';
    }
    return '$_homeDir/.piframe/runtime';
  }

  static Future<DaemonEndpoint?> restartDaemon() async {
    final jsonFile = File('$_runtimeDir/daemon.json');
    final tokenFile = File('$_runtimeDir/daemon.token');
    if (await jsonFile.exists()) {
      try {
        final data = jsonDecode(await jsonFile.readAsString()) as Map<String, dynamic>;
        final pid = data['pid'] as int?;
        if (pid != null) {
          Process.killPid(pid);
        }
      } catch (_) {}
      try { await jsonFile.delete(); } catch (_) {}
    }
    if (await tokenFile.exists()) {
      try { await tokenFile.delete(); } catch (_) {}
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return locateOrProbe(autoSpawn: true);
  }

  static Future<DaemonEndpoint?> locateOrProbe({bool autoSpawn = true}) async {
    if (kIsWeb) {
      // Browsers cannot inspect native runtime files. Use daemon-hosted same-origin bootstrap.
      final base = Uri.base;
      final isSecure = base.scheme == 'https';
      final port = base.hasPort && base.port != 0 ? base.port : (isSecure ? 443 : 80);

      final webToken = await getWebDeviceToken();

      // Request session bootstrap (authenticated via cookie, Authorization header, or local loopback)
      try {
        final headers = <String, String>{};
        if (webToken != null && webToken.isNotEmpty) {
          headers['Authorization'] = 'Bearer $webToken';
        }
        final response = await http.get(base.resolve('/api/session-bootstrap'), headers: headers)
            .timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final token = (data['token'] as String?) ?? webToken;
          if (token != null && token.isNotEmpty) {
            return DaemonEndpoint(
              host: base.host,
              port: port,
              token: token,
              isSecure: isSecure,
            );
          }
        } else if (response.statusCode != 401 &&
            response.statusCode != 403 &&
            webToken != null &&
            webToken.isNotEmpty) {
          return DaemonEndpoint(
            host: base.host,
            port: port,
            token: webToken,
            isSecure: isSecure,
          );
        }
      } catch (_) {
        if (webToken != null && webToken.isNotEmpty) {
          return DaemonEndpoint(
            host: base.host,
            port: port,
            token: webToken,
            isSecure: isSecure,
          );
        }
      }

      return null;
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
          final health = jsonDecode(resp.body) as Map<String, dynamic>;
          final runningVersionStr = health['version'] as String?;
          final pid = (health['pid'] ?? data['pid']) as int?;

          final appSemVer = SemVer.tryParse(piFrameVersion);
          final runningSemVer = SemVer.tryParse(runningVersionStr);

          // If the running daemon is an older version than this client, terminate it
          // so that a matching sidecar is spawned.
          if (appSemVer != null && runningSemVer != null && runningSemVer < appSemVer) {
            if (pid != null) {
              Process.killPid(pid);
            }
            try { await jsonFile.delete(); } catch (_) {}
            try { await tokenFile.delete(); } catch (_) {}
            return null;
          }

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
      final exeDir = File(Platform.resolvedExecutable).parent.path;

      String? webDir = Platform.environment['PI_FRAME_WEB_DIR'];
      if (webDir == null || !Directory(webDir).existsSync()) {
        final webCandidates = [
          '$exeDir/web',
          '$exeDir/../../../../build/web',
          '$exeDir/../../../../../apps/pi_frame/build/web',
          '$exeDir/data/flutter_assets/web',
          '${Platform.environment['USERPROFILE'] ?? ''}/.piframe/web',
          '${Platform.environment['HOME'] ?? ''}/.piframe/web',
        ];
        for (final candidate in webCandidates) {
          if (candidate.isEmpty) continue;
          final d = Directory(candidate);
          if (d.existsSync() && File('${d.path}/index.html').existsSync()) {
            webDir = d.absolute.path;
            break;
          }
        }
      }
      final env = Map<String, String>.from(Platform.environment);
      if (webDir != null) {
        env['PI_FRAME_WEB_DIR'] = webDir;
      }

      final envBin = Platform.environment['PI_FRAME_DAEMON_BIN'];
      if (envBin != null && await File(envBin).exists()) {
        final isScript = RegExp(r'\.(c?js|mjs)$', caseSensitive: false).hasMatch(envBin);
        await Process.start(
          isScript ? 'node' : envBin,
          isScript ? [File(envBin).absolute.path] : [],
          mode: ProcessStartMode.detached,
          environment: env,
        );
        return true;
      }

      // Check next to executable (bundle sidecar)
      final bundledExeName = Platform.isWindows ? 'pi-agentd.exe' : 'pi-agentd';
      final bundledSidecar = File('$exeDir/$bundledExeName');
      if (await bundledSidecar.exists()) {
        await Process.start(
          bundledSidecar.path,
          [],
          mode: ProcessStartMode.detached,
          environment: env,
        );
        return true;
      }

      // Release installers bundle Node beside the daemon so users need no Node install.
      final bundledDaemon = File('$exeDir/pi-agentd.cjs');
      final bundledNode = File(
        '$exeDir/${Platform.isWindows ? 'node.exe' : 'node'}',
      );
      if (await bundledDaemon.exists() && await bundledNode.exists()) {
        await Process.start(
          bundledNode.path,
          [bundledDaemon.path],
          mode: ProcessStartMode.detached,
          environment: env,
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
            environment: env,
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
