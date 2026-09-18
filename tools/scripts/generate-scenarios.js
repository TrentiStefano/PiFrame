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

console.log('All 12 fake-pi scenarios generated successfully.');
