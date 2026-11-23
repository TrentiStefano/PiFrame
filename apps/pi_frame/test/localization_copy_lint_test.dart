import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Copy lint for the Italian UI.
///
/// Reads every Italian value in `lib/data/language/strings_*.dart` (the first
/// branch of each `isItalian ? '...' : '...'` expression) and fails when an
/// internal ID or an English word that must not appear in Italian copy leaks in.
/// Loanwords that the Italian dev UI keeps on purpose (Git, commit, push,
/// stage, thinking, daemon, Pi) are deliberately not on the deny-list.
void main() {
  final languageDir = Directory('lib/data/language');

  // Matches the Italian branch: `isItalian ? 'value'`.
  final italianValue = RegExp(_italianBranch);

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
    expect(violations, isEmpty, reason: 'Fix these Italian strings:\n${violations.join('\n')}');
  });

  // English is the default language (#56): Italian text belongs only in the
  // translation tables (lib/data/language), never hard-coded in app sources
  // or in the daemon's messages.
  test('the detector recognizes Italian copy and leaves English and code alone', () {
    for (final italian in [
      'Errore conversazione laterale',
      'Sessione in sola lettura.',
      "L'agente sta lavorando",
      'Ogni settimana (consigliato)',
      'Impossibile scaricare il file',
    ]) {
      expect(looksItalian(italian), isTrue, reason: italian);
    }
    for (final other in [
      'Read-only session.',
      'Daemon not connected',
      'non-empty',
      'session_id',
      'Il Mulino',
      'https://example.com/il/',
    ]) {
      expect(looksItalian(other), isFalse, reason: other);
    }
    final literals = stringLiterals('''
// Un commento non conta
final a = 'Errore: \${x ? 'sì' : 'no'}'; /* né questo */
final b = "Sessione in sola lettura";
final c = `template \${'nella cartella'} end`;
''').map((l) => l.text).toList();
    expect(literals, containsAll(['Errore: ', 'sì', 'Sessione in sola lettura', 'nella cartella']));
    expect(literals.any((t) => t.contains('commento') || t.contains('questo')), isFalse);
  });

  test('app sources outside the translation tables contain no Italian text', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.replaceAll('\\', '/').startsWith('lib/data/language/'))
        .toList();
    expect(files.length, greaterThan(100), reason: 'Expected to scan the app sources');
    final violations = italianLiterals(files);
    expect(violations, isEmpty, reason: 'Move these strings into the translation tables:\n${violations.join('\n')}');
  });

  test("the daemon's messages contain no Italian text", () {
    final files = Directory('../agentd/src')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.ts') && !f.path.endsWith('.test.ts'))
        .where((f) => !f.path.replaceAll('\\', '/').contains('/test/'))
        .toList();
    expect(files.length, greaterThan(50), reason: 'Expected to scan the daemon sources');
    final violations = italianLiterals(files);
    expect(violations, isEmpty, reason: 'Write these daemon messages in English:\n${violations.join('\n')}');
  });
}

/// A single-quoted, single-line Dart string literal; group 1 is its contents.
const _singleQuoted = r"'((?:[^'\\\r\n]|\\.)*)'";

/// The Italian branch of an `isItalian ? '...' : '...'` expression.
const _italianBranch = r'isItalian\s*\?\s*' + _singleQuoted;

/// Words that appear only on the Italian side of the translation tables
/// (lib/data/language): Italian vocabulary that English copy and code never use.
final Set<String> _italianVocabulary = () {
  final pair = RegExp(_italianBranch + r'\s*:\s*' + _singleQuoted);
  final italian = <String>{};
  final english = <String>{};
  for (final file in Directory('lib/data/language').listSync().whereType<File>()) {
    for (final match in pair.allMatches(file.readAsStringSync())) {
      italian.addAll(_words(match.group(1)!));
      english.addAll(_words(match.group(2)!));
    }
  }
  // English loanwords the Italian copy keeps (token, host, ...).
  return italian.difference(english).difference(_loanwords).where((w) => w.length >= 2).toSet();
}();

const _loanwords = {'token', 'host', 'base', 'mouse', 'loop', 'quote'};

final _wordPattern = RegExp(r'\p{L}+', unicode: true);
final _interpolation = RegExp(r'\$\{[^}]*\}|\$\w+');

Iterable<String> _words(String text) =>
    _wordPattern.allMatches(text.replaceAll(_interpolation, ' ')).map((m) => m.group(0)!.toLowerCase());

/// Italian elisions such as l'agente, dell'app, un'altra.
final _italianElision = RegExp(r"\b(l|dell|all|nell|sull|dall|un|quest)['’][a-zàèéìòù]", caseSensitive: false);

/// True when [text] reads as Italian copy: an elision, a long Italian-only
/// word, or two short ones (short words alone, such as "di", also occur in code).
bool looksItalian(String text) {
  if (_italianElision.hasMatch(text)) return true;
  final hits = _words(text).where(_italianVocabulary.contains).toList();
  return hits.any((w) => w.length >= 4) || hits.length >= 2;
}

/// Italian literals that are input, not copy: todo statuses Pi may write in
/// Italian, which the todo parser maps to its own statuses.
const _allowedItalianInput = <String, Set<String>>{
  'lib/features/transcript/todo_provider.dart': {'completato', 'completata', 'in corso', 'da fare'},
};

List<String> italianLiterals(List<File> files) {
  final violations = <String>[];
  for (final file in files) {
    final allowed = _allowedItalianInput[file.path.replaceAll('\\', '/')] ?? const <String>{};
    for (final literal in stringLiterals(file.readAsStringSync())) {
      if (allowed.contains(literal.text)) continue;
      if (looksItalian(literal.text)) violations.add('${file.path}:${literal.line}: "${literal.text}"');
    }
  }
  return violations;
}

class Literal {
  Literal(this.text, this.line);
  final String text;
  final int line;
}

/// String literals of Dart or TypeScript source, without comments. Interpolated
/// code (`${...}`) is scanned for nested literals; the literal's own text keeps
/// only its plain parts. Escapes are decoded (`\'` becomes `'`).
List<Literal> stringLiterals(String source) {
  final out = <Literal>[];
  int lineAt(int index) => '\n'.allMatches(source.substring(0, index)).length + 1;

  // Scans code until [closer] at depth 0 (or end of input) and returns the index after it.
  late int Function(int, String?) code;
  int str(int start, String quote) {
    final triple = source.startsWith(quote * 3, start);
    final delimiter = triple ? quote * 3 : quote;
    var j = start + delimiter.length;
    final buffer = StringBuffer();
    void flush() {
      if (buffer.isNotEmpty) out.add(Literal(buffer.toString(), lineAt(start)));
      buffer.clear();
    }

    while (j < source.length) {
      if (source.startsWith(delimiter, j)) {
        flush();
        return j + delimiter.length;
      }
      final ch = source[j];
      if (ch == '\\' && j + 1 < source.length) {
        buffer.write(source[j + 1]);
        j += 2;
        continue;
      }
      if (ch == r'$' && j + 1 < source.length && source[j + 1] == '{') {
        flush();
        j = code(j + 2, '}');
        continue;
      }
      if (!triple && quote != '`' && ch == '\n') {
        flush();
        return j + 1;
      }
      buffer.write(ch);
      j++;
    }
    flush();
    return j;
  }

  code = (int start, String? closer) {
    var j = start;
    var depth = 0;
    while (j < source.length) {
      final ch = source[j];
      if (source.startsWith('//', j)) {
        final end = source.indexOf('\n', j);
        j = end < 0 ? source.length : end;
        continue;
      }
      if (source.startsWith('/*', j)) {
        final end = source.indexOf('*/', j + 2);
        j = end < 0 ? source.length : end + 2;
        continue;
      }
      if (ch == "'" || ch == '"' || ch == '`') {
        j = str(j, ch);
        continue;
      }
      if (ch == '{') depth++;
      if (ch == '}') {
        if (depth == 0 && closer == '}') return j + 1;
        depth--;
      }
      j++;
    }
    return j;
  };

  code(0, null);
  return out;
}
