import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/session/agent_status.dart';
import '../../domain/session/session_state.dart';
import '../daemon/daemon_providers.dart';
import '../../features/sessions_sidebar/pinned_sessions_provider.dart';
import '../../features/transcript/subagents_provider.dart';
import '../../features/transcript/workflows_provider.dart';
import 'notification_providers.dart';

/// How long a session must stay finished before its answer counts as the
/// final one. The status reads "settled" for a moment between steps of one
/// run (after a question is answered, after compaction, between turns the
/// agent continues on its own), and those moments must not notify.
const finalAnswerQuietPeriod = Duration(milliseconds: 1500);

/// The text of the agent's final answer in [entries], or null when the last
/// assistant message is not one (it hands off to a tool, or has no text).
SessionEntry? finalAnswerEntry(List<SessionEntry> entries) {
  for (final e in entries.reversed) {
    if (e.role != 'assistant') continue;
    if (e.text.contains('<task-notification>')) continue;
    if (e.text.trim().isEmpty || e.toolCallsAfterText.isNotEmpty) return null;
    return e;
  }
  return null;
}

class SessionNotificationWatcher extends ConsumerStatefulWidget {
  const SessionNotificationWatcher({super.key});

  @override
  ConsumerState<SessionNotificationWatcher> createState() =>
      _SessionNotificationWatcherState();
}

class _SessionNotificationWatcherState
    extends ConsumerState<SessionNotificationWatcher> {
  @override
  void initState() {
    super.initState();
    ref
        .read(desktopNotificationServiceProvider)
        .onNotificationClicked = (sessionId) {
      if (mounted) {
        ref.read(activeSessionIdProvider.notifier).state = sessionId;
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    final activeId = ref.watch(activeSessionIdProvider);
    final pinnedIds = ref.watch(pinnedSessionsProvider);
    final monitoredIds = <String>{
      if (activeId != null && activeId.isNotEmpty) activeId,
      ...pinnedIds,
    };

    return Stack(
      children: [
        for (final id in monitoredIds)
          _SessionWatcherItem(key: ValueKey('watcher_$id'), sessionId: id),
      ],
    );
  }
}

class _SessionWatcherItem extends ConsumerStatefulWidget {
  final String sessionId;

  const _SessionWatcherItem({super.key, required this.sessionId});

  @override
  ConsumerState<_SessionWatcherItem> createState() =>
      _SessionWatcherItemState();
}

class _SessionWatcherItemState extends ConsumerState<_SessionWatcherItem> {
  final Set<String> _handledUiRequestIds = <String>{};
  final Set<String> _handledEntryIds = <String>{};
  bool _isRunActive = false;
  Timer? _completionTimer;

  @override
  void dispose() {
    _completionTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final initial = ref.read(sessionStateFamily(widget.sessionId));
    for (final e in initial.entries) {
      if (e.role == 'assistant') {
        _handledEntryIds.add(e.id);
      }
    }
    for (final r in initial.pendingUiRequests) {
      final reqId = r['requestId']?.toString();
      if (reqId != null && reqId.isNotEmpty) {
        _handledUiRequestIds.add(reqId);
      }
    }
    _isRunActive =
        initial.agentStatus == AgentStatus.working ||
        initial.agentStatus == AgentStatus.retrying ||
        initial.agentStatus == AgentStatus.compacting ||
        initial.isStreaming ||
        initial.activeToolCalls.values.any((t) => t.isRunning);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionStateFamily(widget.sessionId), (prev, next) {
      final subagents = ref.read(subagentsFamily(widget.sessionId));
      _checkNotifications(next, subagents);
    });

    ref.listen<List<SubagentItem>>(subagentsFamily(widget.sessionId), (
      prev,
      next,
    ) {
      final session = ref.read(sessionStateFamily(widget.sessionId));
      _checkNotifications(session, next);
    });

    // Workflow runs and unlinked agents keep the run going too.
    ref.listen<bool>(backgroundAgentsRunningProvider(widget.sessionId), (
      prev,
      next,
    ) {
      _checkNotifications(
        ref.read(sessionStateFamily(widget.sessionId)),
        ref.read(subagentsFamily(widget.sessionId)),
      );
    });

    return const SizedBox.shrink();
  }

  Future<void> _checkNotifications(
    SessionState next,
    List<SubagentItem> subagents,
  ) async {
    // Run tracking (steps 2 and 3) happens whatever the focus: a run started
    // while PiFrame was in front must still notify if it ends while it is not.
    _trackRun(next, subagents);

    final enabled = ref.read(notificationsEnabledProvider);
    if (!enabled) return;

    final service = ref.read(desktopNotificationServiceProvider);
    final isFocusedCached = ref.read(appFocusProvider);

    // 1. Attention required: interactive choice, question, or confirmation dialog
    if (next.pendingUiRequests.isNotEmpty &&
        !await service.checkIsAppFocused(isFocusedCached) &&
        mounted) {
      final pendingInteraction = next.pendingUiRequests.where((r) {
        final method = r['method']?.toString();
        return r['dialog'] == true ||
            method == 'confirm' ||
            method == 'select' ||
            method == 'input' ||
            method == 'editor';
      }).toList();

      if (pendingInteraction.isNotEmpty) {
        for (final req in pendingInteraction) {
          final reqId = req['requestId']?.toString() ?? '';
          if (reqId.isNotEmpty && !_handledUiRequestIds.contains(reqId)) {
            _handledUiRequestIds.add(reqId);
            final sessionName = ref.read(
              sessionDisplayNameProvider(widget.sessionId),
            );
            final title = req['title']?.toString() ?? 'Attenzione richiesta';
            final message =
                req['message']?.toString() ??
                'L\'agente richiede una tua risposta o scelta.';
            unawaited(
              service.showNotification(
                title: 'Richiesta attenzione · $sessionName',
                body: '$title: $message',
                sessionId: widget.sessionId,
              ),
            );
          }
        }
      }
    }
  }

  void _trackRun(SessionState next, List<SubagentItem> subagents) {
    // 2. Track whether the agent is currently working or operating
    final hasRunningSubagents =
        subagents.any((s) => !s.isUnlinked && s.isRunning) ||
        ref.read(backgroundAgentsRunningProvider(widget.sessionId));
    final isCurrentlyOperating =
        next.agentStatus == AgentStatus.working ||
        next.agentStatus == AgentStatus.retrying ||
        next.agentStatus == AgentStatus.compacting ||
        next.isStreaming ||
        next.activeToolCalls.values.any((t) => t.isRunning) ||
        hasRunningSubagents;

    if (isCurrentlyOperating) {
      _isRunActive = true;
      // Still working: an answer seen a moment ago was not the final one.
      _completionTimer?.cancel();
      _completionTimer = null;
    }

    // Agent crashed or worker error: reset active run flag so no false completion is fired
    if (next.agentStatus == AgentStatus.workerError ||
        next.agentStatus == AgentStatus.error) {
      _isRunActive = false;
      _completionTimer?.cancel();
      _completionTimer = null;
      return;
    }

    // 3. Agent completed its final answer: the run must stay settled for
    // [finalAnswerQuietPeriod] with nothing left running, queued or waiting
    // on the user, so intermediate answers between steps never notify.
    if (_isRunActive && _isSettled(next, hasRunningSubagents)) {
      _completionTimer ??= Timer(finalAnswerQuietPeriod, _notifyIfFinished);
    }
  }

  bool _isSettled(SessionState state, bool hasRunningSubagents) =>
      (state.agentStatus == AgentStatus.settled ||
          state.agentStatus == AgentStatus.idle) &&
      !state.isStreaming &&
      !state.activeToolCalls.values.any((t) => t.isRunning) &&
      !hasRunningSubagents &&
      state.steeringQueue.isEmpty &&
      state.followUpQueue.isEmpty &&
      state.pendingUiRequests.isEmpty;

  Future<void> _notifyIfFinished() async {
    _completionTimer = null;
    if (!mounted || !_isRunActive) return;
    final state = ref.read(sessionStateFamily(widget.sessionId));
    final subagents = ref.read(subagentsFamily(widget.sessionId));
    final hasRunningSubagents =
        subagents.any((s) => !s.isUnlinked && s.isRunning) ||
        ref.read(backgroundAgentsRunningProvider(widget.sessionId));
    if (!_isSettled(state, hasRunningSubagents)) return;
    _isRunActive = false;

    final answer = finalAnswerEntry(state.entries);
    if (answer == null || _handledEntryIds.contains(answer.id)) return;
    _handledEntryIds.add(answer.id);

    if (!ref.read(notificationsEnabledProvider)) return;
    final service = ref.read(desktopNotificationServiceProvider);
    final isFocused = await service.checkIsAppFocused(
      ref.read(appFocusProvider),
    );
    if (isFocused || !mounted) return;
    final sessionName = ref.read(sessionDisplayNameProvider(widget.sessionId));
    final rawText = answer.text.trim();
    final preview = rawText.length > 120
        ? '${rawText.substring(0, 120)}...'
        : rawText;
    unawaited(
      service.showNotification(
        title: 'Risposta completata · $sessionName',
        body: preview,
        sessionId: widget.sessionId,
      ),
    );
  }
}
