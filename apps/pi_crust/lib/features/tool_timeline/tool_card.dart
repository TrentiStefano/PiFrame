import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

import '../../domain/session/session_state.dart';
import '../../ui/code/diff_block.dart';

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
        return Icons.terminal_outlined;
      case 'grep':
      case 'find':
      case 'search':
        return Icons.search_outlined;
      default:
        return Icons.build_circle_outlined;
    }
  }

  Color _getToolColor(String name, CrustTokens tokens) {
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
    final raw = tool.output.trim();
    if (raw.isEmpty) return const _ParsedToolOutput(rawText: '');

    String? summary;
    String? diff;
    String? filename = tool.args['path']?.toString() ??
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
          if (details['patch'] != null && details['patch'].toString().isNotEmpty) {
            diff = details['patch'].toString();
          } else if (details['diff'] != null && details['diff'].toString().isNotEmpty) {
            diff = details['diff'].toString();
          }
        }
      }
    } catch (_) {
      // Not standard JSON - check if details/patch string pattern exists
      final patchMatch = RegExp(r'(?:patch|diff)\s*[:=]\s*([---|\+\+\+|@@].*)', dotAll: true).firstMatch(raw);
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
      final fileMatch = RegExp(r'(?:---|\+\+\+)\s+[ab]?/?([^\s\n]+)').firstMatch(diff);
      if (fileMatch != null) filename = fileMatch.group(1);
    }

    return _ParsedToolOutput(
      summaryText: summary,
      diffText: diff,
      filename: filename,
      rawText: raw,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final tool = widget.tool;
    final isBash = tool.toolName.toLowerCase() == 'bash';
    final parsed = _parseOutput(tool);

    if (!_initializedExpansion) {
      _initializedExpansion = true;
      if (parsed.diffText != null || tool.isRunning) {
        _isExpanded = true;
      }
    }

    // Format arg preview
    String argPreview = '';
    if (tool.args.containsKey('path')) {
      argPreview = tool.args['path'].toString();
    } else if (tool.args.containsKey('file')) {
      argPreview = tool.args['file'].toString();
    } else if (tool.args.containsKey('command')) {
      argPreview = tool.args['command'].toString();
    } else if (tool.args.isNotEmpty) {
      argPreview = tool.args.values.first.toString();
    }

    final hasOutput = tool.output.isNotEmpty;
    final toolColor = _getToolColor(tool.toolName, tokens);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(
          color: tool.isError
              ? tokens.agentError
              : tool.isRunning
              ? tokens.agentWorking.withValues(alpha: 0.6)
              : tokens.border,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row
          TextButton(
            onPressed: hasOutput
                ? () => setState(() => _isExpanded = !_isExpanded)
                : null,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              alignment: Alignment.centerLeft,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(tokens.radiusSm),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: toolColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                    child: Icon(
                      _getToolIcon(tool.toolName),
                      size: 14,
                      color: tool.isError
                          ? tokens.agentError
                          : tool.isRunning
                          ? tokens.agentWorking
                          : toolColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tool.toolName,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 12,
                      fontFamily: tokens.uiFontFamily,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (argPreview.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        argPreview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isBash ? tokens.syntaxNumber : tokens.syntaxString,
                          fontSize: 11.5,
                          fontFamily: tokens.monoFontFamily,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  if (tool.durationMs != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: tokens.surfaceElevated,
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                      ),
                      child: Text(
                        '${tool.durationMs}ms',
                        style: TextStyle(
                          color: tokens.syntaxFunction,
                          fontSize: 10,
                          fontFamily: tokens.monoFontFamily,
                          fontWeight: FontWeight.w500,
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
                  if (hasOutput) ...[
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

          // Output body (if expanded or running)
          if (hasOutput && (_isExpanded || tool.isRunning)) ...[
            Divider(color: tokens.border, height: 1),
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
                            Icon(Icons.check, size: 13, color: tokens.syntaxString),
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
            ] else
              Container(
                padding: const EdgeInsets.all(8),
                constraints: BoxConstraints(maxHeight: _isExpanded ? 320 : 120),
                decoration: BoxDecoration(
                  color: isBash
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
              ),
          ],
        ],
      ),
    );
  }
}
