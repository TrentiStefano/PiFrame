import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

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

  static Future<DaemonEndpoint?> locateOrProbe() async {
    final jsonFile = File('$_runtimeDir/daemon.json');
    final tokenFile = File('$_runtimeDir/daemon.token');

    if (await jsonFile.exists() && await tokenFile.exists()) {
      try {
        final jsonContent = await jsonFile.readAsString();
        final token = (await tokenFile.readAsString()).trim();
        final data = jsonDecode(jsonContent) as Map<String, dynamic>;
        final port = data['port'] as int;

        // Health check probe
        final healthUri = Uri.parse('http://127.0.0.1:$port/api/health');
        final resp = await http.get(healthUri).timeout(const Duration(seconds: 2));
        if (resp.statusCode == 200) {
          return DaemonEndpoint(port: port, token: token);
        }
      } catch (_) {
        // Stale or error, fallback to null
      }
    }
    return null;
  }
}
