const fs = require('fs');
const path = require('path');

const pcpFixturesDir = path.resolve(__dirname, '../../packages/pcp-spec/fixtures/pcp');
fs.mkdirSync(pcpFixturesDir, { recursive: true });

function writeFixture(filename, data) {
  fs.writeFileSync(path.join(pcpFixturesDir, filename), JSON.stringify(data, null, 2), 'utf8');
  console.log(`Wrote PCP fixture: ${filename}`);
}

// Hello
writeFixture('hello.valid.json', {
  protocol: 1,
  kind: 'hello',
  id: 'msg_01HZHELLO0000000000000001',
  ts: 1726640000000,
  type: 'connection.hello',
  payload: {
    token: 'dGhpcy1pcy1hLXRlc3QtdG9rZW4tMjU2LWJpdHM',
    client: { name: 'pi-frame', version: '0.1.0', platform: 'windows' },
    encoding: 'json',
    capabilities: ['replay.v1', 'ui.claim.v1', 'workspace.v1']
  }
});

writeFixture('hello.invalid.json', {
  protocol: 2, // invalid protocol
  kind: 'hello',
  id: 'msg_01HZHELLO0000000000000001',
  ts: 1726640000000,
  type: 'connection.hello',
  payload: {
    // missing token
    client: { name: 'pi-frame', version: '0.1.0', platform: 'windows' },
    encoding: 'json',
    capabilities: ['replay.v1']
  }
});

// Welcome
writeFixture('welcome.valid.json', {
  protocol: 1,
  kind: 'welcome',
  id: 'msg_01HZWELCOME0000000000001',
  ts: 1726640000050,
  type: 'connection.welcome',
  payload: {
    clientId: 'c_01HZCLIENT00000000000001',
    daemon: { version: '0.1.0', startedAt: 1726639000000, pid: 12345 },
    pi: { path: 'node .../cli.js', version: '0.85.1', supported: true },
    capabilities: ['replay.v1', 'ui.claim.v1', 'workspace.v1'],
    limits: { maxFrameBytes: 4194304, journalMaxEvents: 2000 }
  }
});

writeFixture('welcome.invalid.json', {
  protocol: 1,
  kind: 'welcome',
  id: 'msg_01HZWELCOME0000000000001',
  ts: 1726640000050,
  type: 'connection.welcome',
  payload: {
    // missing limits
    clientId: 'c_01HZCLIENT00000000000001',
    daemon: { version: '0.1.0', startedAt: 1726639000000, pid: 12345 },
    pi: { path: 'node .../cli.js', version: '0.85.1', supported: true },
    capabilities: ['replay.v1']
  }
});

// Command
writeFixture('command.valid.json', {
  protocol: 1,
  kind: 'command',
  id: 'msg_01HZCMD00000000000000001',
  ts: 1726640000100,
  commandId: 'cmd_01HZIDEMPOTENT000000001',
  sessionId: 's_01HZSESSION00000000000001',
  type: 'agent.prompt',
  payload: {
    message: 'Implement OAuth authentication',
    streamingBehavior: 'steer'
  }
});

writeFixture('command.invalid.json', {
  protocol: 1,
  kind: 'command',
  id: 'msg_01HZCMD00000000000000001',
  ts: 1726640000100,
  // missing commandId
  type: 'unsupported.command.type',
  payload: {}
});

// Ack
writeFixture('ack.valid.json', {
  protocol: 1,
  kind: 'ack',
  id: 'msg_01HZACK00000000000000001',
  ts: 1726640000105,
  commandId: 'cmd_01HZIDEMPOTENT000000001',
  sessionId: 's_01HZSESSION00000000000001',
  type: 'command.ack',
  payload: {
    state: 'accepted'
  }
});

writeFixture('ack.invalid.json', {
  protocol: 1,
  kind: 'ack',
  id: 'msg_01HZACK00000000000000001',
  ts: 1726640000105,
  commandId: 'cmd_01HZIDEMPOTENT000000001',
  type: 'command.ack',
  payload: {
    state: 'invalid_state' // not in enum
  }
});

// Result
writeFixture('result.valid.json', {
  protocol: 1,
  kind: 'result',
  id: 'msg_01HZRES00000000000000001',
  ts: 1726640000150,
  commandId: 'cmd_01HZIDEMPOTENT000000001',
  sessionId: 's_01HZSESSION00000000000001',
  type: 'command.result',
  payload: {
    state: 'completed',
    data: { success: true }
  }
});

writeFixture('result.invalid.json', {
  protocol: 1,
  kind: 'result',
  id: 'msg_01HZRES00000000000000001',
  ts: 1726640000150,
  commandId: 'cmd_01HZIDEMPOTENT000000001',
  type: 'command.result',
  payload: {} // missing state
});

// Event
writeFixture('event.valid.json', {
  protocol: 1,
  kind: 'event',
  id: 'msg_01HZEVT00000000000000001',
  ts: 1726640000200,
  sessionId: 's_01HZSESSION00000000000001',
  seq: 42,
  type: 'text.delta',
  payload: {
    contentIndex: 0,
    delta: 'Generating files...'
  }
});

writeFixture('event.invalid.json', {
  protocol: 1,
  kind: 'event',
  id: 'msg_01HZEVT00000000000000001',
  ts: 1726640000200,
  sessionId: 's_01HZSESSION00000000000001',
  // missing seq
  type: 'invalid.event.type',
  payload: {}
});

// Snapshot
writeFixture('snapshot.valid.json', {
  protocol: 1,
  kind: 'snapshot',
  id: 'msg_01HZSNA00000000000000001',
  ts: 1726640000300,
  sessionId: 's_01HZSESSION00000000000001',
  seq: 100,
  type: 'session.snapshot',
  payload: {
    session: {
      id: 's_01HZSESSION00000000000001',
      name: 'Refactor auth',
      cwd: 'C:/Personale/Repos/pi-frame',
      gitRoot: 'C:/Personale/Repos/pi-frame',
      sessionFile: 'session.jsonl',
      createdAt: 1726639000000,
      lastActivityAt: 1726640000000
    },
    runtime: {
      status: 'working',
      model: { id: 'gpt-5.6-luna', name: 'GPT-5.6 Luna' },
      thinkingLevel: 'low',
      steeringMode: 'one-at-a-time',
      followUpMode: 'one-at-a-time',
      isStreaming: true,
      isCompacting: false,
      autoCompaction: true,
      queue: { steering: [], followUp: [] }
    },
    transcript: {
      entries: [
        { id: 'e_1', type: 'user', text: 'Start' }
      ],
      leafId: 'e_1'
    },
    liveMessage: null,
    activeTools: [],
    pendingUiRequests: [],
    usage: { tokens: { total: 500 }, cost: 0.005 },
    workspace: { branch: 'main', dirty: false }
  }
});

writeFixture('snapshot.invalid.json', {
  protocol: 1,
  kind: 'snapshot',
  id: 'msg_01HZSNA00000000000000001',
  ts: 1726640000300,
  sessionId: 's_01HZSESSION00000000000001',
  seq: 100,
  type: 'session.snapshot',
  payload: {
    // missing session and transcript
    runtime: { isStreaming: false }
  }
});

// Error
writeFixture('error.valid.json', {
  protocol: 1,
  kind: 'error',
  id: 'msg_01HZERR00000000000000001',
  ts: 1726640000400,
  commandId: 'cmd_01HZIDEMPOTENT000000001',
  sessionId: 's_01HZSESSION00000000000001',
  type: 'error',
  payload: {
    code: 'PI_NOT_FOUND',
    message: 'Could not find pi executable in PATH',
    retryable: false,
    hint: 'Set path in Settings'
  }
});

writeFixture('error.invalid.json', {
  protocol: 1,
  kind: 'error',
  id: 'msg_01HZERR00000000000000001',
  ts: 1726640000400,
  type: 'error',
  payload: {
    code: 'NOT_A_VALID_CODE', // not in allowed enum
    message: 'Something went wrong'
  }
});

// Ping and Pong
writeFixture('ping.valid.json', {
  protocol: 1,
  kind: 'ping',
  id: 'msg_01HZPING0000000000000001',
  ts: 1726640000500,
  type: 'heartbeat.ping',
  payload: {}
});

writeFixture('pong.valid.json', {
  protocol: 1,
  kind: 'pong',
  id: 'msg_01HZPONG0000000000000001',
  ts: 1726640000510,
  type: 'heartbeat.pong',
  payload: {}
});

console.log('All PCP fixtures created successfully.');
