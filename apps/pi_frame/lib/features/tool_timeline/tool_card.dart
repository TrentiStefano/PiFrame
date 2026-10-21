import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../domain/session/session_state.dart';
import '../../ui/code/diff_block.dart';
import '../transcript/task_notification_card.dart';

class _ParsedToolOutput {
  final String? summaryText;
  final String? diffText;
  final String? filename;
  final String rawText;

  const _ParsedToolOutput({
    this.summaryText,
    this.diffText,
    this.filename,
    required this.rawText,
  });
}

class ToolCard extends StatefulWidget {
  final ToolExecutionState tool;

  const ToolCard({super.key, required this.tool});

  @override
  State<ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<ToolCard> {
  bool _isExpanded = false;
  bool _initializedExpansion = false;
  Timer? _liveTimer;
  DateTime? _startedAt;

  static final RegExp _patchRegex = RegExp(
    r'(?:patch|diff)\s*[:=]\s*([---|\+\+\+|@@].*)',
    dotAll: true,
  );
  static final RegExp _fileRegex = RegExp(
    r'(?:---|\+\+\+)\s+[ab]?/?([^\s\n]+)',
  );
  static final RegExp _nonDigits = RegExp(r'[^0-9]');

  String? _cachedOutput;
  _ParsedToolOutput? _cachedParsedOutput;

  @override
  void initState() {
    super.initState();
    if (widget.tool.isRunning) {
      _startedAt = DateTime.now();
      _startLiveTimer();
    }
  }

  @override
  void didUpdateWidget(covariant ToolCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tool.isRunning && !oldWidget.tool.isRunning) {
      _startedAt = DateTime.now();
      _startLiveTimer();
    } else if (!widget.tool.isRunning && oldWidget.tool.isRunning) {
      _stopLiveTimer();
    }
  }

  void _startLiveTimer() {
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.tool.isRunning) {
        setState(() {});
      }
    });
  }

  void _stopLiveTimer() {
    _liveTimer?.cancel();
    _liveTimer = null;
  }

  @override
  void dispose() {
    _stopLiveTimer();
    super.dispose();
  }

  bool _isTerminalTool(String name) {
    switch (name.toLowerCase()) {
      case 'bash':
      case 'terminal':
      case 'exec':
      case 'run_command':
      case 'sh':
      case 'shell':
      case 'cmd':
      case 'powershell':
        return true;
      default:
        return false;
    }
  }

  String? _getCommandText(ToolExecutionState tool) {
    if (tool.args.containsKey('command') && tool.args['command'] != null) {
      return tool.args['command'].toString();
    }
    if (tool.args.containsKey('cmd') && tool.args['cmd'] != null) {
      return tool.args['cmd'].toString();
    }
    if (tool.args.containsKey('CommandLine') &&
        tool.args['CommandLine'] != null) {
      return tool.args['CommandLine'].toString();
    }
    if (tool.args.containsKey('script') && tool.args['script'] != null) {
      return tool.args['script'].toString();
    }
    if (_isTerminalTool(tool.toolName) && tool.args.isNotEmpty) {
      final firstVal = tool.args.values.first;
      if (firstVal is String && firstVal.trim().isNotEmpty) {
        return firstVal;
      }
    }
    return null;
  }

  int? _parseTimeoutSeconds(Map<String, dynamic> args) {
    for (final key in [
      'timeout',
      'timeoutSeconds',
      'timeout_seconds',
      'timeoutMs',
      'timeout_ms',
      'WaitMsBeforeAsync',
    ]) {
      if (args.containsKey(key)) {
        final val = args[key];
        if (val is num) {
          if (key.toLowerCase().contains('ms')) {
            return (val / 1000).ceil();
          }
          if (val > 1000) {
            return (val / 1000).ceil();
          }
          return val.toInt();
        }
        if (val is String) {
          final trimmed = val.trim().toLowerCase();
          final numPart = int.tryParse(trimmed.replaceAll(_nonDigits, ''));
          if (numPart != null) {
            if (trimmed.endsWith('ms')) return (numPart / 1000).ceil();
            if (numPart > 1000) return (numPart / 1000).ceil();
            return numPart;
          }
        }
      }
    }
    return null;
  }

  IconData _getToolIcon(String name) {
    switch (name.toLowerCase()) {
      case 'read':
      case 'read_file':
        return Icons.file_open_outlined;
      case 'write':
      case 'write_file':
        return Icons.save_outlined;
      case 'edit':
      case 'edit_file':
        return Icons.edit_note_outlined;
      case 'bash':
      case 'terminal':
      case 'exec':
      case 'run_command':
      case 'sh':
      case 'shell':
      case 'cmd':
      case 'powershell':
        return Icons.terminal_outlined;
      case 'grep':
      case 'find':
      case 'search':
        return Icons.search_outlined;
      default:
        return Icons.build_circle_outlined;
    }
  }

  Color _getToolColor(String name, FrameTokens tokens) {
    switch (name.toLowerCase()) {
      case 'read':
      case 'read_file':
        return tokens.syntaxFunction;
      case 'write':
      case 'write_file':
      case 'edit':
      case 'edit_file':
        return tokens.syntaxString;
      case 'bash':
      case 'terminal':
      case 'exec':
      case 'run_command':
      case 'sh':
      case 'shell':
      case 'cmd':
      case 'powershell':
        return tokens.syntaxNumber;
      case 'grep':
      case 'find':
      case 'search':
        return tokens.syntaxKeyword;
      default:
        return tokens.accent;
    }
  }

  _ParsedToolOutput _parseOutput(ToolExecutionState tool) {
    if (_cachedParsedOutput != null && _cachedOutput == tool.output) {
      return _cachedParsedOutput!;
    }

    final raw = tool.output.trim();
    if (raw.isEmpty) {
      _cachedOutput = tool.output;
      _cachedParsedOutput = const _ParsedToolOutput(rawText: '');
      return _cachedParsedOutput!;
    }

    String? summary;
    String? diff;
    String? filename =
        tool.args['path']?.toString() ??
        tool.args['file']?.toString() ??
        tool.args['filePath']?.toString();

    // 1. Try parsing JSON output
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        // Content array
        if (decoded['content'] is List) {
          final parts = <String>[];
          for (final item in decoded['content']) {
            if (item is Map && item['type'] == 'text' && item['text'] != null) {
              parts.add(item['text'].toString());
            }
          }
          if (parts.isNotEmpty) summary = parts.join('\n');
        }

        // Details map
        if (decoded['details'] is Map) {
          final details = decoded['details'] as Map;
          if (details['patch'] != null &&
              details['patch'].toString().isNotEmpty) {
            diff = details['patch'].toString();
          } else if (details['diff'] != null &&
              details['diff'].toString().isNotEmpty) {
            diff = details['diff'].toString();
          }
        }
      }
    } catch (_) {
      // Not standard JSON - check if details/patch string pattern exists
      final patchMatch = _patchRegex.firstMatch(raw);
      if (patchMatch != null) {
        diff = patchMatch.group(1);
      }
    }

    // Direct unified diff in raw output
    if (diff == null && (raw.contains('@@ -') || raw.startsWith('--- '))) {
      diff = raw;
    }

    // Infer filename from diff header if needed
    if (filename == null && diff != null) {
      final fileMatch = _fileRegex.firstMatch(diff);
      if (fileMatch != null) filename = fileMatch.group(1);
    }

    _cachedOutput = tool.output;
    _cachedParsedOutput = _ParsedToolOutput(
      summaryText: summary,
      diffText: diff,
      filename: filename,
      rawText: raw,
    );
    return _cachedParsedOutput!;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final tool = widget.tool;
    final isTerminal = _isTerminalTool(tool.toolName);
    final commandText = _getCommandText(tool);
    final timeoutSeconds = _parseTimeoutSeconds(tool.args);
    final parsed = _parseOutput(tool);

    if (!_initializedExpansion) {
      _initializedExpansion = true;
      _isExpanded = false;
    }

    // Format arg preview
    String argPreview = '';
    if (tool.args.containsKey('path')) {
      argPreview = tool.args['path'].toString();
    } else if (tool.args.containsKey('file')) {
      argPreview = tool.args['file'].toString();
    } else if (tool.args.containsKey('command')) {
      argPreview = tool.args['command'].toString();
    } else if (commandText != null) {
      argPreview = commandText;
    } else if (tool.args.isNotEmpty) {
      argPreview = tool.args.values.first.toString();
    }

    final hasOutput = tool.output.isNotEmpty;
    final canExpand =
        hasOutput || commandText != null || parsed.diffText != null;
    final toolColor = _getToolColor(tool.toolName, tokens);

    // Timing calculation
    final durationMs =
        tool.durationMs ??
        (tool.isRunning && _startedAt != null
            ? DateTime.now().difference(_startedAt!).inMilliseconds
            : null);
    final durationSeconds = durationMs != null
        ? (durationMs / 1000).floor()
        : 0;
    final isOver5Seconds = durationSeconds >= 5;

    return RepaintBoundary(
      child: Container(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header row
            TextButton(
              onPressed: canExpand
                  ? () => setState(() => _isExpanded = !_isExpanded)
                  : null,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                alignment: Alignment.centerLeft,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 2.5,
                ),
                child: Row(
                  children: [
                    Icon(
                      _getToolIcon(tool.toolName),
                      size: 14,
                      color: tool.isError
                          ? tokens.agentError
                          : tool.isRunning
                          ? tokens.agentWorking
                          : toolColor,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        tool.toolName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 11.5,
                          fontFamily: tokens.uiFontFamily,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (argPreview.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          argPreview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isTerminal
                                ? tokens.syntaxNumber
                                : tokens.syntaxString,
                            fontSize: 11,
                            fontFamily: tokens.monoFontFamily,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    // Seconds counter or ms duration badge
                    if (isOver5Seconds) ...[
                      const SizedBox(width: 6),
                      Container(
                        key: const ValueKey('tool-card-seconds-counter'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.surfaceElevated,
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          border: Border.all(color: tokens.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 11,
                              color: tool.isRunning
                                  ? tokens.agentWorking
                                  : tokens.textMuted,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${durationSeconds}s',
                              style: TextStyle(
                                color: tokens.textSecondary,
                                fontSize: 10,
                                fontFamily: tokens.monoFontFamily,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (timeoutSeconds != null) ...[
                              Text(
                                ' / ${timeoutSeconds}s',
                                style: TextStyle(
                                  color: tokens.textMuted,
                                  fontSize: 9.5,
                                  fontFamily: tokens.monoFontFamily,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ] else if (tool.durationMs != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.surfaceElevated,
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          border: Border.all(color: tokens.border),
                        ),
                        child: Text(
                          '${tool.durationMs}ms',
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 9.5,
                            fontFamily: tokens.monoFontFamily,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    if (timeoutSeconds != null && !isOver5Seconds) ...[
                      const SizedBox(width: 6),
                      Container(
                        key: const ValueKey('tool-card-timeout-badge'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.surfaceElevated,
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          border: Border.all(color: tokens.border),
                        ),
                        child: Text(
                          'limite ${timeoutSeconds}s',
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 9.5,
                            fontFamily: tokens.monoFontFamily,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    if (tool.isRunning)
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: tokens.agentWorking,
                        ),
                      )
                    else if (tool.isError)
                      Icon(
                        Icons.error_outline,
                        size: 14,
                        color: tokens.agentError,
                      )
                    else
                      Icon(
                        Icons.check_circle_outline,
                        size: 14,
                        color: tokens.agentSettled,
                      ),
                    if (canExpand) ...[
                      const SizedBox(width: 4),
                      Icon(
                        _isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 14,
                        color: tokens.textMuted,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Output / command body (if expanded)
            if (canExpand && _isExpanded) ...[
              Divider(color: tokens.border, height: 1),

              // Full bash / terminal command section
              if (commandText != null) ...[
                Container(
                  key: const ValueKey('tool-card-expanded-command'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.background,
                    borderRadius: !hasOutput && parsed.diffText == null
                        ? BorderRadius.only(
                            bottomLeft: Radius.circular(tokens.radiusSm),
                            bottomRight: Radius.circular(tokens.radiusSm),
                          )
                        : BorderRadius.zero,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.terminal,
                            size: 13,
                            color: tokens.syntaxNumber,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isTerminal
                                ? 'Comando lanciato'
                                : 'Parametri comando',
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (timeoutSeconds != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              key: const ValueKey('tool-card-expanded-timeout'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.surfaceElevated,
                                borderRadius: BorderRadius.circular(
                                  tokens.radiusSm,
                                ),
                                border: Border.all(color: tokens.border),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.timer_outlined,
                                    size: 10,
                                    color: tokens.textMuted,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Timeout: ${timeoutSeconds}s',
                                    style: TextStyle(
                                      color: tokens.textMuted,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const Spacer(),
                          InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () {
                              Clipboard.setData(
                                ClipboardData(text: commandText),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Comando copiato negli appunti',
                                  ),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.copy,
                                    size: 11,
                                    color: tokens.textMuted,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Copia comando',
                                    style: TextStyle(
                                      color: tokens.textMuted,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: tokens.surface,
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          border: Border.all(color: tokens.borderStrong),
                        ),
                        child: SelectableText(
                          commandText,
                          style: TextStyle(
                            color: tokens.syntaxNumber,
                            fontSize: 12,
                            fontFamily: tokens.monoFontFamily,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasOutput || parsed.diffText != null)
                  Divider(color: tokens.border, height: 1),
              ],

              if (parsed.diffText != null) ...[
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (parsed.summaryText != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check,
                                size: 13,
                                color: tokens.syntaxString,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  parsed.summaryText!,
                                  style: TextStyle(
                                    color: tokens.textSecondary,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      DiffBlock(
                        diffText: parsed.diffText!,
                        filename: parsed.filename,
                      ),
                    ],
                  ),
                ),
              ] else if (hasOutput) ...[
                Builder(
                  builder: (context) {
                    final notifData = TaskNotificationData.tryParse(tool.output);
                    if (notifData != null) {
                      return Padding(
                        padding: const EdgeInsets.all(8),
                        child: TaskNotificationCard(data: notifData),
                      );
                    }
                    return Container(
                      padding: const EdgeInsets.all(8),
                      constraints: BoxConstraints(
                        maxHeight: _isExpanded ? 320 : 120,
                      ),
                      decoration: BoxDecoration(
                        color: isTerminal
                            ? tokens.background
                            : tokens.surfaceElevated.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(tokens.radiusSm),
                          bottomRight: Radius.circular(tokens.radiusSm),
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          tool.output,
                          style: TextStyle(
                            color: tool.isError
                                ? tokens.agentError
                                : tokens.textSecondary,
                            fontSize: 11.5,
                            fontFamily: tokens.monoFontFamily,
                            height: 1.4,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
