const fs = require('fs');
const path = require('path');

const adrDir = path.resolve(__dirname, '../../docs/adr');
fs.mkdirSync(adrDir, { recursive: true });

const adrs = [
  {
    num: '0001',
    slug: 'daemon-runtime',
    title: 'Daemon Runtime: Node.js 22 LTS',
    section10Ref: null,
    context: 'Pi-coding-agent is implemented in TypeScript/Node.js. The daemon must manage subprocesses, JSONL stdio framing, WebSockets, filesystem watchers, and Git inspection.',
    decision: 'Use Node.js 22+ LTS for pi-agentd.',
    consequences: 'Enables direct compatibility with Node ecosystem (ws, chokidar), mature subprocess/stdio APIs, and single-file executable packaging via Node SEA. Slightly slower startup than Bun, but completely stable.',
    alternatives: 'Bun (less predictable subprocess stdio edge cases and rapid breaking change cadence); Rust (overkill for MVP, losing direct TS type alignment with Pi).'
  },
  {
    num: '0002',
    slug: 'websocket-transport',
    title: 'WebSocket Transport: ws + node:http',
    section10Ref: null,
    context: 'The daemon needs a robust loopback communication channel for Flutter Desktop and Web clients, while serving static Flutter Web assets.',
    decision: 'Use ws library integrated with standard node:http.',
    consequences: 'Full control over connection handshake, Origin headers, upgrade requests, custom close codes, and backpressure. Same HTTP server serves Flutter Web assets.',
    alternatives: 'socket.io (proprietary protocol framing, unofficial Dart client); uWebSockets.js (native build dependencies with negligible loopback performance benefit).'
  },
  {
    num: '0003',
    slug: 'protocol-source-of-truth',
    title: 'Protocol Source of Truth: JSON Schema in packages/pcp-spec',
    section10Ref: null,
    context: 'Both TypeScript (daemon) and Dart (Flutter) must maintain synchronized types and wire validation without silent drift.',
    decision: 'Define normative protocol schemas in packages/pcp-spec/*.schema.json with automated codegen to TS and Dart.',
    consequences: 'Single source of truth. Shared test fixtures validate both implementations identically. Codegen-drift CI check ensures zero divergence.',
    alternatives: 'Hand-written types on both sides (guaranteed eventual drift); Protobuf/CBOR (premature binary optimization making debugging harder).'
  },
  {
    num: '0004',
    slug: 'flutter-state-management',
    title: 'Flutter State Management: Riverpod 2 (code-gen off)',
    section10Ref: null,
    context: 'The Flutter GUI manages multi-session streams, live agent delta updates, connection state machines, and local UI preferences across 3 layout columns.',
    decision: 'Use Flutter Riverpod 2 without code generation.',
    consequences: 'Clean separation between presentation state, live runtime state, and authoritative Pi session state. Supports scoped session providers and easy headless testing.',
    alternatives: 'BLoC (excessively verbose for high-frequency text delta streams); signals/setState (insufficient multi-session fanout and lifecycle scoping).'
  },
  {
    num: '0005',
    slug: 'normalized-pcp-events',
    title: 'Daemon Exposes Normalized Events, Not Raw Pi JSONL',
    section10Ref: null,
    context: 'Directly forwarding Pi JSONL couples Flutter UI to internal changes of Pi, violating isolation requirements.',
    decision: 'The daemon normalizes all Pi events into stable Pi-Crust Protocol (PCP/1) events via PiEventAdapter.',
    consequences: 'Insulates UI from Pi upstream changes. An optional debug capability (debug.raw-pi-events) allows inspection when needed. Adapter covered by golden test fixtures.',
    alternatives: 'Pure passthrough (tightly couples Flutter to specific Pi versions).'
  },
  {
    num: '0006',
    slug: 'event-journal-and-spill',
    title: 'Journal: Ring Buffer in Memory + Disk Spill per Session',
    section10Ref: null,
    context: 'Replay must survive GUI disconnects and transient daemon restarts without turning into a secondary authoritative transcript database.',
    decision: 'Implement an in-memory ring buffer with append-only disk spill under ~/.pi-crust/journal/<sessionId>/ and periodic snapshots.',
    consequences: 'Zero data loss during UI disconnects. Bounded resource usage with guaranteed monotonic sequence numbering.',
    alternatives: 'SQLite (heavyweight for bounded append-only stream); Memory-only (loses replay on daemon restart).'
  },
  {
    num: '0007',
    slug: 'journal-retention-policy',
    title: 'Journal Retention: max(2,000 events, 8 MB) with Snapshot Every 500 Events',
    section10Ref: 2,
    context: 'Memory and disk space must be bounded while providing seamless reconnection for long-running sessions.',
    decision: 'Retain up to 2,000 events or 8 MB per session, snapshot every 500 events, and preserve spill files for 24 hours.',
    consequences: 'Exceeding the window smoothly degrades to sending a full authoritative snapshot, which is always correct.',
    alternatives: 'Unbounded retention (uncontrolled memory/disk growth); Very small window (frequent full-snapshot resyncs).'
  },
  {
    num: '0008',
    slug: 'daemon-lifecycle-on-demand',
    title: 'Daemon Lifecycle: On-Demand Detached Process with Single-Instance Lock',
    section10Ref: 1,
    context: 'Users do not want an intrusive permanent OS background service installed without explicit necessity.',
    decision: 'The daemon is not a permanent OS service. It is spawned on-demand detached by the GUI if the GET /api/health probe fails.',
    consequences: 'Safe, unobtrusive lifecycle with lockfile PID verification. The agent continues working in background when GUI is closed.',
    alternatives: 'Always-running system service (invasive, requires root/admin privilege and difficult uninstall).'
  },
  {
    num: '0009',
    slug: 'worker-idle-timeout',
    title: 'Worker Idle Timeout: 30 Minutes Default, User Configurable',
    section10Ref: 4,
    context: 'Multiple idle Pi processes consume memory, but work in progress must never be interrupted.',
    decision: 'Default 30-minute idle worker shutdown (0 = never), configurable via daemon.setConfig and GUI Settings. Workers in active/working/awaiting_user states are never killed.',
    consequences: 'Prevents phantom processes while safeguarding active generation. Immediate timer updates across all connected GUIs via daemon.configChanged.',
    alternatives: 'No idle timeout (process leaks); Aggressive timeout (kills inactive sessions too quickly).'
  },
  {
    num: '0010',
    slug: 'multi-client-concurrency',
    title: 'Multi-Client: Broadcast Events, Exclusive Claim for UI Requests',
    section10Ref: 9,
    context: 'Multiple GUI windows or browser tabs may attach to the same session, but interactive dialogs (confirm, select, input, editor) require a single decision maker.',
    decision: 'Broadcast all session events to all attached clients. Enforce exclusive 30s renewable claim lease for interactive extension UI dialogs.',
    consequences: 'First client to claim responds; other clients observe read-only indicator. Zero duplicate responses.',
    alternatives: 'Single-client restriction (blocks desktop + web coexistence); Free-for-all responses (race conditions).'
  },
  {
    num: '0011',
    slug: 'authentication-and-tokens',
    title: 'Authentication: 256-Bit Token in ~/.pi-crust/runtime/daemon.token + Web Bootstrap Cookie',
    section10Ref: 6,
    context: 'The daemon executes agent commands on loopback. Web browsers cannot set custom headers during WebSocket handshake and query strings leak into logs.',
    decision: 'Generate a random 256-bit token on daemon startup in daemon.token (chmod 600). Transmit in PCP hello frame. Web client uses HttpOnly SameSite=Strict cookie via GET /api/session-bootstrap.',
    consequences: 'Robust loopback security. No token leakage in URLs or logs. Seamless zero-configuration browser access on localhost.',
    alternatives: 'Token in query string (log/referrer leakage); No authentication (arbitrary code execution risk).'
  },
  {
    num: '0012',
    slug: 'text-json-serialization',
    title: 'Serialization: Textual JSON in PCP/1',
    section10Ref: null,
    context: 'Protocol messages must be easy to debug, inspect, and consume across Node and Flutter Web/Desktop.',
    decision: 'PCP/1 uses strict JSON text frames. The encoding field in handshake allows future CBOR/MessagePack extensions if needed.',
    consequences: 'Standard JSON debugging, native browser support, simple tooling, zero binary compilation friction in MVP.',
    alternatives: 'Protobuf / MessagePack upfront (premature optimization for loopback IPC).'
  },
  {
    num: '0013',
    slug: 'local-web-hosting',
    title: 'Local Web Hosting: Served by Daemon with Separated Path Namespace',
    section10Ref: null,
    context: 'Users should be able to open http://127.0.0.1:<port>/ in their browser without running a separate web server.',
    decision: 'The daemon HTTP server serves static Flutter Web assets on GET /, API endpoints on /api/*, and WebSocket on /api/ws.',
    consequences: 'Zero-setup web experience. Clean URL namespace allows future remote deployment of static assets.',
    alternatives: 'Separate static web server process (unnecessary operational overhead).'
  },
  {
    num: '0014',
    slug: 'daemon-distribution-sidecar',
    title: 'Distribution: Daemon as Sidecar Binary (Node SEA) Inside App Bundle',
    section10Ref: 3,
    context: 'Users installing Pi-Crust must not be forced to manually install or manage Node.js.',
    decision: 'Bundle daemon with esbuild and package as single-file Node Single Executable Application (SEA) bundled inside the Flutter app.',
    consequences: 'Self-contained distribution. Pi remains independent. Uninstalling Pi-Crust removes app and daemon without touching ~/.pi/.',
    alternatives: 'Requiring user to pre-install Node 22 (poor desktop app onboarding experience).'
  },
  {
    num: '0015',
    slug: 'minimum-supported-pi-version',
    title: 'Minimum Supported Pi Version: v0.85.0',
    section10Ref: 5,
    context: 'Pi-Crust requires the modern Pi RPC interface, including session trees, assistantMessageEvent framing, and extension UI capabilities.',
    decision: 'Enforce v0.85.0 as the minimum supported Pi version, verified via semver probe on startup.',
    consequences: 'Daemon enters degraded state with actionable upgrade instructions if Pi < v0.85.0 or missing.',
    alternatives: 'Supporting legacy Pi versions (requires fragile polyfills and breaks protocol consistency).'
  },
  {
    num: '0016',
    slug: 'zero-remote-telemetry',
    title: 'Telemetry: Zero Remote Data Collection (Local Only, No Opt-in)',
    section10Ref: 7,
    context: 'User privacy and data sovereignty are top priorities. No telemetry, usage statistics, or crash reports should ever leave the user machine.',
    decision: 'Zero remote telemetry in any form, not even opt-in. Logging is purely local with manual exportable diagnostic bundles.',
    consequences: 'Complete privacy. No third-party tracking libraries or analytics dependencies permitted in codebase.',
    alternatives: 'Opt-in telemetry (creates privacy attack surface and maintenance burden; rejected by stakeholder).'
  },
  {
    num: '0017',
    slug: 'bundled-typography',
    title: 'Bundled Fonts: Inter (UI) + JetBrains Mono (Code)',
    section10Ref: 8,
    context: 'Visual typography must be identical and high-quality across Windows, macOS, and Web regardless of installed system fonts.',
    decision: 'Bundle open-source Inter (SIL OFL) for UI and JetBrains Mono (SIL OFL) for code within the app assets.',
    consequences: 'Consistent modern aesthetic across all platforms. JSON themes can override font families with graceful fallback.',
    alternatives: 'System fonts (inconsistent rendering across platforms).'
  }
];

for (const adr of adrs) {
  const filename = `${adr.num}-${adr.slug}.md`;
  const content = `# ADR ${adr.num}: ${adr.title}

- **Status:** Accepted
- **Confirmation Date:** 2026-09-18
${adr.section10Ref ? `- **Stakeholder Decision Reference:** Implementation Plan §10, Item #${adr.section10Ref}\n` : ''}

## Context

${adr.context}

## Decision

${adr.decision}

## Consequences

${adr.consequences}

## Alternatives Rejected

${adr.alternatives}
`;

  fs.writeFileSync(path.join(adrDir, filename), content, 'utf8');
  console.log(`Wrote ADR: ${filename}`);
}

console.log(`Successfully generated ${adrs.length} ADRs in docs/adr/`);
