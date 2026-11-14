import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/pcp_client.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_shell.dart';
import '../../ui/frame_focus.dart';
import '../../ui/frame_activity_indicator.dart';

// Layout constants with no matching token in FrameSpace / FrameSize.
const _dialogMaxWidth = 540.0;
const _rowExtent = 40.0;
const _rowIconGap = 10.0;
const _errorIconSize = 28.0;
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
    final text = FrameText.of(context);
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
            maxWidth: _dialogMaxWidth,
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
                      horizontal: FrameSpace.x4,
                      vertical: FrameSpace.x3,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search,
                          size: FrameSize.iconLg,
                          color: tokens.textMuted,
                        ),
                        const SizedBox(width: FrameSpace.x3),
                        Expanded(
                          // Standard keyboard focus ring; the field draws no
                          // border of its own (see the palette search field).
                          child: FrameFocusRing(
                            borderRadius: BorderRadius.circular(tokens.radiusSm),
                            child: TextField(
                              key: const ValueKey('branch-picker-search-field'),
                              controller: _searchController,
                              focusNode: _focusNode,
                              autofocus: true,
                              style: text.monoBody.copyWith(
                                color: tokens.textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText: strings.branchPickerSearchHint,
                                hintStyle: text.body.copyWith(
                                  color: tokens.textMuted,
                                ),
                                filled: false,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: FrameSpace.x2,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                errorBorder: InputBorder.none,
                                focusedErrorBorder: InputBorder.none,
                              ),
                              onChanged: (_) {
                                setState(() => _selectedIndex = 0);
                              },
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: FrameSpace.x2,
                            vertical: FrameSpace.x1,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.surface,
                            borderRadius: BorderRadius.circular(tokens.radiusSm),
                            border: Border.all(color: tokens.border),
                          ),
                          child: Text(
                            strings.paletteEscKeyLabel,
                            style: text.mono.copyWith(
                              color: tokens.textMuted,
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
                                  width: FrameSpace.x6,
                                  height: FrameSpace.x6,
                                  child: FrameActivityIndicator(size: FrameSpace.x6, strokeWidth: 2.5, color: tokens.accent),
                                ),
                                const SizedBox(height: FrameSpace.x3),
                                Text(
                                  strings.branchPickerLoading,
                                  style: text.body.copyWith(
                                    color: tokens.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _error != null
                            ? Center(
                                heightFactor: 1,
                                child: Padding(
                                  padding: const EdgeInsets.all(FrameSpace.x4),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: tokens.danger,
                                        size: _errorIconSize,
                                      ),
                                      const SizedBox(height: FrameSpace.x2),
                                      Text(
                                        strings.branchPickerError,
                                        style: text.body.copyWith(
                                          color: tokens.textPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: FrameSpace.x1),
                                      Text(
                                        _error!,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: text.caption.copyWith(
                                          color: tokens.textMuted,
                                        ),
                                      ),
                                      const SizedBox(height: FrameSpace.x3),
                                      OutlinedButton(
                                        onPressed: _loadBranches,
                                        style: OutlinedButton.styleFrom(
                                          side: BorderSide(color: tokens.border),
                                        ),
                                        child: Text(
                                          strings.branchPickerRetry,
                                          style: text.label.copyWith(
                                            color: tokens.textPrimary,
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
                                      padding: const EdgeInsets.all(FrameSpace.x4),
                                      child: Text(
                                        strings.branchPickerNoBranches,
                                        style: text.body.copyWith(
                                          color: tokens.textMuted,
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
                                            horizontal: FrameSpace.x4,
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
                                                size: FrameSize.icon,
                                                color: isCurrent
                                                    ? tokens.accent
                                                    : tokens.textMuted,
                                              ),
                                              const SizedBox(width: _rowIconGap),
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
                                                        style: text.monoBody.copyWith(
                                                          color: isCurrent
                                                              ? tokens.accent
                                                              : tokens.textPrimary,
                                                          fontWeight: isCurrent
                                                              ? FontWeight.bold
                                                              : FontWeight.normal,
                                                        ),
                                                      ),
                                                    ),
                                                    if (isCurrent) ...[
                                                      const SizedBox(width: FrameSpace.x2),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                          horizontal: FrameSpace.x2,
                                                          vertical: FrameSpace.x1,
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
                                                          style: text.caption.copyWith(
                                                            color: tokens.accent,
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
                                              const SizedBox(width: FrameSpace.x3),
                                              SizedBox(
                                                key: const ValueKey(
                                                  'branch-picker-remote-column',
                                                ),
                                                width: _remoteColumnWidth,
                                                child: Text(
                                                  branch.upstream ?? '',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: text.mono.copyWith(
                                                    color: tokens.textMuted,
                                                  ),
                                                ),
                                              ),
                                              // Ahead/behind column: fixed width, right aligned.
                                              const SizedBox(width: FrameSpace.x2),
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
                                                  style: text.mono.copyWith(
                                                    color: (branch.ahead ?? 0) > 0 ||
                                                            (branch.behind ?? 0) > 0
                                                        ? tokens.accent
                                                        : tokens.textMuted,
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
