import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/transcript/subagents_provider.dart';
import 'package:pi_frame/features/transcript/workflows_provider.dart';

void main() {
  const script = '''export const meta = {
  name: 'review-changes',
  description: 'Review then verify',
  phases: [{ title: 'Review' }, { title: 'Verify' }],
}
phase('Review')''';

  ToolExecutionState launch({String output = '', bool running = false, bool error = false}) =>
      ToolExecutionState(
        toolCallId: 'call_wf',
        toolName: 'SubagentWorkflow',
        args: const {'script': script},
        output: output,
        isRunning: running,
        isError: error,
      );

  const started = 'Workflow "review-changes" started in the background.\n'
      'Task ID: wf_abc123def456\n'
      'Script: C:\\tmp\\tasks\\wf_abc123def456.workflow.js\n';

  test('a started workflow runs until its task notification settles it', () {
    final running = parseWorkflows([
      SessionEntry(id: 'a', role: 'assistant', text: '', toolCalls: [launch(output: started)], timestamp: 1),
    ], const []);
    expect(running.single.id, 'wf_abc123def456');
    expect(running.single.name, 'review-changes');
    expect(running.single.description, 'Review then verify');
    expect(running.single.phases, ['Review', 'Verify']);
    expect(running.single.isRunning, isTrue);
    expect(running.single.journalPath, 'C:\\tmp\\tasks\\wf_abc123def456.workflow.jsonl');

    final done = parseWorkflows([
      SessionEntry(id: 'a', role: 'assistant', text: '', toolCalls: [launch(output: started)], timestamp: 1),
      const SessionEntry(
        id: 'n',
        role: 'custom',
        text: '<task-notification>\n<task-id>wf_abc123def456</task-id>\n<status>Done</status>\n'
            '<summary>Workflow "review-changes" completed — 3/3 agents</summary>\n<result>All good</result>\n'
            '</task-notification>',
        timestamp: 2,
      ),
    ], const []);
    expect(done.single.status, 'completed');
    expect(done.single.result, 'All good');
  });

  test('a launch still in flight is running and a rejected script is an error', () {
    expect(parseWorkflows(const [], [launch(running: true)]).single.isRunning, isTrue);
    final failed = parseWorkflows([
      SessionEntry(
        id: 'a',
        role: 'assistant',
        text: '',
        toolCalls: [launch(output: 'meta must be a pure literal')],
        timestamp: 1,
      ),
    ], const []);
    expect(failed.single.status, 'error');
    expect(failed.single.result, 'meta must be a pure literal');
  });

  test('child sessions go to the run that was live when they started', () {
    const old = WorkflowItem(id: 'wf_old', name: 'old', status: 'completed', timestamp: 1000, endedAt: 20000);
    const live = WorkflowItem(id: 'wf_new', name: 'new', timestamp: 60000);
    SubagentItem child(String id, int? startedAt) =>
        SubagentItem(id: id, name: id, isUnlinked: true, startedAt: startedAt);
    final split = workflowChildren(
      [old, live],
      [child('b', 70000), child('a', 2000), child('late', 61000), child('stray', 40000), child('unknown', null)],
    );
    expect(split['wf_old']!.map((c) => c.id), ['a']);
    expect(split['wf_new']!.map((c) => c.id), ['late', 'b']);
    expect(split['']!.map((c) => c.id), ['stray', 'unknown']);
  });
}
