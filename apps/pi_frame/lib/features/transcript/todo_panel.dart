import 'package:flutter/material.dart';

import '../../ui/precision.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/language/language_settings.dart';
import '../../data/language/strings_transcript.dart';
import '../../ui/frame_activity_indicator.dart';
import '../../ui/motion.dart';
import 'todo_provider.dart';

class TodoPopDown extends ConsumerStatefulWidget {
  final String sessionId;
  final VoidCallback? onClose;
  final bool? isExpanded;
  final VoidCallback? onToggleExpand;
  final bool hideBookTab;
  final Set<int>? filterTaskIds;

  /// Fills the Tasks tab of the panel beside the chat: no card border or
  /// shadow, the list takes the full height, and the close button hides the
  /// tab instead of collapsing a popup.
  final bool embedded;

  const TodoPopDown({
    super.key,
    required this.sessionId,
    this.onClose,
    this.isExpanded,
    this.onToggleExpand,
    this.hideBookTab = false,
    this.filterTaskIds,
    this.embedded = false,
  });

  @override
  ConsumerState<TodoPopDown> createState() => _TodoPopDownState();
}

class _TodoPopDownState extends ConsumerState<TodoPopDown> {
  final TextEditingController _addController = TextEditingController();
  final Set<int> _expandedTaskIds = <int>{};
  Set<int>? _activeFilterTaskIds;
  bool _isAdding = false;
  bool _internalExpanded = true;

  bool get _isExpanded => widget.isExpanded ?? _internalExpanded;

  @override
  void initState() {
    super.initState();
    _activeFilterTaskIds = widget.filterTaskIds != null
        ? Set<int>.from(widget.filterTaskIds!)
        : null;
  }

  @override
  void didUpdateWidget(TodoPopDown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filterTaskIds != oldWidget.filterTaskIds) {
      setState(() {
        _activeFilterTaskIds = widget.filterTaskIds != null
            ? Set<int>.from(widget.filterTaskIds!)
            : null;
      });
    }
  }

  void _handleToggle() {
    if (widget.onToggleExpand != null) {
      widget.onToggleExpand!();
    } else if (widget.onClose != null && _isExpanded) {
      widget.onClose!();
    } else {
      setState(() => _internalExpanded = !_internalExpanded);
    }
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  void _submitNewTask() {
    final text = _addController.text.trim();
    if (text.isEmpty) return;
    ref.read(todosFamily(widget.sessionId).notifier).addTask(text);
    _addController.clear();
    setState(() => _isAdding = false);
  }

  void _toggleTaskExpanded(int id) {
    setState(() {
      if (_expandedTaskIds.contains(id)) {
        _expandedTaskIds.remove(id);
      } else {
        _expandedTaskIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = ref.watch(appStringsProvider);
    final todos = ref.watch(todosFamily(widget.sessionId));
    final notifier = ref.read(todosFamily(widget.sessionId).notifier);

    if (todos.isEmpty) {
      return const SizedBox.shrink();
    }

    final completedCount = todos.where((t) => t.isCompleted).length;
    final inProgressCount = todos.where((t) => t.isInProgress).length;
    final totalCount = todos.length;
    final percent = totalCount > 0 ? (completedCount / totalCount) : 0.0;
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    final visibleTodos =
        (_activeFilterTaskIds != null && _activeFilterTaskIds!.isNotEmpty)
        ? todos.where((t) => _activeFilterTaskIds!.contains(t.id)).toList()
        : todos;
    final isFiltered =
        _activeFilterTaskIds != null &&
        _activeFilterTaskIds!.isNotEmpty &&
        visibleTodos.length < todos.length;

    final embedded = widget.embedded;
    final panelContent = _isExpanded || embedded
        ? Container(
            key: const ValueKey('todo-popdown-panel'),
            width: double.infinity,
            margin: embedded
                ? EdgeInsets.zero
                : EdgeInsets.fromLTRB(
                    isMobile ? 12 : 8,
                    0,
                    isMobile ? 12 : 8,
                    6,
                  ),
            decoration: embedded
                ? BoxDecoration(color: tokens.surface)
                : BoxDecoration(
                    color: tokens.surfaceElevated,
                    borderRadius: widget.hideBookTab
                        ? BorderRadius.only(
                            topRight: Radius.circular(tokens.radiusMd),
                            bottomLeft: Radius.circular(tokens.radiusMd),
                            bottomRight: Radius.circular(tokens.radiusMd),
                          )
                        : BorderRadius.circular(tokens.radiusMd),
                    border: Border.all(color: tokens.borderStrong, width: 1.0),
                    boxShadow: [
                      BoxShadow(
                        color: tokens.overlay.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
            child: Column(
              mainAxisSize: embedded ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Bar
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: embedded ? tokens.surfaceElevated : tokens.surface,
                    borderRadius: embedded
                        ? null
                        : widget.hideBookTab
                        ? BorderRadius.only(
                            topRight: Radius.circular(tokens.radiusMd),
                          )
                        : BorderRadius.vertical(
                            top: Radius.circular(tokens.radiusMd),
                          ),
                    border: Border(
                      bottom: BorderSide(
                        color: tokens.border.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.checklist_rtl_outlined,
                        size: FrameSize.icon,
                        color: tokens.accent,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          strings.todoAgentTasksTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: FrameText.of(context).label.fontSize,
                            fontWeight: FontWeight.bold,
                          ),
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
                            color:
                                (percent >= 1.0
                                        ? tokens.success
                                        : tokens.accent)
                                    .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(
                              tokens.radiusSm,
                            ),
                          ),
                          child: Text(
                            // The narrow side panel shows just the fraction.
                            embedded
                                ? '$completedCount/$totalCount'
                                : strings.todoCompletedCount(
                                    completedCount,
                                    totalCount,
                                  ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: percent >= 1.0
                                  ? tokens.success
                                  : tokens.accent,
                              fontSize: FrameText.of(context).caption.fontSize,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      if (inProgressCount > 0) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.agentWorking.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(
                                tokens.radiusSm,
                              ),
                            ),
                            child: Text(
                              strings.todoInProgressCount(inProgressCount),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.agentWorking,
                                fontSize: FrameText.of(context)
                                    .caption
                                    .fontSize,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      IconButton(
                        tooltip: _isAdding
                            ? strings.todoCancelTooltip
                            : strings.todoAddTaskTooltip,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 26,
                          minHeight: 26,
                        ),
                        icon: Icon(
                          _isAdding
                              ? Icons.close_outlined
                              : Icons.add_circle_outline,
                          size: FrameSize.icon,
                          color: tokens.accent,
                        ),
                        onPressed: () => setState(() => _isAdding = !_isAdding),
                      ),
                      IconButton(
                        key: const ValueKey('todo-popdown-close-btn'),
                        tooltip: strings.todoHideTasksTooltip,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 26,
                          minHeight: 26,
                        ),
                        icon: Icon(
                          embedded
                              ? Icons.chevron_right_outlined
                              : Icons.keyboard_arrow_up_outlined,
                          size: FrameSize.icon,
                          color: tokens.textMuted,
                        ),
                        onPressed: embedded ? widget.onClose : _handleToggle,
                      ),
                    ],
                  ),
                ),

                // Add Task Form (collapsible)
                if (_isAdding)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    color: tokens.background,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('todo-add-task-field'),
                            controller: _addController,
                            autofocus: true,
                            onSubmitted: (_) => _submitNewTask(),
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: FrameText.of(context).label.fontSize,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 4,
                              ),
                              hintText: strings.todoAddTaskHint,
                              hintStyle: TextStyle(
                                color: tokens.textMuted,
                                fontSize: FrameText.of(context)
                                    .caption
                                    .fontSize,
                              ),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        PressFeedback(
                          enabled: true,
                          child: FilledButton(
                            key: const ValueKey('todo-add-task-submit'),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                            ),
                            onPressed: _submitNewTask,
                            child: Text(
                              strings.todoAddButton,
                              style: TextStyle(
                                fontSize: FrameText.of(context)
                                    .caption
                                    .fontSize,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Filter banner if showing only newly added tasks
                if (isFiltered)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: 0.08),
                      border: Border(
                        bottom: BorderSide(
                          color: tokens.border.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 12,
                          color: tokens.accent,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            strings.todoNewlyAddedTasks(visibleTodos.length),
                            style: TextStyle(
                              fontSize: FrameText.of(context).caption.fontSize,
                              color: tokens.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        InkWell(
                          key: const ValueKey('todo-show-all-filter-btn'),
                          onTap: () =>
                              setState(() => _activeFilterTaskIds = null),
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Text(
                              strings.todoShowAllTasks(todos.length),
                              style: TextStyle(
                                fontSize: FrameText.of(context)
                                    .caption
                                    .fontSize,
                                color: tokens.accent,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Compact, scrollable list of collapsed tasks
                if (visibleTodos.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Center(
                      child: Text(
                        strings.todoNoTasksYet,
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: FrameText.of(context).caption.fontSize,
                        ),
                      ),
                    ),
                  )
                else
                  _listSlot(
                    embedded: embedded,
                    child: ListView.separated(
                      shrinkWrap: !embedded,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      itemCount: visibleTodos.length,
                      separatorBuilder: (ctx, i) => Divider(
                        color: tokens.border.withValues(alpha: 0.35),
                        height: 1,
                      ),
                      itemBuilder: (ctx, index) {
                        final task = visibleTodos[index];
                        final isExpanded = _expandedTaskIds.contains(task.id);
                        final hasDescription =
                            task.description != null &&
                            task.description!.trim().isNotEmpty;

                        return InkWell(
                          key: ValueKey('todo-item-row-${task.id}'),
                          onTap: () => _toggleTaskExpanded(task.id),
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 4,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // Checkbox
                                    SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: Checkbox(
                                        key: ValueKey(
                                          'todo-checkbox-${task.id}',
                                        ),
                                        value: task.isCompleted,
                                        activeColor: tokens.accent,
                                        checkColor: tokens.surface,
                                        side: BorderSide(
                                          color: task.isCompleted
                                              ? tokens.accent
                                              : tokens.borderStrong,
                                          width: 1.4,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            tokens.radiusSm,
                                          ),
                                        ),
                                        onChanged: (val) {
                                          notifier.toggleStatus(task.id);
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // Task Title
                                    Expanded(
                                      child: Text(
                                        task.subject,
                                        maxLines: isExpanded ? null : 1,
                                        overflow: isExpanded
                                            ? null
                                            : TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: task.isCompleted
                                              ? tokens.textMuted
                                              : task.isInProgress
                                              ? tokens.textPrimary
                                              : tokens.textSecondary,
                                          fontSize: FrameText.of(context)
                                              .label
                                              .fontSize,
                                          fontWeight: task.isInProgress
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          decoration: task.isCompleted
                                              ? TextDecoration.lineThrough
                                              : null,
                                          decorationColor: tokens.textMuted,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),

                                    // Status Badge
                                    _buildStatusBadge(task, tokens, strings),

                                    // Expand / Collapse Chevron
                                    const SizedBox(width: 4),
                                    Icon(
                                      isExpanded
                                          ? Icons.keyboard_arrow_up_outlined
                                          : Icons.keyboard_arrow_down_outlined,
                                      size: FrameSize.icon,
                                      color: hasDescription
                                          ? tokens.textSecondary
                                          : tokens.textMuted.withValues(
                                              alpha: 0.4,
                                            ),
                                    ),
                                  ],
                                ),

                                // Expanded Description
                                if (isExpanded) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    margin: const EdgeInsets.only(
                                      left: 30,
                                      right: 4,
                                      bottom: 4,
                                    ),
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: tokens.background.withValues(
                                        alpha: 0.7,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        tokens.radiusSm,
                                      ),
                                      border: Border.all(
                                        color: tokens.border.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      hasDescription
                                          ? task.description!
                                          : strings.todoNoDetailedDescription,
                                      style: TextStyle(
                                        color: hasDescription
                                            ? tokens.textSecondary
                                            : tokens.textMuted,
                                        fontSize: FrameText.of(context)
                                            .caption
                                            .fontSize,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          )
        : (widget.hideBookTab
              ? const SizedBox.shrink()
              : Container(
                  margin: EdgeInsets.only(
                    left: isMobile ? 16 : 14,
                    right: isMobile ? 16 : 14,
                    bottom: 4,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 2.5,
                        decoration: BoxDecoration(
                          color: tokens.accent.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(
                            context.tokens.radiusSm,
                          ),
                        ),
                      ),
                      InkWell(
                        key: const ValueKey('todo-peek-tab'),
                        onTap: _handleToggle,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(6),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.surfaceElevated,
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(6),
                            ),
                            border: Border(
                              left: BorderSide(
                                color: tokens.borderStrong,
                                width: 1,
                              ),
                              right: BorderSide(
                                color: tokens.borderStrong,
                                width: 1,
                              ),
                              bottom: BorderSide(
                                color: tokens.borderStrong,
                                width: 1,
                              ),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: tokens.overlay.withValues(alpha: 0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.checklist_rtl_outlined,
                                size: 11,
                                color: tokens.accent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                strings.todoPeekTab(completedCount, totalCount),
                                style: TextStyle(
                                  color: tokens.textSecondary,
                                  fontSize: FrameText.of(context)
                                      .caption
                                      .fontSize,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                Icons.keyboard_arrow_down_outlined,
                                size: 12,
                                color: tokens.textMuted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ));

    if (widget.hideBookTab || embedded) {
      return panelContent;
    }

    // Not FrameMotion.move: a zero-duration AnimatedSize mutates layout mid-frame.
    return AnimatedSize(
      duration: FrameMotion.fade(context, FrameMotion.small),
      curve: FrameMotion.enterCurve,
      alignment: Alignment.topCenter,
      child: panelContent,
    );
  }

  /// Embedded, the list fills the tab; as a popup it stays at most 220 px.
  Widget _listSlot({required bool embedded, required Widget child}) =>
      embedded
          ? Expanded(child: child)
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: child,
            );

  Widget _buildStatusBadge(
    TodoItem task,
    FrameTokens tokens,
    AppStrings strings,
  ) {
    if (task.isCompleted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: tokens.success.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(
            color: tokens.success.withValues(alpha: 0.35),
            width: 0.8,
          ),
        ),
        child: Text(
          strings.todoBadgeCompleted,
          style: TextStyle(
            color: tokens.success,
            fontSize: FrameText.of(context).caption.fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    if (task.isInProgress) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: tokens.agentWorking.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(
            color: tokens.agentWorking.withValues(alpha: 0.4),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 7,
              height: 7,
              child: FrameActivityIndicator(
                size: 7,
                strokeWidth: 1.2,
                color: tokens.agentWorking,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              strings.todoBadgeInProgress,
              style: TextStyle(
                color: tokens.agentWorking,
                fontSize: FrameText.of(context).caption.fontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border, width: 0.8),
      ),
      child: Text(
        strings.todoBadgePending,
        style: TextStyle(
          color: tokens.textMuted,
          fontSize: FrameText.of(context).caption.fontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
