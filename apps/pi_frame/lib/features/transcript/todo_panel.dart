import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'todo_provider.dart';

class TodoPopDown extends ConsumerStatefulWidget {
  final String sessionId;
  final VoidCallback? onClose;

  const TodoPopDown({
    super.key,
    required this.sessionId,
    this.onClose,
  });

  @override
  ConsumerState<TodoPopDown> createState() => _TodoPopDownState();
}

class _TodoPopDownState extends ConsumerState<TodoPopDown> {
  final TextEditingController _addController = TextEditingController();
  bool _isAdding = false;

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

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final todos = ref.watch(todosFamily(widget.sessionId));
    final notifier = ref.read(todosFamily(widget.sessionId).notifier);

    final completedCount = todos.where((t) => t.isCompleted).length;
    final inProgressCount = todos.where((t) => t.isInProgress).length;
    final totalCount = todos.length;
    final percent = totalCount > 0 ? (completedCount / totalCount) : 0.0;
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return Container(
      key: const ValueKey('todo-popdown-panel'),
      margin: EdgeInsets.fromLTRB(isMobile ? 14 : 8, 0, isMobile ? 14 : 8, 8),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: tokens.borderStrong),
        boxShadow: [
          BoxShadow(
            color: tokens.overlay.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
            child: Row(
              children: [
                Icon(
                  Icons.checklist_rtl_rounded,
                  size: 17,
                  color: tokens.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Task Agente (Todo)',
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: percent >= 1.0
                                  ? tokens.success.withValues(alpha: 0.15)
                                  : tokens.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(tokens.radiusSm),
                            ),
                            child: Text(
                              '$completedCount / $totalCount completati',
                              style: TextStyle(
                                color: percent >= 1.0 ? tokens.success : tokens.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (inProgressCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.agentWorking.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(tokens.radiusSm),
                              ),
                              child: Text(
                                '$inProgressCount in corso',
                                style: TextStyle(
                                  color: tokens.agentWorking,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: percent,
                          backgroundColor: tokens.background,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            percent >= 1.0 ? tokens.success : tokens.accent,
                          ),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Aggiungi task',
                  icon: Icon(
                    _isAdding ? Icons.close : Icons.add_circle_outline,
                    size: 16,
                    color: tokens.accent,
                  ),
                  onPressed: () => setState(() => _isAdding = !_isAdding),
                ),
                if (widget.onClose != null)
                  IconButton(
                    key: const ValueKey('todo-popdown-close-btn'),
                    tooltip: 'Chiudi elenco task',
                    icon: Icon(Icons.close, size: 16, color: tokens.textMuted),
                    onPressed: widget.onClose,
                  ),
              ],
            ),
          ),
          Divider(color: tokens.border, height: 1),

          // Add Task Field (if open)
          if (_isAdding)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: tokens.background,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('todo-add-task-field'),
                      controller: _addController,
                      autofocus: true,
                      onSubmitted: (_) => _submitNewTask(),
                      style: TextStyle(color: tokens.textPrimary, fontSize: 12.5),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Aggiungi task per l\'agente e premi Invio...',
                        hintStyle: TextStyle(color: tokens.textMuted, fontSize: 12),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  FilledButton(
                    key: const ValueKey('todo-add-task-submit'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                    onPressed: _submitNewTask,
                    child: const Text('Aggiungi', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),

          // Task List
          if (todos.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'Nessun task ancora pianificato dall\'agente.',
                  style: TextStyle(color: tokens.textMuted, fontSize: 12),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                itemCount: todos.length,
                separatorBuilder: (ctx, i) => Divider(
                  color: tokens.border.withValues(alpha: 0.5),
                  height: 1,
                ),
                itemBuilder: (ctx, index) {
                  final task = todos[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Interactive Checkbox
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            key: ValueKey('todo-checkbox-${task.id}'),
                            value: task.isCompleted,
                            activeColor: tokens.accent,
                            checkColor: tokens.surface,
                            side: BorderSide(
                              color: task.isCompleted ? tokens.accent : tokens.borderStrong,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(tokens.radiusSm),
                            ),
                            onChanged: (val) {
                              notifier.toggleStatus(task.id);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Subject & description
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task.subject,
                                  style: TextStyle(
                                    color: task.isCompleted
                                        ? tokens.textMuted
                                        : task.isInProgress
                                        ? tokens.textPrimary
                                        : tokens.textSecondary,
                                    fontSize: 12.5,
                                    fontWeight: task.isInProgress
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    decoration: task.isCompleted
                                        ? TextDecoration.lineThrough
                                        : null,
                                    decorationColor: tokens.textMuted,
                                  ),
                                ),
                                if (task.description != null &&
                                    task.description!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    task.description!,
                                    style: TextStyle(
                                      color: tokens.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Status Badge
                        _buildStatusBadge(task, tokens),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(TodoItem task, FrameTokens tokens) {
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
          'COMPLETATO',
          style: TextStyle(
            color: tokens.success,
            fontSize: 9,
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
              width: 8,
              height: 8,
              child: CircularProgressIndicator(
                strokeWidth: 1.2,
                color: tokens.agentWorking,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'IN CORSO',
              style: TextStyle(
                color: tokens.agentWorking,
                fontSize: 9,
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
        'IN ATTESA',
        style: TextStyle(
          color: tokens.textMuted,
          fontSize: 9,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
