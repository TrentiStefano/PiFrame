import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens links in the user's default application (browser, mail client, ...).
abstract class LinkService {
  /// Returns false when no application can open [uri].
  Future<bool> openExternal(Uri uri);
}

class UrlLauncherLinkService implements LinkService {
  const UrlLauncherLinkService();

  @override
  Future<bool> openExternal(Uri uri) async {
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

final linkServiceProvider = Provider<LinkService>((ref) => const UrlLauncherLinkService());
