import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../workspace/repository_workspace.dart';

class InstructionFileDialog extends ConsumerStatefulWidget {
  final String folder;
  final String? sessionId;

  const InstructionFileDialog({
    super.key,
    required this.folder,
    this.sessionId,
  });

  static Future<void> show(
    BuildContext context, {
    required String folder,
    String? sessionId,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => InstructionFileDialog(
        folder: folder,
        sessionId: sessionId,
      ),
    );
  }

  @override
  ConsumerState<InstructionFileDialog> createState() =>
      _InstructionFileDialogState();
}

class _InstructionFileDialogState extends ConsumerState<InstructionFileDialog> {
  static const List<String> standardFiles = [
    'AGENTS.md',
    'CLAUDE.md',
    'GEMINI.md',
    '.github/copilot-instructions.md',
    '.cursorrules',
    '.windsurfrules',
  ];

  late String _selectedFile;
  final Map<String, bool> _fileExists = {};
  final TextEditingController _contentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _initialContent = '';
  bool _loading = false;
  bool _saving = false;
  String? _errorMessage;

  bool get _isDirty => _contentController.text != _initialContent;

  String _fullPath(String fileName) {
    final cleanFolder = widget.folder.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
    final cleanFile = fileName.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
    return '$cleanFolder/$cleanFile';
  }

  String _folderName(String path) {
    final parts = path
        .replaceAll('\\', '/')
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? 'Repository' : parts.last;
  }

  @override
  void initState() {
    super.initState();
    _selectedFile = standardFiles.first;
    _scanAndLoad();
  }

  @override
  void dispose() {
    _contentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scanAndLoad() {
    setState(() {
      _errorMessage = null;
    });

    try {
      for (final f in standardFiles) {
        final path = _fullPath(f);
        final file = File(path);
        _fileExists[f] = file.existsSync();
      }

      // Pick first file that exists, or default to AGENTS.md
      final firstExisting = standardFiles.firstWhere(
        (f) => _fileExists[f] == true,
        orElse: () => standardFiles.first,
      );
      _selectedFile = firstExisting;
      _loadFileContent(_selectedFile);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Errore scansione file: $e';
          _loading = false;
        });
      }
    }
  }

  String _getStarterTemplate(String fileName) {
    final baseName = fileName.split('/').last.toUpperCase();
    if (baseName.contains('AGENT')) {
      return '# Agent Instructions\n\n'
          '## Project Overview\n'
          'Short description of the project, technology stack, and architecture.\n\n'
          '## Development Workflow\n'
          '- Commands to build, run, and test the project.\n\n'
          '## Guidelines\n'
          '- Key architectural principles, code conventions, and safety constraints.\n';
    } else if (baseName.contains('CLAUDE')) {
      return '# Claude Guidelines\n\n'
          '## Build & Test Commands\n'
          '- Build: \n'
          '- Test: \n\n'
          '## Architecture & Conventions\n'
          '- Code standards and style preferences.\n';
    } else if (baseName.contains('GEMINI')) {
      return '# Gemini Context & Instructions\n\n'
          '## Repository Guidelines\n'
          '- Key context for Gemini coding assistant.\n';
    } else if (fileName.contains('copilot-instructions')) {
      return '# GitHub Copilot Instructions\n\n'
          '## Instructions\n'
          '- Specific guidance for Copilot in this codebase.\n';
    }
    return '# Instructions for $fileName\n\n'
        '## Guidelines\n'
        '- Repository instructions and rules.\n';
  }

  void _loadFileContent(String fileName) {
    final path = _fullPath(fileName);
    final file = File(path);

    String content = '';
    if (file.existsSync()) {
      try {
        content = file.readAsStringSync();
      } catch (_) {
        content = '';
      }
    } else {
      content = _getStarterTemplate(fileName);
    }

    if (mounted) {
      setState(() {
        _contentController.text = content;
        _initialContent = content;
        _loading = false;
      });
    }
  }

  Future<void> _selectFile(String fileName) async {
    if (fileName == _selectedFile) return;

    if (_isDirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final tokens = context.tokens;
          return AlertDialog(
            backgroundColor: tokens.surfaceElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusMd),
              side: BorderSide(color: tokens.borderStrong),
            ),
            title: Text(
              'Modifiche non salvate',
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              'Hai modifiche non salvate su $_selectedFile. Vuoi ignorarle e passare a $fileName?',
              style: TextStyle(color: tokens.textSecondary, fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('Annulla', style: TextStyle(color: tokens.textMuted)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: tokens.danger,
                  foregroundColor: tokens.accentContrast,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Ignora modifiche'),
              ),
            ],
          );
        },
      );

      if (discard != true) return;
    }

    setState(() {
      _selectedFile = fileName;
      _errorMessage = null;
    });

    _loadFileContent(fileName);
  }

  void _saveCurrentFile() {
    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final path = _fullPath(_selectedFile);
      final file = File(path);

      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }

      file.writeAsStringSync(_contentController.text);

      _initialContent = _contentController.text;
      _fileExists[_selectedFile] = true;

      // If active session exists, refresh workspace files
      if (widget.sessionId != null) {
        try {
          ref
              .read(repositoryStateProvider(widget.sessionId!).notifier)
              .loadFiles();
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File $_selectedFile salvato con successo'),
            backgroundColor: context.tokens.surfaceElevated,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorMessage = 'Errore salvataggio: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final exists = _fileExists[_selectedFile] == true;
    final text = _contentController.text;
    final lineCount = text.isEmpty ? 1 : '\n'.allMatches(text).length + 1;
    final charCount = text.length;

    return Dialog(
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        side: BorderSide(color: tokens.borderStrong, width: 1),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 780,
          maxHeight: 680,
          minWidth: 480,
          minHeight: 400,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Dialog Header
            Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: tokens.border, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                    child: Icon(
                      Icons.integration_instructions_outlined,
                      size: 18,
                      color: tokens.accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Istruzioni repository',
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                fontFamily: tokens.headingFontFamily,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: tokens.surfaceElevated,
                                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                                  border: Border.all(color: tokens.border),
                                ),
                                child: Text(
                                  _folderName(widget.folder),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: tokens.textSecondary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.folder,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 11,
                            fontFamily: tokens.monoFontFamily,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: tokens.textMuted),
                    tooltip: 'Chiudi',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // File selection chip list
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: tokens.surfaceElevated.withValues(alpha: 0.4),
                border: Border(
                  bottom: BorderSide(color: tokens.border, width: 1),
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final f in standardFiles) ...[
                      _buildFileChip(f, tokens),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
            ),

            // Error banner if any
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: tokens.danger.withValues(alpha: 0.15),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 16, color: tokens.danger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: tokens.danger, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            // Editor Status Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: tokens.surface,
                border: Border(
                  bottom: BorderSide(color: tokens.border, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.file_present_outlined,
                    size: 14,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _selectedFile,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 12,
                        fontFamily: tokens.monoFontFamily,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: exists
                          ? tokens.agentSettled.withValues(alpha: 0.12)
                          : tokens.syntaxFunction.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                    child: Text(
                      exists ? 'Presente sul disco' : 'File nuovo',
                      style: TextStyle(
                        color: exists ? tokens.agentSettled : tokens.syntaxFunction,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$lineCount righe · $charCount caratteri',
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 11,
                      fontFamily: tokens.monoFontFamily,
                    ),
                  ),
                ],
              ),
            ),

            // Content Editor
            Expanded(
              child: _loading
                  ? Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: tokens.accent,
                        ),
                      ),
                    )
                  : Container(
                      color: tokens.background,
                      padding: const EdgeInsets.all(12),
                      child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        child: TextField(
                          key: ValueKey('instruction-editor-$_selectedFile'),
                          controller: _contentController,
                          scrollController: _scrollController,
                          maxLines: null,
                          expands: true,
                          keyboardType: TextInputType.multiline,
                          onChanged: (_) => setState(() {}),
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 12.5,
                            fontFamily: tokens.monoFontFamily,
                            height: 1.45,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Inserisci le istruzioni del repository qui...',
                            hintStyle: TextStyle(
                              color: tokens.textMuted,
                              fontFamily: tokens.monoFontFamily,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),

            // Dialog Footer Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: tokens.surface,
                border: Border(
                  top: BorderSide(color: tokens.border, width: 1),
                ),
              ),
              child: Row(
                children: [
                  if (_isDirty)
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: tokens.syntaxNumber,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Modifiche non salvate',
                          style: TextStyle(
                            color: tokens.syntaxNumber,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    )
                  else if (exists)
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 13,
                          color: tokens.agentSettled,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Sincronizzato con il disco',
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.textMuted,
                    ),
                    child: const Text('Chiudi'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    key: const ValueKey('instruction-save-btn'),
                    onPressed: _saving || (!_isDirty && exists)
                        ? null
                        : _saveCurrentFile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tokens.accent,
                      foregroundColor: tokens.accentContrast,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                      ),
                    ),
                    icon: _saving
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: tokens.accentContrast,
                            ),
                          )
                        : const Icon(Icons.save_outlined, size: 16),
                    label: Text(
                      exists ? 'Salva modifiche' : 'Crea e salva file',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileChip(String fileName, FrameTokens tokens) {
    final isSelected = fileName == _selectedFile;
    final exists = _fileExists[fileName] == true;

    return InkWell(
      key: ValueKey('instruction-chip-$fileName'),
      borderRadius: BorderRadius.circular(tokens.radiusSm),
      onTap: () => _selectFile(fileName),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? tokens.accent.withValues(alpha: 0.15)
              : tokens.surface,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(
            color: isSelected
                ? tokens.accent
                : exists
                ? tokens.borderStrong
                : tokens.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: exists ? tokens.agentSettled : tokens.textMuted,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              fileName,
              style: TextStyle(
                color: isSelected
                    ? tokens.textPrimary
                    : exists
                    ? tokens.textSecondary
                    : tokens.textMuted,
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontFamily: tokens.monoFontFamily,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              exists ? '' : '+',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
