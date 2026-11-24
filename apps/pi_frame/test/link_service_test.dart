import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/platform/link_service.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  final uri = Uri.parse('https://example.com/docs');

  test('openExternal opens the link in the external application and reports success', () async {
    final modes = <LaunchMode>[];
    final service = UrlLauncherLinkService(
      launch: (_, mode) async {
        modes.add(mode);
        return true;
      },
    );

    expect(await service.openExternal(uri), isTrue);
    expect(modes, [LaunchMode.externalApplication]);
  });

  test('openExternal retries in the default mode when the external application fails', () async {
    final modes = <LaunchMode>[];
    final service = UrlLauncherLinkService(
      launch: (_, mode) async {
        modes.add(mode);
        return mode == LaunchMode.platformDefault;
      },
    );

    expect(await service.openExternal(uri), isTrue);
    expect(modes, [LaunchMode.externalApplication, LaunchMode.platformDefault]);
  });

  test('openExternal retries in the default mode when the external launch throws', () async {
    final modes = <LaunchMode>[];
    final service = UrlLauncherLinkService(
      launch: (_, mode) async {
        modes.add(mode);
        if (mode == LaunchMode.externalApplication) throw StateError('no handler');
        return true;
      },
    );

    expect(await service.openExternal(uri), isTrue);
    expect(modes, [LaunchMode.externalApplication, LaunchMode.platformDefault]);
  });

  test('openExternal reports failure instead of throwing when every mode fails', () async {
    final modes = <LaunchMode>[];
    final service = UrlLauncherLinkService(
      launch: (_, mode) async {
        modes.add(mode);
        throw StateError('no handler');
      },
    );

    expect(await service.openExternal(uri), isFalse);
    expect(modes, [LaunchMode.externalApplication, LaunchMode.platformDefault]);
  });
}
