// The remote-access web app compiles lib/main.dart and everything it imports.
// The web has no `dart:ffi`, so one unconditional import of a file that uses
// it (the Windows taskbar progress did) breaks every release installer at
// "Build Flutter web app". Native-only code must be reached through a
// conditional import whose default branch is a stub.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _directive = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]((?:\s+if\s*\([^)]*\)\s*['"][^'"]+['"])*)''',
  multiLine: true,
);
final _condition = RegExp(r'''if\s*\(\s*([\w.]+)\s*\)\s*['"]([^'"]+)['"]''');
const _webLibraries = {'dart.library.html', 'dart.library.js_interop', 'dart.library.js', 'dart.library.ui_web'};

/// The library URIs a web build resolves for [source]'s imports and exports.
List<String> _webImports(String source) {
  final uris = <String>[];
  for (final match in _directive.allMatches(source)) {
    var chosen = match.group(1)!;
    for (final condition in _condition.allMatches(match.group(2) ?? '')) {
      if (_webLibraries.contains(condition.group(1))) {
        chosen = condition.group(2)!;
        break;
      }
    }
    uris.add(chosen);
  }
  return uris;
}

/// Files under lib/ a web build of [entry] compiles, by path from lib/.
Set<String> _reachableFromWeb(String entry) {
  final libDir = Directory('lib').absolute.uri;
  final seen = <String>{};
  final pending = [libDir.resolve(entry)];
  while (pending.isNotEmpty) {
    final uri = pending.removeLast();
    final relative = uri.path.substring(libDir.path.length);
    if (!seen.add(relative)) continue;
    final file = File.fromUri(uri);
    if (!file.existsSync()) continue;
    for (final import in _webImports(file.readAsStringSync())) {
      if (import.startsWith('package:pi_frame/')) {
        pending.add(libDir.resolve(import.substring('package:pi_frame/'.length)));
      } else if (!import.contains(':')) {
        pending.add(uri.resolve(import));
      }
    }
  }
  return seen;
}

void main() {
  test('the conditional-import parser picks the branch the web build compiles', () {
    expect(_webImports("import 'stub.dart' if (dart.library.ffi) 'native.dart';"), ['stub.dart']);
    expect(_webImports("import 'io.dart' if (dart.library.html) 'web.dart';"), ['web.dart']);
    expect(_webImports("import 'native.dart';\nexport 'other.dart';"), ['native.dart', 'other.dart']);
  });

  test('the web build of main.dart never reaches dart:ffi or package:ffi', () {
    final reached = _reachableFromWeb('main.dart');
    expect(reached, contains('data/notifications/desktop_notification_service.dart'));
    final offenders = [
      for (final path in reached)
        if (File('lib/$path').existsSync() &&
            _webImports(File('lib/$path').readAsStringSync())
                .any((u) => u == 'dart:ffi' || u.startsWith('package:ffi/')))
          path,
    ];
    expect(offenders, isEmpty, reason: 'reach these through a conditional import with a web-safe stub');
  });
}
