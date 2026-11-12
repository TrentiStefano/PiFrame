const fs = require('fs');
const path = require('path');

const scenariosDir = path.resolve(__dirname, '../../tools/fake-pi/scenarios');
fs.mkdirSync(scenariosDir, { recursive: true });

function writeScenario(name, data) {
  fs.writeFileSync(path.join(scenariosDir, `${name}.json`), JSON.stringify(data, null, 2), 'utf8');
  console.log(`Wrote scenario: ${name}.json`);
}

// 1. hello-world
writeScenario('hello-world', {
  name: 'hello-world',
  events: [
    { delayMs: 10, event: { type: 'agent_start' } },
    { delayMs: 10, event: { type: 'turn_start' } },
    { delayMs: 10, event: { type: 'message_start', message: { role: 'assistant', content: [] } } },
    { delayMs: 10, event: { type: 'message_update', usage: { input: 100, output: 5, total: 105 }, assistantMessageEvent: { type: 'text_start', contentIndex: 0 } } },
    { delayMs: 10, event: { type: 'message_update', usage: { input: 100, output: 15, total: 115 }, assistantMessageEvent: { type: 'text_delta', contentIndex: 0, delta: 'Hello from fake-pi!' } } },
    { delayMs: 10, event: { type: 'message_update', usage: { input: 100, output: 20, total: 120 }, assistantMessageEvent: { type: 'text_end', contentIndex: 0, content: 'Hello from fake-pi!' } } },
    { delayMs: 10, event: { type: 'message_end', message: { role: 'assistant', content: [{ type: 'text', text: 'Hello from fake-pi!' }] } } },
    { delayMs: 10, event: { type: 'turn_end', message: { role: 'assistant', content: [{ type: 'text', text: 'Hello from fake-pi!' }] }, toolResults: [] } },
    { delayMs: 10, event: { type: 'agent_end', messages: [{ role: 'assistant', content: [{ type: 'text', text: 'Hello from fake-pi!' }] }], willRetry: false } },
    { delayMs: 10, event: { type: 'agent_settled' } }
  ]
});

// 2. with-thinking
writeScenario('with-thinking', {
  name: 'with-thinking',
  events: [
    { delayMs: 10, event: { type: 'agent_start' } },
    { delayMs: 10, event: { type: 'turn_start' } },
    { delayMs: 10, event: { type: 'message_start', message: { role: 'assistant', content: [] } } },
    { delayMs: 10, event: { type: 'message_update', usage: { input: 150, output: 10, total: 160 }, assistantMessageEvent: { type: 'thinking_start', contentIndex: 0 } } },
    { delayMs: 10, event: { type: 'message_update', usage: { input: 150, output: 20, total: 170 }, assistantMessageEvent: { type: 'thinking_delta', contentIndex: 0, delta: 'Reasoning about problem...' } } },
    { delayMs: 10, event: { type: 'message_update', usage: { input: 150, output: 30, total: 180 }, assistantMessageEvent: { type: 'thinking_end', contentIndex: 0, content: 'Reasoning about problem...' } } },
    { delayMs: 10, event: { type: 'message_update', usage: { input: 150, output: 40, total: 190 }, assistantMessageEvent: { type: 'text_start', contentIndex: 1 } } },
    { delayMs: 10, event: { type: 'message_update', usage: { input: 150, output: 50, total: 200 }, assistantMessageEvent: { type: 'text_delta', contentIndex: 1, delta: 'Solution verified.' } } },
    { delayMs: 10, event: { type: 'message_update', usage: { input: 150, output: 60, total: 210 }, assistantMessageEvent: { type: 'text_end', contentIndex: 1, content: 'Solution verified.' } } },
    { delayMs: 10, event: { type: 'message_end', message: { role: 'assistant', content: [{ type: 'thinking', thinking: 'Reasoning about problem...' }, { type: 'text', text: 'Solution verified.' }] } } },
    { delayMs: 10, event: { type: 'turn_end', message: { role: 'assistant', content: [] }, toolResults: [] } },
    { delayMs: 10, event: { type: 'agent_end', messages: [], willRetry: false } },
    { delayMs: 10, event: { type: 'agent_settled' } }
  ]
});

// 3. tool-call
writeScenario('tool-call', {
  name: 'tool-call',
  events: [
    { delayMs: 10, event: { type: 'agent_start' } },
    { delayMs: 10, event: { type: 'turn_start' } },
    { delayMs: 10, event: { type: 'message_start', message: { role: 'assistant', content: [] } } },
    { delayMs: 10, event: { type: 'message_update', usage: { input: 200, output: 10, total: 210 }, assistantMessageEvent: { type: 'toolcall_start', contentIndex: 0, id: 'call_1', toolName: 'read' } } },
    { delayMs: 10, event: { type: 'message_update', usage: { input: 200, output: 20, total: 220 }, assistantMessageEvent: { type: 'toolcall_delta', contentIndex: 0, delta: '{"path":"file.txt"}' } } },
    { delayMs: 10, event: { type: 'message_update', usage: { input: 200, output: 30, total: 230 }, assistantMessageEvent: { type: 'toolcall_end', contentIndex: 0, toolCall: { id: 'call_1', name: 'read', args: { path: 'file.txt' } } } } },
    { delayMs: 10, event: { type: 'message_end', message: { role: 'assistant', content: [{ type: 'tool_call', id: 'call_1', name: 'read', args: { path: 'file.txt' } }] } } },
    { delayMs: 10, event: { type: 'tool_execution_start', toolCallId: 'call_1', toolName: 'read', args: { path: 'file.txt' } } },
    { delayMs: 10, event: { type: 'tool_execution_update', toolCallId: 'call_1', toolName: 'read', args: { path: 'file.txt' }, partialResult: 'File content preview...' } },
    { delayMs: 10, event: { type: 'tool_execution_end', toolCallId: 'call_1', toolName: 'read', result: 'File content complete.', isError: false } },
    { delayMs: 10, event: { type: 'turn_end', message: { role: 'assistant', content: [] }, toolResults: [{ role: 'toolResult', toolCallId: 'call_1', result: 'File content complete.' }] } },
    { delayMs: 10, event: { type: 'agent_end', messages: [], willRetry: false } },
    { delayMs: 10, event: { type: 'agent_settled' } }
  ]
});

// 4. parallel-tools
writeScenario('parallel-tools', {
  name: 'parallel-tools',
  events: [
    { delayMs: 10, event: { type: 'agent_start' } },
    { delayMs: 10, event: { type: 'turn_start' } },
    { delayMs: 10, event: { type: 'message_start', message: { role: 'assistant', content: [] } } },
    { delayMs: 10, event: { type: 'message_update', usage: { input: 200, output: 10, total: 210 }, assistantMessageEvent: { type: 'toolcall_start', contentIndex: 0, id: 'call_a', toolName: 'read' } } },
    { delayMs: 10, event: { type: 'message_update', usage: { input: 200, output: 20, total: 220 }, assistantMessageEvent: { type: 'toolcall_end', contentIndex: 0, toolCall: { id: 'call_a', name: 'read', args: { path: 'a.txt' } } } } },
    { delayMs: 10, event: { type: 'message_update', usage: { input: 200, output: 30, total: 230 }, assistantMessageEvent: { type: 'toolcall_start', contentIndex: 1, id: 'call_b', toolName: 'read' } } },
    { delayMs: 10, event: { type: 'message_update', usage: { input: 200, output: 40, total: 240 }, assistantMessageEvent: { type: 'toolcall_end', contentIndex: 1, toolCall: { id: 'call_b', name: 'read', args: { path: 'b.txt' } } } } },
    { delayMs: 10, event: { type: 'message_end', message: { role: 'assistant', content: [{ type: 'tool_call', id: 'call_a', name: 'read', args: { path: 'a.txt' } }, { type: 'tool_call', id: 'call_b', name: 'read', args: { path: 'b.txt' } }] } } },
    { delayMs: 10, event: { type: 'tool_execution_start', toolCallId: 'call_a', toolName: 'read', args: { path: 'a.txt' } } },
    { delayMs: 10, event: { type: 'tool_execution_start', toolCallId: 'call_b', toolName: 'read', args: { path: 'b.txt' } } },
    { delayMs: 10, event: { type: 'tool_execution_end', toolCallId: 'call_a', toolName: 'read', result: 'Content A', isError: false } },
    { delayMs: 10, event: { type: 'tool_execution_end', toolCallId: 'call_b', toolName: 'read', result: 'Content B', isError: false } },
    { delayMs: 10, event: { type: 'turn_end', message: { role: 'assistant', content: [] }, toolResults: [] } },
    { delayMs: 10, event: { type: 'agent_end', messages: [], willRetry: false } },
    { delayMs: 10, event: { type: 'agent_settled' } }
  ]
});

// 5. retry-then-success
writeScenario('retry-then-success', {
  name: 'retry-then-success',
  events: [
    { delayMs: 10, event: { type: 'agent_start' } },
    { delayMs: 10, event: { type: 'auto_retry_start', attempt: 1, maxAttempts: 3, delayMs: 100, errorMessage: 'Provider temporary error' } },
    { delayMs: 10, event: { type: 'auto_retry_end', success: true, attempt: 1 } },
    { delayMs: 10, event: { type: 'turn_start' } },
    { delayMs: 10, event: { type: 'message_start', message: { role: 'assistant', content: [] } } },
    { delayMs: 10, event: { type: 'message_update', usage: { input: 120, output: 10, total: 130 }, assistantMessageEvent: { type: 'text_start', contentIndex: 0 } } },
    { delayMs: 10, event: { type: 'message_update', usage: { input: 120, output: 20, total: 140 }, assistantMessageEvent: { type: 'text_delta', contentIndex: 0, delta: 'Success after retry!' } } },
    { delayMs: 10, event: { type: 'message_update', usage: { input: 120, output: 25, total: 145 }, assistantMessageEvent: { type: 'text_end', contentIndex: 0, content: 'Success after retry!' } } },
    { delayMs: 10, event: { type: 'message_end', message: { role: 'assistant', content: [{ type: 'text', text: 'Success after retry!' }] } } },
    { delayMs: 10, event: { type: 'turn_end', message: { role: 'assistant', content: [] }, toolResults: [] } },
    { delayMs: 10, event: { type: 'agent_end', messages: [], willRetry: false } },
    { delayMs: 10, event: { type: 'agent_settled' } }
  ]
});

// 6. compaction
writeScenario('compaction', {
  name: 'compaction',
  events: [
    { delayMs: 10, event: { type: 'compaction_start', reason: 'manual' } },
    { delayMs: 20, event: { type: 'compaction_end', result: { tokensBefore: 50000, tokensAfter: 8000, cost: 0.05 }, aborted: false, willRetry: false } }
  ]
});

// 7. ui-confirm
writeScenario('ui-confirm', {
  name: 'ui-confirm',
  events: [
    { delayMs: 10, event: { type: 'agent_start' } },
    { delayMs: 10, event: { type: 'extension_ui_request', id: 'req_conf_test', method: 'confirm', title: 'Confirm Delete', message: 'Proceed with deletion?' } },
    { delayMs: 10, event: { type: 'agent_settled' } }
  ]
});

// 8. ui-select-timeout
writeScenario('ui-select-timeout', {
  name: 'ui-select-timeout',
  events: [
    { delayMs: 10, event: { type: 'agent_start' } },
    { delayMs: 10, event: { type: 'extension_ui_request', id: 'req_sel_test', method: 'select', title: 'Select Option', options: ['A', 'B'], timeout: 200 } },
    { delayMs: 250, event: { type: 'agent_settled' } }
  ]
});

// 9. crash-mid-stream
writeScenario('crash-mid-stream', {
  name: 'crash-mid-stream',
  events: [
    { delayMs: 10, event: { type: 'agent_start' } },
    { delayMs: 10, event: { type: 'turn_start' } },
    { delayMs: 10, event: { type: 'message_start', message: { role: 'assistant', content: [] } } },
    { delayMs: 10, event: { type: 'message_update', usage: { input: 100, output: 5, total: 105 }, assistantMessageEvent: { type: 'text_start', contentIndex: 0 } } },
    { delayMs: 10, event: { type: 'message_update', usage: { input: 100, output: 10, total: 110 }, assistantMessageEvent: { type: 'text_delta', contentIndex: 0, delta: 'About to crash...' } } },
    { delayMs: 20, crash: true, exitCode: 137 }
  ]
});

// 10. malformed-line
writeScenario('malformed-line', {
  name: 'malformed-line',
  events: [
    { delayMs: 10, event: { type: 'agent_start' } },
    { delayMs: 10, malformed: true },
    { delayMs: 10, event: { type: 'agent_settled' } }
  ]
});

// 11. slow-stream (60s slow stream for proof of architecture Step 3.5)
const slowEvents = [
  { delayMs: 50, event: { type: 'agent_start' } },
  { delayMs: 50, event: { type: 'turn_start' } },
  { delayMs: 50, event: { type: 'message_start', message: { role: 'assistant', content: [] } } },
  { delayMs: 50, event: { type: 'message_update', usage: { input: 100, output: 1, total: 101 }, assistantMessageEvent: { type: 'text_start', contentIndex: 0 } } }
];
for (let i = 1; i <= 60; i++) {
  slowEvents.push({
    delayMs: 200,
    event: {
      type: 'message_update',
      usage: { input: 100, output: i * 2, total: 100 + i * 2 },
      assistantMessageEvent: { type: 'text_delta', contentIndex: 0, delta: ` Token #${i}...` }
    }
  });
}
slowEvents.push(
  { delayMs: 50, event: { type: 'message_update', usage: { input: 100, output: 120, total: 220 }, assistantMessageEvent: { type: 'text_end', contentIndex: 0, content: 'Slow stream finished.' } } },
  { delayMs: 50, event: { type: 'message_end', message: { role: 'assistant', content: [{ type: 'text', text: 'Slow stream finished.' }] } } },
  { delayMs: 50, event: { type: 'turn_end', message: { role: 'assistant', content: [] }, toolResults: [] } },
  { delayMs: 50, event: { type: 'agent_end', messages: [], willRetry: false } },
  { delayMs: 50, event: { type: 'agent_settled' } }
);
writeScenario('slow-stream', {
  name: 'slow-stream',
  events: slowEvents
});

// 12. huge-output
const largeText = 'A'.repeat(50000);
writeScenario('huge-output', {
  name: 'huge-output',
  events: [
    { delayMs: 10, event: { type: 'agent_start' } },
    { delayMs: 10, event: { type: 'turn_start' } },
    { delayMs: 10, event: { type: 'message_start', message: { role: 'assistant', content: [] } } },
    { delayMs: 10, event: { type: 'message_update', usage: { input: 100, output: 10000, total: 10100 }, assistantMessageEvent: { type: 'text_start', contentIndex: 0 } } },
    { delayMs: 10, event: { type: 'message_update', usage: { input: 100, output: 20000, total: 20100 }, assistantMessageEvent: { type: 'text_delta', contentIndex: 0, delta: largeText } } },
    { delayMs: 10, event: { type: 'message_update', usage: { input: 100, output: 30000, total: 30100 }, assistantMessageEvent: { type: 'text_end', contentIndex: 0, content: largeText } } },
    { delayMs: 10, event: { type: 'message_end', message: { role: 'assistant', content: [{ type: 'text', text: largeText }] } } },
    { delayMs: 10, event: { type: 'turn_end', message: { role: 'assistant', content: [] }, toolResults: [] } },
    { delayMs: 10, event: { type: 'agent_end', messages: [], willRetry: false } },
    { delayMs: 10, event: { type: 'agent_settled' } }
  ]
});

// fake-pi replaces '{{prompt}}' with the prompt the user sent and '{{now}}' with the send time,
// so elapsed-time chips stay realistic.
function promptStart(message = '{{prompt}}') {
  return [
    { delayMs: 5, event: { type: 'agent_start' } },
    { delayMs: 5, event: { type: 'turn_start' } },
    { event: { type: 'message_start', message: { role: 'user', content: message, timestamp: '{{now}}' } } },
    { event: { type: 'message_end', message: { role: 'user', content: message, timestamp: '{{now}}' } } }
  ];
}
function finish(events, summary = 'The requested work is complete.') {
  events.push(
    { delayMs: 5, event: { type: 'turn_end', message: { role: 'assistant', content: [{ type: 'text', text: summary }] }, toolResults: [] } },
    { delayMs: 5, event: { type: 'agent_end', messages: [{ role: 'assistant', content: [{ type: 'text', text: summary }] }], willRetry: false } },
    { delayMs: 5, event: { type: 'agent_settled' } }
  );
  return events;
}
function textReply(events, text) {
  events.push(
    { event: { type: 'message_start', message: { role: 'assistant', content: [] } } },
    { event: { type: 'message_update', usage: { input: 80, output: 8, total: 88 }, assistantMessageEvent: { type: 'text_start', contentIndex: 0 } } },
    { event: { type: 'message_update', usage: { input: 80, output: 24, total: 104 }, assistantMessageEvent: { type: 'text_delta', contentIndex: 0, delta: text } } },
    { event: { type: 'message_end', message: { role: 'assistant', content: [{ type: 'text', text }] } } }
  );
}
function toolCall(events, id, name, args, output, delayMs = 10) {
  events.push(
    { event: { type: 'message_start', message: { role: 'assistant', content: [] } } },
    { event: { type: 'message_end', message: { role: 'assistant', content: [{ type: 'toolCall', id, name, arguments: args }] } } },
    { event: { type: 'tool_execution_start', toolCallId: id, toolName: name, args } },
    { delayMs, event: { type: 'tool_execution_update', toolCallId: id, toolName: name, args, partialResult: typeof output === 'string' ? output.slice(0, 60) : JSON.stringify(output).slice(0, 60) } },
    { event: { type: 'tool_execution_end', toolCallId: id, toolName: name, result: output, isError: false } }
  );
}
function writeScenarioWithIndex(name, description, covers, data) {
  writeScenario(name, { name, description, ...data });
  scenarioIndex.push({ name, description, covers });
}
const scenarioIndex = [
  { name: 'hello-world', description: 'Basic text, tool history and successful reply.', covers: ['transcript', 'tool calls'] },
  { name: 'with-thinking', description: 'Thinking stream followed by assistant text.', covers: ['thinking', 'transcript'] },
  { name: 'tool-call', description: 'Single tool call with progress and result.', covers: ['tool timeline', 'tool progress'] },
  { name: 'parallel-tools', description: 'Two tool calls executed in one turn.', covers: ['parallel tools', 'tool timeline'] },
  { name: 'retry-then-success', description: 'Provider retry followed by a successful answer.', covers: ['retry state'] },
  { name: 'compaction', description: 'Standalone compaction lifecycle events.', covers: ['compaction'] },
  { name: 'ui-confirm', description: 'Extension confirmation dialog request.', covers: ['extension UI', 'confirm dialog'] },
  { name: 'ui-select-timeout', description: 'Select dialog request with a timeout.', covers: ['extension UI', 'select dialog'] },
  { name: 'crash-mid-stream', description: 'Process exits during a streamed response.', covers: ['worker recovery', 'streaming'] },
  { name: 'malformed-line', description: 'Malformed JSONL followed by a valid event.', covers: ['protocol diagnostics'] },
  { name: 'slow-stream', description: 'Progressive token stream for live rendering and abort checks.', covers: ['streaming', 'abort'] },
  { name: 'huge-output', description: 'Large assistant output for rendering limits.', covers: ['large output'] }
];

// 13. provider-error: empty terminal assistant message must mark the user prompt failed.
{
  const events = promptStart();
  events.push(
    { event: { type: 'message_start', message: { role: 'assistant', content: [] } } },
    { event: { type: 'message_end', message: { role: 'assistant', content: [], stopReason: 'error', errorMessage: '429 Too Many Requests: rate limit exceeded' } } }
  );
  writeScenarioWithIndex('provider-error', 'Empty provider error marks the user prompt failed.', ['failed user prompt', 'provider error'], { events: finish(events, '') });
}
// 14. provider-error-after-reply
{
  const events = promptStart();
  textReply(events, 'The notes mention a small offline simulator.');
  events.push(
    { event: { type: 'message_start', message: { role: 'assistant', content: [] } } },
    { event: { type: 'message_end', message: { role: 'assistant', content: [], stopReason: 'error', errorMessage: '429 Too Many Requests: rate limit exceeded' } } }
  );
  writeScenarioWithIndex('provider-error-after-reply', 'Partial assistant reply followed by a terminal provider error.', ['provider error', 'partial reply'], { events: finish(events, '') });
}
// 15. retry-exhausted
{
  const events = promptStart();
  for (let attempt = 1; attempt <= 3; attempt++) {
    events.push(
      { delayMs: 10, event: { type: 'auto_retry_start', attempt, maxAttempts: 3, delayMs: attempt * 100, errorMessage: `Provider request failed on attempt ${attempt}` } },
      { delayMs: 10, event: { type: 'auto_retry_end', success: false, attempt, finalError: attempt === 3 ? '429 Too Many Requests: retry limit reached' : undefined } }
    );
  }
  writeScenarioWithIndex('retry-exhausted', 'Three failed retries with a final provider error.', ['retry state', 'failed user prompt'], { events: finish(events, '') });
}
// 16. aborted-turn
{
  const events = promptStart();
  events.push(
    { event: { type: 'message_start', message: { role: 'assistant', content: [] } } },
    { event: { type: 'message_update', assistantMessageEvent: { type: 'text_start', contentIndex: 0 } } },
    { event: { type: 'message_update', assistantMessageEvent: { type: 'text_delta', contentIndex: 0, delta: 'I was checking the project structure when the run was stopped.' } } },
    { event: { type: 'message_end', message: { role: 'assistant', content: [{ type: 'text', text: 'I was checking the project structure when the run was stopped.' }], stopReason: 'aborted' } } }
  );
  writeScenarioWithIndex('aborted-turn', 'Partial assistant text ends with an aborted stop reason.', ['abort', 'partial reply'], { events: finish(events, '') });
}
// 17. edit-files
{
  const events = promptStart();
  const patch = '--- a/notes.md\n+++ b/notes.md\n@@ -1,2 +1,3 @@\n # Notes\n-Status: draft\n+Status: reviewed\n+Feature: offline timeline preview\n';
  toolCall(events, 'write_feature', 'write', { path: 'src/feature.dart', content: 'class Feature {}\n' }, 'Wrote src/feature.dart.');
  events.push({ writeFile: { path: 'src/feature.dart', content: 'class Feature {}\n' } });
  toolCall(events, 'edit_notes', 'edit', { path: 'notes.md', oldText: 'Status: draft', newText: 'Status: reviewed' }, JSON.stringify({ summary: 'Updated notes.md', details: { patch } }));
  events.push({ writeFile: { path: 'notes.md', content: '# Notes\nStatus: reviewed\nFeature: offline timeline preview\n' } });
  textReply(events, 'Added `src/feature.dart` and updated `notes.md`. Review the changes before merging.');
  writeScenarioWithIndex('edit-files', 'Writes a source file and returns a parsed unified diff for review.', ['file writing', 'diff preview', 'review changes'], { events: finish(events, 'Added a small feature and updated the notes.') });
}
// 18. subagents
{
  const events = promptStart();
  const launches = [
    ['agent_review', 'reviewer', { subagent_type: 'reviewer', description: 'Review the Dart changes for correctness.' }],
    ['agent_tests', 'worker', { subagent_type: 'worker', description: 'Check the offline test coverage.' }]
  ];
  events.push({ event: { type: 'message_start', message: { role: 'assistant', content: [] } } });
  events.push({ event: { type: 'message_end', message: { role: 'assistant', content: launches.map(([id, , args]) => ({ type: 'toolCall', id, name: 'agent', arguments: args })) } } });
  for (const [id, , args] of launches) events.push({ event: { type: 'tool_execution_start', toolCallId: id, toolName: 'agent', args } });
  for (let tick = 1; tick <= 4; tick++) {
    for (const [id, , args] of launches) events.push({ delayMs: 1000, event: { type: 'tool_execution_update', toolCallId: id, toolName: 'agent', args, partialResult: `Agent started in background.\nProgress: ${tick * 25}% — reviewing files and tests.` } });
  }
  for (const [id, , args] of launches) events.push({ event: { type: 'tool_execution_end', toolCallId: id, toolName: 'agent', result: 'Agent started in background.', isError: false } });
  const workflowArgs = { name: 'Offline verification', script: '---\nname: Offline verification\ndescription: Check simulator scenarios\n---\nRun the test suite.' };
  toolCall(events, 'workflow_call', 'SubagentWorkflow', workflowArgs, 'Task ID: wf_offline-001\nWorkflow "Offline verification" started\nScript: offline.workflow.js');
  const notices = [
    '<task-notification><task-id>agent-review-001</task-id><tool-use-id>agent_review</tool-use-id><status>completed</status><summary>Agent "reviewer" finished</summary><result>Review passed.\n```dart\nfinal ready = true;\n```</result><usage><total_tokens>1200</total_tokens><tool_uses>3</tool_uses><context_percent>4</context_percent><duration_ms>8000</duration_ms></usage></task-notification>',
    '<task-notification><task-id>agent-tests-001</task-id><tool-use-id>agent_tests</tool-use-id><status>completed</status><summary>Agent "worker" finished</summary><result>Tests passed.\n```dart\nexpect(ok, isTrue);\n```</result><usage><total_tokens>900</total_tokens><tool_uses>2</tool_uses><context_percent>3</context_percent><duration_ms>8000</duration_ms></usage></task-notification>',
    '<task-notification><task-id>wf_offline-001</task-id><tool-use-id>workflow_call</tool-use-id><status>completed</status><summary>Offline verification completed</summary><result>Simulator checks passed.\n```text\n18 scenarios available\n```</result></task-notification>'
  ].join('\n\n');
  textReply(events, `Delegated checks are complete.\n\n${notices}`);
  writeScenarioWithIndex('subagents', 'Two background agents show progress, then agent and workflow notifications complete.', ['subagents', 'workflows', 'background progress', 'task notifications'], { events: finish(events, 'Delegated checks are complete.') });
}
// 19. todos
{
  const events = promptStart();
  const tasks = [
    { id: 1, subject: 'Inspect the existing flow', status: 'pending', activeForm: 'Inspecting the existing flow' },
    { id: 2, subject: 'Update the simulator', status: 'pending', activeForm: 'Updating the simulator' },
    { id: 3, subject: 'Run offline checks', status: 'pending', activeForm: 'Running offline checks' }
  ];
  toolCall(events, 'todo_create', 'todo', { action: 'create', subject: tasks[0].subject, id: 1, status: 'pending' }, JSON.stringify({ tasks: [tasks[0]] }), 300);
  toolCall(events, 'todo_progress', 'todo', { action: 'update', id: 1, status: 'in_progress' }, JSON.stringify({ tasks: [{ ...tasks[0], status: 'in_progress' }] }), 600);
  toolCall(events, 'todo_add', 'todo', { action: 'create', subject: tasks[1].subject, id: 2, status: 'pending' }, JSON.stringify({ tasks: [{ ...tasks[0], status: 'in_progress' }, tasks[1]] }), 600);
  toolCall(events, 'todo_complete', 'todo', { action: 'update', id: 1, status: 'completed' }, JSON.stringify({ tasks: [{ ...tasks[0], status: 'completed' }, tasks[1]] }), 600);
  toolCall(events, 'todo_checks', 'todo', { action: 'create', subject: tasks[2].subject, id: 3, status: 'pending' }, JSON.stringify({ tasks: [{ ...tasks[0], status: 'completed' }, tasks[1], tasks[2]] }), 600);
  toolCall(events, 'todo_finish', 'todo', { action: 'update', id: 2, status: 'completed' }, JSON.stringify({ tasks: [{ ...tasks[0], status: 'completed' }, { ...tasks[1], status: 'completed' }, tasks[2]] }), 600);
  toolCall(events, 'todo_last', 'todo', { action: 'update', id: 3, status: 'completed' }, JSON.stringify({ tasks: tasks.map((task) => ({ ...task, status: 'completed' })) }), 600);
  textReply(events, 'All three tasks are complete.');
  writeScenarioWithIndex('todos', 'Todo calls create tasks and move them through pending, in progress and completed.', ['todos', 'task status'], { events: finish(events, 'All three tasks are complete.') });
}
// 20-23. Extension dialogs and live status widgets.
writeScenarioWithIndex('ui-input', 'Extension input dialog with a placeholder and prefilled value.', ['extension UI', 'input dialog'], { events: finish([
  ...promptStart(),
  { event: { type: 'extension_ui_request', id: 'req_input', method: 'input', title: 'Project label', message: 'Choose a short label for this workspace.', placeholder: 'for example, mobile-app', prefill: 'offline-demo' } }
], 'The project label is ready.') });
writeScenarioWithIndex('ui-editor', 'Extension editor dialog with prefilled multiline text.', ['extension UI', 'editor dialog'], { events: finish([
  ...promptStart(),
  { event: { type: 'extension_ui_request', id: 'req_editor', method: 'editor', title: 'Release note', message: 'Review and edit the draft.', prefill: 'Offline simulator update\n\n- Added workflow coverage\n- Improved error states' } }
], 'The release note was saved.') });
writeScenarioWithIndex('ui-question-preview', 'Select dialog with numbered options and inline code previews.', ['extension UI', 'select dialog', 'option previews'], { events: finish([
  ...promptStart(),
  { event: { type: 'extension_ui_request', id: 'req_preview', method: 'select', title: 'Choose an implementation\n\n--- 1. Minimal preview ---\n```dart\nreturn const Feature();\n```\n\n--- 2. Expanded preview ---\n```dart\nclass Feature extends StatelessWidget {\n  const Feature({super.key});\n}\n```', options: ['1. Minimal — Keep the change compact', '2. Expanded — Add a small reusable widget'] } }
], 'The selected implementation is ready.') });
writeScenarioWithIndex('ui-status-widgets', 'Sends non-blocking notifications and updates extension status, widget and title.', ['extension UI', 'notifications', 'status', 'widgets', 'title'], { events: finish([
  ...promptStart(),
  { event: { type: 'extension_ui_request', id: 'notify_info', method: 'notify', notifyType: 'info', message: 'Workspace check started.' } },
  { event: { type: 'extension_ui_request', id: 'notify_warning', method: 'notify', notifyType: 'warning', message: 'One optional setting is not configured.' } },
  { event: { type: 'extension_ui_request', id: 'notify_error', method: 'notify', notifyType: 'error', message: 'A simulated check failed; the session remains available.' } },
  { event: { type: 'extension_ui_request', id: 'status', method: 'setStatus', statusKey: 'offline-check', statusText: 'Checking scenarios' } },
  { event: { type: 'extension_ui_request', id: 'widget', method: 'setWidget', widgetKey: 'offline-summary', widgetLines: ['Scenarios: 18', 'Mode: offline'], widgetPlacement: 'status' } },
  { event: { type: 'extension_ui_request', id: 'title', method: 'setTitle', title: 'Offline review' } },
  ...(() => { const nested = []; textReply(nested, 'Status updates are visible and the session is ready.'); return nested; })()
], 'Status updates are visible and the session is ready.') });
// 24. rich-content
{
  const events = promptStart();
  const text = '# Offline review\n\nA **small** project update with `inline code`.\n\n- First item\n- Second item\n\n1. Inspect the code\n2. Run the tests\n\n| Check | Result |\n| --- | --- |\n| Build | Ready |\n\n> Keep the change focused.\n\nSee [the notes](https://example.invalid/notes) and `notes.md:3`.\n\n```dart\nclass Feature {}\n```\n\n```diff\n-Status: draft\n+Status: reviewed\n```';
  events.push(
    { event: { type: 'message_start', message: { role: 'assistant', content: [] } } },
    { event: { type: 'message_update', assistantMessageEvent: { type: 'text_start', contentIndex: 0 } } },
    { event: { type: 'message_update', assistantMessageEvent: { type: 'text_delta', contentIndex: 0, delta: text } } },
    { event: { type: 'message_end', message: { role: 'assistant', content: [{ type: 'text', text }, { type: 'image', data: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l2sAAAAASUVORK5CYII=', mimeType: 'image/png' }] } } }
  );
  writeScenarioWithIndex('rich-content', 'Markdown, fenced code, links, path mention and a valid tiny PNG image block.', ['markdown', 'code blocks', 'image content'], { events: finish(events, 'Here is the requested content overview.') });
}
// 25. transcript-entries
{
  const events = promptStart();
  const specialMessages = [
    { role: 'bashExecution', id: 'bash_fail_1', command: 'npm test', output: '2 tests failed', exitCode: 1, timestamp: '{{now}}' },
    { role: 'compactionSummary', id: 'compact_1', summary: 'Earlier messages were summarized.', tokensBefore: 48000, timestamp: '{{now}}' },
    { role: 'branchSummary', id: 'branch_1', summary: 'Alternative implementation considered.', fromId: 'entry_old', timestamp: '{{now}}' },
    { role: 'custom', id: 'custom_1', customType: 'offline-note', display: true, content: [{ type: 'text', text: 'Visible custom transcript entry.' }], details: { source: 'fake-pi' }, timestamp: '{{now}}' }
  ];
  for (const message of specialMessages) events.push({ event: { type: 'message_end', message } });
  textReply(events, 'Special transcript entries were added.');
  writeScenarioWithIndex('transcript-entries', 'Adds bash failure, compaction summary, branch summary and visible custom entry.', ['transcript entries', 'bash output', 'milestones'], { events: finish(events, 'Special transcript entries were added.'), messages: specialMessages });
}
// 26. context-high
{
  const events = promptStart();
  events.push(
    { event: { type: 'message_start', message: { role: 'assistant', content: [] } } },
    { event: { type: 'message_update', usage: { input: 110000, output: 500, total: 110500 }, assistantMessageEvent: { type: 'text_start', contentIndex: 0 } } },
    { event: { type: 'message_update', usage: { input: 117000, output: 900, total: 117900 }, assistantMessageEvent: { type: 'text_delta', contentIndex: 0, delta: 'Context usage is now near the configured limit.' } } },
    { event: { type: 'compaction_start', reason: 'threshold' } },
    { event: { type: 'compaction_end', result: { tokensBefore: 117900, tokensAfter: 24000, estimatedTokensAfter: 24000, cost: 0.03 }, aborted: false, willRetry: false } },
    { event: { type: 'message_end', message: { role: 'assistant', content: [{ type: 'text', text: 'Context usage is now near the configured limit.' }], usage: { input: 117000, output: 900, total: 117900 } } } }
  );
  writeScenarioWithIndex('context-high', 'Usage reaches about 92 percent of a 128k context before compaction.', ['context usage', 'compaction'], { events: finish(events, 'Context was compacted successfully.'), stats: { tokens: { input: 117000, output: 900, total: 117900 }, cost: 0.03, contextUsage: { tokens: 117760, contextWindow: 128000, percent: 92 } } });
}
// 27. session-tree
{
  const tree = [
    { id: 'root_user', role: 'user', summary: 'Start a small feature', isLeaf: false, isActive: false },
    { id: 'main_answer', role: 'assistant', summary: 'The current implementation uses a compact API.', isLeaf: true, isActive: true },
    { id: 'branch_answer', role: 'assistant', summary: 'An alternative implementation uses an adapter.', isLeaf: true, isActive: false }
  ];
  const entries = [
    { id: 'root_user', parentId: null, type: 'message', message: { role: 'user', content: 'Start a small feature', timestamp: 1000 } },
    { id: 'main_answer', parentId: 'root_user', type: 'message', message: { role: 'assistant', content: 'The current implementation uses a compact API.', timestamp: 2000 } },
    { id: 'branch_answer', parentId: 'root_user', type: 'message', message: { role: 'assistant', content: 'An alternative implementation uses an adapter.', timestamp: 3000 } }
  ];
  const events = promptStart();
  textReply(events, 'The session has one active branch and one alternative.');
  writeScenarioWithIndex('session-tree', 'Provides a branched session tree and entries with an active leaf.', ['session tree', 'branches'], { events: finish(events, 'The session has one active branch and one alternative.'), tree, leafId: 'main_answer', entries });
}
// 28. long-history
{
  const messages = [];
  for (let i = 0; i < 150; i++) {
    if (i % 3 === 0) messages.push({ role: 'user', content: [{ type: 'text', text: `Question ${i / 3 + 1}: inspect this small change.` }], timestamp: 1700000000000 + i * 1000 });
    else if (i % 3 === 1) messages.push({ role: 'assistant', content: [{ type: 'text', text: `I will inspect the relevant file for exchange ${Math.ceil(i / 3)}.` }, { type: 'toolCall', id: `history_call_${i}`, name: 'read', arguments: { path: 'notes.md' } }], timestamp: 1700000000000 + i * 1000 });
    else messages.push({ role: 'toolResult', toolCallId: `history_call_${i - 1}`, toolName: 'read', content: [{ type: 'text', text: `Notes excerpt ${Math.ceil(i / 3)}.` }], isError: false, timestamp: 1700000000000 + i * 1000 });
  }
  const events = promptStart();
  textReply(events, 'I have the earlier context and can continue.');
  writeScenarioWithIndex('long-history', 'Static snapshot contains 150 alternating user, assistant tool-call and tool-result messages.', ['long history', 'transcript scrolling', 'tool calls'], { events: finish(events, 'I have the earlier context and can continue.'), messages });
}
// 29. slash-commands
{
  const commands = [
    { name: 'help', description: 'Show practical guidance for the current workspace, including supported commands, common interaction patterns, offline behavior, and examples tailored to the topic supplied after the command.', source: 'prompt', sourceInfo: { name: 'help' }, argumentHint: '[topic]' },
    { name: 'review', description: 'Inspect the selected files or current changes for correctness, regressions, missing tests, and maintainability. Report actionable findings first, explain their impact, and include relevant file locations.', source: 'skill', sourceInfo: { name: 'review' }, argumentHint: '[files...]' },
    { name: 'offline-report', description: 'Create a local status report without network access. Include the active scenario, recent tool results, package state, and any checks that still need attention; choose summary for a compact report or full for details.', source: 'extension', sourceInfo: { name: 'fake-pi' }, argumentHint: '<summary|full>' }
  ];
  const events = promptStart();
  textReply(events, 'The command list is available.');
  writeScenarioWithIndex('slash-commands', 'Static command catalog spans prompt, skill and extension sources.', ['slash commands', 'command sources', 'argument hints'], { events: finish(events, 'The command list is available.'), commands });
}
// 30. steer-queue (~30 seconds)
{
  const events = [
    ...promptStart(),
    { event: { type: 'message_start', message: { role: 'assistant', content: [] } } },
    { event: { type: 'message_update', usage: { input: 100, output: 1, total: 101 }, assistantMessageEvent: { type: 'text_start', contentIndex: 0 } } }
  ];
  for (let i = 1; i <= 145; i++) {
    events.push({ delayMs: 200, event: { type: 'message_update', usage: { input: 100, output: i, total: 100 + i }, assistantMessageEvent: { type: 'text_delta', contentIndex: 0, delta: ` Streaming update ${i}/145.` } } });
  }
  events.push(
    { event: { type: 'message_end', message: { role: 'assistant', content: [{ type: 'text', text: 'The slow response completed after roughly thirty seconds.' }] } } }
  );
  writeScenarioWithIndex('steer-queue', 'Slow 30-second stream for steering, follow-up queue and abort checks.', ['steer queue', 'follow-up queue', 'abort', 'slow streaming'], { events: finish(events, 'The slow response completed after roughly thirty seconds.') });
}

fs.writeFileSync(path.join(scenariosDir, 'index.json'), JSON.stringify(scenarioIndex, null, 2), 'utf8');
console.log(`All ${scenarioIndex.length} fake-pi scenarios generated successfully.`);
