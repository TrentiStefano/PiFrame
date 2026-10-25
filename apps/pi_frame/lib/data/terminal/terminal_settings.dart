import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum TerminalMode {
  integrated,
  native,
}

enum NativeTerminalApp {
  systemDefault,
  powershell,
  cmd,
  wsl,
  custom,
}

class TerminalSettings {
  final TerminalMode mode;
  final NativeTerminalApp nativeApp;
  final String customPath;
  final String integratedShell;

  const TerminalSettings({
    this.mode = TerminalMode.integrated,
    this.nativeApp = NativeTerminalApp.systemDefault,
    this.customPath = '',
    this.integratedShell = 'default',
  });

  TerminalSettings copyWith({
    TerminalMode? mode,
    NativeTerminalApp? nativeApp,
    String? customPath,
    String? integratedShell,
  }) {
    return TerminalSettings(
      mode: mode ?? this.mode,
      nativeApp: nativeApp ?? this.nativeApp,
      customPath: customPath ?? this.customPath,
      integratedShell: integratedShell ?? this.integratedShell,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'nativeApp': nativeApp.name,
        'customPath': customPath,
        'integratedShell': integratedShell,
      };

  factory TerminalSettings.fromJson(Map<String, dynamic> json) {
    TerminalMode mode = TerminalMode.integrated;
    if (json['mode'] == 'native') {
      mode = TerminalMode.native;
    }

    NativeTerminalApp nativeApp = NativeTerminalApp.systemDefault;
    final appStr = json['nativeApp'] as String?;
    if (appStr != null) {
      for (final a in NativeTerminalApp.values) {
        if (a.name == appStr) {
          nativeApp = a;
          break;
        }
      }
    }

    return TerminalSettings(
      mode: mode,
      nativeApp: nativeApp,
      customPath: json['customPath'] as String? ?? '',
      integratedShell: json['integratedShell'] as String? ?? 'default',
    );
  }
}

class TerminalSettingsNotifier extends StateNotifier<TerminalSettings> {
  TerminalSettingsNotifier() : super(const TerminalSettings()) {
    _load();
  }

  File? _getStorageFile() {
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
      return File('${dir.path}/terminal_settings.json');
    } catch (_) {
      return null;
    }
  }

  void _load() {
    final file = _getStorageFile();
    if (file != null && file.existsSync()) {
      try {
        final content = file.readAsStringSync();
        final map = jsonDecode(content) as Map<String, dynamic>;
        state = TerminalSettings.fromJson(map);
      } catch (_) {}
    }
  }

  void _save() {
    final file = _getStorageFile();
    if (file != null) {
      try {
        file.writeAsStringSync(jsonEncode(state.toJson()));
      } catch (_) {}
    }
  }

  void setMode(TerminalMode mode) {
    state = state.copyWith(mode: mode);
    _save();
  }

  void setNativeApp(NativeTerminalApp nativeApp) {
    state = state.copyWith(nativeApp: nativeApp);
    _save();
  }

  void setCustomPath(String path) {
    state = state.copyWith(customPath: path);
    _save();
  }

  void setIntegratedShell(String shell) {
    state = state.copyWith(integratedShell: shell);
    _save();
  }
}

final terminalSettingsProvider =
    StateNotifierProvider<TerminalSettingsNotifier, TerminalSettings>((ref) {
  return TerminalSettingsNotifier();
});

Map<String, String>? parseWslPath(String path) {
  final normalized =
      path.trim().replaceFirst(RegExp(r'^[\\/]+'), '//').replaceAll('\\', '/');
  final match = RegExp(
    r'^//(wsl(?:\.localhost|\$))/([^/]+)(?:/(.*))?$',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (match == null) return null;
  final distro = match.group(2)!;
  final rest = match.group(3) ?? '';
  final linuxPath = '/$rest'.replaceAll(RegExp(r'/+'), '/');
  return {
    'distro': distro,
    'linuxPath': linuxPath.length > 1 && linuxPath.endsWith('/')
        ? linuxPath.substring(0, linuxPath.length - 1)
        : linuxPath,
  };
}

Future<bool> launchNativeTerminal({
  required String cwd,
  NativeTerminalApp? nativeApp,
  String? customPath,
}) async {
  if (kIsWeb) return false;

  final effectiveDir = cwd.trim().isNotEmpty && Directory(cwd).existsSync()
      ? cwd
      : Directory.current.path;

  final wslInfo = Platform.isWindows ? parseWslPath(cwd) : null;

  try {
    if (Platform.isWindows) {
      if (nativeApp == NativeTerminalApp.custom &&
          customPath != null &&
          customPath.isNotEmpty) {
        await Process.start(
          customPath,
          [],
          workingDirectory: effectiveDir,
          mode: ProcessStartMode.detached,
        );
        return true;
      }

      if (nativeApp == NativeTerminalApp.wsl && wslInfo != null) {
        await Process.start(
          'wsl.exe',
          ['-d', wslInfo['distro']!, '--cd', wslInfo['linuxPath']!],
          mode: ProcessStartMode.detached,
        );
        return true;
      }

      if (nativeApp == NativeTerminalApp.cmd) {
        await Process.start(
          'cmd.exe',
          ['/c', 'start', 'cmd.exe', '/k', 'cd /d "$effectiveDir"'],
          mode: ProcessStartMode.detached,
        );
        return true;
      }

      if (nativeApp == NativeTerminalApp.powershell) {
        await Process.start(
          'cmd.exe',
          [
            '/c',
            'start',
            'powershell.exe',
            '-NoExit',
            '-Command',
            'Set-Location "$effectiveDir"',
          ],
          mode: ProcessStartMode.detached,
        );
        return true;
      }

      // Default on Windows: Try Windows Terminal (wt.exe) first
      try {
        final wtArgs = wslInfo != null
            ? ['-d', cwd]
            : ['-d', effectiveDir];
        await Process.start('wt.exe', wtArgs, mode: ProcessStartMode.detached);
        return true;
      } catch (_) {
        // Fallback to powershell in new window
        await Process.start(
          'cmd.exe',
          [
            '/c',
            'start',
            'powershell.exe',
            '-NoExit',
            '-Command',
            'Set-Location "$effectiveDir"',
          ],
          mode: ProcessStartMode.detached,
        );
        return true;
      }
    } else if (Platform.isMacOS) {
      if (nativeApp == NativeTerminalApp.custom &&
          customPath != null &&
          customPath.isNotEmpty) {
        await Process.start(
          customPath,
          [],
          workingDirectory: effectiveDir,
          mode: ProcessStartMode.detached,
        );
        return true;
      }
      await Process.start(
        'open',
        ['-a', 'Terminal', effectiveDir],
        mode: ProcessStartMode.detached,
      );
      return true;
    } else if (Platform.isLinux) {
      if (nativeApp == NativeTerminalApp.custom &&
          customPath != null &&
          customPath.isNotEmpty) {
        await Process.start(
          customPath,
          [],
          workingDirectory: effectiveDir,
          mode: ProcessStartMode.detached,
        );
        return true;
      }
      for (final candidate in [
        'x-terminal-emulator',
        'gnome-terminal',
        'konsole',
        'xterm'
      ]) {
        try {
          await Process.start(
            candidate,
            ['--working-directory=$effectiveDir'],
            mode: ProcessStartMode.detached,
          );
          return true;
        } catch (_) {}
      }
    }
  } catch (e) {
    debugPrint('Failed to launch native terminal: $e');
    return false;
  }
  return false;
}
