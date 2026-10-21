import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Strict theme token enforcement: No hardcoded Colors.* or Color(0x...) in apps/pi_frame/lib', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib directory must exist');

    final dartFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    final violations = <String>[];
    final colorRegex = RegExp(r'(Colors\.[a-zA-Z]+|Color\(0x)');

    for (final file in dartFiles) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Ignore comments
        final trimmed = line.trim();
        if (trimmed.startsWith('//') || trimmed.startsWith('/*')) continue;

        if (colorRegex.hasMatch(line)) {
          violations.add('${file.path}:${i + 1}: $line');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'All colors in apps/pi_frame/lib must be accessed via context.tokens or Theme.of(context). Found hardcoded colors:\n${violations.join('\n')}',
    );
  });
}
