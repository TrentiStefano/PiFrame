import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../ui/precision.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../composer/composer_draft.dart';
import '../../../ui/code/code_editor_controller.dart';
import '../../transcript/rich_content.dart';
import '../../../ui/code/syntax_highlighter.dart';
import '../../../ui/frame_dialog.dart';
import '../../../ui/frame_icon_action.dart';
import '../../../ui/frame_snack_bar.dart';
import '../../../data/language/language_settings.dart';
import '../../../data/language/strings_workspace.dart';
import '../../../data/language/strings_errors.dart';
import '../repository_error_callout.dart';
import '../repository_state.dart';
import 'code_line_layout.dart';
import 'repository_file_save.dart';

/// Width of the line-number gutter (plan 9.1).
const double _gutterWidth = 44;

/// Inset of the code text inside the editor surface, on every side.
const double _codePadding = FrameSpace.x3;

/// Gap between the gutter numbers and the right edge of the gutter.
const double _gutterRightInset = FrameSpace.x2;

/// Marks a file with unsaved changes after its name.
const String _dirtyMark = '●';

bool _isMarkdown(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.md') || lower.endsWith('.markdown');
}

/// Markdown and plain text wrap by default. Code does not.
bool _prefersWrap(String path) {
  final language = SyntaxHighlighter.inferLanguage(path);
  return language == 'markdown' || language == 'text' || language == 'txt';
}

class RepositoryEditorPane extends ConsumerStatefulWidget {
  const RepositoryEditorPane({
    super.key,
    required this.sessionId,
    required this.compact,
    required this.readOnly,
    required this.writeBlocked,
    required this.blockReason,
  });

  final String sessionId;
  final bool compact;
  final bool readOnly;
  final bool writeBlocked;
  final String? blockReason;

  @override
  ConsumerState<RepositoryEditorPane> createState() =>
      _RepositoryEditorPaneState();
}

class _RepositoryEditorPaneState extends ConsumerState<RepositoryEditorPane> {
  AppStrings _getStrings() => repositoryStrings(ref);

  CodeEditorController? _editor;
  String? _editorPath;
  bool _previewMarkdown = true;
  bool _wrapLines = false;
  final _markdownScrollController = ScrollController();

  // Vertical scroll of the whole code surface (gutter and text move together).
  final _bodyScrollController = ScrollController();
  // Horizontal scroll, used only when soft wrap is off.
  final _horizontalScrollController = ScrollController();
  final _codeLayout = CodeLineLayout();
  // Top of each line in the code surface, from the last layout pass.
  List<double> _lineTops = const [];

  bool _showFileSearch = false;
  final _fileSearchQueryController = TextEditingController();
  final _fileSearchFocusNode = FocusNode();
  final _editorFocusNode = FocusNode();
  final _textFocusNode = FocusNode();
  bool _fileSearchCaseSensitive = false;
  int _fileSearchCurrentIndex = 0;
  List<TextRange> _fileSearchMatches = const [];

  CodeEditorController _ensureEditor(FrameTokens tokens) {
    if (_editor == null) {
      _editor = CodeEditorController(tokens: tokens, filePath: _editorPath);
    } else {
      _editor!.tokens = tokens;
    }
    return _editor!;
  }

  void _onFileSearchQueryChanged() {
    _updateFileSearch();
  }

  void _openFileSearch() {
    setState(() {
      _showFileSearch = true;
      if (_editor != null &&
          _editor!.selection.isValid &&
          !_editor!.selection.isCollapsed) {
        final start = _editor!.selection.start;
        final end = _editor!.selection.end;
        if (start < end && end <= _editor!.text.length) {
          final selectedText = _editor!.text.substring(start, end);
          if (selectedText.isNotEmpty && !selectedText.contains('\n')) {
            _fileSearchQueryController.text = selectedText;
          }
        }
      }
    });
    _updateFileSearch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fileSearchFocusNode.requestFocus();
        _fileSearchQueryController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _fileSearchQueryController.text.length,
        );
      }
    });
  }

  void _closeFileSearch() {
    setState(() {
      _showFileSearch = false;
      _editor?.searchQuery = '';
      _fileSearchMatches = const [];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _textFocusNode.requestFocus();
    });
  }

  void _updateFileSearch() {
    if (_editor == null) return;
    final query = _fileSearchQueryController.text;
    _editor!.searchQuery = query;
    _editor!.caseSensitive = _fileSearchCaseSensitive;
    final matches = _editor!.findMatches();
    setState(() {
      _fileSearchMatches = matches;
      if (matches.isEmpty) {
        _fileSearchCurrentIndex = 0;
        _editor!.currentMatchIndex = 0;
      } else {
        if (_fileSearchCurrentIndex >= matches.length) {
          _fileSearchCurrentIndex = 0;
        }
        _editor!.currentMatchIndex = _fileSearchCurrentIndex;
        _jumpToMatch(_fileSearchCurrentIndex);
      }
    });
  }

  void _nextFileSearchMatch() {
    if (_fileSearchMatches.isEmpty || _editor == null) return;
    setState(() {
      _fileSearchCurrentIndex =
          (_fileSearchCurrentIndex + 1) % _fileSearchMatches.length;
      _editor!.currentMatchIndex = _fileSearchCurrentIndex;
      _jumpToMatch(_fileSearchCurrentIndex);
    });
  }

  void _prevFileSearchMatch() {
    if (_fileSearchMatches.isEmpty || _editor == null) return;
    setState(() {
      _fileSearchCurrentIndex =
          (_fileSearchCurrentIndex - 1 + _fileSearchMatches.length) %
          _fileSearchMatches.length;
      _editor!.currentMatchIndex = _fileSearchCurrentIndex;
      _jumpToMatch(_fileSearchCurrentIndex);
    });
  }

  void _jumpToMatch(int index) {
    if (_editor == null || index < 0 || index >= _fileSearchMatches.length) {
      return;
    }
    final match = _fileSearchMatches[index];
    _editor!.selection = TextSelection(
      baseOffset: match.start,
      extentOffset: match.end,
    );
  }

  /// Saves [path]. Errors are shown in a snack bar, not thrown.
  Future<void> _saveFile(String path) async {
    final strings = _getStrings();
    try {
      await saveRepositoryFile(context, ref, widget.sessionId, path);
    } catch (error) {
      if (mounted) {
        FrameSnackBar.show(context, message: strings.saveFailed(error), isError: true);
      }
    }
  }

  /// Ctrl/Cmd+S inside the editor. Does nothing when the file is clean or
  /// writes are blocked.
  void _saveIfDirty(String path) {
    final dirty =
        ref.read(repositoryStateProvider(widget.sessionId)).buffers[path]?.dirty ??
        false;
    if (!dirty || widget.writeBlocked) return;
    _saveFile(path);
  }

  /// Closes the file. Unsaved changes ask first (Salva / Non salvare / Annulla).
  Future<void> _closeEditor() async {
    final repo = ref.read(repositoryStateProvider(widget.sessionId));
    if (repo.dirty &&
        !await resolveDirtyRepository(context, ref, widget.sessionId)) {
      return;
    }
    if (!mounted) return;
    ref.read(repositoryStateProvider(widget.sessionId).notifier).showFileList();
  }

  /// Ctrl/Cmd+G: asks for a line number and moves the caret and the view there.
  Future<void> _promptGoToLine() async {
    final editor = _editor;
    if (editor == null) return;
    final strings = _getStrings();
    final lineCount = editor.text.split('\n').length;
    final input = TextEditingController();
    void submit() => Navigator.of(context, rootNavigator: true).pop(true);

    final confirmed = await showFrameDialog<bool>(
      context: context,
      dialog: FrameDialog<bool>(
        title: strings.goToLineTitle,
        body: TextField(
          key: const ValueKey('repository-goto-line-field'),
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => submit(),
          decoration: InputDecoration(
            isDense: true,
            hintText: strings.goToLineHint(lineCount),
          ),
        ),
        actions: [
          FrameDialogAction<bool>(
            label: strings.cancel,
            role: FrameDialogActionRole.cancel,
          ),
          FrameDialogAction<bool>(
            label: strings.goToLineAction,
            role: FrameDialogActionRole.primary,
            value: true,
            key: const ValueKey('repository-goto-line-confirm'),
          ),
        ],
      ),
    );
    final requested = int.tryParse(input.text.trim());
    WidgetsBinding.instance.addPostFrameCallback((_) => input.dispose());
    if (confirmed != true || !mounted) return;
    if (requested == null || requested < 1 || requested > lineCount) {
      FrameSnackBar.show(context, message: strings.invalidLineNumber, isError: true);
      return;
    }
    _jumpToLine(editor, requested - 1);
  }

  void _jumpToLine(CodeEditorController editor, int lineIndex) {
    final lines = editor.text.split('\n');
    var offset = 0;
    for (var i = 0; i < lineIndex && i < lines.length; i++) {
      offset += lines[i].length + 1;
    }
    editor.selection = TextSelection.collapsed(offset: offset);
    if (lineIndex < _lineTops.length && _bodyScrollController.hasClients) {
      final max = _bodyScrollController.position.maxScrollExtent;
      _bodyScrollController.jumpTo(_lineTops[lineIndex].clamp(0.0, max));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _textFocusNode.requestFocus();
    });
  }

  KeyEventResult _onEditorKey(KeyEvent event, String path) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isControl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (!isControl) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyF:
        _openFileSearch();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyG:
        _promptGoToLine();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyS:
        _saveIfDirty(path);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void initState() {
    super.initState();
    _fileSearchQueryController.addListener(_onFileSearchQueryChanged);
  }

  @override
  void didUpdateWidget(RepositoryEditorPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _editorPath = null;
      _editor?.clear();
      _editor?.filePath = null;
      _showFileSearch = false;
      _previewMarkdown = true;
      _fileSearchQueryController.clear();
      _fileSearchMatches = const [];
    }
  }

  @override
  void dispose() {
    _fileSearchQueryController.removeListener(_onFileSearchQueryChanged);
    _fileSearchQueryController.dispose();
    _fileSearchFocusNode.dispose();
    _editorFocusNode.dispose();
    _textFocusNode.dispose();
    _editor?.dispose();
    _markdownScrollController.dispose();
    _bodyScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final editor = _ensureEditor(tokens);
    final repo = ref.watch(repositoryStateProvider(widget.sessionId));
    final path = repo.selectedPath;
    final buffer = path == null ? null : repo.buffers[path];
    if (path != _editorPath) {
      _editorPath = path;
      _previewMarkdown = true;
      _wrapLines = path != null && _prefersWrap(path);
      editor.filePath = path;
      editor.value = TextEditingValue(text: buffer?.content ?? '');
      if (_showFileSearch) {
        _updateFileSearch();
      }
    } else if (buffer != null && editor.text != buffer.content) {
      editor.filePath = path;
      editor.value = TextEditingValue(
        text: buffer.content,
        selection: TextSelection.collapsed(offset: buffer.content.length),
      );
      if (_showFileSearch) {
        _updateFileSearch();
      }
    }
    return _editorPane(
      context,
      tokens,
      repo,
      path,
      buffer,
      widget.writeBlocked,
      widget.blockReason,
      readOnly: widget.readOnly,
      compact: widget.compact,
    );
  }

  Widget _editorPane(
    BuildContext context,
    FrameTokens tokens,
    RepositoryState repo,
    String? path,
    WorkspaceFileBuffer? buffer,
    bool writeBlocked,
    String? blockReason, {
    required bool readOnly,
    required bool compact,
  }) {
    final strings = _getStrings();
    final text = FrameText.of(context);
    if (path == null) {
      return Center(
        child: Text(
          strings.selectAFile,
          style: text.body.copyWith(color: tokens.textMuted),
        ),
      );
    }
    if (buffer == null) {
      final error = repo.error;
      if (error == null) {
        return Center(
          child: Text(
            strings.loadingFiles,
            style: text.body.copyWith(color: tokens.textMuted),
          ),
        );
      }
      return repositoryErrorCallout(strings, error, strings.filesLoadFailed);
    }
    final isMarkdown = _isMarkdown(path);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(FrameSpace.x2),
          child: Row(
            children: [
              if (compact)
                FrameIconAction(
                  key: const ValueKey('repository-editor-back-btn'),
                  icon: Icons.arrow_back_outlined,
                  tooltip: strings.backToFilesTooltip,
                  onPressed: _closeEditor,
                ),
              Expanded(
                child: Row(
                  key: const ValueKey('repository-editor-title'),
                  children: [
                    // The path ellipsizes; the dirty dot sits outside it so a
                    // long name can never hide the unsaved state.
                    Flexible(
                      child: Text(
                        path,
                        style: text.mono.copyWith(color: tokens.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (buffer.dirty) ...[
                      const SizedBox(width: FrameSpace.x1),
                      Text(
                        _dirtyMark,
                        key: const ValueKey('repository-editor-dirty-mark'),
                        style: text.mono.copyWith(color: tokens.accent),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: FrameSpace.x2),
              Tooltip(
                message: strings.saveWithShortcutTooltip,
                child: buffer.dirty
                    ? PressFeedback(enabled: (writeBlocked
                            ? null
                            : () => _saveFile(path)) != null, child: FilledButton(
                        key: const ValueKey('repository-save-btn'),
                        onPressed: writeBlocked
                            ? null
                            : () => _saveFile(path),
                        child: Text(strings.save),
                      ))
                    : TextButton(
                        key: const ValueKey('repository-save-btn'),
                        onPressed: null,
                        child: Text(strings.save),
                      ),
              ),
              const SizedBox(width: FrameSpace.x1),
              FrameIconAction(
                key: const ValueKey('repository-editor-wrap-btn'),
                icon: Icons.wrap_text_outlined,
                tooltip: strings.wrapLinesTooltip,
                selected: _wrapLines,
                onPressed: () => setState(() => _wrapLines = !_wrapLines),
              ),
              FrameIconAction(
                icon: Icons.add_comment_outlined,
                tooltip: strings.addFileToChatTooltip,
                onPressed: () {
                  appendFileMentionToComposer(ref, widget.sessionId, path);
                  FrameSnackBar.show(
                    context,
                    message: strings.addedFileToChat(path),
                  );
                },
              ),
              if (isMarkdown)
                FrameIconAction(
                  key: const ValueKey('repository-markdown-toggle-btn'),
                  icon: _previewMarkdown
                      ? Icons.edit_note_outlined
                      : Icons.visibility_outlined,
                  tooltip: _previewMarkdown
                      ? strings.editMarkdownSourceTooltip
                      : strings.viewMarkdownPreviewTooltip,
                  selected: _previewMarkdown,
                  onPressed: () {
                    setState(() {
                      _previewMarkdown = !_previewMarkdown;
                    });
                  },
                ),
              FrameIconAction(
                key: const ValueKey('repository-editor-search-btn'),
                icon: Icons.search_outlined,
                tooltip: strings.searchInFileTooltip,
                selected: _showFileSearch,
                onPressed: _openFileSearch,
              ),
              FrameIconAction(
                icon: Icons.close_outlined,
                tooltip: strings.closeFileTooltip,
                onPressed: _closeEditor,
              ),
            ],
          ),
        ),
        if (writeBlocked)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: FrameSpace.x3,
              vertical: FrameSpace.x1,
            ),
            color: tokens.signalWarning.withValues(alpha: 0.16),
            child: Text(
              blockReason!,
              style: text.caption.copyWith(color: tokens.textSecondary),
            ),
          ),
        Expanded(
          child: isMarkdown && _previewMarkdown
              ? Container(
                  color: tokens.background,
                  child: Scrollbar(
                    controller: _markdownScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _markdownScrollController,
                      primary: false,
                      padding: const EdgeInsets.symmetric(
                        horizontal: FrameSpace.x6,
                        vertical: FrameSpace.x4,
                      ),
                      child: SelectionArea(
                        child: RichContent(
                          key: ValueKey('repository-md-preview-$path'),
                          text: buffer.content,
                          cwd: repo.rootPath,
                        ),
                      ),
                    ),
                  ),
                )
              : Stack(
                  children: [
                    Focus(
                      focusNode: _editorFocusNode,
                      onKeyEvent: (node, event) => _onEditorKey(event, path),
                      child: _codeSurface(
                        context,
                        tokens,
                        _editor!,
                        path,
                        readOnly: readOnly,
                        writeBlocked: writeBlocked,
                        strings: strings,
                      ),
                    ),
                    if (_showFileSearch)
                      Positioned(
                        top: FrameSpace.x2,
                        right: FrameSpace.x4,
                        child: _fileSearchBar(context, tokens, strings),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// The source view: a gutter with line numbers, the current-line band and
  /// the editable text, all in one vertical scroll so they stay aligned when
  /// lines soft-wrap. With soft wrap off the text scrolls horizontally.
  Widget _codeSurface(
    BuildContext context,
    FrameTokens tokens,
    CodeEditorController editor,
    String path, {
    required bool readOnly,
    required bool writeBlocked,
    required AppStrings strings,
  }) {
    final text = FrameText.of(context);
    final codeStyle = text.monoBody.copyWith(
      color: tokens.textPrimary,
      decoration: TextDecoration.none,
    );
    final numberStyle = text.monoBody.copyWith(color: tokens.textMuted);
    final currentNumberStyle = text.monoBody.copyWith(
      color: tokens.textPrimary,
    );
    final wrap = _wrapLines;
    final textScaler = MediaQuery.textScalerOf(context);

    return ColoredBox(
      color: tokens.background,
      child: ListenableBuilder(
        listenable: editor,
        builder: (context, _) {
          final source = editor.text;
          final lines = source.split('\n');
          final selection = editor.selection;
          final caret = selection.isValid
              ? math.min(math.max(selection.baseOffset, 0), source.length)
              : 0;
          final caretLine = '\n'.allMatches(source.substring(0, caret)).length;

          return LayoutBuilder(
            builder: (context, constraints) {
              final viewportWidth = constraints.maxWidth;
              final viewportHeight = constraints.maxHeight;
              final textAreaWidth = math.max(0.0, viewportWidth - _gutterWidth);
              final wrapWidth = math.max(1.0, textAreaWidth - 2 * _codePadding);

              final heights = _codeLayout.lineHeights(
                lines,
                codeStyle,
                wrap ? wrapWidth : null,
                textScaler: textScaler,
              );
              final tops = <double>[];
              var y = _codePadding;
              for (final height in heights) {
                tops.add(y);
                y += height;
              }
              final contentHeight = math.max(viewportHeight, y + _codePadding);
              _lineTops = tops;

              final fieldWidth = wrap
                  ? textAreaWidth
                  : math.max(
                      textAreaWidth,
                      // The field lays mono text out a few percent wider
                      // than the bare TextPainter measures it, so leave
                      // headroom: a no-wrap line must never soft-wrap, or
                      // the gutter drifts from the text.
                      _codeLayout.widestLineWidth(
                                lines,
                                codeStyle,
                                textScaler: textScaler,
                              ) *
                              1.1 +
                          2 * _codePadding +
                          FrameSpace.x6,
                    );
              final bandTop = caretLine < tops.length
                  ? tops[caretLine]
                  : _codePadding;
              final bandHeight = caretLine < heights.length
                  ? heights[caretLine]
                  : 0.0;

              final field = SizedBox(
                width: fieldWidth,
                height: contentHeight,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: bandTop,
                      height: bandHeight,
                      child: ColoredBox(
                        key: const ValueKey('repository-editor-current-line'),
                        color: tokens.surfaceElevated,
                      ),
                    ),
                    Positioned.fill(
                      child: TextField(
                        key: ValueKey('repository-editor-${widget.sessionId}'),
                        controller: editor,
                        focusNode: _textFocusNode,
                        enabled: !readOnly,
                        onChanged: (value) => ref
                            .read(
                              repositoryStateProvider(widget.sessionId)
                                  .notifier,
                            )
                            .edit(path, value),
                        contextMenuBuilder: (context, editorState) {
                          final value = editorState.textEditingValue;
                          final selection = value.selection;
                          final items = List<ContextMenuButtonItem>.of(
                            editorState.contextMenuButtonItems,
                          );
                          if (selection.isValid && !selection.isCollapsed) {
                            final range = CodeEditorController.selectedLineRange(
                              value.text,
                              selection,
                            );
                            items.add(
                              ContextMenuButtonItem(
                                // The menu label shows the file name so the
                                // line range fits; the chat gets the full path.
                                label: strings.addSelectionToChat(
                                  strings.codeLineReference(
                                    path.split(RegExp(r'[\\/]')).last,
                                    range.start,
                                    range.end,
                                  ),
                                ),
                                onPressed: () {
                                  appendCodeSelectionToComposer(
                                    ref,
                                    widget.sessionId,
                                    path,
                                    value.text,
                                    selection,
                                  );
                                  editorState.hideToolbar();
                                },
                              ),
                            );
                          }
                          return AdaptiveTextSelectionToolbar.buttonItems(
                            anchors: editorState.contextMenuAnchors,
                            buttonItems: items,
                          );
                        },
                        maxLines: null,
                        minLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        style: codeStyle,
                        decoration: InputDecoration(
                          isDense: true,
                          // The app input theme fills and outlines every
                          // field; the code surface is a plain page.
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.all(_codePadding),
                          hintText: writeBlocked
                              ? strings.readOnlyBlockedReason
                              : strings.fileContentHint,
                          hintStyle: codeStyle.copyWith(color: tokens.textMuted),
                        ),
                      ),
                    ),
                  ],
                ),
              );

              final gutter = SizedBox(
                width: _gutterWidth,
                height: contentHeight,
                child: CustomPaint(
                  key: const ValueKey('repository-editor-gutter'),
                  painter: CodeLineGutterPainter(
                    lineCount: lines.length,
                    tops: tops,
                    heights: heights,
                    caretLine: caretLine,
                    numberStyle: numberStyle,
                    currentStyle: currentNumberStyle,
                    scroll: _bodyScrollController,
                    viewportHeight: viewportHeight,
                    padding: _codePadding,
                    rightInset: _gutterRightInset,
                    textScaler: textScaler,
                  ),
                ),
              );

              final row = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  gutter,
                  if (wrap)
                    field
                  else
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _horizontalScrollController,
                        scrollDirection: Axis.horizontal,
                        child: field,
                      ),
                    ),
                ],
              );

              return Scrollbar(
                controller: _bodyScrollController,
                child: SingleChildScrollView(
                  controller: _bodyScrollController,
                  child: SizedBox(
                    width: viewportWidth,
                    height: contentHeight,
                    child: row,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _fileSearchBar(
    BuildContext context,
    FrameTokens tokens,
    AppStrings strings,
  ) {
    final text = FrameText.of(context);
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            _closeFileSearch();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            if (HardwareKeyboard.instance.isShiftPressed) {
              _prevFileSearchMatch();
            } else {
              _nextFileSearchMatch();
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        key: const ValueKey('repository-file-search-bar'),
        padding: const EdgeInsets.symmetric(
          horizontal: FrameSpace.x2,
          vertical: FrameSpace.x1,
        ),
        decoration: BoxDecoration(
          color: tokens.surfaceElevated,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(color: tokens.borderStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_outlined, size: FrameSize.icon - 2, color: tokens.textMuted),
            const SizedBox(width: FrameSpace.x1 + 2),
            SizedBox(
              width: 170,
              height: FrameSize.hitMin - 2,
              child: TextField(
                key: const ValueKey('repository-file-search-field'),
                controller: _fileSearchQueryController,
                focusNode: _fileSearchFocusNode,
                style: text.body.copyWith(color: tokens.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: strings.searchInFileHint,
                  hintStyle: text.body.copyWith(color: tokens.textMuted),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: FrameSpace.x1),
                ),
              ),
            ),
            const SizedBox(width: FrameSpace.x1 + 2),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: FrameSpace.x1 + 1,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
              ),
              child: Text(
                _fileSearchQueryController.text.isEmpty
                    ? ''
                    : _fileSearchMatches.isEmpty
                    ? strings.zeroResults
                    : strings.searchResultsCount(
                        _fileSearchCurrentIndex + 1,
                        _fileSearchMatches.length,
                      ),
                style: text.caption.copyWith(
                  color:
                      _fileSearchMatches.isEmpty &&
                          _fileSearchQueryController.text.isNotEmpty
                      ? tokens.danger
                      : tokens.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: FrameSpace.x1),
            FrameIconAction(
              key: const ValueKey('repository-file-search-prev'),
              icon: Icons.keyboard_arrow_up_outlined,
              tooltip: strings.previousMatchTooltip,
              onPressed: _fileSearchMatches.isEmpty
                  ? null
                  : _prevFileSearchMatch,
            ),
            FrameIconAction(
              key: const ValueKey('repository-file-search-next'),
              icon: Icons.keyboard_arrow_down_outlined,
              tooltip: strings.nextMatchTooltip,
              onPressed: _fileSearchMatches.isEmpty
                  ? null
                  : _nextFileSearchMatch,
            ),
            FrameIconAction(
              key: const ValueKey('repository-file-search-case'),
              icon: Icons.text_fields_outlined,
              tooltip: strings.matchCaseTooltip,
              selected: _fileSearchCaseSensitive,
              onPressed: () {
                setState(() {
                  _fileSearchCaseSensitive = !_fileSearchCaseSensitive;
                });
                _updateFileSearch();
              },
            ),
            FrameIconAction(
              key: const ValueKey('repository-file-search-close'),
              icon: Icons.close_outlined,
              tooltip: strings.closeFileSearchTooltip,
              onPressed: _closeFileSearch,
            ),
          ],
        ),
      ),
    );
  }
}
