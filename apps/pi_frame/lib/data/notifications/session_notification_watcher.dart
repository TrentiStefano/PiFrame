import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/session/agent_status.dart';
import '../../domain/session/session_state.dart';
import '../daemon/daemon_providers.dart';
import '../../features/sessions_sidebar/pinned_sessions_provider.dart';
import '../../features/transcript/subagents_provider.dart';
import 'notification_providers.dart';

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
    ref.read(desktopNotificationServiceProvider).onNotificationClicked =
        (sessionId) {
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
    _isRunActive = initial.agentStatus == AgentStatus.working ||
        initial.agentStatus == AgentStatus.retrying ||
        initial.agentStatus == AgentStatus.compacting ||
        initial.isStreaming ||
        initial.activeToolCalls.values.any((t) => t.isRunning);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      sessionStateFamily(widget.sessionId),
      (prev, next) {
        final subagents = ref.read(subagentsFamily(widget.sessionId));
        _checkNotifications(next, subagents);
      },
    );

    ref.listen<List<SubagentItem>>(
      subagentsFamily(widget.sessionId),
      (prev, next) {
        final session = ref.read(sessionStateFamily(widget.sessionId));
        _checkNotifications(session, next);
      },
    );

    return const SizedBox.shrink();
  }

  Future<void> _checkNotifications(
    SessionState next,
    List<SubagentItem> subagents,
  ) async {
    final enabled = ref.read(notificationsEnabledProvider);
    if (!enabled) return;

    final service = ref.read(desktopNotificationServiceProvider);
    final isFocusedCached = ref.read(appFocusProvider);
    final isFocused = await service.checkIsAppFocused(isFocusedCached);
    if (isFocused) return;

    // 1. Attention required: interactive choice, question, or confirmation dialog
    if (next.pendingUiRequests.isNotEmpty) {
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
            final message = req['message']?.toString() ??
                'L\'agente richiede una tua risposta o scelta.';
            unawaited(service.showNotification(
              title: 'Richiesta attenzione · $sessionName',
              body: '$title: $message',
              sessionId: widget.sessionId,
            ));
          }
        }
      }
    }

    // 2. Track whether the agent is currently working or operating
    final hasRunningSubagents =
        subagents.any((s) => !s.isUnlinked && s.isRunning);
    final isCurrentlyOperating = next.agentStatus == AgentStatus.working ||
        next.agentStatus == AgentStatus.retrying ||
        next.agentStatus == AgentStatus.compacting ||
        next.isStreaming ||
        next.activeToolCalls.values.any((t) => t.isRunning) ||
        hasRunningSubagents;

    if (isCurrentlyOperating) {
      _isRunActive = true;
    }

    // Agent crashed or worker error: reset active run flag so no false completion is fired
    if (next.agentStatus == AgentStatus.workerError ||
        next.agentStatus == AgentStatus.error) {
      _isRunActive = false;
      return;
    }

    // 3. Agent completed an answer:
    // Only fire when there was an active run that is now fully settled and idle,
    // with NO active tools, NO streaming, NO subagents running, NO queued steering/followups,
    // and NO pending interaction dialogs.
    final isSettledNow = (next.agentStatus == AgentStatus.settled ||
            next.agentStatus == AgentStatus.idle) &&
        !next.isStreaming &&
        !next.activeToolCalls.values.any((t) => t.isRunning) &&
        !hasRunningSubagents &&
        next.steeringQueue.isEmpty &&
        next.followUpQueue.isEmpty &&
        next.pendingUiRequests.isEmpty;

    if (_isRunActive && isSettledNow && next.entries.isNotEmpty) {
      _isRunActive = false;

      SessionEntry? lastAssistantEntry;
      for (final e in next.entries.reversed) {
        if (e.role == 'assistant' && !e.text.contains('<task-notification>')) {
          lastAssistantEntry = e;
          break;
        }
      }

      if (lastAssistantEntry != null &&
          !_handledEntryIds.contains(lastAssistantEntry.id)) {
        _handledEntryIds.add(lastAssistantEntry.id);
        final sessionName = ref.read(
          sessionDisplayNameProvider(widget.sessionId),
        );
        final rawText = lastAssistantEntry.text.trim();
        final preview = rawText.isNotEmpty
            ? (rawText.length > 120
                ? '${rawText.substring(0, 120)}...'
                : rawText)
            : 'L\'agente ha completato la risposta.';
        unawaited(service.showNotification(
          title: 'Risposta completata · $sessionName',
          body: preview,
          sessionId: widget.sessionId,
        ));
      }
    }
  }
}
