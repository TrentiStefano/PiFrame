import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../domain/session/session_state.dart';
import 'subagents_provider.dart';
import 'task_notification_card.dart';

/// A `SubagentWorkflow` run, rebuilt from the parent transcript: the launch
/// tool call and the `<task-notification>` the run sends when it settles.
class WorkflowItem {
  final String id;
  final String name;
  final String? description;
  final List<String> phases;
  final String status; // 'running', 'completed', 'stopped', 'error'
  final String? toolCallId;
  final String? scriptPath;
  final String summary;
  final String result;
  final int timestamp;
  /// When the run's settling notification arrived, if it has.
  final int? endedAt;

  const WorkflowItem({
    required this.id,
    required this.name,
    this.description,
    this.phases = const [],
    this.status = 'running',
    this.toolCallId,
    this.scriptPath,
    this.summary = '',
    this.result = '',
    required this.timestamp,
    this.endedAt,
  });

  bool get isRunning => status == 'running';

  /// The run's journal of settled agents sits beside the script it saved.
  String? get journalPath {
    final path = scriptPath;
    // shortcut: a user-supplied scriptPath has no sibling journal, so progress is unknown until the run settles.
    if (path == null || !path.endsWith('.workflow.js')) return null;
    return path.replaceFirst(RegExp(r'\.js$'), '.jsonl');
  }

  WorkflowItem copyWith({String? status, String? summary, String? result, int? endedAt}) => WorkflowItem(
        id: id,
        name: name,
        description: description,
        phases: phases,
        status: status ?? this.status,
        toolCallId: toolCallId,
        scriptPath: scriptPath,
        summary: summary ?? this.summary,
        result: result ?? this.result,
        timestamp: timestamp,
        endedAt: endedAt ?? this.endedAt,
      );
}

String? _metaField(String script, String field) {
  final start = script.indexOf('meta');
  if (start < 0) return null;
  return RegExp('\\b$field\\s*:\\s*([\'"`])((?:(?!\\1).)*)\\1')
      .firstMatch(script.substring(start))
      ?.group(2);
}

List<String> _phaseTitles(String script) {
  final phases = RegExp(r'phases\s*:\s*\[([\s\S]*?)\]').firstMatch(script)?.group(1);
  if (phases == null) return const [];
  return [
    for (final match in RegExp(r'''title\s*:\s*(['"`])((?:(?!\1).)*)\1''').allMatches(phases))
      match.group(2)!,
  ];
}

String _workflowStatus(String notificationStatus) {
  final status = notificationStatus.toLowerCase();
  if (status.contains('error') || status.contains('fail')) return 'error';
  if (status.contains('stop') || status.contains('kill') || status.contains('cancel')) return 'stopped';
  return 'completed';
}

/// Workflow runs in transcript order, newest last.
List<WorkflowItem> parseWorkflows(
  List<SessionEntry> entries,
  Iterable<ToolExecutionState> activeTools,
) {
  final runs = <String, WorkflowItem>{};
  final byToolCall = <String, String>{};

  void addLaunch(ToolExecutionState tool, int timestamp) {
    if (tool.toolName.toLowerCase() != 'subagentworkflow') return;
    final output = tool.output;
    final runId = RegExp(r'Task ID:\s*(wf_[\w-]+)').firstMatch(output)?.group(1);
    final id = runId ?? tool.toolCallId;
    final script = tool.args['script']?.toString() ?? '';
    final previous = runs.remove(byToolCall[tool.toolCallId]);
    byToolCall[tool.toolCallId] = id;
    runs[id] = WorkflowItem(
      id: id,
      name: RegExp(r'Workflow "([^"]+)" started').firstMatch(output)?.group(1) ??
          _metaField(script, 'name') ??
          tool.args['name']?.toString() ??
          'Workflow',
      description: _metaField(script, 'description'),
      phases: _phaseTitles(script),
      // A launch that never reached "started" failed before the run existed.
      status: tool.isError || (!tool.isRunning && runId == null && output.isNotEmpty)
          ? 'error'
          : previous?.status ?? 'running',
      toolCallId: tool.toolCallId,
      scriptPath: RegExp(r'^Script:\s*(.+?)\s*$', multiLine: true).firstMatch(output)?.group(1),
      result: tool.isError || runId == null ? output : previous?.result ?? '',
      summary: previous?.summary ?? '',
      timestamp: previous?.timestamp ?? timestamp,
      endedAt: previous?.endedAt,
    );
  }

  for (final entry in entries) {
    for (final tool in entry.toolCalls) {
      addLaunch(tool, entry.timestamp);
    }
    for (final match in RegExp(r'<task-notification>[\s\S]*?</task-notification>')
        .allMatches(entry.text)) {
      final notification = TaskNotificationData.tryParse(match.group(0)!);
      if (notification == null) continue;
      final id = runs.containsKey(notification.taskId)
          ? notification.taskId
          : byToolCall[notification.toolUseId];
      final run = id == null ? null : runs[id];
      if (run == null) continue;
      runs[id!] = run.copyWith(
        status: _workflowStatus(notification.status),
        summary: notification.summary,
        result: notification.result,
        endedAt: entry.timestamp,
      );
    }
  }
  for (final tool in activeTools) {
    addLaunch(tool, DateTime.now().millisecondsSinceEpoch);
  }
  return runs.values.toList();
}

final workflowsFamily = Provider.autoDispose.family<List<WorkflowItem>, String>((ref, sessionId) {
  final (entries, activeTools) = ref.watch(
    sessionStateFamily(sessionId).select((s) => (s.entries, s.activeToolCalls)),
  );
  return parseWorkflows(entries, activeTools.values);
});

/// Splits child sessions the daemon could not tie to an `Agent` call between
/// the workflow runs whose lifetime covers their start. Runs are matched
/// newest first; children no run claims come back under the `''` key.
Map<String, List<SubagentItem>> workflowChildren(
  List<WorkflowItem> runs,
  List<SubagentItem> unlinked,
) {
  const slack = 5000;
  final byRun = <String, List<SubagentItem>>{for (final run in runs) run.id: []};
  final loose = <SubagentItem>[];
  final newestFirst = [...runs]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  for (final child in unlinked) {
    final started = child.startedAt;
    WorkflowItem? owner;
    if (started != null) {
      for (final run in newestFirst) {
        final end = run.endedAt;
        if (started >= run.timestamp - slack && (end == null || started <= end + slack)) {
          owner = run;
          break;
        }
      }
    }
    (owner == null ? loose : byRun[owner.id]!).add(child);
  }
  for (final list in byRun.values) {
    list.sort((a, b) => (a.startedAt ?? 0).compareTo(b.startedAt ?? 0));
  }
  return {...byRun, '': loose};
}

/// Whether the session still has background agents or workflows at work,
/// even when its own turn has ended.
final backgroundAgentsRunningProvider = Provider.autoDispose.family<bool, String>((ref, sessionId) {
  return ref.watch(subagentsFamily(sessionId)).any((agent) => agent.isRunning) ||
      ref.watch(workflowsFamily(sessionId)).any((run) => run.isRunning);
});

/// Whether the Agents/Workflows side panel is open for a session.
final agentActivityPanelOpenProvider = StateProvider.family<bool, String>((ref, sessionId) => false);
