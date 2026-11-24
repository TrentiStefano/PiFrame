import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../terminal/terminal_settings.dart';
import 'file_system_service.dart';
import 'host_environment_service.dart';
import 'link_service.dart';
import 'process_service.dart';

/// Opens links and reveals files in the host's own applications. Every call
/// goes through the platform services, so the browser build and tests can swap them.
class HostFileOpener {
  final LinkService links;
  final ProcessService processes;
  final FileSystemService files;
  final HostEnvironmentService host;

  const HostFileOpener({required this.links, required this.processes, required this.files, required this.host});

  /// Opens [url] in the default application. Falls back to the OS opener when
  /// the link service cannot.
  Future<void> openUrl(String url) async {
    if (await links.openExternal(Uri.parse(url))) return;
    if (host.isWeb) return;
    try {
      switch (host.operatingSystem) {
        case 'windows':
          await processes.run('rundll32', ['url.dll,FileProtocolHandler', url]);
        case 'macos':
          await processes.run('open', [url]);
        case 'linux':
          await processes.run('xdg-open', [url]);
      }
    } catch (error) {
      debugPrint('openUrl OS opener failed for $url: $error');
    }
  }

  /// Reveals [rawPath] in the host file explorer, selecting it when it exists.
  Future<void> openInOsFileExplorer(String rawPath, {String? cwd}) async {
    // Remote browsers cannot reveal files in the host OS explorer.
    if (host.isWeb) return;
    try {
      final os = host.operatingSystem;
      final targetPath = resolvePathForOsExplorer(rawPath, cwd: cwd, operatingSystem: os);

      if (os == 'windows') {
        await _revealOnWindows(rawPath, targetPath, cwd: cwd);
      } else if (os == 'macos') {
        if (await files.fileExists(targetPath)) {
          await processes.run('open', ['-R', targetPath]);
        } else {
          await processes.run('open', [targetPath]);
        }
      } else if (os == 'linux') {
        if (await files.fileExists(targetPath)) {
          await processes.run('xdg-open', [p.dirname(targetPath)]);
        } else {
          await processes.run('xdg-open', [targetPath]);
        }
      }
    } catch (e) {
      debugPrint('openInOsFileExplorer error: $e');
    }
  }

  Future<void> _revealOnWindows(String rawPath, String targetPath, {String? cwd}) async {
    var winPath = targetPath.replaceAll('/', '\\');
    var isFile = await files.fileExists(winPath);
    var isDir = await files.directoryExists(winPath);

    // If target does not exist and appears to be WSL, try dynamic resolution via wslpath
    if (!isFile &&
        !isDir &&
        (cwd?.contains('wsl') == true ||
            cwd?.startsWith('/') == true ||
            rawPath.contains('wsl') ||
            rawPath.startsWith('/'))) {
      try {
        final rawClean = rawPath
            .replaceFirst(RegExp(r'^file://+'), '')
            .replaceAll(RegExp(r'#.*$'), '')
            .replaceAll(RegExp(r':\d+(?::\d+)?$'), '');
        final targetLinux = rawClean.startsWith('/')
            ? rawClean
            : (cwd != null ? '${parseWslPath(cwd)?['linuxPath'] ?? cwd}/$rawClean' : rawClean);
        final res = await processes.run('wsl.exe', ['wslpath', '-w', targetLinux], timeout: const Duration(seconds: 1));
        if (res.exitCode == 0) {
          final out = res.stdout.trim();
          if (out.isNotEmpty && (await files.fileExists(out) || await files.directoryExists(out))) {
            winPath = out;
            isFile = await files.fileExists(winPath);
            isDir = await files.directoryExists(winPath);
          }
        }
      } catch (error) {
        debugPrint('wslpath resolution failed for $rawPath: $error');
      }
    }

    if (isFile) {
      await processes.run('explorer.exe', ['/select,$winPath']);
    } else if (isDir) {
      await processes.run('explorer.exe', [winPath]);
    } else {
      final parentPath = p.dirname(winPath);
      if (await files.directoryExists(parentPath)) {
        await processes.run('explorer.exe', [parentPath]);
      } else {
        await processes.run('explorer.exe', ['/select,$winPath']);
      }
    }
  }
}

/// Resolves a path mentioned in a message to a path the host explorer understands.
/// [operatingSystem] is the host's (`web` in the browser build).
String resolvePathForOsExplorer(String rawPath, {String? cwd, required String operatingSystem}) {
  // The browser has no OS file system: keep the raw reference untouched.
  if (operatingSystem == 'web') return rawPath.trim();
  final isWindows = operatingSystem == 'windows';
  String resolved = rawPath.trim();
  if (resolved.startsWith('file://')) {
    final uri = Uri.tryParse(resolved);
    if (uri != null) {
      if (uri.host.isNotEmpty) {
        resolved = '\\\\${uri.host}${uri.path}'.replaceAll('/', '\\');
      } else if (isWindows && RegExp(r'^/[a-zA-Z]:').hasMatch(uri.path)) {
        resolved = uri.path.substring(1).replaceAll('/', '\\');
      } else {
        resolved = uri.path;
      }
    } else {
      resolved = resolved.replaceFirst(RegExp(r'^file://+'), '');
    }
  }

  // Remove query, anchor or line:col numbers like :42:10 or #L10-20
  resolved = resolved.replaceAll(RegExp(r'#.*$'), '');
  resolved = resolved.replaceAll(RegExp(r':\d+(?::\d+)?$'), '');

  if (!isWindows) {
    if (cwd != null && cwd.isNotEmpty && !resolved.startsWith('/')) {
      final sep = cwd.endsWith('/') ? '' : '/';
      return '$cwd$sep$resolved';
    }
    return resolved;
  }

  // Windows platform handling:
  // 1. Check if resolved is already a WSL UNC path (e.g. \\wsl.localhost\... or \\wsl$\...)
  final directWsl = parseWslPath(resolved);
  if (directWsl != null) {
    final host = resolved.contains(r'wsl$') ? r'wsl$' : 'wsl.localhost';
    final linuxRest = directWsl['linuxPath'] ?? '';
    return '\\\\$host\\${directWsl['distro']}$linuxRest'.replaceAll('/', '\\');
  }

  // 2. Check if cwd is a WSL path
  final cwdWsl = cwd != null ? parseWslPath(cwd) : null;
  if (cwdWsl != null) {
    final host = cwd!.contains(r'wsl$') ? r'wsl$' : 'wsl.localhost';
    final distro = cwdWsl['distro']!;
    final baseLinux = cwdWsl['linuxPath']!;
    if (resolved.startsWith('/')) {
      return '\\\\$host\\$distro$resolved'.replaceAll('/', '\\');
    }
    final sep = baseLinux.endsWith('/') || resolved.startsWith('/') ? '' : '/';
    return '\\\\$host\\$distro$baseLinux$sep$resolved'.replaceAll('/', '\\');
  }

  // 3. A pure Linux path on Windows with no known WSL distro: keep the Linux
  // path. openInOsFileExplorer maps it with `wslpath -w` on the default distro.
  if (cwd != null && (cwd.startsWith('/') || resolved.startsWith('/'))) {
    return resolved.startsWith('/') ? resolved : (cwd.endsWith('/') ? '$cwd$resolved' : '$cwd/$resolved');
  }

  // 4. Standard Windows path
  if (cwd != null && cwd.isNotEmpty) {
    final isAbsolute = RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(resolved) || resolved.startsWith(r'\\');
    if (!isAbsolute) {
      final separator = cwd.endsWith('\\') || cwd.endsWith('/') ? '' : '\\';
      return '$cwd$separator$resolved'.replaceAll('/', '\\');
    }
  }

  return resolved.replaceAll('/', '\\');
}

final hostFileOpenerProvider = Provider<HostFileOpener>(
  (ref) => HostFileOpener(
    links: ref.watch(linkServiceProvider),
    processes: ref.watch(processServiceProvider),
    files: ref.watch(fileSystemServiceProvider),
    host: ref.watch(hostEnvironmentServiceProvider),
  ),
);
