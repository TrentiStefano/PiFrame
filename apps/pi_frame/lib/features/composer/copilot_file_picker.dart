import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_composer.dart';
import '../../ui/frame_dialog.dart';

enum CopilotFileActionType { mention, attach }

class CopilotFileResult {
  final String path;
  final CopilotFileActionType action;

  const CopilotFileResult({required this.path, required this.action});
}

class CopilotFilePicker extends StatefulWidget {
  final List<Map<String, dynamic>> files;
  final AppStrings? strings;

  const CopilotFilePicker({super.key, required this.files, this.strings});

  static Future<CopilotFileResult?> show(
    BuildContext context, {
    required List<Map<String, dynamic>> files,
    AppStrings? strings,
  }) {
    return showFrameDialogBuilder<CopilotFileResult>(
      context: context,
      builder: (ctx) => CopilotFilePicker(files: files, strings: strings),
    );
  }

  @override
  State<CopilotFilePicker> createState() => _CopilotFilePickerState();
}

class _CopilotFilePickerState extends State<CopilotFilePicker> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();
  int _selectedIndex = 0;
  List<Map<String, dynamic>> _filteredFiles = const [];
  int _renderedLimit = 50;

  @override
  void initState() {
    super.initState();
    _filteredFiles = widget.files;
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 200 && _renderedLimit < _filteredFiles.length) {
      setState(() {
        _renderedLimit = (_renderedLimit + 50).clamp(0, _filteredFiles.length);
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredFiles = widget.files;
      } else {
        _filteredFiles = widget.files.where((f) {
          final path = (f['path']?.toString() ?? '').toLowerCase();
          return path.contains(query);
        }).toList();
      }
      _selectedIndex = 0;
      _renderedLimit = 50;
    });
  }

  IconData _getFileIcon(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.dart')) return Icons.code_outlined;
    if (lower.endsWith('.js') || lower.endsWith('.ts') || lower.endsWith('.tsx') || lower.endsWith('.jsx')) {
      return Icons.javascript_outlined;
    }
    if (lower.endsWith('.json') || lower.endsWith('.yaml') || lower.endsWith('.yml')) {
      return Icons.data_object_outlined;
    }
    if (lower.endsWith('.md') || lower.endsWith('.txt')) {
      return Icons.article_outlined;
    }
    return Icons.description_outlined;
  }

  String _formatBytes(dynamic size) {
    final bytes = (size as num?)?.toInt() ?? 0;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _selectFile(String path, CopilotFileActionType action) {
    Navigator.of(context).pop(CopilotFileResult(path: path, action: action));
  }

  AppStrings _resolveStrings(BuildContext context) {
    if (widget.strings != null) return widget.strings!;
    try {
      return ProviderScope.containerOf(context, listen: false).read(appStringsProvider);
    } catch (_) {
      return const AppStrings(AppLanguage.it);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = _resolveStrings(context);

    return Dialog(
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        side: BorderSide(color: tokens.border, width: 1),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: FrameSpace.x6, vertical: FrameSpace.x8),
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              if (_filteredFiles.isNotEmpty) {
                setState(() {
                  _selectedIndex = (_selectedIndex + 1) % _filteredFiles.length;
                });
                return KeyEventResult.handled;
              }
            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              if (_filteredFiles.isNotEmpty) {
                setState(() {
                  _selectedIndex = (_selectedIndex - 1 + _filteredFiles.length) % _filteredFiles.length;
                });
                return KeyEventResult.handled;
              }
            } else if (event.logicalKey == LogicalKeyboardKey.enter) {
              if (_filteredFiles.isNotEmpty && _selectedIndex < _filteredFiles.length) {
                final path = _filteredFiles[_selectedIndex]['path']?.toString() ?? '';
                if (path.isNotEmpty) {
                  _selectFile(path, CopilotFileActionType.attach);
                  return KeyEventResult.handled;
                }
              }
            }
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          width: 580,
          height: 460,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                    child: Icon(Icons.add_link_outlined, size: FrameSize.icon, color: tokens.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.copilotAddContextTitle,
                          style: FrameText.of(context).bodyLarge.copyWith(color: tokens.textPrimary, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          strings.copilotAddContextSubtitle,
                          style: FrameText.of(context).caption.copyWith(color: tokens.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_outlined, size: FrameSize.iconLg, color: tokens.textMuted),
                    tooltip: strings.copilotCloseEscTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: FrameSpace.x3),

              // Search Box
              TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                style: FrameText.of(context).body.copyWith(color: tokens.textPrimary),
                decoration: InputDecoration(
                  hintText: strings.copilotSearchHint,
                  hintStyle: FrameText.of(context).body.copyWith(color: tokens.textMuted),
                  prefixIcon: Icon(Icons.search_outlined, size: FrameSize.iconLg, color: tokens.textMuted),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear_outlined, size: FrameSize.icon, color: tokens.textMuted),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  filled: true,
                  fillColor: tokens.surfaceElevated,
                  contentPadding: const EdgeInsets.symmetric(horizontal: FrameSpace.x3, vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    borderSide: BorderSide(color: tokens.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    borderSide: BorderSide(color: tokens.accent, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Filter summary
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    strings.copilotFilesFound(_filteredFiles.length),
                    style: FrameText.of(context).caption.copyWith(color: tokens.textMuted),
                  ),
                  Flexible(
                    child: Text(
                      strings.copilotKeyNavHint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: FrameText.of(context).caption.copyWith(color: tokens.textMuted, fontFamily: tokens.monoFontFamily),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Results List
              Expanded(
                child: _filteredFiles.isEmpty
                    ? Center(
                        child: Text(
                          strings.copilotNoFilesMatch,
                          style: FrameText.of(context).label.copyWith(color: tokens.textMuted),
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          color: tokens.surfaceElevated.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          border: Border.all(color: tokens.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListView.builder(
                          controller: _scrollController,
                          itemCount: (_renderedLimit < _filteredFiles.length)
                              ? _renderedLimit + 1
                              : _filteredFiles.length,
                          itemExtent: 44.0,
                          itemBuilder: (context, index) {
                            if (index == _renderedLimit && _renderedLimit < _filteredFiles.length) {
                              return Center(
                                child: Text(
                                  strings.copilotLoadingMore(_renderedLimit, _filteredFiles.length),
                                  style: FrameText.of(context).caption.copyWith(color: tokens.textMuted, fontFamily: tokens.monoFontFamily),
                                ),
                              );
                            }
                            final file = _filteredFiles[index];
                            final path = file['path']?.toString() ?? '';
                            final isSelected = index == _selectedIndex;

                            return InkWell(
                              onTap: () => _selectFile(path, CopilotFileActionType.attach),
                              child: Container(
                                color: isSelected
                                    ? tokens.accent.withValues(alpha: 0.12)
                                    : tokens.surface.withValues(alpha: 0),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _getFileIcon(path),
                                      size: 16,
                                      color: isSelected ? tokens.accent : tokens.textSecondary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        path,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: FrameText.of(context).label.copyWith(color: isSelected ? tokens.accent : tokens.textPrimary, fontWeight: FontWeight.w600, fontFamily: tokens.monoFontFamily),
                                      ),
                                    ),
                                    const SizedBox(width: FrameSpace.x2),
                                    Text(
                                      _formatBytes(file['sizeBytes']),
                                      style: FrameText.of(context).caption.copyWith(color: tokens.textMuted, fontFamily: tokens.monoFontFamily),
                                    ),
                                    const SizedBox(width: FrameSpace.x2),
                                    // Action buttons
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x2, vertical: FrameSpace.x1),
                                        side: BorderSide(color: tokens.border),
                                        foregroundColor: tokens.textSecondary,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                                        ),
                                      ),
                                      onPressed: () => _selectFile(path, CopilotFileActionType.mention),
                                      child: Text(strings.copilotLinkAtAction, style: FrameText.of(context).caption),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
