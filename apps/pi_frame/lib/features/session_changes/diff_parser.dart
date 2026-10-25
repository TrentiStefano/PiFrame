/// Parser for Git unified diffs into structured hunks and lines.
class DiffParser {
  static final RegExp _hunkHeaderRegex = RegExp(
    r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)',
  );

  /// Parses a unified diff string into a [ParsedDiff] with hunks and lines.
  static ParsedDiff parse(String diffText) {
    if (diffText.trim().isEmpty) {
      return const ParsedDiff(hunks: []);
    }

    final rawLines = diffText.split('\n');
    final hunks = <DiffHunk>[];

    DiffHunkBuilder? currentBuilder;

    for (final rawLine in rawLines) {
      final match = _hunkHeaderRegex.firstMatch(rawLine);
      if (match != null) {
        if (currentBuilder != null) {
          hunks.add(currentBuilder.build());
        }
        final oldStart = int.tryParse(match.group(1) ?? '1') ?? 1;
        final oldCount = int.tryParse(match.group(2) ?? '1') ?? 1;
        final newStart = int.tryParse(match.group(3) ?? '1') ?? 1;
        final newCount = int.tryParse(match.group(4) ?? '1') ?? 1;
        final header = match.group(5)?.trim() ?? '';

        currentBuilder = DiffHunkBuilder(
          oldStart: oldStart,
          oldCount: oldCount,
          newStart: newStart,
          newCount: newCount,
          header: header,
        );
        continue;
      }

      if (currentBuilder != null) {
        // Skip git diff headers before the first hunk or file boundary markers
        if (rawLine.startsWith('diff --git') ||
            rawLine.startsWith('index ') ||
            rawLine.startsWith('--- ') ||
            rawLine.startsWith('+++ ')) {
          continue;
        }

        if (rawLine.startsWith('+')) {
          currentBuilder.addLine(DiffLine(
            type: DiffLineType.addition,
            oldLineNumber: null,
            newLineNumber: currentBuilder.currentNewLine++,
            text: rawLine.length > 1 ? rawLine.substring(1) : '',
          ));
        } else if (rawLine.startsWith('-')) {
          currentBuilder.addLine(DiffLine(
            type: DiffLineType.deletion,
            oldLineNumber: currentBuilder.currentOldLine++,
            newLineNumber: null,
            text: rawLine.length > 1 ? rawLine.substring(1) : '',
          ));
        } else if (rawLine.startsWith('\\ No newline at end of file')) {
          // Ignore newline marker
          continue;
        } else {
          // Context line (starts with space or empty)
          final text = rawLine.startsWith(' ')
              ? (rawLine.length > 1 ? rawLine.substring(1) : '')
              : rawLine;
          currentBuilder.addLine(DiffLine(
            type: DiffLineType.context,
            oldLineNumber: currentBuilder.currentOldLine++,
            newLineNumber: currentBuilder.currentNewLine++,
            text: text,
          ));
        }
      }
    }

    if (currentBuilder != null) {
      hunks.add(currentBuilder.build());
    }

    return ParsedDiff(hunks: hunks);
  }
}

class DiffHunkBuilder {
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final String header;
  final List<DiffLine> lines = [];

  late int currentOldLine;
  late int currentNewLine;

  DiffHunkBuilder({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.header,
  }) {
    currentOldLine = oldStart;
    currentNewLine = newStart;
  }

  void addLine(DiffLine line) {
    lines.add(line);
  }

  DiffHunk build() {
    return DiffHunk(
      oldStart: oldStart,
      oldCount: oldCount,
      newStart: newStart,
      newCount: newCount,
      header: header,
      lines: List.unmodifiable(lines),
    );
  }
}

class ParsedDiff {
  final List<DiffHunk> hunks;

  const ParsedDiff({required this.hunks});

  bool get isEmpty => hunks.isEmpty;
  bool get isNotEmpty => hunks.isNotEmpty;
}

class DiffHunk {
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final String header;
  final List<DiffLine> lines;

  const DiffHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.header,
    required this.lines,
  });

  /// Aligns lines for side-by-side two column diff view.
  List<SplitDiffRow> toSplitRows() {
    final rows = <SplitDiffRow>[];
    int i = 0;
    while (i < lines.length) {
      final line = lines[i];
      if (line.type == DiffLineType.context) {
        rows.add(SplitDiffRow(left: line, right: line));
        i++;
      } else if (line.type == DiffLineType.deletion) {
        // Collect consecutive deletions
        final deletions = <DiffLine>[];
        while (i < lines.length && lines[i].type == DiffLineType.deletion) {
          deletions.add(lines[i]);
          i++;
        }
        // Collect consecutive additions that immediately follow
        final additions = <DiffLine>[];
        while (i < lines.length && lines[i].type == DiffLineType.addition) {
          additions.add(lines[i]);
          i++;
        }
        final maxCount = deletions.length > additions.length
            ? deletions.length
            : additions.length;
        for (int k = 0; k < maxCount; k++) {
          rows.add(SplitDiffRow(
            left: k < deletions.length ? deletions[k] : null,
            right: k < additions.length ? additions[k] : null,
          ));
        }
      } else if (line.type == DiffLineType.addition) {
        rows.add(SplitDiffRow(left: null, right: line));
        i++;
      } else {
        i++;
      }
    }
    return rows;
  }
}

enum DiffLineType {
  context,
  addition,
  deletion,
}

class DiffLine {
  final DiffLineType type;
  final int? oldLineNumber;
  final int? newLineNumber;
  final String text;

  const DiffLine({
    required this.type,
    this.oldLineNumber,
    this.newLineNumber,
    required this.text,
  });
}

class SplitDiffRow {
  final DiffLine? left;
  final DiffLine? right;

  const SplitDiffRow({this.left, this.right});
}
