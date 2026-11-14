import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../composer/composer_draft.dart';
import '../../../ui/code/code_editor_controller.dart';
import '../../transcript/rich_content.dart';
import '../../../ui/frame_snack_bar.dart';
import '../../../data/language/language_settings.dart';
import '../../../data/language/strings_workspace.dart';
import '../../../data/language/strings_errors.dart';
import '../repository_error_callout.dart';
import '../repository_state.dart';
import 'repository_file_save.dart';

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
  final _markdownScrollController = ScrollController();

  bool _showFileSearch = false;
  final _fileSearchQueryController = TextEditingController();
  final _fileSearchFocusNode = FocusNode();
  final _editorFocusNode = FocusNode();
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
      if (mounted) _editorFocusNode.requestFocus();
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
    _editor?.dispose();
    _markdownScrollController.dispose();
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
    if (path == null) {
      return Center(
        child: Text(
          strings.selectAFile,
          style: TextStyle(color: tokens.textMuted),
        ),
      );
    }
    if (buffer == null) {
      final error = repo.error;
      if (error == null) {
        return Center(
          child: Text(
            strings.loadingFiles,
            style: TextStyle(color: tokens.textMuted),
          ),
        );
      }
      return repositoryErrorCallout(strings, error, strings.filesLoadFailed);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            children: [
              if (compact)
                IconButton(
                  tooltip: strings.backToFilesTooltip,
                  onPressed: () => ref
                      .read(repositoryStateProvider(widget.sessionId).notifier)
                      .showFileList(),
                  icon: const Icon(Icons.arrow_back, size: 16),
                ),
              Expanded(
                child: Text(
                  path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 12,
                    fontFamily: tokens.monoFontFamily,
                  ),
                ),
              ),
              if (buffer.dirty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.warning.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    border: Border.all(color: tokens.border),
                  ),
                  child: Text(
                    strings.modifiedBadge,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: !buffer.dirty || writeBlocked
                    ? null
                    : () async {
                        if (!context.mounted) return;
                        try {
                          await saveRepositoryFile(
                            context,
                            ref,
                            widget.sessionId,
                            path,
                          );
                        } catch (error) {
                          if (context.mounted) {
                            FrameSnackBar.show(
                              context,
                              message: strings.saveFailed(error),
                            );
                          }
                        }
                      },
                child: Text(strings.save),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: strings.addFileToChatTooltip,
                onPressed: () {
                  appendFileMentionToComposer(ref, widget.sessionId, path);
                  FrameSnackBar.show(
                    context,
                    message: strings.addedFileToChat(path),
                  );
                },
                icon: const Icon(Icons.add_comment_outlined, size: 16),
              ),
              if (path.toLowerCase().endsWith('.md') ||
                  path.toLowerCase().endsWith('.markdown')) ...[
                const SizedBox(width: 4),
                IconButton(
                  key: const ValueKey('repository-markdown-toggle-btn'),
                  tooltip: _previewMarkdown
                      ? strings.editMarkdownSourceTooltip
                      : strings.viewMarkdownPreviewTooltip,
                  onPressed: () {
                    setState(() {
                      _previewMarkdown = !_previewMarkdown;
                    });
                  },
                  icon: Icon(
                    _previewMarkdown
                        ? Icons.edit_note_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                    color: _previewMarkdown ? tokens.accent : tokens.textMuted,
                  ),
                ),
              ],
              const SizedBox(width: 4),
              IconButton(
                key: const ValueKey('repository-editor-search-btn'),
                tooltip: strings.searchInFileTooltip,
                onPressed: _openFileSearch,
                icon: Icon(
                  Icons.search,
                  size: 16,
                  color: _showFileSearch ? tokens.accent : tokens.textMuted,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: strings.closeFileTooltip,
                onPressed: () => ref
                    .read(repositoryStateProvider(widget.sessionId).notifier)
                    .showFileList(),
                icon: const Icon(Icons.close, size: 16),
              ),
            ],
          ),
        ),
        if (writeBlocked)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: tokens.signalWarning.withValues(alpha: 0.16),
            child: Text(
              blockReason!,
              style: TextStyle(color: tokens.textSecondary, fontSize: 11),
            ),
          ),
        Expanded(
          child:
              (path.toLowerCase().endsWith('.md') ||
                      path.toLowerCase().endsWith('.markdown')) &&
                  _previewMarkdown
              ? Container(
                  color: tokens.background,
                  child: Scrollbar(
                    controller: _markdownScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _markdownScrollController,
                      primary: false,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
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
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent) {
                          final isControl =
                              HardwareKeyboard.instance.isControlPressed ||
                              HardwareKeyboard.instance.isMetaPressed;
                          if (isControl &&
                              event.logicalKey == LogicalKeyboardKey.keyF) {
                            _openFileSearch();
                            return KeyEventResult.handled;
                          }
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        key: ValueKey('repository-editor-${widget.sessionId}'),
                        controller: _editor,
                        enabled: !readOnly,
                        onChanged: (value) => ref
                            .read(
                              repositoryStateProvider(widget.sessionId)
                                  .notifier,
                            )
                            .edit(path, value),
                        contextMenuBuilder: (context, editorState) {
                          final selection =
                              editorState.textEditingValue.selection;
                          final items = List<ContextMenuButtonItem>.of(
                            editorState.contextMenuButtonItems,
                          );
                          if (selection.isValid && !selection.isCollapsed) {
                            items.add(
                              ContextMenuButtonItem(
                                label: strings.addPathToChat,
                                onPressed: () {
                                  appendCodeSelectionToComposer(
                                    ref,
                                    widget.sessionId,
                                    path,
                                    editorState.textEditingValue.text,
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
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        style: TextStyle(
                          fontFamily: tokens.monoFontFamily,
                          fontSize: 12,
                          color: tokens.textPrimary,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: tokens.background,
                          contentPadding: const EdgeInsets.all(12),
                          border: InputBorder.none,
                          hintText: writeBlocked
                              ? strings.readOnlyBlockedReason
                              : strings.fileContentHint,
                        ),
                      ),
                    ),
                    if (_showFileSearch)
                      Positioned(
                        top: 8,
                        right: 16,
                        child: Focus(
                          onKeyEvent: (node, event) {
                            if (event is KeyDownEvent) {
                              if (event.logicalKey ==
                                  LogicalKeyboardKey.escape) {
                                _closeFileSearch();
                                return KeyEventResult.handled;
                              } else if (event.logicalKey ==
                                      LogicalKeyboardKey.enter ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.numpadEnter) {
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
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.surfaceElevated,
                              borderRadius: BorderRadius.circular(
                                tokens.radiusSm,
                              ),
                              border: Border.all(color: tokens.borderStrong),
                              boxShadow: [
                                BoxShadow(
                                  color: tokens.borderStrong.withValues(
                                    alpha: 0.25,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.search,
                                  size: 14,
                                  color: tokens.textMuted,
                                ),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 170,
                                  height: 26,
                                  child: TextField(
                                    key: const ValueKey(
                                      'repository-file-search-field',
                                    ),
                                    controller: _fileSearchQueryController,
                                    focusNode: _fileSearchFocusNode,
                                    style: TextStyle(
                                      color: tokens.textPrimary,
                                      fontSize: 12,
                                    ),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      hintText: strings.searchInFileHint,
                                      hintStyle: TextStyle(
                                        color: tokens.textMuted,
                                        fontSize: 12,
                                      ),
                                      border: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            vertical: 4,
                                          ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: tokens.surface,
                                    borderRadius: BorderRadius.circular(
                                      tokens.radiusSm,
                                    ),
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
                                    style: TextStyle(
                                      color:
                                          _fileSearchMatches.isEmpty &&
                                              _fileSearchQueryController
                                                  .text
                                                  .isNotEmpty
                                          ? tokens.danger
                                          : tokens.textMuted,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  key: const ValueKey(
                                    'repository-file-search-prev',
                                  ),
                                  tooltip: strings.previousMatchTooltip,
                                  icon: const Icon(
                                    Icons.keyboard_arrow_up,
                                    size: 16,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 22,
                                    minHeight: 22,
                                  ),
                                  onPressed: _fileSearchMatches.isEmpty
                                      ? null
                                      : _prevFileSearchMatch,
                                ),
                                IconButton(
                                  key: const ValueKey(
                                    'repository-file-search-next',
                                  ),
                                  tooltip: strings.nextMatchTooltip,
                                  icon: const Icon(
                                    Icons.keyboard_arrow_down,
                                    size: 16,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 22,
                                    minHeight: 22,
                                  ),
                                  onPressed: _fileSearchMatches.isEmpty
                                      ? null
                                      : _nextFileSearchMatch,
                                ),
                                IconButton(
                                  key: const ValueKey(
                                    'repository-file-search-case',
                                  ),
                                  tooltip: strings.matchCaseTooltip,
                                  icon: Text(
                                    'Aa',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: _fileSearchCaseSensitive
                                          ? tokens.accent
                                          : tokens.textMuted,
                                    ),
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 22,
                                    minHeight: 22,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _fileSearchCaseSensitive =
                                          !_fileSearchCaseSensitive;
                                    });
                                    _updateFileSearch();
                                  },
                                ),
                                IconButton(
                                  key: const ValueKey(
                                    'repository-file-search-close',
                                  ),
                                  tooltip: strings.closeFileSearchTooltip,
                                  icon: const Icon(Icons.close, size: 14),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 22,
                                    minHeight: 22,
                                  ),
                                  onPressed: _closeFileSearch,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
