import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/pcp_client.dart';
import '../../data/language/language_settings.dart';

const _rowExtent = 40.0;
const _remoteColumnWidth = 150.0;
const _syncColumnWidth = 64.0;

class BranchPickerDialog extends ConsumerStatefulWidget {
  final String sessionId;
  final PcpClient client;
  final String? currentBranch;

  const BranchPickerDialog({
    super.key,
    required this.sessionId,
    required this.client,
    this.currentBranch,
  });

  static Future<String?> show(
    BuildContext context, {
    required String sessionId,
    required PcpClient client,
    String? currentBranch,
  }) {
    return showDialog<String>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      barrierColor: context.tokens.overlay,
      builder: (_) => BranchPickerDialog(
        sessionId: sessionId,
        client: client,
        currentBranch: currentBranch,
      ),
    );
  }

  @override
  ConsumerState<BranchPickerDialog> createState() => _BranchPickerDialogState();
}

class _BranchPickerDialogState extends ConsumerState<BranchPickerDialog> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  bool _loading = true;
  bool _submitted = false;
  String? _error;
  List<WorkspaceBranchInfo> _branches = [];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await widget.client.listBranches(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _branches = result.branches;
        _loading = false;
        _selectedIndex = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _move(int delta, int count) {
    if (count == 0) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta).clamp(0, count - 1);
    });
    if (_scrollController.hasClients) {
      final offset = (_selectedIndex * _rowExtent).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.jumpTo(offset);
    }
  }

  void _selectBranch(WorkspaceBranchInfo branch) {
    if (_submitted) return;
    _submitted = true;
    if (branch.isCurrent || branch.name == widget.currentBranch) {
      Navigator.of(context).pop(null);
    } else {
      Navigator.of(context).pop(branch.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = ref.watch(appStringsProvider);
    final query = _searchController.text.trim().toLowerCase();

    final filtered = _branches.where((b) {
      return b.name.toLowerCase().contains(query);
    }).toList();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _move(1, filtered.length),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _move(-1, filtered.length),
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (filtered.isNotEmpty && _selectedIndex < filtered.length) {
            _selectBranch(filtered[_selectedIndex]);
          }
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_submitted) return;
          _submitted = true;
          Navigator.of(context).pop(null);
        },
      },
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 540,
            maxHeight: MediaQuery.sizeOf(context).height * 0.6,
          ),
          child: Material(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(tokens.radiusLg),
            clipBehavior: Clip.antiAlias,
            elevation: 0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(tokens.radiusLg),
                border: Border.all(color: tokens.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Search Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search, size: 20, color: tokens.textMuted),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            key: const ValueKey('branch-picker-search-field'),
                            controller: _searchController,
                            focusNode: _focusNode,
                            autofocus: true,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: 14,
                              fontFamily: tokens.monoFontFamily,
                            ),
                            decoration: InputDecoration(
                              hintText: strings.branchPickerSearchHint,
                              hintStyle: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 13,
                                fontFamily: tokens.uiFontFamily,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onChanged: (_) {
                              setState(() => _selectedIndex = 0);
                            },
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.surface,
                            borderRadius: BorderRadius.circular(tokens.radiusSm),
                            border: Border.all(color: tokens.border),
                          ),
                          child: Text(
                            'ESC',
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 10,
                              fontFamily: tokens.monoFontFamily,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: tokens.border),

                  // Body: the list is sized to its rows, capped by the dialog.
                  Flexible(
                    child: _loading
                        ? Center(
                            heightFactor: 1,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      tokens.accent,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  strings.branchPickerLoading,
                                  style: TextStyle(
                                    color: tokens.textMuted,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _error != null
                            ? Center(
                                heightFactor: 1,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: tokens.danger,
                                        size: 28,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        strings.branchPickerError,
                                        style: TextStyle(
                                          color: tokens.textPrimary,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _error!,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: tokens.textMuted,
                                          fontSize: 11,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      OutlinedButton(
                                        onPressed: _loadBranches,
                                        style: OutlinedButton.styleFrom(
                                          side: BorderSide(color: tokens.border),
                                        ),
                                        child: Text(
                                          strings.branchPickerRetry,
                                          style: TextStyle(
                                            color: tokens.textPrimary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : filtered.isEmpty
                                ? Center(
                                    heightFactor: 1,
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Text(
                                      strings.branchPickerNoBranches,
                                      style: TextStyle(
                                        color: tokens.textMuted,
                                        fontSize: 13,
                                      ),
                                    ),
                                    ),
                                  )
                                : ListView.builder(
                                    key: const ValueKey('branch-picker-list'),
                                    shrinkWrap: true,
                                    controller: _scrollController,
                                    itemCount: filtered.length,
                                    itemBuilder: (context, index) {
                                      final branch = filtered[index];
                                      final isCurrent = branch.isCurrent ||
                                          branch.name == widget.currentBranch;
                                      final isSelected =
                                          index == _selectedIndex;

                                      return InkWell(
                                        key: ValueKey(
                                          'branch-picker-item-${branch.name}',
                                        ),
                                        onTap: () => _selectBranch(branch),
                                        hoverColor: tokens.accent.withValues(
                                          alpha: 0.06,
                                        ),
                                        child: Container(
                                          color: isSelected
                                              ? tokens.accent.withValues(
                                                  alpha: 0.12,
                                                )
                                              : isCurrent
                                                  ? tokens.accent.withValues(
                                                      alpha: 0.05,
                                                    )
                                                  : null,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                          ),
                                          height: _rowExtent,
                                          child: Row(
                                            children: [
                                              Icon(
                                                isCurrent
                                                    ? Icons.check
                                                    : Icons.fork_right,
                                                key: isCurrent
                                                    ? const ValueKey(
                                                        'branch-picker-current-check',
                                                      )
                                                    : null,
                                                size: 16,
                                                color: isCurrent
                                                    ? tokens.accent
                                                    : tokens.textMuted,
                                              ),
                                              const SizedBox(width: 10),
                                              // Branch column: flexible, takes the remaining width.
                                              Expanded(
                                                child: Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        branch.name,
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                          color: isCurrent
                                                              ? tokens.accent
                                                              : tokens.textPrimary,
                                                          fontWeight: isCurrent
                                                              ? FontWeight.bold
                                                              : FontWeight.normal,
                                                          fontSize: 13,
                                                          fontFamily:
                                                              tokens.monoFontFamily,
                                                        ),
                                                      ),
                                                    ),
                                                    if (isCurrent) ...[
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 2,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: tokens.accent
                                                              .withValues(
                                                            alpha: 0.15,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                            tokens.radiusSm,
                                                          ),
                                                        ),
                                                        child: Text(
                                                          strings.branchPickerCurrentBranch,
                                                          style: TextStyle(
                                                            color: tokens.accent,
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              // Remote column: fixed width, so rows line up.
                                              const SizedBox(width: 12),
                                              SizedBox(
                                                key: const ValueKey(
                                                  'branch-picker-remote-column',
                                                ),
                                                width: _remoteColumnWidth,
                                                child: Text(
                                                  branch.upstream ?? '',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: tokens.textMuted,
                                                    fontSize: 11,
                                                    fontFamily:
                                                        tokens.monoFontFamily,
                                                  ),
                                                ),
                                              ),
                                              // Ahead/behind column: fixed width, right aligned.
                                              const SizedBox(width: 8),
                                              SizedBox(
                                                key: const ValueKey(
                                                  'branch-picker-sync-column',
                                                ),
                                                width: _syncColumnWidth,
                                                child: Text(
                                                  branch.ahead != null ||
                                                          branch.behind != null
                                                      ? '↑${branch.ahead ?? 0} ↓${branch.behind ?? 0}'
                                                      : '',
                                                  maxLines: 1,
                                                  textAlign: TextAlign.right,
                                                  style: TextStyle(
                                                    color: (branch.ahead ?? 0) > 0 ||
                                                            (branch.behind ?? 0) > 0
                                                        ? tokens.accent
                                                        : tokens.textMuted,
                                                    fontSize: 11,
                                                    fontFamily:
                                                        tokens.monoFontFamily,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
