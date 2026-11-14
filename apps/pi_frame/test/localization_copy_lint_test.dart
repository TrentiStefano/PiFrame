import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Copy lint for the Italian UI (audit P2-2, N7).
///
/// Reads every Italian value in `lib/data/language/strings_*.dart` (the first
/// branch of each `isItalian ? '...' : '...'` expression) and fails when an
/// internal ID or an English word that must not appear in Italian copy leaks in.
/// Loanwords that the Italian dev UI keeps on purpose (Git, commit, push,
/// stage, thinking, daemon, Pi) are deliberately not on the deny-list.
void main() {
  final languageDir = Directory('lib/data/language');

  // Matches the Italian branch: `isItalian ? 'value'` (value may span lines).
  final italianValue = RegExp(
    r"isItalian\s*\?\s*'((?:[^'\\\r\n]|\\.)*)'",
  );

  // Internal IDs from the design docs must never reach user copy.
  final internalIds = <String, RegExp>{
    'internal ID "(Dn)"': RegExp(r'\(D\d+\)'),
    'internal ID D16': RegExp(r'\bD16\b'),
  };

  // English words that must not appear in Italian copy (case-sensitive).
  final englishWords = <String, RegExp>{
    'CONNECTED': RegExp(r'\bCONNECTED\b'),
    'Connected': RegExp(r'\bConnected\b'),
    'untracked': RegExp(r'\buntracked\b'),
    'unstaged': RegExp(r'\bunstaged\b'),
    'read-only': RegExp(r'\bread-only\b'),
    'Reasoning': RegExp(r'\bReasoning\b'),
    'builtin': RegExp(r'\bbuiltin\b'),
    'No subagent': RegExp(r'\bNo subagent'),
    'Side': RegExp(r'\bSide\b'),
  };

  test('Italian strings contain no internal IDs or deny-listed English words', () {
    final files = languageDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('strings_') && f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty, reason: 'strings_*.dart files must exist');

    var checked = 0;
    final violations = <String>[];

    for (final file in files) {
      final source = file.readAsStringSync();
      for (final match in italianValue.allMatches(source)) {
        checked++;
        final value = match.group(1)!;
        final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
        final where = '${file.path}:$line';

        for (final entry in [...internalIds.entries, ...englishWords.entries]) {
          if (entry.value.hasMatch(value)) {
            violations.add('$where: ${entry.key} in Italian copy: "$value"');
          }
        }
      }
    }

    // Guard against a regex that silently matches nothing.
    expect(checked, greaterThan(100), reason: 'Expected to scan the Italian strings');
    expect(
      violations,
      isEmpty,
      reason: 'Fix these Italian strings:\n${violations.join('\n')}',
    );
  });
}
