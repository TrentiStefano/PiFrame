import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui/code/code_block.dart';
import '../../ui/code/diff_block.dart';

Future<void> _openUrl(String url) async {
  try {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await launchUrl(uri);
    }
  } catch (_) {
    try {
      if (Platform.isWindows) {
        await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      }
    } catch (_) {}
  }
}

Future<void> openInOsFileExplorer(String rawPath, {String? cwd}) async {
  try {
    String resolved = rawPath.trim();
    if (resolved.startsWith('file://')) {
      final uri = Uri.tryParse(resolved);
      if (uri != null && uri.toFilePath().isNotEmpty) {
        resolved = uri.toFilePath();
      } else {
        resolved = resolved.replaceFirst(RegExp(r'^file://+'), '');
      }
    }
    // Remove query, anchor or line:col numbers like :42:10 or #L10-20
    resolved = resolved.replaceAll(RegExp(r'#.*$'), '');
    resolved = resolved.replaceAll(RegExp(r':\d+(?::\d+)?$'), '');

    String targetPath = resolved;
    if (cwd != null && cwd.isNotEmpty) {
      final isAbsolute = Platform.isWindows
          ? RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(targetPath) ||
                targetPath.startsWith(r'\\')
          : targetPath.startsWith('/');
      if (!isAbsolute) {
        final separator = Platform.isWindows ? '\\' : '/';
        final normalizedCwd = cwd.endsWith('/') || cwd.endsWith('\\')
            ? cwd.substring(0, cwd.length - 1)
            : cwd;
        targetPath = '$normalizedCwd$separator$targetPath';
      }
    }

    if (Platform.isWindows) {
      final winPath = targetPath.replaceAll('/', '\\');
      final file = File(winPath);
      final dir = Directory(winPath);
      if (file.existsSync()) {
        await Process.run('explorer.exe', ['/select,', winPath]);
      } else if (dir.existsSync()) {
        await Process.run('explorer.exe', [winPath]);
      } else {
        await Process.run('explorer.exe', ['/select,', winPath]);
      }
    } else if (Platform.isMacOS) {
      final file = File(targetPath);
      if (file.existsSync()) {
        await Process.run('open', ['-R', targetPath]);
      } else {
        await Process.run('open', [targetPath]);
      }
    } else if (Platform.isLinux) {
      final file = File(targetPath);
      if (file.existsSync()) {
        await Process.run('xdg-open', [file.parent.path]);
      } else {
        await Process.run('xdg-open', [targetPath]);
      }
    }
  } catch (e) {
    debugPrint('openInOsFileExplorer error: $e');
  }
}

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

class RichContent extends StatefulWidget {
  final String text;
  final String? cwd;

  const RichContent({super.key, required this.text, this.cwd});

  @override
  State<RichContent> createState() => _RichContentState();

  static final RegExp _fenceRegex = RegExp(
    r'```([a-zA-Z0-9_\-\+]*)\n([\s\S]*?)```',
  );
  static final RegExp _numberedListRegex = RegExp(r'^(\d+)\.\s');
  static final RegExp _mdLinkRegex = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');
  static final RegExp _rawUrlRegex = RegExp(
    r'(?<![\(\[])(https?://[^\s\)]+|file://[^\s\)]+)',
  );
  static final RegExp _inlineCodeRegex = RegExp(r'`([^`]+)`');
  static final RegExp _boldRegex = RegExp(r'\*\*([^*]+)\*\*');
  static final RegExp _rawFilePathRegex = RegExp(
    r'(?<![/\w\-])((?:[a-zA-Z]:[\\/]|(?:\.{1,2}[\\/])|(?:[\w\-]+[\\/]))[\w\-./\\]+\.(?:dart|ts|js|jsx|tsx|json|yaml|yml|md|txt|html|css|sh|ps1|bat|cpp|c|h|rs|go|py|lock|toml))\b',
  );

  static List<_Segment> _parseSegments(String raw) {
    final segments = <_Segment>[];
    final normalized = raw.contains('\r') ? raw.replaceAll('\r\n', '\n') : raw;

    int lastIndex = 0;
    for (final match in _fenceRegex.allMatches(normalized)) {
      if (match.start > lastIndex) {
        final textPart = normalized.substring(lastIndex, match.start).trim();
        if (textPart.isNotEmpty) {
          segments.add(_TextSegment(textPart));
        }
      }

      final lang = match.group(1);
      final code = match.group(2) ?? '';
      segments.add(_CodeSegment(code: code, language: lang));
      lastIndex = match.end;
    }

    if (lastIndex < normalized.length) {
      final remaining = normalized.substring(lastIndex).trim();
      if (remaining.isNotEmpty) {
        segments.add(_TextSegment(remaining));
      }
    }

    if (segments.isEmpty && normalized.isNotEmpty) {
      segments.add(_TextSegment(normalized));
    }

    return segments;
  }

  static Widget _buildMarkdownText(
    String text,
    CrustTokens tokens, {
    String? cwd,
  }) {
    final rawLines =
        (text.contains('\r') ? text.replaceAll('\r\n', '\n') : text).split(
          '\n',
        );
    final widgets = <Widget>[];
    final currentPara = StringBuffer();

    void flushPara() {
      if (currentPara.isNotEmpty) {
        final content = currentPara.toString().trim();
        if (content.isNotEmpty) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text.rich(
                _parseInlineSpans(content, tokens, cwd: cwd),
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 13.5,
                  height: 1.55,
                ),
              ),
            ),
          );
        }
        currentPara.clear();
      }
    }

    for (final line in rawLines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('# ') ||
          trimmed.startsWith('## ') ||
          trimmed.startsWith('### ')) {
        flushPara();
        if (trimmed.startsWith('### ')) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(
                trimmed.substring(4),
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 14.5,
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
                  border: Border(
                    left: BorderSide(color: tokens.accent, width: 3),
                  ),
                ),
                child: Text(
                  trimmed.substring(3),
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 16.5,
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
                  fontSize: 20,
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
              border: Border(
                left: BorderSide(
                  color: tokens.accent.withValues(alpha: 0.6),
                  width: 3,
                ),
              ),
            ),
            child: Text.rich(
              _parseInlineSpans(trimmed.substring(2).trim(), tokens, cwd: cwd),
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 13,
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
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tokens.accent,
                    ),
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    _parseInlineSpans(
                      trimmed.substring(2).trim(),
                      tokens,
                      cwd: cwd,
                    ),
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 13.5,
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
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: tokens.monoFontFamily,
                    ),
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    _parseInlineSpans(itemText, tokens, cwd: cwd),
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 13.5,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  static TextSpan _parseInlineSpans(
    String text,
    CrustTokens tokens, {
    String? cwd,
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
        matches.add(
          _InlineMatch(
            m.start,
            m.end,
            m.group(1)!,
            _InlineType.link,
            target: m.group(2)!,
          ),
        );
      }

      // Raw URLs: https://... or file://...
      for (final m in _rawUrlRegex.allMatches(line)) {
        final start = m.start;
        final end = m.end;
        // Skip if already inside a markdown link match
        final overlaps = matches.any(
          (other) =>
              (start >= other.start && start < other.end) ||
              (end > other.start && end <= other.end),
        );
        if (!overlaps) {
          matches.add(
            _InlineMatch(
              start,
              end,
              m.group(1)!,
              _InlineType.link,
              target: m.group(1)!,
            ),
          );
        }
      }

      // Inline code: `code`
      for (final m in _inlineCodeRegex.allMatches(line)) {
        final start = m.start;
        final end = m.end;
        final overlaps = matches.any(
          (other) =>
              (start >= other.start && start < other.end) ||
              (end > other.start && end <= other.end),
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
          (other) =>
              (start >= other.start && start < other.end) ||
              (end > other.start && end <= other.end),
        );
        if (!overlaps) {
          matches.add(_InlineMatch(start, end, m.group(1)!, _InlineType.bold));
        }
      }

      // Raw file paths in text (e.g. apps/pi_crust/lib/main.dart)
      for (final m in _rawFilePathRegex.allMatches(line)) {
        final start = m.start;
        final end = m.end;
        final overlaps = matches.any(
          (other) =>
              (start >= other.start && start < other.end) ||
              (end > other.start && end <= other.end),
        );
        if (!overlaps) {
          matches.add(
            _InlineMatch(
              start,
              end,
              m.group(1)!,
              _InlineType.filePath,
              target: m.group(1)!,
            ),
          );
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
                  fontSize: 12,
                ),
              ),
            );
            lastEnd = m.end;
            continue;
          }

          Widget codeWidget = Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            constraints: const BoxConstraints(maxWidth: 320),
            decoration: BoxDecoration(
              color: tokens.surfaceElevated,
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border.all(
                color: tokens.accent.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.insert_drive_file_outlined,
                  size: 11,
                  color: tokens.accent,
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    m.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontFamily: tokens.monoFontFamily,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          );

          if (isFile) {
            codeWidget = Tooltip(
              message: 'CTRL+clic per aprire in Esplora file',
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final isControl =
                        HardwareKeyboard.instance.isControlPressed ||
                        HardwareKeyboard.instance.isMetaPressed;
                    if (isControl) {
                      openInOsFileExplorer(m.text, cwd: cwd);
                    }
                  },
                  child: codeWidget,
                ),
              ),
            );
          }

          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: codeWidget,
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
            TextSpan(
              text: m.text,
              style: TextStyle(
                color: tokens.accent,
                decoration: TextDecoration.underline,
                decorationColor: tokens.accent.withValues(alpha: 0.5),
                fontFamily: tokens.monoFontFamily,
                fontSize: 12.5,
              ),
              mouseCursor: SystemMouseCursors.click,
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  final isControl =
                      HardwareKeyboard.instance.isControlPressed ||
                      HardwareKeyboard.instance.isMetaPressed;
                  if (isControl) {
                    openInOsFileExplorer(target, cwd: cwd);
                  }
                },
            ),
          );
        } else if (m.type == _InlineType.link) {
          final targetUrl = m.target ?? m.text;
          final isFile =
              targetUrl.startsWith('file://') || isLikelyFilePath(targetUrl);
          spans.add(
            TextSpan(
              text: m.text,
              style: TextStyle(
                color: tokens.accent,
                decoration: TextDecoration.underline,
                decorationColor: tokens.accent.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500,
              ),
              mouseCursor: SystemMouseCursors.click,
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  final isControl =
                      HardwareKeyboard.instance.isControlPressed ||
                      HardwareKeyboard.instance.isMetaPressed;
                  if (isFile || isControl) {
                    if (isFile) {
                      openInOsFileExplorer(targetUrl, cwd: cwd);
                    } else if (targetUrl.startsWith('http://') ||
                        targetUrl.startsWith('https://')) {
                      _openUrl(targetUrl);
                    } else {
                      openInOsFileExplorer(targetUrl, cwd: cwd);
                    }
                  } else {
                    _openUrl(targetUrl);
                  }
                },
            ),
          );
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
}

class _RichContentState extends State<RichContent> {
  String? _cachedText;
  CrustTokens? _cachedTokens;
  String? _cachedCwd;
  Widget? _cachedBuiltWidget;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (_cachedBuiltWidget != null &&
        _cachedText == widget.text &&
        _cachedCwd == widget.cwd &&
        identical(_cachedTokens, tokens)) {
      return _cachedBuiltWidget!;
    }

    _cachedText = widget.text;
    _cachedTokens = tokens;
    _cachedCwd = widget.cwd;

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
          } else if (seg is _TextSegment) {
            return RichContent._buildMarkdownText(
              seg.content,
              tokens,
              cwd: widget.cwd,
            );
          }
          return const SizedBox.shrink();
        }).toList(),
      ),
    );

    return _cachedBuiltWidget!;
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

class _CodeSegment extends _Segment {
  final String code;
  final String? language;
  _CodeSegment({required this.code, this.language});
}
