import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/update/update_models.dart';

abstract class InstallerLauncher {
  Future<void> launchInstaller(String filePath, {required AppRelease release});
  Future<void> openReleasePage(String url);
}

class PlatformInstallerLauncher implements InstallerLauncher {
  const PlatformInstallerLauncher();

  @override
  Future<void> launchInstaller(
    String filePath, {
    required AppRelease release,
  }) async {
    if (kIsWeb) {
      await openReleasePage(release.htmlUrl);
      return;
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File di installazione non trovato', filePath);
    }

    if (Platform.isWindows) {
      // Launch Inno Setup installer detached so it continues after app exits
      await Process.start(filePath, const [], mode: ProcessStartMode.detached);
      exit(0);
    } else if (Platform.isMacOS) {
      // Opens the DMG volume in Finder
      await Process.run('open', [filePath]);
    } else if (Platform.isLinux) {
      // Opens the .deb package manager or installer
      await Process.run('xdg-open', [filePath]);
    } else {
      await openReleasePage(release.htmlUrl);
    }
  }

  @override
  Future<void> openReleasePage(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
