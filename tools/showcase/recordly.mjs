// Minimal Chrome DevTools Protocol bridge to a Recordly instance started with
// `Recordly.exe --remote-debugging-port=9333`.
//
//   node recordly.mjs targets
//   node recordly.mjs eval <hud|editor|url-substring> "<js expression>"
//   node recordly.mjs select-window "<title substring>"
//   node recordly.mjs start | stop
//
// Every command evaluates JS inside Recordly's own renderer, so recordings go
// through Recordly's real pipeline (WGC capture, cursor telemetry, editor).
const PORT = process.env.RECORDLY_CDP_PORT || 9333;

async function targets() {
  const r = await fetch(`http://127.0.0.1:${PORT}/json/list`);
  return (await r.json()).filter((t) => t.type === 'page');
}

async function pick(which) {
  const list = await targets();
  const match = (t) =>
    which === 'hud' ? t.url.includes('windowType=hud-overlay')
      : which === 'editor' ? t.url.includes('windowType=editor')
        : t.url.includes(which) || t.title.includes(which);
  const t = list.find(match);
  if (!t) throw new Error(`no target for ${which}: ${list.map((x) => x.url).join(' | ')}`);
  return t;
}

export async function evaluate(which, expression, { awaitPromise = true } = {}) {
  const t = await pick(which);
  const ws = new WebSocket(t.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  const id = 1;
  const result = await new Promise((res, rej) => {
    ws.onmessage = (ev) => {
      const msg = JSON.parse(ev.data);
      if (msg.id === id) res(msg);
    };
    ws.send(JSON.stringify({
      id, method: 'Runtime.evaluate',
      params: { expression, awaitPromise, returnByValue: true, userGesture: true },
    }));
    setTimeout(() => rej(new Error('timeout')), 120000);
  });
  ws.close();
  if (result.result?.exceptionDetails) {
    throw new Error(JSON.stringify(result.result.exceptionDetails).slice(0, 800));
  }
  return result.result?.result?.value;
}

const SELECT_WINDOW = (title) => `(async () => {
  const sources = await window.electronAPI.getSources({ types: ['window'], thumbnailSize: { width: 0, height: 0 }, fetchWindowIcons: false });
  const src = sources.find((s) => (s.name || '').includes(${JSON.stringify(title)}));
  if (!src) return { ok: false, names: sources.map((s) => s.name) };
  await window.electronAPI.selectSource(src);
  return { ok: true, src: { id: src.id, name: src.name } };
})()`;

const SELECT_SCREEN = `(async () => {
  const sources = await window.electronAPI.getSources({ types: ['screen'], thumbnailSize: { width: 0, height: 0 }, fetchWindowIcons: false });
  const src = sources[0];
  if (!src) return { ok: false };
  await window.electronAPI.selectSource(src);
  return { ok: true, src: { id: src.id, name: src.name } };
})()`;

const CLICK_REC = `(() => {
  const btn = [...document.querySelectorAll('button')].find((b) => /record/i.test(b.title || '') || b.querySelector('[class*=recDot]'));
  if (!btn) return 'no-rec-button';
  btn.click();
  return 'clicked';
})()`;

const CLICK_STOP = `(() => {
  const btn = [...document.querySelectorAll('button')].find((b) => /^stop$/i.test(b.getAttribute('aria-label') || ''));
  if (!btn) return 'no-stop-button';
  btn.click();
  return 'clicked';
})()`;

async function main() {
  const [cmd, a, b] = process.argv.slice(2);
  let out;
  switch (cmd) {
    case 'targets': out = (await targets()).map((t) => `${t.title} :: ${t.url}`); break;
    case 'eval': out = await evaluate(a, b); break;
    case 'select-window': out = await evaluate('hud', SELECT_WINDOW(a)); break;
    case 'select-screen': out = await evaluate('hud', SELECT_SCREEN); break;
    case 'start': out = await evaluate('hud', CLICK_REC); break;
    case 'stop': out = await evaluate('hud', CLICK_STOP); break;
    default: throw new Error(`unknown command ${cmd}`);
  }
  console.log(typeof out === 'string' ? out : JSON.stringify(out, null, 2));
  process.exit(0);
}

if (import.meta.url === `file:///${process.argv[1].replace(/\\/g, '/')}`) {
  main().catch((e) => { console.error(e.message); process.exit(1); });
}
