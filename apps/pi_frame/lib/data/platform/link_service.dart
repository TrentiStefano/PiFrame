import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens links in the user's default application (browser, mail client, ...).
abstract class LinkService {
  /// Returns true when a application opened [uri]. Returns false, never throws, when none did.
  Future<bool> openExternal(Uri uri);
}

/// Launches a [uri] in [mode]. Returns false when the platform could not open it.
typedef LinkLauncher = Future<bool> Function(Uri uri, LaunchMode mode);

/// The one link-opening policy: try the external application first, then retry in the
/// platform's default mode. Every caller goes through this service.
class UrlLauncherLinkService implements LinkService {
  UrlLauncherLinkService({LinkLauncher? launch}) : _launch = launch ?? _launchWithUrlLauncher;

  final LinkLauncher _launch;

  static Future<bool> _launchWithUrlLauncher(Uri uri, LaunchMode mode) => launchUrl(uri, mode: mode);

  @override
  Future<bool> openExternal(Uri uri) async {
    if (await _tryLaunch(uri, LaunchMode.externalApplication)) return true;
    return _tryLaunch(uri, LaunchMode.platformDefault);
  }

  Future<bool> _tryLaunch(Uri uri, LaunchMode mode) async {
    try {
      return await _launch(uri, mode);
    } catch (error) {
      debugPrint('openExternal($mode) failed for $uri: $error');
      return false;
    }
  }
}

final linkServiceProvider = Provider<LinkService>((ref) => UrlLauncherLinkService());
