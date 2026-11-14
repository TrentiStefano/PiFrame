import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Ratchet for design literals (DESIGN.md §07, plan task 2.5).
///
/// Each pattern has a baseline. The test fails when a count goes UP, so the
/// number can only fall over time. When a migration lowers a count, lower the
/// matching baseline in the same commit. The test prints every current count
/// so the new value is easy to read off.
///
/// Allow-listed files (theme tokens and the startup animation) are not counted:
/// they are where the literals are meant to live.
const _allowList = <String>{
  'lib/ui/motion.dart',
  'lib/ui/startup_assemble_animation.dart',
};

final _fontSizeLiteral = RegExp(r'fontSize:\s*(\d+(?:\.\d+)?)');
final _radiusLiteral = RegExp(r'BorderRadius\.circular\(\s*\d');
final _durationLiteral = RegExp(r'Duration\(\s*milliseconds:\s*\d');
final _curvesLiteral = RegExp(r'\bCurves\.');
final _boxShadow = RegExp(r'\bBoxShadow\(');
final _gestureDetector = RegExp(r'\bGestureDetector\(');

/// Baselines are today's counts. Lower them as literals are migrated.
const _baselines = <String, int>{
  'fontSize numeric literal': 719,
  'fontSize below 11': 132,
  'BorderRadius.circular numeric': 43,
  'Duration(milliseconds:) numeric': 41,
  'Curves.': 22,
  'BoxShadow(': 16,
  'GestureDetector(': 14,
};

typedef _Hit = ({String file, int line});

void main() {
  test('Design literal ratchet: counts may only go down (DESIGN.md §07)', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib directory must exist');

    final hits = <String, List<_Hit>>{
      for (final key in _baselines.keys) key: <_Hit>[],
    };

    final dartFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    for (final file in dartFiles) {
      final rel = file.path.replaceAll('\\', '/').replaceFirst(
        RegExp(r'^.*?lib/'),
        'lib/',
      );
      if (_allowList.contains(rel)) continue;

      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trim();
        if (trimmed.startsWith('//') || trimmed.startsWith('/*')) continue;

        final lineNo = i + 1;
        final fontSize = _fontSizeLiteral.firstMatch(line);
        if (fontSize != null) {
          hits['fontSize numeric literal']!.add((file: rel, line: lineNo));
          if (double.parse(fontSize.group(1)!) < 11) {
            hits['fontSize below 11']!.add((file: rel, line: lineNo));
          }
        }
        if (_radiusLiteral.hasMatch(line)) {
          hits['BorderRadius.circular numeric']!.add((file: rel, line: lineNo));
        }
        if (_durationLiteral.hasMatch(line)) {
          hits['Duration(milliseconds:) numeric']!.add((
            file: rel,
            line: lineNo,
          ));
        }
        if (_curvesLiteral.hasMatch(line)) {
          hits['Curves.']!.add((file: rel, line: lineNo));
        }
        if (_boxShadow.hasMatch(line)) {
          hits['BoxShadow(']!.add((file: rel, line: lineNo));
        }
        if (_gestureDetector.hasMatch(line)) {
          hits['GestureDetector(']!.add((file: rel, line: lineNo));
        }
      }
    }

    final report = StringBuffer('\nDesign literal counts (count / baseline):\n');
    for (final entry in _baselines.entries) {
      report.writeln(
        '  ${entry.key.padRight(34)} ${hits[entry.key]!.length} / ${entry.value}',
      );
    }
    // ignore: avoid_print
    print(report.toString());

    final failures = <String>[];
    for (final entry in _baselines.entries) {
      final found = hits[entry.key]!;
      if (found.length <= entry.value) continue;
      final byFile = <String, List<int>>{};
      for (final h in found) {
        byFile.putIfAbsent(h.file, () => <int>[]).add(h.line);
      }
      final files = byFile.entries
          .map((e) => '    ${e.key}: lines ${e.value.join(', ')}')
          .join('\n');
      failures.add(
        '${entry.key}: ${found.length} hits, baseline ${entry.value}\n$files',
      );
    }

    expect(
      failures,
      isEmpty,
      reason:
          'Design literals went up. Use FrameText / FrameSpace / radius tokens / '
          'FrameMotion instead. Over baseline:\n${failures.join('\n')}',
    );
  });
}
