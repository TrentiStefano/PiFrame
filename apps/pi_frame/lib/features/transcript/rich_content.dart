import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/language/language_settings.dart';
import '../../data/language/strings_transcript.dart';
import '../../ui/code/code_block.dart';
import '../../ui/code/diff_block.dart';
import '../../ui/frame_focus.dart';
import '../../data/platform/host_file_opener.dart';
import 'task_notification_card.dart';

bool isLikelyFilePath(String s) {
  final clean = s.trim();
  if (clean.isEmpty || clean.contains('\n') || clean.length > 300) return false;
  if (clean.startsWith('http://') || clean.startsWith('https://')) return false;
  if (clean.startsWith('file://')) return true;
  if (RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(clean)) return true;
  final hasSep = clean.contains('/') || clean.contains(r'\');
  final hasExt = RegExp(
    r'\.(dart|ts|js|jsx|tsx|json|yaml|yml|md|markdown|txt|html|css|scss|sh|ps1|bat|cpp|c|h|hpp|rs|go|py|lock|toml|env|gradle|properties|xml|svg|png|jpg|jpeg|gif|webp|ico|wasm)$',
    caseSensitive: false,
  ).hasMatch(clean);
  if (hasExt) return true;
  if (hasSep && RegExp(r'[\w\-.]+$').hasMatch(clean)) {
    return true;
  }
  return false;
}

class RichContent extends ConsumerStatefulWidget {
  final String text;
  final String? cwd;
  final Color? textColor;

  const RichContent({super.key, required this.text, this.cwd, this.textColor});

  @override
  ConsumerState<RichContent> createState() => _RichContentState();

  static final RegExp _fenceRegex = RegExp(r'```([a-zA-Z0-9_\-\+]*)\n([\s\S]*?)```');
  static final RegExp _numberedListRegex = RegExp(r'^(\d+)\.\s');
  static final RegExp _mdLinkRegex = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');
  static final RegExp _rawUrlRegex = RegExp(r'(?<![\(\[])(https?://[^\s\)]+|file://[^\s\)]+)');
  static final RegExp _inlineCodeRegex = RegExp(r'`([^`]+)`');
  static final RegExp _boldRegex = RegExp(r'\*\*([^*]+)\*\*');
  static final RegExp _rawFilePathRegex = RegExp(
    r'(?<![/\w\-])((?:[a-zA-Z]:[\\/]|(?:\.{1,2}[\\/])|(?:[\w\-]+[\\/]))[\w\-./\\]+\.(?:dart|ts|js|jsx|tsx|json|yaml|yml|md|txt|html|css|sh|ps1|bat|cpp|c|h|rs|go|py|lock|toml))\b',
  );
  static final RegExp _taskNotifRegex = RegExp(
    r'<task-notification>[\s\S]*?</task-notification>(?:\s*Full transcript available at:\s*[^\r\n]+)?',
    caseSensitive: false,
  );

  static void _addTextAndCode(List<_Segment> segments, String text) {
    int lastIndex = 0;
    for (final match in _fenceRegex.allMatches(text)) {
      final textPart = text.substring(lastIndex, match.start).trim();
      if (textPart.isNotEmpty) segments.add(_TextSegment(textPart));
      segments.add(_CodeSegment(code: match.group(2) ?? '', language: match.group(1)));
      lastIndex = match.end;
    }
    final remaining = text.substring(lastIndex).trim();
    if (remaining.isNotEmpty) segments.add(_TextSegment(remaining));
  }

  static List<_Segment> _parseSegments(String raw) {
    final segments = <_Segment>[];
    final normalized = raw.contains('\r') ? raw.replaceAll('\r\n', '\n') : raw;

    // Task notifications first: a ``` fence inside their <result> would otherwise split the
    // notification and show its raw XML.
    int lastIndex = 0;
    for (final match in _taskNotifRegex.allMatches(normalized)) {
      _addTextAndCode(segments, normalized.substring(lastIndex, match.start));
      final data = TaskNotificationData.tryParse(match.group(0)!);
      if (data != null) {
        segments.add(_TaskNotificationSegment(data));
      } else {
        _addTextAndCode(segments, match.group(0)!);
      }
      lastIndex = match.end;
    }
    _addTextAndCode(segments, normalized.substring(lastIndex));
    return segments;
  }

  static final RegExp _tableSeparatorRegex = RegExp(r'^\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?$');

  /// A table row is any line with a pipe; the header is the first such line
  /// followed directly by a `|---|` separator row.
  static bool _isTableRow(String line) => line.trim().contains('|');

  static bool _isTableHeaderAt(List<String> lines, int index) {
    if (index + 1 >= lines.length || !_isTableRow(lines[index])) return false;
    final separator = lines[index + 1].trim();
    return separator.contains('-') && _tableSeparatorRegex.hasMatch(separator);
  }

  static List<String> _splitTableRow(String line) {
    var content = line.trim();
    if (content.startsWith('|')) content = content.substring(1);
    if (content.endsWith('|')) content = content.substring(0, content.length - 1);
    return content.split(RegExp(r'(?<!\\)\|')).map((c) => c.trim()).toList();
  }

  /// Renders a Markdown table. [rows] holds the header, the separator and the body rows.
  /// The table is as wide as its content and scrolls horizontally inside the block.
  static Widget _buildMarkdownTable(
    List<String> rows,
    FrameTokens tokens, {
    String? cwd,
    AppStrings? strings,
    required TapGestureRecognizer Function(VoidCallback) createTapRecognizer,
    required HostFileOpener opener,
  }) {
    final header = _splitTableRow(rows.first);
    final columnCount = header.length;
    List<String> normalize(List<String> cells) => List.generate(columnCount, (c) => c < cells.length ? cells[c] : '');

    Widget cell(String content, {required bool isHeader}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text.rich(
          _parseInlineSpans(
            content,
            tokens,
            cwd: cwd,
            strings: strings,
            createTapRecognizer: createTapRecognizer,
            opener: opener,
          ),
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: FrameText.fromTokens(tokens).label.fontSize,
            height: 1.45,
            fontWeight: isHeader ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      );
    }

    final tableRows = <TableRow>[
      TableRow(
        decoration: BoxDecoration(color: tokens.surfaceElevated),
        children: [for (final c in normalize(header)) cell(c, isHeader: true)],
      ),
      for (final row in rows.skip(2))
        TableRow(children: [for (final c in normalize(_splitTableRow(row))) cell(c, isHeader: false)]),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder.all(
                color: tokens.border,
                width: 1,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
              ),
              children: tableRows,
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildMarkdownText(
    String text,
    FrameTokens tokens, {
    String? cwd,
    AppStrings? strings,
    required TapGestureRecognizer Function(VoidCallback) createTapRecognizer,
    required HostFileOpener opener,
    Color? textColor,
  }) {
    final rawLines = (text.contains('\r') ? text.replaceAll('\r\n', '\n') : text).split('\n');
    final widgets = <Widget>[];
    final currentPara = StringBuffer();
    final effectiveTextColor = textColor ?? tokens.textPrimary;

    void flushPara() {
      if (currentPara.isNotEmpty) {
        final content = currentPara.toString().trim();
        if (content.isNotEmpty) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text.rich(
                _parseInlineSpans(
                  content,
                  tokens,
                  cwd: cwd,
                  strings: strings,
                  createTapRecognizer: createTapRecognizer,
                  opener: opener,
                ),
                style: TextStyle(
                  color: effectiveTextColor,
                  fontSize: FrameText.fromTokens(tokens).body.fontSize,
                  height: 1.55,
                ),
              ),
            ),
          );
        }
        currentPara.clear();
      }
    }

    for (var i = 0; i < rawLines.length; i++) {
      final line = rawLines[i];
      final trimmed = line.trim();
      if (_isTableHeaderAt(rawLines, i)) {
        flushPara();
        var end = i + 2;
        while (end < rawLines.length && _isTableRow(rawLines[end])) {
          end++;
        }
        widgets.add(
          _buildMarkdownTable(
            rawLines.sublist(i, end),
            tokens,
            cwd: cwd,
            strings: strings,
            createTapRecognizer: createTapRecognizer,
            opener: opener,
          ),
        );
        i = end - 1;
      } else if (trimmed.startsWith('# ') || trimmed.startsWith('## ') || trimmed.startsWith('### ')) {
        flushPara();
        if (trimmed.startsWith('### ')) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(
                trimmed.substring(4),
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FrameText.fromTokens(tokens).bodyLarge.fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        } else if (trimmed.startsWith('## ')) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Container(
                padding: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: tokens.accent, width: 3)),
                ),
                child: Text(
                  trimmed.substring(3),
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FrameText.fromTokens(tokens).title.fontSize,
                    fontWeight: FontWeight.bold,
                    fontFamily: tokens.headingFontFamily,
                  ),
                ),
              ),
            ),
          );
        } else if (trimmed.startsWith('# ')) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 8),
              child: Text(
                trimmed.substring(2),
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FrameText.fromTokens(tokens).heading.fontSize,
                  fontWeight: FontWeight.bold,
                  fontFamily: tokens.headingFontFamily,
                ),
              ),
            ),
          );
        }
      } else if (trimmed.startsWith('> ')) {
        flushPara();
        widgets.add(
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: tokens.surfaceElevated.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border(left: BorderSide(color: tokens.accent.withValues(alpha: 0.6), width: 3)),
            ),
            child: Text.rich(
              _parseInlineSpans(
                trimmed.substring(2).trim(),
                tokens,
                cwd: cwd,
                strings: strings,
                createTapRecognizer: createTapRecognizer,
                opener: opener,
              ),
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FrameText.fromTokens(tokens).body.fontSize,
                fontStyle: FontStyle.italic,
                height: 1.5,
              ),
            ),
          ),
        );
      } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        flushPara();
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 8, left: 4),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: tokens.accent),
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    _parseInlineSpans(
                      trimmed.substring(2).trim(),
                      tokens,
                      cwd: cwd,
                      strings: strings,
                      createTapRecognizer: createTapRecognizer,
                      opener: opener,
                    ),
                    style: TextStyle(
                      color: effectiveTextColor,
                      fontSize: FrameText.fromTokens(tokens).body.fontSize,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (_numberedListRegex.hasMatch(trimmed)) {
        flushPara();
        final match = _numberedListRegex.firstMatch(trimmed)!;
        final numStr = match.group(1)!;
        final itemText = trimmed.substring(match.end).trim();
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 20,
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    '$numStr.',
                    style: TextStyle(
                      color: tokens.accent,
                      fontSize: FrameText.fromTokens(tokens).label.fontSize,
                      fontWeight: FontWeight.bold,
                      fontFamily: tokens.monoFontFamily,
                    ),
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    _parseInlineSpans(
                      itemText,
                      tokens,
                      cwd: cwd,
                      strings: strings,
                      createTapRecognizer: createTapRecognizer,
                      opener: opener,
                    ),
                    style: TextStyle(
                      color: effectiveTextColor,
                      fontSize: FrameText.fromTokens(tokens).body.fontSize,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (trimmed.isEmpty) {
        flushPara();
      } else {
        if (currentPara.isNotEmpty) currentPara.write('\n');
        currentPara.write(line);
      }
    }
    flushPara();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }

  static TextSpan _parseInlineSpans(
    String text,
    FrameTokens tokens, {
    String? cwd,
    AppStrings? strings,
    required TapGestureRecognizer Function(VoidCallback) createTapRecognizer,
    required HostFileOpener opener,
  }) {
    final spans = <InlineSpan>[];

    final lines = text.split('\n');
    for (var l = 0; l < lines.length; l++) {
      final line = lines[l];
      final hasMarkdown =
          line.contains('[') ||
          line.contains('http') ||
          line.contains('file') ||
          line.contains('`') ||
          line.contains('*') ||
          line.contains('/') ||
          line.contains(r'\');
      if (!hasMarkdown) {
        if (line.isNotEmpty) {
          spans.add(TextSpan(text: line));
        }
        if (l < lines.length - 1) {
          spans.add(const TextSpan(text: '\n'));
        }
        continue;
      }

      final matches = <_InlineMatch>[];

      // Markdown links: [label](target)
      for (final m in _mdLinkRegex.allMatches(line)) {
        matches.add(_InlineMatch(m.start, m.end, m.group(1)!, _InlineType.link, target: m.group(2)!));
      }

      // Raw URLs: https://... or file://...
      for (final m in _rawUrlRegex.allMatches(line)) {
        final start = m.start;
        final end = m.end;
        // Skip if already inside a markdown link match
        final overlaps = matches.any(
          (other) => (start >= other.start && start < other.end) || (end > other.start && end <= other.end),
        );
        if (!overlaps) {
          matches.add(_InlineMatch(start, end, m.group(1)!, _InlineType.link, target: m.group(1)!));
        }
      }

      // Inline code: `code`
      for (final m in _inlineCodeRegex.allMatches(line)) {
        final start = m.start;
        final end = m.end;
        final overlaps = matches.any(
          (other) => (start >= other.start && start < other.end) || (end > other.start && end <= other.end),
        );
        if (!overlaps) {
          matches.add(_InlineMatch(start, end, m.group(1)!, _InlineType.code));
        }
      }

      // Bold: **text**
      for (final m in _boldRegex.allMatches(line)) {
        final start = m.start;
        final end = m.end;
        final overlaps = matches.any(
          (other) => (start >= other.start && start < other.end) || (end > other.start && end <= other.end),
        );
        if (!overlaps) {
          matches.add(_InlineMatch(start, end, m.group(1)!, _InlineType.bold));
        }
      }

      // Raw file paths in text (e.g. apps/pi_frame/lib/main.dart)
      for (final m in _rawFilePathRegex.allMatches(line)) {
        final start = m.start;
        final end = m.end;
        final overlaps = matches.any(
          (other) => (start >= other.start && start < other.end) || (end > other.start && end <= other.end),
        );
        if (!overlaps) {
          matches.add(_InlineMatch(start, end, m.group(1)!, _InlineType.filePath, target: m.group(1)!));
        }
      }

      matches.sort((a, b) => a.start.compareTo(b.start));

      int lastEnd = 0;
      for (final m in matches) {
        if (m.start < lastEnd) continue;
        if (m.start > lastEnd) {
          spans.add(TextSpan(text: line.substring(lastEnd, m.start)));
        }
        if (m.type == _InlineType.code) {
          final isFile = isLikelyFilePath(m.text);
          if (!isFile) {
            spans.add(
              TextSpan(
                text: m.text,
                style: TextStyle(
                  color: tokens.textPrimary,
                  backgroundColor: tokens.surfaceElevated,
                  fontFamily: tokens.monoFontFamily,
                  fontSize: FrameText.fromTokens(tokens).label.fontSize,
                ),
              ),
            );
            lastEnd = m.end;
            continue;
          }

          spans.add(
            _buildFileChip(
              displayText: m.text,
              targetPath: m.text,
              tokens: tokens,
              cwd: cwd,
              strings: strings,
              createTapRecognizer: createTapRecognizer,
              opener: opener,
            ),
          );
        } else if (m.type == _InlineType.bold) {
          spans.add(
            TextSpan(
              text: m.text,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        } else if (m.type == _InlineType.filePath) {
          final target = m.target ?? m.text;
          spans.add(
            _buildFileChip(
              displayText: m.text,
              targetPath: target,
              tokens: tokens,
              cwd: cwd,
              strings: strings,
              createTapRecognizer: createTapRecognizer,
              opener: opener,
            ),
          );
        } else if (m.type == _InlineType.link) {
          final targetUrl = m.target ?? m.text;
          final isFile = targetUrl.startsWith('file://') || isLikelyFilePath(targetUrl);
          if (isFile) {
            spans.add(
              _buildFileChip(
                displayText: m.text,
                targetPath: targetUrl,
                tokens: tokens,
                cwd: cwd,
                strings: strings,
                createTapRecognizer: createTapRecognizer,
                opener: opener,
              ),
            );
          } else {
            spans.add(
              _buildWebLink(
                displayText: m.text,
                targetUrl: targetUrl,
                tokens: tokens,
                createTapRecognizer: createTapRecognizer,
                opener: opener,
              ),
            );
          }
        }
        lastEnd = m.end;
      }

      if (lastEnd < line.length) {
        spans.add(TextSpan(text: line.substring(lastEnd)));
      }

      if (l < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }

    return TextSpan(children: spans);
  }

  static InlineSpan _buildFileChip({
    required String displayText,
    required String targetPath,
    required FrameTokens tokens,
    required TapGestureRecognizer Function(VoidCallback) createTapRecognizer,
    required HostFileOpener opener,
    String? cwd,
    AppStrings? strings,
  }) {
    void openFile() => opener.openInOsFileExplorer(targetPath, cwd: cwd);

    return TextSpan(
      children: [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: SelectionContainer.disabled(
            child: Tooltip(
              message: strings?.richContentOpenFileTooltip ?? 'Ctrl+Click to open in File Explorer',
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                // Focusable link (plan 6.1): reachable by Tab, activated by
                // Enter or Space, announced as a link.
                child: Semantics(
                  link: true,
                  label: displayText,
                  child: FrameFocusRing(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      onTap: openFile,
                      child: Container(
                        margin: const EdgeInsets.only(right: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                        decoration: BoxDecoration(
                          color: tokens.surfaceElevated,
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          border: Border.all(color: tokens.accent.withValues(alpha: 0.5)),
                        ),
                        child: Icon(Icons.insert_drive_file_outlined, size: 11, color: tokens.accent),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        TextSpan(
          text: displayText,
          style: TextStyle(
            color: tokens.textPrimary,
            backgroundColor: tokens.surfaceElevated,
            fontFamily: tokens.monoFontFamily,
            fontSize: FrameText.fromTokens(tokens).label.fontSize,
            decoration: TextDecoration.underline,
            decorationColor: tokens.accent.withValues(alpha: 0.6),
          ),
          recognizer: createTapRecognizer(openFile),
        ),
      ],
    );
  }

  static InlineSpan _buildWebLink({
    required String displayText,
    required String targetUrl,
    required FrameTokens tokens,
    required TapGestureRecognizer Function(VoidCallback) createTapRecognizer,
    required HostFileOpener opener,
  }) {
    return TextSpan(
      text: displayText,
      style: TextStyle(
        color: tokens.accent,
        decoration: TextDecoration.underline,
        decorationColor: tokens.accent.withValues(alpha: 0.6),
        fontWeight: FontWeight.w500,
      ),
      recognizer: createTapRecognizer(() => opener.openUrl(targetUrl)),
    );
  }
}

class _RichContentState extends ConsumerState<RichContent> {
  final _tapRecognizers = <TapGestureRecognizer>[];
  String? _cachedText;
  FrameTokens? _cachedTokens;
  String? _cachedCwd;
  AppStrings? _cachedStrings;
  Color? _cachedTextColor;
  Widget? _cachedBuiltWidget;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = safeTranscriptStrings(context);
    final opener = ref.read(hostFileOpenerProvider);
    if (_cachedBuiltWidget != null &&
        _cachedText == widget.text &&
        _cachedCwd == widget.cwd &&
        identical(_cachedTokens, tokens) &&
        _cachedStrings == strings &&
        _cachedTextColor == widget.textColor) {
      return _cachedBuiltWidget!;
    }

    for (final recognizer in _tapRecognizers) {
      recognizer.dispose();
    }
    _tapRecognizers.clear();

    _cachedText = widget.text;
    _cachedTokens = tokens;
    _cachedCwd = widget.cwd;
    _cachedStrings = strings;
    _cachedTextColor = widget.textColor;

    TapGestureRecognizer createTapRecognizer(VoidCallback onTap) {
      final recognizer = TapGestureRecognizer()..onTap = onTap;
      _tapRecognizers.add(recognizer);
      return recognizer;
    }

    final segments = RichContent._parseSegments(widget.text);

    _cachedBuiltWidget = SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: segments.map((seg) {
          if (seg is _CodeSegment) {
            if (seg.language == 'diff') {
              return DiffBlock(diffText: seg.code);
            }
            return CodeBlock(code: seg.code, language: seg.language);
          } else if (seg is _TaskNotificationSegment) {
            return TaskNotificationCard(data: seg.data, cwd: widget.cwd);
          } else if (seg is _TextSegment) {
            return RichContent._buildMarkdownText(
              seg.content,
              tokens,
              cwd: widget.cwd,
              strings: strings,
              createTapRecognizer: createTapRecognizer,
              opener: opener,
              textColor: widget.textColor,
            );
          }
          return const SizedBox.shrink();
        }).toList(),
      ),
    );

    return _cachedBuiltWidget!;
  }

  @override
  void dispose() {
    for (final recognizer in _tapRecognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }
}

enum _InlineType { code, bold, link, filePath }

class _InlineMatch {
  final int start;
  final int end;
  final String text;
  final _InlineType type;
  final String? target;
  _InlineMatch(this.start, this.end, this.text, this.type, {this.target});
}

abstract class _Segment {}

class _TextSegment extends _Segment {
  final String content;
  _TextSegment(this.content);
}

class _TaskNotificationSegment extends _Segment {
  final TaskNotificationData data;
  _TaskNotificationSegment(this.data);
}

class _CodeSegment extends _Segment {
  final String code;
  final String? language;
  _CodeSegment({required this.code, this.language});
}
