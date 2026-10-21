const fs = require('fs');
const path = require('path');

const fixtureDir = path.resolve(__dirname, '../../packages/pcp-spec/fixtures/pi');
fs.mkdirSync(fixtureDir, { recursive: true });

function writeFixture(filename, records) {
  const content = records.map(r => JSON.stringify(r)).join('\n') + '\n';
  fs.writeFileSync(path.join(fixtureDir, filename), content, 'utf8');
  console.log(`Wrote fixture: ${filename} (${records.length} records)`);
}

// 1. text-only.jsonl
writeFixture('text-only.jsonl', [
  { id: 'cmd_prompt_01', type: 'response', command: 'prompt', success: true },
  { type: 'agent_start' },
  { type: 'turn_start' },
  { type: 'message_start', message: { role: 'assistant', content: [] } },
  { type: 'message_update', usage: { input: 120, output: 5, total: 125 }, assistantMessageEvent: { type: 'text_start', contentIndex: 0 } },
  { type: 'message_update', usage: { input: 120, output: 10, total: 130 }, assistantMessageEvent: { type: 'text_delta', contentIndex: 0, delta: 'Hello, ' } },
  { type: 'message_update', usage: { input: 120, output: 18, total: 138 }, assistantMessageEvent: { type: 'text_delta', contentIndex: 0, delta: 'world! How can I help?' } },
  { type: 'message_update', usage: { input: 120, output: 25, total: 145 }, assistantMessageEvent: { type: 'text_end', contentIndex: 0, content: 'Hello, world! How can I help?' } },
  { type: 'message_end', message: { role: 'assistant', content: [{ type: 'text', text: 'Hello, world! How can I help?' }] } },
  { type: 'turn_end', message: { role: 'assistant', content: [{ type: 'text', text: 'Hello, world! How can I help?' }] }, toolResults: [] },
  { type: 'agent_end', messages: [{ role: 'assistant', content: [{ type: 'text', text: 'Hello, world! How can I help?' }] }], willRetry: false },
  { type: 'agent_settled' }
]);

// 2. with-thinking.jsonl
writeFixture('with-thinking.jsonl', [
  { id: 'cmd_prompt_02', type: 'response', command: 'prompt', success: true },
  { type: 'agent_start' },
  { type: 'turn_start' },
  { type: 'message_start', message: { role: 'assistant', content: [] } },
  { type: 'message_update', usage: { input: 150, output: 10, total: 160 }, assistantMessageEvent: { type: 'thinking_start', contentIndex: 0 } },
  { type: 'message_update', usage: { input: 150, output: 20, total: 170 }, assistantMessageEvent: { type: 'thinking_delta', contentIndex: 0, delta: 'The user wants an OAuth implementation analysis.' } },
  { type: 'message_update', usage: { input: 150, output: 35, total: 185 }, assistantMessageEvent: { type: 'thinking_end', contentIndex: 0, content: 'The user wants an OAuth implementation analysis.' } },
  { type: 'message_update', usage: { input: 150, output: 40, total: 190 }, assistantMessageEvent: { type: 'text_start', contentIndex: 1 } },
  { type: 'message_update', usage: { input: 150, output: 60, total: 210 }, assistantMessageEvent: { type: 'text_delta', contentIndex: 1, delta: 'Here is the OAuth architecture plan.' } },
  { type: 'message_update', usage: { input: 150, output: 70, total: 220 }, assistantMessageEvent: { type: 'text_end', contentIndex: 1, content: 'Here is the OAuth architecture plan.' } },
  { type: 'message_end', message: { role: 'assistant', content: [{ type: 'thinking', thinking: 'The user wants an OAuth implementation analysis.' }, { type: 'text', text: 'Here is the OAuth architecture plan.' }] } },
  { type: 'turn_end', message: { role: 'assistant', content: [] }, toolResults: [] },
  { type: 'agent_end', messages: [], willRetry: false },
  { type: 'agent_settled' }
]);

// 3. single-tool.jsonl
writeFixture('single-tool.jsonl', [
  { id: 'cmd_prompt_03', type: 'response', command: 'prompt', success: true },
  { type: 'agent_start' },
  { type: 'turn_start' },
  { type: 'message_start', message: { role: 'assistant', content: [] } },
  { type: 'message_update', usage: { input: 200, output: 15, total: 215 }, assistantMessageEvent: { type: 'toolcall_start', contentIndex: 0, id: 'call_read_01', toolName: 'read' } },
  { type: 'message_update', usage: { input: 200, output: 25, total: 225 }, assistantMessageEvent: { type: 'toolcall_delta', contentIndex: 0, delta: '{"path":"package.json"}' } },
  { type: 'message_update', usage: { input: 200, output: 35, total: 235 }, assistantMessageEvent: { type: 'toolcall_end', contentIndex: 0, toolCall: { id: 'call_read_01', name: 'read', args: { path: 'package.json' } } } },
  { type: 'message_end', message: { role: 'assistant', content: [{ type: 'tool_call', id: 'call_read_01', name: 'read', args: { path: 'package.json' } }] } },
  { type: 'tool_execution_start', toolCallId: 'call_read_01', toolName: 'read', args: { path: 'package.json' } },
  { type: 'tool_execution_update', toolCallId: 'call_read_01', toolName: 'read', args: { path: 'package.json' }, partialResult: '{\n  "name": "pi-frame",\n' },
  { type: 'tool_execution_end', toolCallId: 'call_read_01', toolName: 'read', result: '{\n  "name": "pi-frame",\n  "version": "0.1.0"\n}\n', isError: false },
  { type: 'turn_end', message: { role: 'assistant', content: [] }, toolResults: [{ role: 'toolResult', toolCallId: 'call_read_01', result: '{\n  "name": "pi-frame",\n  "version": "0.1.0"\n}\n' }] },
  { type: 'turn_start' },
  { type: 'message_start', message: { role: 'assistant', content: [] } },
  { type: 'message_update', usage: { input: 280, output: 10, total: 290 }, assistantMessageEvent: { type: 'text_start', contentIndex: 0 } },
  { type: 'message_update', usage: { input: 280, output: 20, total: 300 }, assistantMessageEvent: { type: 'text_delta', contentIndex: 0, delta: 'The package name is pi-frame.' } },
  { type: 'message_update', usage: { input: 280, output: 25, total: 305 }, assistantMessageEvent: { type: 'text_end', contentIndex: 0, content: 'The package name is pi-frame.' } },
  { type: 'message_end', message: { role: 'assistant', content: [{ type: 'text', text: 'The package name is pi-frame.' }] } },
  { type: 'turn_end', message: { role: 'assistant', content: [] }, toolResults: [] },
  { type: 'agent_end', messages: [], willRetry: false },
  { type: 'agent_settled' }
]);

// 4. parallel-tools.jsonl
writeFixture('parallel-tools.jsonl', [
  { id: 'cmd_prompt_04', type: 'response', command: 'prompt', success: true },
  { type: 'agent_start' },
  { type: 'turn_start' },
  { type: 'message_start', message: { role: 'assistant', content: [] } },
  { type: 'message_update', usage: { input: 300, output: 20, total: 320 }, assistantMessageEvent: { type: 'toolcall_start', contentIndex: 0, id: 'call_p1', toolName: 'read' } },
  { type: 'message_update', usage: { input: 300, output: 30, total: 330 }, assistantMessageEvent: { type: 'toolcall_end', contentIndex: 0, toolCall: { id: 'call_p1', name: 'read', args: { path: 'a.txt' } } } },
  { type: 'message_update', usage: { input: 300, output: 45, total: 345 }, assistantMessageEvent: { type: 'toolcall_start', contentIndex: 1, id: 'call_p2', toolName: 'read' } },
  { type: 'message_update', usage: { input: 300, output: 55, total: 355 }, assistantMessageEvent: { type: 'toolcall_end', contentIndex: 1, toolCall: { id: 'call_p2', name: 'read', args: { path: 'b.txt' } } } },
  { type: 'message_end', message: { role: 'assistant', content: [{ type: 'tool_call', id: 'call_p1', name: 'read', args: { path: 'a.txt' } }, { type: 'tool_call', id: 'call_p2', name: 'read', args: { path: 'b.txt' } }] } },
  { type: 'tool_execution_start', toolCallId: 'call_p1', toolName: 'read', args: { path: 'a.txt' } },
  { type: 'tool_execution_start', toolCallId: 'call_p2', toolName: 'read', args: { path: 'b.txt' } },
  { type: 'tool_execution_end', toolCallId: 'call_p1', toolName: 'read', result: 'Content A', isError: false },
  { type: 'tool_execution_end', toolCallId: 'call_p2', toolName: 'read', result: 'Content B', isError: false },
  { type: 'turn_end', message: { role: 'assistant', content: [] }, toolResults: [] },
  { type: 'agent_end', messages: [], willRetry: false },
  { type: 'agent_settled' }
]);

// 5. bash-output.jsonl
writeFixture('bash-output.jsonl', [
  { id: 'cmd_bash_01', type: 'response', command: 'bash', success: true },
  { type: 'bash_execution_update', commandId: 'cmd_bash_01', output: 'Step 1/3: Installing packages...\n' },
  { type: 'bash_execution_update', commandId: 'cmd_bash_01', output: 'Step 2/3: Compiling...\n' },
  { type: 'bash_execution_update', commandId: 'cmd_bash_01', output: 'Step 3/3: Done in 1.42s.\n' }
]);

// 6. abort-mid-stream.jsonl
writeFixture('abort-mid-stream.jsonl', [
  { id: 'cmd_prompt_06', type: 'response', command: 'prompt', success: true },
  { type: 'agent_start' },
  { type: 'turn_start' },
  { type: 'message_start', message: { role: 'assistant', content: [] } },
  { type: 'message_update', usage: { input: 100, output: 5, total: 105 }, assistantMessageEvent: { type: 'text_start', contentIndex: 0 } },
  { type: 'message_update', usage: { input: 100, output: 15, total: 115 }, assistantMessageEvent: { type: 'text_delta', contentIndex: 0, delta: 'Generating large report...' } },
  { id: 'cmd_abort_01', type: 'response', command: 'abort', success: true },
  { type: 'agent_end', messages: [], willRetry: false },
  { type: 'agent_settled' }
]);

// 7. clear-queue.jsonl
writeFixture('clear-queue.jsonl', [
  { type: 'queue_update', steering: ['Please focus on OAuth PKCE only'], followUp: ['Also write unit tests', 'Document the endpoints'] },
  { id: 'cmd_clear_01', type: 'response', command: 'clear_queue', success: true, data: { steering: ['Please focus on OAuth PKCE only'], followUp: ['Also write unit tests', 'Document the endpoints'] } },
  { type: 'queue_update', steering: [], followUp: [] }
]);

// 8. compaction.jsonl
writeFixture('compaction.jsonl', [
  { id: 'cmd_compact_01', type: 'response', command: 'compact', success: true, data: { tokensBefore: 85000, tokensAfter: 12500, cost: 0.12 } },
  { type: 'compaction_start', reason: 'manual' },
  { type: 'compaction_end', result: { tokensBefore: 85000, tokensAfter: 12500, cost: 0.12 }, aborted: false, willRetry: false }
]);

// 9. extension-ui-dialogs.jsonl
writeFixture('extension-ui-dialogs.jsonl', [
  { type: 'extension_ui_request', id: 'req_conf_01', method: 'confirm', title: 'Confirm deployment', message: 'Do you want to deploy to production?', timeout: 30000 },
  { type: 'extension_ui_request', id: 'req_sel_01', method: 'select', title: 'Pick environment', options: ['staging', 'production', 'local'] },
  { type: 'extension_ui_request', id: 'req_inp_01', method: 'input', title: 'API Key name', placeholder: 'my-key' },
  { type: 'extension_ui_request', id: 'req_ed_01', method: 'editor', title: 'Edit commit note', prefill: 'Initial release note' },
  { type: 'extension_ui_request', id: 'req_not_01', method: 'notify', message: 'Build finished successfully', notifyType: 'info' },
  { type: 'extension_ui_request', id: 'req_stat_01', method: 'setStatus', statusKey: 'pipeline', statusText: 'Healthy' },
  { type: 'extension_ui_request', id: 'req_wid_01', method: 'setWidget', widgetKey: 'metrics', widgetLines: ['CPU: 12%', 'RAM: 240MB'] }
]);

// 10. provider-retry.jsonl
writeFixture('provider-retry.jsonl', [
  { id: 'cmd_prompt_10', type: 'response', command: 'prompt', success: true },
  { type: 'agent_start' },
  { type: 'auto_retry_start', attempt: 1, maxAttempts: 3, delayMs: 1500, errorMessage: 'HTTP 429 Too Many Requests' },
  { type: 'auto_retry_end', success: true, attempt: 1 },
  { type: 'turn_start' },
  { type: 'message_start', message: { role: 'assistant', content: [] } },
  { type: 'message_update', usage: { input: 110, output: 5, total: 115 }, assistantMessageEvent: { type: 'text_start', contentIndex: 0 } },
  { type: 'message_update', usage: { input: 110, output: 12, total: 122 }, assistantMessageEvent: { type: 'text_delta', contentIndex: 0, delta: 'Recovered after retry.' } },
  { type: 'message_update', usage: { input: 110, output: 15, total: 125 }, assistantMessageEvent: { type: 'text_end', contentIndex: 0, content: 'Recovered after retry.' } },
  { type: 'message_end', message: { role: 'assistant', content: [{ type: 'text', text: 'Recovered after retry.' }] } },
  { type: 'turn_end', message: { role: 'assistant', content: [] }, toolResults: [] },
  { type: 'agent_end', messages: [], willRetry: false },
  { type: 'agent_settled' }
]);

// 11. get-state.jsonl
writeFixture('get-state.jsonl', [
  { id: 'cmd_state_01', type: 'response', command: 'get_state', success: true, data: {
    model: { id: 'gpt-5.6-luna', name: 'GPT-5.6 Luna', provider: 'github-copilot', reasoning: true, contextWindow: 1050000 },
    thinkingLevel: 'high',
    isStreaming: false,
    isCompacting: false,
    steeringMode: 'one-at-a-time',
    followUpMode: 'one-at-a-time',
    sessionId: '01a0b348-dfdf-770d-ad68-b5cd8054300f',
    autoCompactionEnabled: true,
    messageCount: 4,
    pendingMessageCount: 0
  }}
]);

// 12. get-entries.jsonl
writeFixture('get-entries.jsonl', [
  { id: 'cmd_entries_01', type: 'response', command: 'get_entries', success: true, data: {
    entries: [
      { id: 'e_01', parentId: null, type: 'user', message: { role: 'user', content: 'Init repo' }, ts: 1726640000000 },
      { id: 'e_02', parentId: 'e_01', type: 'assistant', message: { role: 'assistant', content: [{ type: 'text', text: 'Repo initialized' }] }, ts: 1726640005000 }
    ],
    leafId: 'e_02'
  }}
]);

// 13. get-tree.jsonl
writeFixture('get-tree.jsonl', [
  { id: 'cmd_tree_01', type: 'response', command: 'get_tree', success: true, data: {
    tree: [
      { id: 'e_01', parentId: null, children: ['e_02'] },
      { id: 'e_02', parentId: 'e_01', children: [] }
    ],
    leafId: 'e_02'
  }}
]);

// 14. get-commands.jsonl
writeFixture('get-commands.jsonl', [
  { id: 'cmd_commands_01', type: 'response', command: 'get_commands', success: true, data: {
    commands: [
      { name: 'help', description: 'Show help message', source: 'prompt', sourceInfo: { name: 'help', path: '/builtin/help' } },
      { name: 'review', description: 'Review changes in workspace', source: 'skill', sourceInfo: { name: 'review', path: '/skills/review' } },
      { name: 'subagent', description: 'Delegate to background subagent', source: 'extension', sourceInfo: { name: 'subagent', path: '/extensions/subagent' } }
    ]
  }}
]);
