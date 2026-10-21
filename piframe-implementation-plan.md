# PiFrame — Implementation Plan

> GUI Flutter (Windows / macOS / Web) per `pi-coding-agent`, ispirata a OpenAI Codex e GitHub Copilot app.
> Documento operativo destinato a uno o più **coding agent implementatori**.
>
> Versione piano: `1.1` — aggiornato con le decisioni del committente del 18 settembre 2026 (vedi §10).
> Basato su: `pi_gui_implementation_planning_brief.md`
> Verifica upstream effettuata su: `earendil-works/pi` → `packages/coding-agent/docs/rpc.md` (branch `main`) e `pi.dev/docs/latest/session-format`.

---

## 0. Come usare questo documento

**Regole per l'agente implementatore:**

1. Gli step vanno eseguiti **in ordine**. Ogni step dichiara i propri prerequisiti: non iniziare uno step se i suoi prerequisiti non hanno passato gli acceptance criteria.
2. Lo **Step 0.1 è bloccante**: nessun contratto va congelato prima di aver verificato la superficie RPC contro la versione di Pi effettivamente installata sulla macchina di sviluppo. Le informazioni RPC in questo documento sono verificate su `main` alla data di stesura, ma **vanno riconfermate** e registrate in `docs/pi-compatibility.md`.
3. **Le interfacce si definiscono prima delle implementazioni.** Ogni step di tipo "contract" produce file di tipi/schema + fixture, mai logica.
4. Dove il documento dice *"Decisione"*, la scelta è già presa: implementala. Dove dice *"Decisione aperta"*, fermati, scrivi un ADR in `docs/adr/` e chiedi conferma prima di procedere.
5. Ogni step produce codice **e** test. Uno step senza test verdi non è completo.
6. Non introdurre dipendenze non elencate senza registrarle in un ADR.
7. **Non modificare mai `~/.pi/`**. Pi è un componente indipendente e la GUI ne è solo un client.

---

## 1. Architecture summary

### 1.1 Topologia

```text
┌───────────────────────────────────────────────────────────────┐
│  PiFrame (Flutter)                                           │
│  Windows · macOS · Web                                        │
│  ── presentation + session projection + commands              │
└──────────────────────────┬────────────────────────────────────┘
                           │  PCP/1  (PiFrame Protocol, JSON su WebSocket)
                           │  127.0.0.1 · bearer token · origin check
                           ▼
┌───────────────────────────────────────────────────────────────┐
│  pi-agentd  (TypeScript / Node.js, processo persistente)      │
│                                                               │
│  ConnectionManager   SessionRegistry    EventJournal          │
│  CommandDispatcher   WorkspaceService   UiRequestBroker       │
│  PiDiscovery         WorkerSupervisor   SnapshotBuilder       │
│                          │                                    │
│                          ▼  PiTransport (interfaccia)         │
│                     StdioPiTransport                          │
└──────────────────────────┬────────────────────────────────────┘
                           │  JSONL strict LF su stdin/stdout
              ┌────────────┼────────────┬────────────┐
              ▼            ▼            ▼            ▼
        pi --mode rpc  pi --mode rpc  pi --mode rpc  …
         (session A)    (session B)    (session C)
              │
              ▼
        ~/.pi/agent/sessions/--<path>--/<ts>_<uuid>.jsonl
        (source of truth della cronologia — di proprietà di Pi)
```

### 1.2 Chi conosce cosa

| Componente | Conosce | NON conosce |
|---|---|---|
| **Flutter (PiFrame)** | UX, projection di sessione, comandi PCP, eventi PCP, theming | processi, stdio, JSONL di Pi, path di sessione, git plumbing |
| **pi-agentd** | lifecycle processi, Pi RPC, registry sessioni, journal/replay, workspace, git, auth | widget, layout, temi, scroll, stato UI |
| **Pi** | agent runtime, modelli, tool, extension, persistenza sessione | l'esistenza di PiFrame |

### 1.3 Flussi principali

**Prompt:**
`Flutter → command(PCP) → CommandDispatcher (dedup + validate) → SessionWorker → stdin JSONL → Pi → stdout JSONL → PiEventAdapter (normalizza) → EventJournal (assegna seq) → broadcast WS → reducer Dart → UI`

**Chiusura GUI durante il lavoro:**
`WS close → client detach → worker resta vivo → Pi continua → gli eventi continuano a essere consumati e journalizzati`

**Riapertura GUI:**
`WS open → hello/auth → welcome → session.list → session.attach{lastSeq} → (resume: eventi lastSeq+1…) oppure (snapshot + eventi) → live`

### 1.4 Tre livelli di stato — non confonderli mai

| Livello | Proprietario | Persistenza | Esempi |
|---|---|---|---|
| **Persisted authoritative** | Pi | `~/.pi/agent/sessions/**.jsonl` (tree v3) | entries, messaggi, branch, fork |
| **Live runtime** | pi-agentd | memoria + journal a breve termine | status agente, delta in volo, queue, tool attivi, pending UI request, seq |
| **Presentation** | Flutter | memoria + preferenze locali | scroll, pannelli aperti, bozza composer, tema selezionato |

---

## 2. Repository structure

```text
pi-frame/
├── apps/
│   ├── pi_frame/                     # App Flutter (Windows, macOS, Web)
│   │   ├── lib/
│   │   │   ├── main.dart
│   │   │   ├── app/                  # bootstrap, router, DI, shell
│   │   │   ├── core/                 # logging, errori, utils, platform
│   │   │   ├── data/
│   │   │   │   ├── daemon/           # PcpClient, reconnect, auth, discovery
│   │   │   │   └── settings/         # persistenza preferenze locali
│   │   │   ├── domain/
│   │   │   │   ├── session/          # SessionState, reducer, statusi
│   │   │   │   ├── workspace/        # file changed, git
│   │   │   │   └── ui_request/       # extension UI
│   │   │   ├── features/
│   │   │   │   ├── sessions_sidebar/
│   │   │   │   ├── transcript/
│   │   │   │   ├── composer/
│   │   │   │   ├── tool_timeline/
│   │   │   │   ├── context_panel/
│   │   │   │   ├── dialogs/
│   │   │   │   ├── command_palette/
│   │   │   │   └── settings/
│   │   │   └── ui/                   # widget riusabili, design system
│   │   ├── assets/themes/            # temi JSON bundlati
│   │   └── test/ , integration_test/
│   └── agentd/                       # Daemon TypeScript
│       ├── src/
│       │   ├── main.ts               # entrypoint, CLI, single-instance lock
│       │   ├── config/               # config, runtime dir, token
│       │   ├── server/               # http + ws, handshake, auth, static web
│       │   ├── protocol/             # encode/decode PCP, validazione
│       │   ├── sessions/             # registry, worker supervisor, index
│       │   ├── pi/                   # PiTransport, StdioPiTransport, discovery,
│       │   │                         #   jsonl framing, event adapter, capabilities
│       │   ├── journal/              # ring buffer, spill, snapshot, replay
│       │   ├── commands/             # dispatcher, idempotency, mapping PCP→Pi
│       │   ├── ui/                   # UiRequestBroker (claim/lease)
│       │   ├── workspace/            # watcher, git status/diff
│       │   └── telemetry/            # logging strutturato, metriche LOCALI (D16: zero invio remoto)
│       └── test/
├── packages/
│   ├── pcp-spec/                     # SOURCE OF TRUTH del protocollo
│   │   ├── spec.md
│   │   ├── schema/*.schema.json
│   │   └── fixtures/                 # messaggi golden condivisi TS↔Dart
│   ├── pcp-ts/                       # tipi + validator TS generati da schema
│   ├── pi_frame_protocol/            # package Dart: tipi + codec generati
│   └── pi_frame_theme/               # package Dart: theme engine JSON
├── themes/                           # temi JSON ufficiali (sorgente)
│   ├── piframe-dark.json
│   ├── piframe-light.json
│   └── theme.schema.json
├── tools/
│   ├── codegen/                      # schema → TS + Dart
│   ├── fake-pi/                      # finto `pi --mode rpc` scriptabile (test)
│   └── fault-proxy/                  # proxy WS per fault injection
├── test/e2e/                         # scenari cross-componente
└── docs/
    ├── adr/
    ├── pi-compatibility.md
    ├── protocol.md
    └── theming.md
```

---

## 3. Decisioni architetturali

Formato: **Decisione · Motivo · Trade-off · Alternative scartate**. Ogni voce va copiata in `docs/adr/NNNN-*.md` allo Step 0.3.

### D1 — Runtime del daemon: **Node.js 22 LTS**
- **Motivo:** Pi è TypeScript/Node; ecosistema `ws`/`chokidar`/`zod` maturo; Node è comunque già richiesto per installare Pi via npm; SEA (`--experimental-sea-config`) consente un binario single-file per il packaging.
- **Trade-off:** startup più lento di Bun; bundling meno immediato.
- **Alternative scartate:** *Bun* (bundling e performance migliori, ma superficie API di compatibilità meno prevedibile per subprocess/stdio edge case e ciclo di release più rapido dei breaking change); *Rust* (nessun beneficio nell'MVP, perdita dell'accesso diretto ai tipi Pi).

### D2 — Libreria WebSocket: **`ws` + `node:http`**
- **Motivo:** controllo totale su handshake, header, origin, upgrade; nessuna magia di trasporto; lo stesso server HTTP serve gli asset Flutter Web.
- **Trade-off:** reconnect/heartbeat da implementare a mano (già richiesto dal protocollo).
- **Alternative scartate:** *socket.io* (protocollo proprietario sopra WS, client Dart non ufficiale); *uWebSockets.js* (build native, guadagno irrilevante su loopback).

### D3 — Source of truth del protocollo: **JSON Schema in `packages/pcp-spec`, codegen verso TS e Dart**
- **Motivo:** un solo contratto, due implementazioni generate, fixture condivise → impossibile divergere silenziosamente.
- **Trade-off:** step di codegen in CI.
- **Alternative scartate:** *tipi scritti a mano su entrambi i lati* (divergenza garantita); *protobuf/CBOR* (ottimizzazione prematura, debug peggiore; rimandato — vedi D12).

### D4 — State management Flutter: **Riverpod 2 (code-generation off)**
- **Motivo:** separazione naturale dei tre livelli di stato; provider scoped per `sessionId`; testabilità senza `BuildContext`; `AsyncNotifier` adatto a stream WS; nessun singleton globale.
- **Trade-off:** curva d'apprendimento; boilerplate dei provider.
- **Alternative scartate:** *BLoC* (verboso per stream ad alta frequenza di delta); *signals/setState* (non regge la fan-out multi-sessione); *Provider classico* (scoping e dispose meno rigorosi).

### D5 — Il daemon espone **eventi normalizzati**, non il JSONL di Pi
- **Motivo:** requisito §8 del brief; isola la UI dai breaking change di Pi; consente un futuro transport remoto senza toccare Flutter.
- **Trade-off:** un adapter da mantenere (`PiEventAdapter`) e mapping da aggiornare a ogni upgrade di Pi.
- **Mitigazione:** campo opzionale `raw` incluso solo se il client negozia la capability `debug.raw-pi-events`; test golden sui fixture di mapping.
- **Alternative scartate:** *passthrough puro* (accoppia la UI alla versione di Pi).

### D6 — Journal: **ring buffer in memoria + spill JSONL su disco per sessione**
- **Motivo:** replay deve sopravvivere alla disconnessione della GUI ma non deve diventare un secondo database del transcript (§21). Lo spill serve solo a superare un riavvio del daemon.
- **Percorso:** `~/.piframe/journal/<sessionId>/<epoch>.jsonl` + `snapshot.json`.
- **Trade-off:** I/O aggiuntivo; retention da gestire.
- **Alternative scartate:** *SQLite* (utile per l'indice, sovradimensionato per un journal append-only a finestra); *solo memoria* (riavvio daemon ⇒ perdita replay); *nessun journal* (viola il requisito di reconnect).

### D7 — Retention journal: **finestra per sessione = max(2.000 eventi, 8 MB) con snapshot ogni 500 eventi, spill conservato 24 ore**
- **Motivo:** copre ampiamente un disconnect tipico; oltre la finestra il client riceve uno snapshot completo, che è sempre corretto.
- **Trade-off:** un client offline a lungo perde il dettaglio dei delta intermedi (non il risultato: lo snapshot è costruito dai messaggi finali).
- **Configurabile:** `journal.maxEvents` (2.000), `journal.maxBytes` (8 MB), `journal.snapshotEvery` (500), `journal.retentionHours` (24).
- **Status: Confermata dal committente il 18/09/2026.**

### D8 — Avvio del daemon: **on-demand, detached, con lock file — nessun servizio di sistema nell'MVP**
- **Motivo:** l'utente non vuole un demone sempre attivo installato di nascosto; l'app lo avvia se non risponde all'health check.
- **Trade-off:** il primo avvio dopo il reboot è più lento; "agent continua a lavorare" vale finché l'utente non riavvia la macchina.
- **Post-MVP:** LaunchAgent (macOS) / Scheduled Task o servizio utente (Windows) opzionali da Impostazioni.
- **Alternative scartate:** *servizio sempre attivo di default* (invasivo, problematico per disinstallazione e permessi).
- **Status: Confermata dal committente il 18/09/2026** — "il daemon NON è un servizio permanente; la GUI lo avvia da sola alla bisogna se l'health check fallisce". Lo shutdown per inattività del daemon stesso (distinto dal timeout dei singoli worker, vedi D9) **resta al default proposto (disattivato nell'MVP)**: una volta avviato, il daemon rimane in esecuzione finché non viene fermato esplicitamente o la macchina non viene riavviata. Questo punto non è stato oggetto di una decisione esplicita e può essere rivisto in futuro senza impatti sul protocollo.

### D9 — Idle shutdown: **worker idle timeout 30 min di default, regolabile dall'utente; daemon vive finché esiste ≥1 worker o ≥1 client**
- **Motivo:** evita decine di processi Pi fantasma senza uccidere lavoro in corso.
- **Regola ferrea:** un worker in stato `working`/`retrying`/`compacting`/`awaiting_user` **non** viene mai spento per idle, qualunque sia il timeout configurato.
- **Configurabilità:** il valore di default è 30 minuti (`0` = mai). Non è pensato come una voce di un file di configurazione da modificare a mano: è esposto come comando PCP (`daemon.getConfig`/`daemon.setConfig`, vedi §4.4) e regolabile dall'utente nella **pagina Impostazioni di PiFrame** (Step 5.4), con effetto immediato sui worker già in esecuzione e persistenza in `~/.piframe/config.json`.
- **Daemon idle shutdown:** default `off` nell'MVP (altrimenti "chiudo la GUI e l'agent continua" smette di valere in modo sottile). Questo è distinto dal timeout dei worker e non è regolabile da UI nell'MVP.
- **Status: Confermata dal committente il 18/09/2026** — timeout worker 30 minuti, regolabile da Impostazioni.

### D10 — Multi-client: **broadcast per gli eventi, claim esclusivo per le UI request**
- **Motivo:** due GUI devono poter guardare la stessa sessione, ma una sola può rispondere a un `confirm`.
- **Meccanismo:** `ui.claim{requestId}` → lease 30 s rinnovabile; il primo che reclama vince; gli altri vedono la dialog in stato *read-only / "risposta in corso su un altro client"*.
- **Trade-off:** complessità aggiuntiva nel broker; necessaria comunque per correttezza.

### D11 — Auth: **token random 256 bit in `~/.piframe/runtime/daemon.token` (chmod 600), rigenerato a ogni avvio del daemon**
- **Motivo:** i browser non possono impostare header su WebSocket → il token viaggia nel primo frame `hello`, non in query string (evita log/referrer leak).
- **Difese aggiuntive:** bind esclusivo su `127.0.0.1`, validazione `Origin`, chiusura della connessione entro 5 s se non autenticata, rate limit sui tentativi.
- **Alternative scartate:** *token in query string* (finisce nei log); *nessun auth* (il daemon esegue comandi arbitrari: inaccettabile).
- **Bootstrap per il client Web — Status: Confermata dal committente il 18/09/2026:** quando l'utente apre `http://127.0.0.1:<port>/` dallo stesso browser/macchina, il daemon imposta automaticamente un cookie `HttpOnly; SameSite=Strict; Secure` (dove supportato su loopback) contenente il token, tramite l'endpoint `GET /api/session-bootstrap` (vedi §4.9 e Step 3.2/9.2). L'utente non deve mai incollare il token a mano nel caso desktop-locale standard; l'inserimento manuale resta disponibile come fallback per scenari futuri di daemon remoto.

### D12 — Serializzazione: **solo JSON testuale in PCP/1**
- **Motivo:** debug banale, supporto browser nativo, nessun codegen binario.
- **Estendibilità:** il campo `encoding` nella handshake è previsto ma nell'MVP accetta solo `json`; CBOR/MessagePack restano aggiungibili senza rompere il protocollo.

### D13 — Hosting web locale: **servito dallo stesso daemon, path separato dall'API**
- **Motivo:** esperienza `http://127.0.0.1:<port>/` a costo zero.
- **Separazione obbligatoria:** asset su `GET /`, API su `GET /api/*`, WebSocket su `/api/ws`. Nessuna logica applicativa nel layer statico, così un deploy remoto futuro può servire gli asset altrove.

### D14 — Distribuzione: **daemon come binario sidecar dentro il bundle della GUI**
- **Motivo:** l'utente installa PiFrame e ottiene GUI + daemon; Pi resta separato e non viene toccato; zero setup aggiuntivo richiesto all'utente (non deve avere Node installato).
- **Implementazione:** `esbuild` → bundle singolo → Node SEA per Windows/macOS (x64 + arm64). Fallback documentato (solo per sviluppo/debug): eseguire il daemon con un Node ≥ 22 già presente.
- **Disinstallazione:** rimuove GUI + daemon + `~/.piframe/`; **non** tocca `~/.pi/` né le sessioni.
- **Status: Confermata dal committente il 18/09/2026.**

### D15 — Versione minima di Pi supportata: **v0.85.0**
- **Regola:** il daemon esegue `pi --version` + una probe RPC di capability all'avvio del primo worker. Versione inferiore a `v0.85.0` ⇒ sessione rifiutata con errore strutturato `PI_VERSION_UNSUPPORTED` e istruzioni nella UI ("aggiorna Pi con `npm i -g @earendil-works/pi-coding-agent@latest`"). Matrice di compatibilità mantenuta in `docs/pi-compatibility.md` e testata in CI su almeno 2 versioni (`v0.85.0` + ultima disponibile).
- **Nota per lo Step 0.1:** questa versione minima è già decisa, non va scelta. Lo Step 0.1 deve **verificare** che la superficie RPC descritta in questo piano (§4.7, Appendice A) sia effettivamente compatibile con `v0.85.0`; se la macchina di sviluppo ha una versione diversa, va installata esplicitamente `v0.85.0` per la ricognizione, e ogni scostamento rilevato va annotato in `docs/pi-compatibility.md` **prima** di congelare lo Step 1.1.
- **Status: Confermata dal committente il 18/09/2026.**

### D16 — Telemetria: **zero raccolta dati remota, in nessuna forma, nemmeno opt-in**
- **Motivo:** decisione esplicita del committente; nessun dato di utilizzo, crash report o metrica lascia la macchina dell'utente verso un server controllato da PiFrame o da terzi.
- **Cosa resta:** logging strutturato **locale** (`~/.piframe/runtime/daemon.log`, ring buffer di diagnostica in memoria) e un bundle diagnostico esportabile **manualmente** dall'utente dalla pagina Impostazioni (Step 10.3), con redazione automatica di token e segreti. Questo bundle non viene mai inviato automaticamente: l'utente lo allega lui stesso, ad esempio a una segnalazione.
- **Trade-off:** nessuna visibilità aggregata su crash o errori reali degli utenti; il debug di problemi in produzione dipende dalla collaborazione volontaria dell'utente (bundle diagnostico) o dalla riproduzione locale.
- **Alternative scartate:** *telemetria con opt-in* (anche opt-in introduce infrastruttura di raccolta, superficie di privacy e un flag da mantenere corretto: il committente ha scelto di eliminare il problema alla radice); *crash reporting automatico verso servizi terzi (es. Sentry)* (stesso motivo).
- **Status: Confermata dal committente il 18/09/2026.**

### D17 — Font bundlati: **Inter (UI) + JetBrains Mono (codice), inclusi nell'app**
- **Motivo:** coerenza visiva identica su Windows, macOS e Web, indipendentemente dai font di sistema disponibili; entrambi i font sono open source (licenza SIL OFL) e liberamente ridistribuibili.
- **Implementazione:** i due font sono asset (`apps/pi_frame/assets/fonts/`) dichiarati in `pubspec.yaml`; il tema JSON (§6.2, campo `typography.uiFontFamily`/`monoFontFamily`) può referenziarli per nome o sostituirli con un font di sistema/alternativo — l'app deve comunque avviarsi correttamente se un tema richiede un font non presente, ricadendo su Inter/JetBrains Mono (vedi Step 6.1, gestione tollerante dei font mancanti).
- **Trade-off:** dimensione dell'installer maggiore di qualche centinaio di KB rispetto all'uso dei soli font di sistema.
- **Alternative scartate:** *font di sistema* (aspetto incoerente fra piattaforme, in contrasto con l'obiettivo di design moderno e curato).
- **Status: Confermata dal committente il 18/09/2026.**

---

## 4. Protocol specification — PCP/1 (PiFrame Protocol)

Sorgente normativa: `packages/pcp-spec/spec.md` + `schema/*.schema.json`. Questa sezione è il contenuto da implementare.

### 4.1 Trasporto

- WebSocket, frame **text**, un messaggio JSON per frame.
- Endpoint: `ws://127.0.0.1:<port>/api/ws`.
- Heartbeat: il daemon invia `ping` PCP applicativo ogni 15 s; il client risponde `pong` entro 10 s; niente risposta ⇒ chiusura con codice `4008`.
- Dimensione massima frame: 4 MiB (immagini in base64 vanno spezzate o passate per `POST /api/blobs` — vedi §4.9).

### 4.2 Envelope comune

```jsonc
{
  "protocol": 1,              // int, obbligatorio
  "kind": "event",            // hello|welcome|command|ack|result|event|snapshot|error|ping|pong
  "id": "evt_01HZ…",          // ULID univoco del messaggio
  "ts": 1789730000123,        // epoch ms, assegnato dal mittente
  "sessionId": "s_01HZ…",     // presente per tutto ciò che è session-scoped
  "seq": 481,                 // solo per kind=event/snapshot: monotono per sessione
  "type": "text.delta",       // tipo semantico specifico del kind
  "payload": { }              // oggetto, mai null
}
```

Invarianti:
- `seq` è **per sessione**, monotono crescente di 1, assegnato esclusivamente dal journal del daemon.
- Gli eventi non session-scoped (indice sessioni, stato daemon) usano `sessionId: "@daemon"` e una propria sequenza.
- Un client non deve mai assumere di conoscere tutti i `type`: i tipi sconosciuti vanno **ignorati con log**, mai trattati come errore fatale.

### 4.3 Handshake e autenticazione

Client → `hello`:
```jsonc
{ "protocol": 1, "kind": "hello", "id": "…", "ts": …,
  "payload": {
    "token": "<contenuto di daemon.token>",
    "client": { "name": "pi-frame", "version": "0.1.0", "platform": "macos" },
    "encoding": "json",
    "capabilities": ["replay.v1", "ui.claim.v1", "workspace.v1"]
  } }
```

Daemon → `welcome`:
```jsonc
{ "protocol": 1, "kind": "welcome", "id": "…", "ts": …,
  "payload": {
    "clientId": "c_01HZ…",
    "daemon": { "version": "0.1.0", "startedAt": …, "pid": 1234 },
    "pi": { "path": "/Users/me/.local/bin/pi", "version": "x.y.z", "supported": true },
    "capabilities": ["replay.v1", "ui.claim.v1", "workspace.v1", "git.readonly.v1"],
    "limits": { "maxFrameBytes": 4194304, "journalMaxEvents": 2000 }
  } }
```

Regole: `hello` deve arrivare entro **5 s** dall'apertura, altrimenti close `4001`. Token errato ⇒ close `4003` senza dettagli. `Origin` non in allowlist ⇒ upgrade rifiutato con 403. Le capability sono l'**intersezione** dichiarata: il client usa solo ciò che compare in `welcome`.

### 4.4 Comandi (client → daemon)

```jsonc
{ "protocol": 1, "kind": "command", "id": "…", "ts": …,
  "commandId": "cmd_01HZ…",     // ULID generato dal client; chiave di idempotenza
  "sessionId": "s_01HZ…",       // assente per comandi daemon-scoped
  "type": "agent.prompt",
  "payload": { "message": "Implementa OAuth", "images": [] } }
```

| `type` | Payload | Mappatura Pi RPC | Idempotente |
|---|---|---|---|
| `daemon.getStatus` | — | — | sì |
| `daemon.getConfig` | — | — (legge `~/.piframe/config.json`) | sì |
| `daemon.setConfig` | `{ workerIdleTimeoutMs? }` (patch parziale; altri campi in sola lettura nell'MVP) | — (persiste su config.json, applica ai timer attivi) | sì |
| `session.list` | `{ filter?, cursor?, limit? }` | scan indice + `get_state` | sì |
| `session.create` | `{ cwd, name?, model?, thinkingLevel? }` | spawn `pi --mode rpc` in `cwd` | **no** |
| `session.open` | `{ sessionPath? \| sessionId }` | spawn + `switch_session` | sì (converge) |
| `session.attach` | `{ lastSeq?: int \| null }` | — | sì |
| `session.detach` | — | — | sì |
| `session.closeWorker` | `{ force?: bool }` | SIGTERM → SIGKILL | sì |
| `session.rename` | `{ name }` | `set_session_name` | sì |
| `session.fork` | `{ entryId }` | `fork` | **no** |
| `session.clone` | — | `clone` | **no** |
| `session.getTree` | — | `get_tree` | sì |
| `session.getEntries` | `{ since? }` | `get_entries` | sì |
| `session.getStats` | — | `get_session_stats` | sì |
| `session.getForkPoints` | — | `get_fork_messages` | sì |
| `agent.prompt` | `{ message, images?, streamingBehavior? }` | `prompt` | **no** |
| `agent.steer` | `{ message, images? }` | `steer` | **no** |
| `agent.followUp` | `{ message, images? }` | `follow_up` | **no** |
| `agent.abort` | — | `abort` | sì |
| `agent.clearQueue` | — | `clear_queue` → restituisce i testi | sì |
| `agent.interrupt` | — | `clear_queue` **poi** `abort` (semantica Esc) | sì |
| `agent.compact` | `{ customInstructions? }` | `compact` | **no** |
| `agent.setAutoCompaction` | `{ enabled }` | `set_auto_compaction` | sì |
| `agent.setAutoRetry` | `{ enabled }` | `set_auto_retry` | sì |
| `agent.abortRetry` | — | `abort_retry` | sì |
| `agent.setModel` | `{ provider, modelId }` | `set_model` | sì |
| `agent.getModels` | — | `get_available_models` | sì |
| `agent.setThinkingLevel` | `{ level }` | `set_thinking_level` | sì |
| `agent.getThinkingLevels` | — | `get_available_thinking_levels` | sì |
| `agent.setSteeringMode` | `{ mode }` | `set_steering_mode` | sì |
| `agent.setFollowUpMode` | `{ mode }` | `set_follow_up_mode` | sì |
| `agent.getCommands` | — | `get_commands` | sì |
| `ui.claim` | `{ requestId }` | — | sì |
| `ui.respond` | `{ requestId, value? \| confirmed? \| cancelled? }` | `extension_ui_response` | sì (per requestId) |
| `workspace.refresh` | — | WorkspaceService | sì |
| `workspace.getDiff` | `{ path?, staged? }` | git | sì |

> **`daemon.setConfig`:** nell'MVP l'unico campo scrivibile da remoto è `workerIdleTimeoutMs` (D9), con validazione `0 ≤ v ≤ 24h` (`0` = mai). Il daemon applica il nuovo valore immediatamente ai timer dei worker già in esecuzione (senza riavviarli) e persiste la modifica in `~/.piframe/config.json`. Ogni modifica emette l'evento `daemon.configChanged` (§4.7) in broadcast a tutti i client connessi, così più GUI aperte restano coerenti sulla pagina Impostazioni. Altri campi di `config.json` (`journal.*`, `piPath`, `web.origins`) restano leggibili via `daemon.getConfig` ma non scrivibili via protocollo nell'MVP: si modificano a mano nel file, con effetto al riavvio del daemon.

> **Vincolo Pi verificato:** se l'agente sta già streammando, `prompt` **richiede** `streamingBehavior` (`"steer"` o `"followUp"`), altrimenti Pi risponde errore. Il dispatcher deve conoscere lo stato di streaming e o impostare il campo o rifiutare il comando con un errore comprensibile lato UI.

### 4.5 Ack e risultato

Per ogni comando il daemon emette **almeno** un `ack` e poi un `result`:

```jsonc
{ "kind": "ack",    "commandId": "cmd_…", "payload": { "state": "accepted" } }
{ "kind": "result", "commandId": "cmd_…", "payload": { "state": "completed", "data": { } } }
```

Stati ammessi: `accepted` → `executing` → (`completed` | `failed`), oppure `rejected` (mai eseguito), oppure `deduplicated` (già visto: viene ritrasmesso il risultato originale).

**Idempotency:** il dispatcher tiene una `Map<commandId, CommandRecord>` con TTL 10 minuti. Un `commandId` già noto **non** viene rieseguito: si ritrasmette il risultato memorizzato. Il client, dopo un reconnect, ripropone il medesimo `commandId` (mai uno nuovo) per i comandi non idempotenti la cui risposta non ha ricevuto. Timeout lato client: 30 s per comandi rapidi, nessun timeout per `agent.abort` (Pi risponde solo quando la sessione è idle) — mostrare stato "interruzione in corso".

### 4.6 Attach, snapshot e replay

`session.attach{ lastSeq }`:

| Condizione | Risposta del daemon |
|---|---|
| `lastSeq == null` | `snapshot` (seq = seq corrente) poi eventi live |
| `lastSeq >= journal.minSeq - 1` e `<= currentSeq` | `ack{state:"resume"}` poi eventi `lastSeq+1 … currentSeq` poi live |
| `lastSeq < journal.minSeq - 1` (gap) | `snapshot` + evento `journal.gap{ fromSeq, toSeq }` poi live |
| `lastSeq > currentSeq` (client da un'altra istanza di daemon) | `snapshot` + `journal.reset` |

Lo `snapshot` è un messaggio unico:
```jsonc
{ "kind": "snapshot", "sessionId": "s_…", "seq": 481,
  "payload": {
    "session": { "id", "name", "cwd", "gitRoot", "sessionFile", "createdAt", "lastActivityAt" },
    "runtime": { "status", "model", "thinkingLevel", "steeringMode", "followUpMode",
                 "isStreaming", "isCompacting", "autoCompaction", "queue": { "steering": [], "followUp": [] } },
    "transcript": { "entries": [ ], "leafId": "e_…" },
    "liveMessage": null,
    "activeTools": [ ],
    "pendingUiRequests": [ ],
    "usage": { "tokens": { }, "cost": 0.0, "contextUsage": { } },
    "workspace": { "branch", "dirty", "changedFiles": [ ], "diffStat": { } }
  } }
```

Costruzione dello snapshot (ordine obbligatorio):
1. `get_entries` (con `since` se il daemon ha già una proiezione valida — l'`entryId` è un **cursore durevole**, valido anche fra riavvii),
2. `get_state`, `get_session_stats`,
3. stato live in memoria (delta in volo, tool attivi, UI request pendenti, queue),
4. snapshot workspace dalla cache del `WorkspaceService`.

**Ordering e causalità:** il daemon serializza per sessione l'assegnazione di `seq` e l'invio. Nessun evento può essere inviato prima dello snapshot che lo precede. Il client scarta ogni evento con `seq <= lastAppliedSeq` (deduplica) e, se rileva `seq > lastAppliedSeq + 1`, richiede un re-attach con `lastSeq = lastAppliedSeq` invece di indovinare.

### 4.7 Eventi normalizzati (daemon → client)

Nomi **stabili** di prodotto. Tra parentesi l'origine Pi verificata.

**Lifecycle sessione/run**
| `type` | Payload | Origine Pi |
|---|---|---|
| `session.status` | `{ status, reason?, since }` | derivato (§5.4) |
| `run.started` | `{}` | `agent_start` |
| `run.ended` | `{ willRetry }` | `agent_end` |
| `run.settled` | `{}` | `agent_settled` |
| `turn.started` / `turn.ended` | `{}` / `{ message, toolResults }` | `turn_start` / `turn_end` |

**Streaming messaggi**
| `type` | Payload | Origine Pi |
|---|---|---|
| `message.started` | `{ message }` | `message_start` |
| `message.completed` | `{ message }` | `message_end` — **autorevole** |
| `text.started` / `text.delta` / `text.completed` | `{ contentIndex, delta? , content? }` | `message_update.assistantMessageEvent.text_*` |
| `thinking.started` / `thinking.delta` / `thinking.completed` | idem | `thinking_*` |
| `toolcall.started` | `{ contentIndex, toolCallId, toolName }` | `toolcall_start` |
| `toolcall.argsDelta` | `{ contentIndex, delta }` | `toolcall_delta` |
| `toolcall.completed` | `{ contentIndex, toolCall }` | `toolcall_end` |
| `usage.updated` | `{ usage }` | campo `usage` di `message_update` |

> **Regola verificata e non negoziabile:** `message_update` **non** contiene lo snapshot cumulativo del messaggio. Il client deve assemblare il messaggio parziale da `message_start` + i delta usando `contentIndex`, e poi sostituirlo con `message_end.message`, che è autorevole.

**Tool execution**
| `type` | Payload | Origine Pi |
|---|---|---|
| `tool.started` | `{ toolCallId, toolName, args }` | `tool_execution_start` |
| `tool.progress` | `{ toolCallId, toolName, partialResult }` | `tool_execution_update` |
| `tool.completed` | `{ toolCallId, toolName, result, isError, durationMs }` | `tool_execution_end` |

> **Regola verificata:** `partialResult` è **cumulativo**, non un delta → il client **sostituisce**, non concatena.

**Queue, compaction, retry, errori**
| `type` | Payload | Origine Pi |
|---|---|---|
| `queue.changed` | `{ steering: [], followUp: [] }` | `queue_update` |
| `compaction.started` | `{ reason }` | `compaction_start` |
| `compaction.ended` | `{ result, aborted, willRetry, errorMessage? }` | `compaction_end` |
| `retry.started` | `{ attempt, maxAttempts, delayMs, errorMessage }` | `auto_retry_start` |
| `retry.ended` | `{ success, attempt, finalError? }` | `auto_retry_end` |
| `summarization.retry` | `{ phase, attempt?, source?, reason? }` | `summarization_retry_*` |
| `bash.output` | `{ commandId, delta }` | `bash_execution_update` (correlato via `id`) |
| `extension.error` | `{ extensionPath, event, error }` | `extension_error` |

**Extension UI**
| `type` | Payload |
|---|---|
| `ui.request` | `{ requestId, method, title?, message?, options?, placeholder?, prefill?, timeoutMs?, dialog: bool, claimedBy: null }` |
| `ui.claimed` | `{ requestId, clientId }` |
| `ui.resolved` | `{ requestId, resolution: "value"\|"confirmed"\|"cancelled"\|"timeout", byClientId? }` |
| `ui.notify` | `{ level, message }` (fire-and-forget: `notify`) |
| `ui.status` | `{ statusKey, statusText? }` (`setStatus`) |
| `ui.widget` | `{ widgetKey, lines?, placement }` (`setWidget`) |
| `ui.editorText` | `{ text }` (`set_editor_text` → precompila il composer) |
| `ui.title` | `{ title }` (`setTitle`) |

> **Regole verificate:** solo `select`/`confirm`/`input`/`editor` sono dialog che attendono risposta. `notify`, `setStatus`, `setWidget`, `setTitle`, `set_editor_text` sono fire-and-forget: **non** inviare mai `extension_ui_response` per queste. Se una request ha `timeout`, Pi auto-risolve da solo allo scadere: il client **non** deve gestire il timeout, ma deve chiudere la dialog quando arriva `ui.resolved{resolution:"timeout"}`.

**Workspace / daemon**
| `type` | Payload |
|---|---|
| `workspace.changed` | `{ changedFiles, diffStat, branch, dirty }` |
| `worker.diagnostic` | `{ level, message, source: "stderr"\|"supervisor" }` |
| `worker.crashed` | `{ exitCode, signal, lastStderr, recoverable }` |
| `journal.gap` | `{ fromSeq, toSeq }` |
| `session.indexChanged` | `{ added: [], updated: [], removed: [] }` (su `@daemon`) |
| `daemon.configChanged` | `{ config }` (config corrente completa, su `@daemon`) — emesso dopo ogni `daemon.setConfig` riuscito |

### 4.8 Modello di errore

```jsonc
{ "kind": "error", "id": "…", "commandId": "cmd_…",
  "payload": { "code": "PI_NOT_FOUND", "message": "…", "retryable": false,
               "details": { }, "hint": "Imposta il percorso di Pi nelle impostazioni" } }
```

Codici obbligatori: `AUTH_FAILED`, `PROTOCOL_VERSION_UNSUPPORTED`, `INVALID_MESSAGE`, `SESSION_NOT_FOUND`, `SESSION_BUSY`, `WORKER_UNAVAILABLE`, `WORKER_CRASHED`, `PI_NOT_FOUND`, `PI_VERSION_UNSUPPORTED`, `COMMAND_REJECTED`, `COMMAND_TIMEOUT`, `UI_REQUEST_NOT_CLAIMED`, `UI_REQUEST_EXPIRED`, `JOURNAL_GAP`, `CONFIG_INVALID`, `RATE_LIMITED`, `INTERNAL`.

### 4.9 Endpoint HTTP di supporto

- `GET /api/health` → `{ ok, version, pid, uptime }` — **senza auth**, nessun dato sensibile: serve solo al probe di avvio.
- `POST /api/blobs` (auth) → upload immagini/allegati > 1 MB, restituisce `blobId` usabile nei payload comandi.
- `GET /api/themes` (auth) → temi JSON installati lato daemon (necessario per il client web).
- `GET /` → asset Flutter Web.

### 4.10 Codici di chiusura WebSocket

`4001` handshake timeout · `4002` protocollo non supportato · `4003` auth fallita · `4004` origin rifiutata · `4008` heartbeat fallito · `4009` client troppo lento (backpressure) · `4010` daemon in shutdown.

---

## 5. State machines

### 5.1 Daemon

```text
starting → discovering_pi → ready → draining → stopped
                │                      ▲
                └──> degraded ─────────┘   (Pi non trovato o versione non supportata:
                                            server attivo, sessioni rifiutate)
```

### 5.2 Pi worker (per sessione)

```text
idle_no_worker
   │ spawn
   ▼
starting ──ok──> running ──idle timeout──> stopping ──> idle_no_worker
   │                │                                       ▲
   │ fail           │ exit != 0 / EOF inatteso               │
   ▼                ▼                                       │
spawn_error     crashed ──(policy)──> restarting ───────────┘
                    │
                    └──(non sicuro)──> crashed_held  (richiede azione utente)
```

**Politica di restart (obbligatoria):** riavvio automatico consentito **solo** se il crash è avvenuto in stato `idle`/`settled` e non c'erano comandi in volo né UI request pendenti. In ogni altro caso → `crashed_held`: il daemon riconcilia leggendo `get_entries` dalla sessione persistita dopo un respawn *esplicito* richiesto dall'utente, e **non** rinvia mai automaticamente un `prompt`.

### 5.3 Connessione client

```text
disconnected → connecting → authenticating → ready → attached(sessionId…)
     ▲                                          │
     └──────── backoff (1s,2s,4s,8s,15s max) ───┘
```
Lato Flutter esiste in parallelo una UX state machine: `Connesso · Riconnessione… · Sincronizzazione… · Live · Offline (daemon non raggiungibile)`. È **distinta** dallo stato dell'agente: un agente può essere `working` mentre la GUI è `Riconnessione…`.

### 5.4 Stato dell'agente (derivato — questa è la parte critica per la UX)

```text
                ┌───────────────────────────────── settled ◄── run.settled
                │                                     ▲
 idle ──prompt──► working ──run.ended{willRetry:false}┘
                │  │  ▲
                │  │  └───────── retry.ended{success:true}
                │  │
                │  ├─ retry.started ──────────► retrying ──retry.ended{success:false}──► error
                │  ├─ compaction.started ─────► compacting ──compaction.ended──► working|error
                │  ├─ ui.request(dialog) ─────► awaiting_user ──ui.resolved──► working
                │  └─ queue.changed(non vuota) → badge "in coda", NON cambia lo stato principale
                │
                └─ worker.crashed ───────────► worker_error
```

**Regola fondamentale (§6 del brief):** `run.ended` **non** significa "finito". Solo `run.settled` autorizza la UI a mostrare lo stato terminale. Fra `run.ended{willRetry:true}` e il settle, la UI mostra *"Nuovo tentativo…"*. Se dopo `run.ended{willRetry:false}` la coda follow-up non è vuota, la UI mostra *"Eseguo attività in coda"* fino a `run.settled`.

Stati UI richiesti dal brief, mappati: `Working` → `working`; `Retrying` → `retrying`; `Compacting` → `compacting`; `Executing queued task` → `working` + flag `fromQueue`; `Waiting for user input` → `awaiting_user`; `Settled` → `settled`; `Error` → `error` / `worker_error`; `Disconnected` → stato di connessione, **non** stato agente.

### 5.5 Extension UI request

```text
received → broadcast(pending) → claimed(clientId, lease 30s)
                │                    │
                │                    ├─ ui.respond → resolved → inviato a Pi
                │                    ├─ lease scaduto → torna pending
                │                    └─ client disconnesso → torna pending
                └─ timeout lato Pi → resolved(timeout) → broadcast chiusura dialog
```
Le request pendenti sopravvivono al disconnect della GUI e compaiono nello snapshot al re-attach: è l'unico modo per non bloccare un agente in attesa di conferma dopo un riavvio della GUI.

---

## 6. Design system e theming JSON

Questa sezione definisce il requisito "design moderno + temi custom via JSON". Documentazione utente finale: `docs/theming.md`.

### 6.1 Direzione visiva

- **Layout a 3 colonne** (`Sessions | Conversation | Context`) con colonne collassabili e breakpoint: < 900 px → una colonna con navigazione a tab; 900–1300 px → 2 colonne; > 1300 px → 3 colonne.
- **Densità:** confortevole di default, opzione `compact` nelle impostazioni (scala spacing e font size di 0.875×).
- **Tipografia:** UI sans (default Inter), monospace per codice/diff/tool (default JetBrains Mono); entrambe sostituibili dal tema.
- **Movimento sobrio:** transizioni 120–200 ms, curva `easeOutCubic`; caret di streaming pulsante; nessuna animazione che riflowa il transcript durante lo streaming (altezze stabili, append in coda).
- **Superfici:** base → elevata → overlay, bordi 1 px a basso contrasto invece di ombre pesanti; raggio 10 px default.
- **Gerarchia del transcript:** i messaggi utente sono blocchi "card" leggibili, l'assistente è testo a piena larghezza, i tool sono righe compatte espandibili, il thinking è un blocco collassato di default a contrasto ridotto.
- **Keyboard-first:** command palette `Cmd/Ctrl+K`, `Esc` = interrupt (clear queue + abort, con recupero del testo nel composer), `Cmd/Ctrl+Enter` = invio, `Cmd/Ctrl+1..9` = sessione n.
- **Accessibilità:** contrasto minimo AA verificato in test sui temi bundlati; focus ring sempre visibile e tematizzabile; nessuna informazione veicolata dal solo colore (gli stati agente hanno icona + etichetta).

### 6.2 Formato tema JSON (`theme.schema.json`, versione 1)

```jsonc
{
  "$schema": "https://pi-frame.dev/theme.schema.json",
  "schemaVersion": 1,
  "id": "piframe-dark",
  "name": "PiFrame Dark",
  "author": "PiFrame",
  "version": "1.0.0",
  "variant": "dark",                       // "dark" | "light"
  "extends": null,                          // id di un tema base: i token mancanti sono ereditati
  "colors": {
    "background": "#0E1116",
    "surface": "#141922",
    "surfaceElevated": "#1B2230",
    "overlay": "#0A0D12CC",
    "border": "#242C3A",
    "borderStrong": "#33405480",
    "textPrimary": "#E6EAF2",
    "textSecondary": "#9AA6B8",
    "textMuted": "#66738A",
    "accent": "#7C9CFF",
    "accentContrast": "#0B0F16",
    "focusRing": "#7C9CFF",
    "success": "#4ED08A", "warning": "#E8B341", "danger": "#F1687A", "info": "#59B9E8",
    "agentWorking": "#7C9CFF", "agentRetrying": "#E8B341", "agentCompacting": "#59B9E8",
    "agentSettled": "#4ED08A", "agentAwaitingUser": "#C08CFF", "agentError": "#F1687A",
    "userBubble": "#18202C", "thinking": "#8E7BD6",
    "diffAddedBg": "#10301F", "diffAddedFg": "#7EE0A8",
    "diffRemovedBg": "#3A1620", "diffRemovedFg": "#F59AA8",
    "diffContextFg": "#8592A6"
  },
  "syntax": {
    "keyword": "#C792EA", "string": "#9CE29C", "number": "#F2A65A",
    "comment": "#5C6A80", "function": "#7C9CFF", "type": "#59D3C0",
    "variable": "#E6EAF2", "operator": "#9AA6B8", "punctuation": "#7E8AA0",
    "invalid": "#F1687A"
  },
  "typography": {
    "uiFontFamily": "Inter",
    "monoFontFamily": "JetBrains Mono",
    "baseSize": 14,
    "scale": { "xs": 11, "sm": 12, "md": 14, "lg": 16, "xl": 20, "xxl": 26 },
    "lineHeight": 1.5,
    "weights": { "regular": 400, "medium": 500, "semibold": 600 }
  },
  "spacing": { "unit": 4, "scale": [0, 4, 8, 12, 16, 24, 32, 48] },
  "radii": { "sm": 6, "md": 10, "lg": 16, "pill": 999 },
  "elevation": {
    "level1": { "color": "#00000059", "blur": 12, "offsetY": 2 },
    "level2": { "color": "#00000073", "blur": 28, "offsetY": 8 }
  },
  "motion": { "fast": 120, "normal": 180, "slow": 280, "curve": "easeOutCubic" },
  "components": {
    "sidebar": { "background": "#0C1015", "width": 280 },
    "composer": { "background": "#141922", "minHeight": 96 },
    "toolCard": { "background": "#141922", "borderRadius": 10 }
  }
}
```

**Regole del formato:**
- Colori: `#RRGGBB` o `#RRGGBBAA`. Nessun colore nominale, nessuna espressione.
- Tutti i campi tranne `schemaVersion`, `id`, `name`, `variant` sono **opzionali**: i token mancanti sono ereditati da `extends`, poi dal tema built-in della stessa `variant`. Un tema è quindi scrivibile in 10 righe.
- `components` è un'estensione libera con chiavi note: chiavi sconosciute vengono ignorate con warning, mai errore.
- Incompatibilità di `schemaVersion` → il tema non viene caricato e la UI mostra un avviso non bloccante.

### 6.3 Risoluzione e caricamento

Ordine di precedenza (il primo che definisce un token vince):
1. tema selezionato dall'utente,
2. suo `extends` (ricorsivo, max 3 livelli, ciclo = errore),
3. tema built-in della stessa `variant`,
4. valori hard-coded di fallback nel codice (garantiscono che l'app si avvii sempre).

Percorsi di ricerca:
| Piattaforma | Sorgenti |
|---|---|
| Desktop | `assets/themes/` (bundlati) → `~/.piframe/themes/*.json` → `<workspace>/.piframe/themes/*.json` |
| Web | asset bundlati → `GET /api/themes` (il daemon espone `~/.piframe/themes/`) → import manuale via file picker, salvato nelle preferenze daemon |

**Hot reload:** su desktop un watcher sulla cartella temi ricarica e riapplica in < 200 ms senza riavvio; su web il daemon emette `session.indexChanged`-style event `@daemon/themes.changed`. Questo rende il file JSON un'esperienza di editing vera e propria, non una configurazione da riavvio.

### 6.4 Implementazione Flutter

Package `packages/pi_frame_theme`:
- `ThemeSpec` — modello immutabile deserializzato dal JSON, con `ThemeSpec.merge(base, override)`.
- `PiFrameTokens extends ThemeExtension<PiFrameTokens>` — tutti i token semantici, con `lerp` implementato per transizioni animate fra temi.
- `ThemeSpec.toThemeData()` — costruisce `ThemeData` (ColorScheme, TextTheme, componenti) e allega `PiFrameTokens`.
- `ThemeRepository` — discovery, parsing, validazione, watching, selezione persistita.
- Accesso nei widget: `context.tokens` (extension method su `BuildContext`). **Vietato** hard-codare colori nei widget: un lint custom (`tools/lint/no_hardcoded_colors.dart` o una regola `custom_lint`) fallisce la build se un `Color(0x…)` compare fuori da `packages/pi_frame_theme`.

---
## 7. Step-by-step implementation plan

Legenda fasi: **F0** ricognizione · **F1** contratto protocollo · **F2** scheletro daemon · **F3** vertical slice · **F4** replay/multi-client · **F5** semantica di controllo · **F6** UI ricca + theming · **F7** workspace/git · **F8** session UX · **F9** packaging · **F10** hardening.

---

### Step 0.1 — Ricognizione della versione Pi target (BLOCCANTE)

**Obiettivo:** eliminare ogni assunzione non verificata sulla superficie RPC di Pi prima di scrivere contratti.

**Prerequisiti:** Pi installato localmente in versione **`v0.85.0`** (`npm i -g @earendil-works/pi-coding-agent@0.85.0`) — la versione minima è già decisa (D15) e va usata per la ricognizione, non scelta in questo step — e una API key provider configurata.

**Componenti/file coinvolti:** `docs/pi-compatibility.md`, `tools/recon/`, `packages/pcp-spec/fixtures/pi/`.

**Implementazione:**
1. Registra `pi --version`, versione npm, versione Node, sistema operativo.
2. Leggi e archivia nel repo (come riferimento, non come copia da modificare): `packages/coding-agent/docs/rpc.md`, `docs/sessions.md`, `src/modes/rpc/rpc-types.ts`, `src/modes/rpc/rpc-client.ts`, `src/client/transcript.ts`, `packages/agent/src/types.ts`.
3. Avvia `pi --mode rpc --no-session` e cattura su file **tutte** le righe stdout per questi scenari: risposta solo testo; risposta con thinking; risposta con 1 tool call; risposta con più tool call in parallelo; `bash` diretto con output lungo; `abort` a metà; `clear_queue` con coda piena; `compact` manuale; extension UI `confirm` e `select` (usa `examples/extensions/rpc-demo.ts`); errore provider che innesca `auto_retry_*`.
4. Da queste catture genera le **fixture golden** in `packages/pcp-spec/fixtures/pi/*.jsonl`. Sono la base di tutti i test dell'adapter.
5. Compila la tabella di verifica in `docs/pi-compatibility.md` per: elenco comandi, elenco eventi, semantica `agent_end`/`agent_settled`, presenza/assenza del campo `message` in `message_update`, cumulatività di `partialResult`, comportamento di `prompt` durante lo streaming, formato di `get_entries`/`get_tree` e del cursore `since`, metodi extension UI dialog vs fire-and-forget, path e formato dei file sessione.
6. Verifica che la versione minima già decisa (**`v0.85.0`**, D15) sia effettivamente compatibile con quanto descritto in questo piano; annota il risultato in `docs/pi-compatibility.md` e nel campo `piCompat` di `agentd/package.json`. Se emergono scostamenti rispetto a quanto verificato durante la stesura di questo piano (Appendice A), documentali esplicitamente prima di procedere allo Step 1.1: non correggere in silenzio.

**API/interfacce:** nessuna — solo documentazione e fixture.

**Test:** uno script `tools/recon/verify.ts` che riesegue le catture e diffa contro le fixture, così il drift di Pi è rilevabile in CI.

**Acceptance criteria:**
- [ ] `docs/pi-compatibility.md` compilato, con versione Pi esatta (`v0.85.0`) e data.
- [ ] ≥ 10 fixture JSONL reali archiviate, generate con `v0.85.0`.
- [ ] Ogni affermazione sul protocollo riportata in questo piano è confermata o corretta esplicitamente nel documento di compatibilità.
- [ ] Eventuali scostamenti tra `v0.85.0` e quanto descritto in questo piano (Appendice A) sono documentati esplicitamente, non silenziosamente "corretti".

**Output prodotto:** documento di compatibilità + fixture golden.

**Dipendenze verso step successivi:** blocca 1.1, 2.3, 2.4, 3.3.

---

### Step 0.2 — Bootstrap del monorepo e toolchain

**Obiettivo:** struttura, CI e comandi unici per tutti i componenti.

**Prerequisiti:** 0.1 avviato (non necessariamente concluso).

**Componenti/file coinvolti:** root `package.json` (workspaces pnpm), `melos.yaml` o semplice `Makefile`, `.github/workflows/ci.yml`, `tsconfig.base.json`, `analysis_options.yaml`, `.editorconfig`.

**Implementazione:**
- pnpm workspaces per `apps/agentd`, `packages/pcp-ts`, `packages/pcp-spec`, `tools/*`.
- Flutter ≥ 3.24 stabile; `apps/pi_frame` con target windows/macos/web abilitati.
- Task runner unico (`make` o `just`): `setup`, `codegen`, `lint`, `test`, `test:e2e`, `run:daemon`, `run:app`, `build:all`.
- CI: job Node (lint + test + build daemon), job Flutter (analyze + test), job codegen-drift (rigenera e fallisce se `git diff` non è vuoto).
- Logging strutturato condiviso: JSON lines su stderr del daemon, livello configurabile.

**API/interfacce:** —

**Test:** la CI passa a vuoto su tutti i job.

**Acceptance criteria:**
- [ ] `make setup && make test` funziona su macOS e Windows.
- [ ] `flutter run -d macos` e `-d chrome` avviano un'app vuota.

**Output prodotto:** scheletro del repository con CI verde.

**Dipendenze verso step successivi:** tutti.

---

### Step 0.3 — ADR delle decisioni aperte

**Obiettivo:** nessuna decisione architetturale implicita.

**Prerequisiti:** 0.2.

**Componenti/file coinvolti:** `docs/adr/0001…0017-*.md`.

**Implementazione:** trascrivi le decisioni D1–D17 della §3 nel formato *Context / Decision / Consequences / Alternatives rejected / Status*. Tutte e 17 vanno registrate come `Accepted`: il committente le ha confermate il 18/09/2026 (riepilogo in §10) — non c'è nulla da segnare come `Proposed` in questo passaggio. Se in futuro emergesse una nuova decisione architetturale non coperta da questo piano, va aggiunta come nuovo ADR in stato `Proposed` e portata all'attenzione del committente prima di essere implementata, seguendo lo stesso processo.

**Test:** check CI che ogni ADR abbia uno status valido (`Accepted` o, per eventuali ADR futuri, `Proposed`/`Superseded`).

**Acceptance criteria:**
- [ ] 17 ADR presenti, tutti in stato `Accepted`; nessuno in stato `Draft` o `Proposed`.
- [ ] Ogni ADR riporta la data di conferma (18/09/2026) e rimanda alla riga corrispondente della §10 dove applicabile.

**Output prodotto:** `docs/adr/`.

---

### Step 0.4 — `fake-pi`: simulatore RPC scriptabile

**Obiettivo:** poter testare tutto il daemon senza chiavi API, senza costi e in modo deterministico.

**Prerequisiti:** 0.1 (fixture).

**Componenti/file coinvolti:** `tools/fake-pi/src/index.ts`, `tools/fake-pi/scenarios/*.json`.

**Implementazione:**
- Un eseguibile che accetta gli stessi flag rilevanti (`--mode rpc`, `--no-session`, `--session-dir`, `--name`) e riproduce scenari dichiarativi: sequenze di eventi con ritardi, risposte ai comandi, extension UI request, crash simulato (exit code), riga JSON malformata, stallo dello stdout, output enorme.
- Deve rispettare **esattamente** il framing JSONL strict LF e rispondere ai comandi con `{"type":"response","command":…,"success":…}`.
- Scenari minimi: `hello-world`, `with-thinking`, `tool-call`, `parallel-tools`, `retry-then-success`, `compaction`, `ui-confirm`, `ui-select-timeout`, `crash-mid-stream`, `malformed-line`, `slow-stream`, `huge-output`.

**API/interfacce:** CLI compatibile con il contratto di spawn del daemon.

**Test:** unit test dello scenario runner; ogni scenario deve essere consumabile dalle fixture reali dello Step 0.1 (`fake-pi --replay fixtures/pi/tool-call.jsonl`).

**Acceptance criteria:**
- [ ] Il daemon (F2) può essere puntato su `fake-pi` tramite `PI_FRAME_PI_PATH` e l'intera test suite gira senza rete.
- [ ] Il replay di una fixture reale produce byte identici all'originale.

**Output prodotto:** simulatore riutilizzabile in unit, integration ed e2e test.

**Dipendenze verso step successivi:** 2.3, 2.5, 3.5, 10.1.

---

### Step 1.1 — Specifica PCP/1

**Obiettivo:** congelare il contratto Flutter ↔ daemon prima di ogni implementazione.

**Prerequisiti:** 0.1.

**Componenti/file coinvolti:** `packages/pcp-spec/spec.md`, `packages/pcp-spec/schema/*.schema.json`, `packages/pcp-spec/fixtures/pcp/*.json`.

**Implementazione:**
- Trascrivi la §4 di questo piano in `spec.md` come documento normativo, correggendo ciò che lo Step 0.1 ha smentito.
- Scrivi i JSON Schema: `envelope`, `hello`, `welcome`, `command` (con `oneOf` per tipo), `ack`, `result`, `event` (`oneOf` per tipo), `snapshot`, `error`.
- Scrivi almeno una fixture valida **e una non valida** per ciascun tipo di messaggio.
- Definisci la policy di versioning: campi aggiuntivi sempre ammessi (forward-compatible), rimozioni/rinomine solo con `protocol: 2`.

**API/interfacce:** i file schema sono l'interfaccia.

**Test:** un test nel package che valida tutte le fixture contro gli schema (valide passano, invalide falliscono con l'errore atteso).

**Acceptance criteria:**
- [ ] Ogni comando ed evento della §4 ha schema + fixture.
- [ ] `spec.md` documenta attach/replay/snapshot/idempotency in modo sufficiente a implementarli senza leggere il codice.

**Output prodotto:** contratto versionato.

**Dipendenze verso step successivi:** 1.2, 1.3, e tutte le F2+.

---

### Step 1.2 — `pcp-ts`: tipi e validatori TypeScript

**Obiettivo:** tipi TS e validazione runtime derivati dallo schema.

**Prerequisiti:** 1.1.

**Componenti/file coinvolti:** `packages/pcp-ts/src/{types.ts,validate.ts,encode.ts,index.ts}`, `tools/codegen/schema-to-ts.ts`.

**Implementazione:**
- Genera i tipi da JSON Schema (`json-schema-to-typescript`) + validatori compilati (`ajv` con `strict: true`).
- API: `parseIncoming(raw: string): Result<ClientMessage, ProtocolError>`, `encode(msg: ServerMessage): string`, `makeEnvelope(...)`, helper ULID.
- Ogni messaggio in ingresso viene validato; un messaggio non valido produce `error{INVALID_MESSAGE}` e **non** chiude la connessione (a meno di 10 violazioni consecutive).

**Test:** round-trip su tutte le fixture; property test su envelope con campi extra (devono passare) e campi obbligatori mancanti (devono fallire).

**Acceptance criteria:**
- [ ] 100 % delle fixture valide passa, 100 % delle invalide fallisce.
- [ ] Zero `any` esportati dall'API pubblica.

**Output prodotto:** package TS consumato dal daemon.

---

### Step 1.3 — `pi_frame_protocol`: package Dart

**Obiettivo:** stessi tipi lato Flutter, generati dalla stessa fonte.

**Prerequisiti:** 1.1.

**Componenti/file coinvolti:** `packages/pi_frame_protocol/lib/src/{envelope.dart,commands.dart,events.dart,snapshot.dart,codec.dart}`, `tools/codegen/schema-to-dart.ts`.

**Implementazione:**
- Classi immutabili con `fromJson`/`toJson` (sealed class Dart 3 per la gerarchia degli eventi → exhaustive `switch` nel reducer).
- **Obbligatorio:** un caso `UnknownEvent(type, payload)` per garantire la forward-compatibility; il reducer lo ignora loggando.
- Le fixture di `pcp-spec` sono copiate come asset di test e verificate anche lato Dart.

**Test:** decode/encode di tutte le fixture; test che un evento di tipo sconosciuto produce `UnknownEvent` e non un'eccezione.

**Acceptance criteria:**
- [ ] Le stesse fixture passano identiche in TS e Dart.
- [ ] Il job CI `codegen-drift` è verde.

**Output prodotto:** package Dart condiviso.

---

### Step 2.1 — Daemon: configurazione, runtime dir, single-instance

**Obiettivo:** un daemon che si avvia una sola volta, in modo sicuro, e dichiara dove vive.

**Prerequisiti:** 0.2.

**Componenti/file coinvolti:** `apps/agentd/src/main.ts`, `src/config/{config.ts,runtime.ts,lock.ts}`.

**Implementazione:**
- Runtime dir `~/.piframe/runtime/`: `daemon.json` (`{port, pid, version, startedAt, protocol}`), `daemon.token` (256 bit, base64url, `chmod 600`, rigenerato a ogni avvio), `daemon.pid`, `daemon.log`.
- Lock a singola istanza: lock file esclusivo + verifica liveness del pid; pid stale ⇒ pulizia e avvio; daemon già vivo e sano ⇒ exit 0 stampando il `daemon.json` esistente.
- Porta: `0` (effimera) di default, scritta in `daemon.json`; opzione `--port` per fissarla.
- Config utente `~/.piframe/config.json`: `piPath`, `journal.*`, `worker.idleTimeoutMs`, `log.level`, `web.enabled`, `origins[]`.
- Shutdown pulito su SIGINT/SIGTERM: stato `draining`, chiusura WS con `4010`, terminazione controllata dei worker (SIGTERM, poi SIGKILL a 5 s), rimozione lock.

**API/interfacce:** `DaemonConfig`, `RuntimeInfo`, `acquireSingleInstanceLock(): Promise<LockHandle>`.

**Test:** unit su pid stale, permessi del token (POSIX), doppio avvio concorrente (solo uno vince), cleanup su SIGTERM.

**Acceptance criteria:**
- [ ] Due avvii simultanei ⇒ un solo processo in ascolto.
- [ ] `daemon.token` ha permessi 600 su macOS/Linux e ACL utente su Windows.
- [ ] Dopo SIGTERM non restano file di lock né processi figli.

**Output prodotto:** processo daemon avviabile.

---

### Step 2.2 — Daemon: server HTTP/WS, handshake, auth

**Obiettivo:** trasporto PCP funzionante e sicuro.

**Prerequisiti:** 1.2, 2.1.

**Componenti/file coinvolti:** `src/server/{httpServer.ts,wsServer.ts,connection.ts,auth.ts,origin.ts}`.

**Implementazione:**
- Bind **esclusivo** su `127.0.0.1` (mai `0.0.0.0`; il bind su altra interfaccia richiede un flag esplicito e stampa un avviso di sicurezza).
- `GET /api/health` senza auth; tutto il resto autenticato.
- Upgrade WS: valida `Origin` contro l'allowlist (`http://127.0.0.1:<port>`, `http://localhost:<port>`, più le origin configurate; le connessioni senza `Origin`, cioè i client desktop, sono ammesse solo con token valido).
- `hello` entro 5 s, token confrontato in tempo costante, `welcome` con capability e limiti.
- `Connection`: coda di uscita **bounded** (default 2.000 messaggi / 16 MB) con politica: superata la soglia → smetti di inviare delta, invia `journal.gap` e forza un re-attach; superato il doppio → chiudi con `4009`.
- Heartbeat applicativo 15 s.
- Rate limit: max 20 `hello` falliti/minuto per IP, max 200 comandi/secondo per connessione.

**API/interfacce:** `ConnectionManager.broadcast(sessionId, msg)`, `Connection.send(msg)`, `Connection.close(code, reason)`.

**Test:** unit su handshake (timeout, token errato, origin errata, protocollo errato); test su client lento simulato (non deve mai bloccare il loop di lettura); heartbeat.

**Acceptance criteria:**
- [ ] Connessione senza token ⇒ chiusa `4003` in < 100 ms.
- [ ] Un client che non legge mai non fa crescere la memoria oltre il limite e viene chiuso `4009`.
- [ ] Nessuna porta esposta oltre loopback (verificato con `netstat` in test manuale documentato).

**Output prodotto:** trasporto PCP operativo.

---

### Step 2.3 — `PiTransport` + `StdioPiTransport` + framing JSONL

**Obiettivo:** parlare con Pi correttamente, senza che il resto del daemon sappia come.

**Prerequisiti:** 0.1, 0.4.

**Componenti/file coinvolti:** `src/pi/{PiTransport.ts,StdioPiTransport.ts,jsonlFramer.ts,piCommands.ts}`.

**Implementazione:**
- Interfaccia:
  ```ts
  interface PiTransport {
    start(opts: { cwd: string; args: string[]; env: Record<string,string> }): Promise<void>;
    send(cmd: PiCommand): Promise<PiResponse>;   // correla via campo `id`
    events(): AsyncIterable<PiEvent>;
    health(): TransportHealth;
    capabilities(): PiCapabilities;
    stop(opts: { graceMs: number }): Promise<ExitInfo>;
  }
  ```
- **Framer JSONL obbligatorio e scritto a mano:** accumula `Buffer`, splitta **solo** su `\n`, elimina un eventuale `\r` finale, decodifica UTF-8 con `StringDecoder` per non spezzare i multibyte fra chunk. **Vietato usare `readline`** (splitta anche su U+2028/U+2029, che sono caratteri legali dentro le stringhe JSON di Pi): questo è un requisito esplicito della documentazione RPC di Pi.
- Riga non parsabile ⇒ evento `worker.diagnostic{level:"warn"}` e **prosegui**; mai crash, mai riavvio.
- stdout e stderr letti **sempre** e in modo indipendente, anche se non c'è alcun client connesso (mai backpressure verso Pi a causa della GUI). stderr in un ring buffer da 200 righe per la diagnostica dei crash.
- Correlazione comandi: ogni comando inviato ottiene un `id` ULID; le risposte `{"type":"response", …}` vengono risolte per `id`; le risposte senza `id` (se emesse) sono risolte FIFO per `command`. Timeout per-comando configurabile, **escluso** `abort` (Pi risponde solo a sessione idle).
- EOF su stdout ⇒ `ExitInfo` con exit code/segnale; nessun restart deciso qui (è compito del supervisor).

**API/interfacce:** vedi sopra; `PiCommand`/`PiEvent` sono tipi interni del daemon, **non** esposti su PCP.

**Test:** unit sul framer con: chunk spezzato a metà carattere UTF-8, `\r\n`, riga da 5 MB, U+2028 dentro una stringa (deve **non** essere trattato come newline), riga vuota, JSON malformato; integration contro `fake-pi` per tutti gli scenari.

**Acceptance criteria:**
- [ ] Il replay di ogni fixture reale dello Step 0.1 produce esattamente la stessa sequenza di eventi tipizzati.
- [ ] Un carattere U+2028 in un delta di testo non spezza il parsing.
- [ ] Il crash di Pi produce `ExitInfo` con l'ultimo stderr disponibile.

**Output prodotto:** adapter di trasporto verso Pi.

---

### Step 2.4 — Pi discovery, health check e capability

**Obiettivo:** trovare Pi senza toccarlo e fallire in modo comprensibile.

**Prerequisiti:** 2.1, 2.3.

**Componenti/file coinvolti:** `src/pi/{discovery.ts,capabilities.ts}`.

**Implementazione:**
- Ordine di ricerca: `config.piPath` esplicito → `PI_FRAME_PI_PATH` → `PATH` → location note (`~/.local/bin/pi`, `/opt/homebrew/bin/pi`, `%APPDATA%\npm\pi.cmd`, prefix npm globale) → fallimento.
- Health check: `pi --version` con timeout 5 s; confronto con la versione minima (D15) usando semver.
- Capability probe: avvio di un processo RPC effimero con `--no-session`, invio di `get_state` e `get_available_thinking_levels`, chiusura. Il risultato è cacheato per path+mtime dell'eseguibile.
- Esito negativo ⇒ daemon in stato `degraded`: il server resta su, `welcome` riporta `pi.supported: false`, i comandi di sessione falliscono con `PI_NOT_FOUND`/`PI_VERSION_UNSUPPORTED` + `hint`.
- **Divieto assoluto:** non scrivere, spostare, installare o disinstallare nulla dentro `~/.pi/`.

**API/interfacce:** `discoverPi(): Promise<PiInstallation>`, `probeCapabilities(path): Promise<PiCapabilities>`.

**Test:** unit con PATH finto, eseguibile inesistente, versione troppo vecchia, binario che non risponde (timeout).

**Acceptance criteria:**
- [ ] Senza Pi installato la GUI mostra un messaggio azionabile con il campo per impostare il percorso, e non va in crash.
- [ ] Il percorso configurato manualmente ha precedenza su `PATH`.

**Output prodotto:** rilevamento robusto di Pi.

---

### Step 2.5 — Session registry e worker supervisor

**Obiettivo:** il daemon diventa l'autorità sul runtime live.

**Prerequisiti:** 2.3, 2.4.

**Componenti/file coinvolti:** `src/sessions/{SessionRegistry.ts,Session.ts,WorkerSupervisor.ts,SessionIndex.ts}`.

**Implementazione:**
- `Session` = identità + `cwd` + `gitRoot` + `sessionFile` + stato runtime + journal + client attaccati + worker **opzionale** (la separazione "sessione persistente / worker vivo" del brief §13).
- `SessionRegistry`: `create`, `open` (lazy spawn), `get`, `list`, `attach`, `detach`, `closeWorker`.
- Spawn: `pi --mode rpc` con `cwd` corretto, env ereditato + `PI_FRAME=1`; `--name` se fornito; **non** usare `--no-session` (la persistenza di Pi è la source of truth) tranne che nei test.
- Riapertura di una sessione esistente: spawn + `switch_session{sessionPath}`; gestisci `data.cancelled: true` (un'extension può annullare lo switch) come errore utente, non come crash.
- Idle timeout per worker (D9) con la regola ferrea: mai spegnere in `working`/`retrying`/`compacting`/`awaiting_user`.
- `SessionIndex`: scansione di `~/.pi/agent/sessions/` (**sola lettura**) per costruire la lista: id, path, cwd derivata dal nome cartella, mtime, nome, anteprima ultimo messaggio, dimensione. Cache in `~/.piframe/index.json` con invalidazione per mtime; **non** è una copia del transcript, solo metadati.

**API/interfacce:** `SessionRegistry`, `WorkerSupervisor.ensureWorker(sessionId)`, `SessionStatus`.

**Test:** integration con `fake-pi`: create/open/close, 5 worker simultanei, idle timeout, spegnimento durante il lavoro (deve essere rifiutato), scansione indice su una directory di sessioni sintetica.

**Acceptance criteria:**
- [ ] 5 sessioni simultanee, ognuna con il proprio processo e cwd.
- [ ] Chiudere il worker non cancella né modifica il file di sessione.
- [ ] L'indice elenca sessioni create dal solo CLI di Pi (mai aperte nella GUI).

**Output prodotto:** gestione sessioni e processi.

---

### Step 2.6 — `PiEventAdapter`: normalizzazione degli eventi

**Obiettivo:** tradurre eventi Pi in eventi PCP stabili.

**Prerequisiti:** 1.1, 2.3.

**Componenti/file coinvolti:** `src/pi/PiEventAdapter.ts`, `src/pi/mapping/*.ts`.

**Implementazione:**
- Mapping 1:1 della tabella §4.7; per `message_update` esplodi `assistantMessageEvent` nei tipi `text.*`, `thinking.*`, `toolcall.*` **preservando `contentIndex`**.
- Estrai `usage` da `message_update` in `usage.updated` solo quando cambia (evita un evento per delta).
- Eventi Pi sconosciuti ⇒ `worker.diagnostic{level:"info"}` con il tipo, più inclusione in `raw` se la capability di debug è attiva. Mai droppare silenziosamente.
- Correla `bash_execution_update.id` con il `commandId` PCP originario.
- L'adapter è **puro**: `(PiEvent, SessionContext) => PcpEvent[]`. Nessun I/O, così è testabile sulle fixture.

**API/interfacce:** `adapt(event: PiEvent, ctx): PcpEvent[]`.

**Test:** golden test su tutte le fixture dello Step 0.1: `fixture.jsonl → expected-pcp.json`. Un cambiamento di mapping deve rompere il test.

**Acceptance criteria:**
- [ ] Ogni evento documentato di Pi ha un mapping o un rifiuto esplicito e documentato.
- [ ] Nessuna informazione semantica persa (verificato manualmente sulle fixture di tool call e retry).

**Output prodotto:** confine stabile fra Pi e il prodotto.

---

### Step 2.7 — Event journal, seq e snapshot

**Obiettivo:** rendere gli eventi rigiocabili.

**Prerequisiti:** 2.5, 2.6.

**Componenti/file coinvolti:** `src/journal/{EventJournal.ts,RingBuffer.ts,Spill.ts,SnapshotBuilder.ts}`.

**Implementazione:**
- Un journal per sessione; assegnazione di `seq` **serializzata** (nessun await fra assegnazione e append).
- Ring buffer in memoria secondo D7 + spill append-only su `~/.piframe/journal/<sessionId>/`.
- `SnapshotBuilder` costruisce lo snapshot secondo §4.6; snapshot periodico ogni `snapshotEvery` eventi, salvato accanto allo spill.
- `getRange(fromSeq, toSeq)`, `minSeq`, `currentSeq`.
- Retention: alla chiusura del worker mantieni journal+snapshot per 24 h, poi elimina; comando manuale di pulizia.
- Riavvio del daemon: journal ricaricato dallo spill; se assente o corrotto, `minSeq` riparte e il primo attach riceve uno snapshot completo ricostruito via `get_entries`.

**API/interfacce:** `EventJournal.append(evt): number`, `EventJournal.snapshotAt(seq)`, `SnapshotBuilder.build(session)`.

**Test:** unit su monotonia sotto append concorrenti, rotazione della finestra, `getRange` a cavallo della finestra, spill corrotto (troncato a metà riga) che deve degradare a snapshot e non crashare.

**Acceptance criteria:**
- [ ] 10.000 eventi appesi, `seq` senza buchi né duplicati.
- [ ] Riavvio del daemon con sessione viva ⇒ il client riceve snapshot coerente.

**Output prodotto:** base del replay.

---

### Step 2.8 — Command dispatcher e idempotency

**Obiettivo:** comandi correlabili, non duplicabili, con ciclo di vita esplicito.

**Prerequisiti:** 2.2, 2.5, 2.6.

**Componenti/file coinvolti:** `src/commands/{Dispatcher.ts,CommandRecord.ts,mapping.ts,validators.ts}`.

**Implementazione:**
- `Map<commandId, CommandRecord{state, result, createdAt}>` con TTL 10 min, per sessione.
- Ciclo: `accepted → executing → completed|failed`, oppure `rejected`, oppure `deduplicated` (ritrasmette il risultato memorizzato senza rieseguire).
- Coda per sessione: i comandi verso lo stesso worker sono **serializzati**; i comandi di sola lettura (`get_*`) possono andare in parallelo.
- Precondizioni prima di toccare Pi: worker vivo, stato compatibile. Esempio verificato: `agent.prompt` mentre `isStreaming` è vero **deve** portare `streamingBehavior`; se manca, il dispatcher rifiuta con `COMMAND_REJECTED` + hint "usa Steer o Follow-up", invece di lasciar fallire Pi.
- `agent.interrupt` implementa la semantica Esc: `clear_queue` → cattura `{steering, followUp}` → `abort` → emette `result` contenente i testi recuperati, che la GUI ripristina nel composer.

**API/interfacce:** `Dispatcher.handle(conn, cmd): Promise<void>`.

**Test:** stesso `commandId` inviato due volte ⇒ una sola esecuzione; comando inviato, connessione caduta, riproposto dopo reconnect ⇒ `deduplicated` con risultato originale; prompt durante streaming senza behavior ⇒ rifiuto pulito.

**Acceptance criteria:**
- [ ] Nessun doppio prompt in nessuno scenario di reconnect testato.
- [ ] Ogni comando produce sempre almeno un `ack` e un `result`.

**Output prodotto:** superficie comandi completa lato daemon.

---

### Step 2.9 — Configurazione daemon via protocollo (`daemon.getConfig`/`daemon.setConfig`)

**Obiettivo:** rendere `workerIdleTimeoutMs` (D9) regolabile dall'utente senza editing manuale di file, con effetto immediato e coerenza fra più GUI aperte.

**Prerequisiti:** 2.1, 2.2, 2.8.

**Componenti/file coinvolti:** `src/config/config.ts` (estensione), `src/commands/mapping.ts`, `src/server/connection.ts` (broadcast).

**Implementazione:**
- `daemon.getConfig` restituisce la configurazione corrente completa (nessun segreto incluso: il token non fa parte di `config.json`).
- `daemon.setConfig` accetta una patch parziale; nell'MVP l'unico campo scrivibile è `workerIdleTimeoutMs` (`0 ≤ v ≤ 86_400_000` ms, `0` = mai). Un valore fuori range o un campo non scrivibile ⇒ `error{CONFIG_INVALID}` con dettaglio del vincolo violato.
- La scrittura è **atomica** (file temporaneo + rename) per evitare corruzione di `config.json` in caso di crash a metà scrittura.
- Il nuovo valore si applica **immediatamente** ai timer di idle già pianificati per i worker attualmente in esecuzione (nessun riavvio del daemon o dei worker necessario).
- Dopo ogni `daemon.setConfig` riuscito, il daemon fa il broadcast di `daemon.configChanged{config}` a **tutti** i client connessi (incluso il mittente), così una seconda GUI aperta sulla pagina Impostazioni vede il nuovo valore senza dover fare polling.

**API/interfacce:** `ConfigStore.get(): DaemonConfig`, `ConfigStore.patch(partial): Result<DaemonConfig, ConfigError>`.

**Test:** unit sui limiti di validazione (0, valore massimo, valore negativo, valore non numerico, campo non scrivibile); integration: worker con timeout residuo di 25 minuti, `setConfig{workerIdleTimeoutMs: 60000}` (1 minuto) ⇒ il worker va in idle-shutdown entro ~1 minuto, non entro i 25 originari; scrittura interrotta a metà (kill del processo durante il rename) non corrompe `config.json` al riavvio successivo.

**Acceptance criteria:**
- [ ] Cambiare il timeout dalla pagina Impostazioni (Step 5.4) si riflette sul comportamento dei worker già vivi, non solo su quelli futuri.
- [ ] Due GUI aperte sullo stesso daemon vedono lo stesso valore dopo una modifica fatta da una sola delle due.
- [ ] Un valore invalido non viene mai scritto su disco.

**Output prodotto:** superficie di configurazione del daemon esposta al prodotto.

---

### Step 3.1 — App Flutter: scheletro, DI, shell

**Obiettivo:** base dell'app con navigazione e struttura a 3 colonne.

**Prerequisiti:** 0.2.

**Componenti/file coinvolti:** `apps/pi_frame/lib/{main.dart,app/*}`.

**Implementazione:** bootstrap Riverpod, router (`go_router`), `AppShell` responsive con le 3 colonne collassabili, gestione finestra desktop (dimensione minima, titolo), placeholder in ogni pannello, tema provvisorio hard-coded che verrà sostituito in F6 (i colori vivono già dietro `context.tokens` per non dover riscrivere i widget).

**Test:** widget test dei breakpoint (1, 2, 3 colonne).

**Acceptance criteria:**
- [ ] L'app parte su macOS, Windows e Chrome con layout corretto a tre larghezze diverse.

**Output prodotto:** shell dell'applicazione.

---

### Step 3.2 — `PcpClient`: connessione, auth, reconnect

**Obiettivo:** client PCP affidabile lato Flutter.

**Prerequisiti:** 1.3, 2.2, 3.1.

**Componenti/file coinvolti:** `lib/data/daemon/{pcp_client.dart,daemon_locator.dart,connection_controller.dart}`.

**Implementazione:**
- **Desktop:** `DaemonLocator` legge `~/.piframe/runtime/daemon.json` + token; probe `GET /api/health`; se assente o non sano, avvia il binario sidecar **detached** (`ProcessStartMode.detached`, stdio rediretto su `daemon.log`) e attende il file di runtime (polling 100 ms, timeout 10 s).
- **Web:** origine e porta derivate da `window.location`; il token è iniettato dal daemon nella pagina servita (endpoint `GET /api/session-bootstrap` autenticato via cookie `SameSite=Strict` generato al primo caricamento locale) oppure inserito manualmente. **Nessun token in query string.**
- Reconnect con backoff esponenziale + jitter (1 s → 15 s), riattacco automatico di tutte le sessioni aperte con `lastSeq` conservato per sessione.
- Comandi: `Future<CommandResult> send(command)` con `commandId` **persistito in memoria** finché non arriva il `result`; al reconnect i comandi pendenti non idempotenti vengono **ri-proposti con lo stesso `commandId`**.
- `Stream<PcpEvent>` per sessione, con deduplica su `seq` e richiesta di re-attach in caso di gap.

**API/interfacce:** `PcpClient.connect()`, `.attach(sessionId, lastSeq)`, `.send(cmd)`, `.events(sessionId)`, `.connectionState`.

**Test:** unit con server WS finto: handshake ok/ko, drop e reconnect, gap di `seq`, dedup, comando ripresentato.

**Acceptance criteria:**
- [ ] Killando il daemon la UI passa a "Riconnessione…" e si riconnette da sola al riavvio.
- [ ] Nessun comando duplicato dopo 20 cicli di drop/reconnect automatizzati.

**Output prodotto:** livello di comunicazione dell'app.

---

### Step 3.3 — Session reducer (Dart)

**Obiettivo:** proiezione deterministica dello stato di sessione dai delta.

**Prerequisiti:** 1.3, 2.6.

**Componenti/file coinvolti:** `lib/domain/session/{session_state.dart,session_reducer.dart,agent_status.dart,live_message.dart}`.

**Implementazione:**
- `SessionState`: `snapshotMeta`, `entries` (storico), `liveMessage` (blocchi per `contentIndex`), `liveThinking`, `liveToolCalls` (mappa per `toolCallId`), `toolOutputs`, `queue`, `pendingUiRequests`, `runtimeStatus`, `usage`, `workspace`, `lastAppliedSeq`.
- Riduzione **pura**: `SessionState reduce(SessionState, PcpEvent)`. Nessun I/O, nessun timer.
- Regole obbligatorie, derivate dalla verifica del protocollo Pi:
  1. i delta di testo/thinking si **accumulano per `contentIndex`**;
  2. `message.completed` **sostituisce** il messaggio live: è autorevole;
  3. `tool.progress.partialResult` **sostituisce** l'output accumulato (è cumulativo, non un delta);
  4. `run.ended` non produce uno stato terminale; solo `run.settled` lo fa;
  5. un evento con `seq <= lastAppliedSeq` viene scartato;
  6. un `UnknownEvent` non modifica lo stato.
- `AgentStatus` derivato dalla state machine §5.4, esposto come singolo enum + `reason` per la UI.

**Test:** golden test che alimentano il reducer con le fixture PCP generate dalle fixture Pi reali e confrontano lo stato finale serializzato; test specifici su: delta duplicati, eventi fuori ordine, tool paralleli, retry, compaction, thinking assente.

**Acceptance criteria:**
- [ ] Applicare due volte lo stesso evento non cambia lo stato.
- [ ] Lo stato finale dopo il replay di una sessione reale coincide con `get_messages` di Pi.

**Output prodotto:** cuore della presentazione.

---

### Step 3.4 — UI minima: lista sessioni, transcript, composer

**Obiettivo:** rendere visibile il vertical slice.

**Prerequisiti:** 3.2, 3.3.

**Componenti/file coinvolti:** `lib/features/{sessions_sidebar,transcript,composer}/**`.

**Implementazione:** lista sessioni dall'indice (con stato live/inattiva), transcript virtualizzato (`ListView.builder` con chiavi stabili per entry) che rende testo in markdown, blocchi codice monospace e placeholder per i tool, composer con invio, indicatore di stato agente. Nessun polish: serve solo a dimostrare il flusso.

**Test:** widget test di streaming (delta → testo che cresce senza saltare lo scroll se l'utente ha scrollato in alto).

**Acceptance criteria:**
- [ ] Creazione sessione, prompt, testo in streaming visibile progressivamente.

**Output prodotto:** UI funzionale minima.

---

### Step 3.5 — PROOF OF ARCHITECTURE (milestone M1)

**Obiettivo:** dimostrare il requisito centrale del progetto: **chiudere la GUI non termina l'agente**.

**Prerequisiti:** 2.7, 2.8, 3.4.

**Componenti/file coinvolti:** `test/e2e/proof_of_architecture.spec.ts`.

**Implementazione:** test automatizzato che esegue esattamente la sequenza del brief §39:
1. avvia il daemon; 2. rileva Pi (`fake-pi` con scenario `slow-stream` da 60 s); 3. crea la sessione; 4. invia il prompt; 5. verifica gli eventi in streaming; 6. **uccide il processo GUI** (o chiude il WS); 7. verifica che il processo Pi sia ancora vivo e che il journal continui a crescere; 8. riconnette con `lastSeq`; 9. verifica di ricevere la coda esatta di eventi mancanti senza buchi né duplicati; 10. verifica che il transcript ricostruito sia identico a quello di un client rimasto sempre connesso.

**Test:** è il test. Va eseguito anche manualmente con Pi reale e documentato con screenshot in `docs/`.

**Acceptance criteria:**
- [ ] Il test passa 20 volte consecutive in CI senza flakiness.
- [ ] Il transcript del client riconnesso è byte-identico a quello del client di controllo.
- [ ] Verifica manuale con Pi reale e un prompt lungo: superata.

**Output prodotto:** **l'architettura è dimostrata.** Da qui in poi si costruisce solo sopra, senza toccare il core di comunicazione.

**Dipendenze verso step successivi:** cancello di ingresso per F4+. Se questo step non è verde, **non procedere**.

---

### Step 4.1 — Replay robusto e gap handling

**Obiettivo:** copertura di tutti i casi di ri-sincronizzazione.

**Prerequisiti:** 3.5.

**Componenti/file coinvolti:** `src/journal/*`, `src/sessions/attach.ts`, lato Dart `connection_controller.dart`.

**Implementazione:** implementa integralmente la tabella §4.6 (resume, snapshot, gap, reset). Aggiungi la riconciliazione via `get_entries{since}` usando l'ultimo `entryId` noto come **cursore durevole** — funziona anche dopo un riavvio del daemon, quando il journal non esiste più.

**Test:** matrice `lastSeq` ∈ {null, minSeq-1, minSeq, currentSeq, currentSeq+10} × {worker vivo, worker morto, daemon riavviato}.

**Acceptance criteria:**
- [ ] In tutti i 15 casi la UI arriva a uno stato corretto senza duplicati e senza messaggi persi.
- [ ] Un client che richiede un `seq` non più disponibile riceve snapshot + `journal.gap` e lo segnala in UI in modo non allarmante.

**Output prodotto:** reconnect a prova di produzione.

---

### Step 4.2 — Multi-client attachment e backpressure

**Obiettivo:** due GUI sulla stessa sessione senza conflitti e senza rallentare l'agente.

**Prerequisiti:** 4.1.

**Componenti/file coinvolti:** `src/server/connection.ts`, `src/sessions/Session.ts`, `src/ui/UiRequestBroker.ts`.

**Implementazione:** broadcast degli eventi a tutti i client attaccati; code di uscita indipendenti per client; il client lento degrada da solo (§4.10 codice `4009`) senza mai toccare il ritmo di lettura di stdout di Pi. Introduci il `UiRequestBroker` con claim/lease (D10).

**Test:** integration con 3 client, uno dei quali non legge mai; verifica che gli altri due restino perfettamente sincronizzati e che il worker Pi non rallenti.

**Acceptance criteria:**
- [ ] Un client bloccato non degrada gli altri né l'agente (misurato: throughput eventi invariato ±5 %).
- [ ] Desktop e browser aperti sulla stessa sessione mostrano lo stesso transcript.

**Output prodotto:** modello multi-client.

---

### Step 4.3 — Crash recovery e riconciliazione

**Obiettivo:** comportamento corretto quando Pi muore.

**Prerequisiti:** 4.1.

**Componenti/file coinvolti:** `src/sessions/WorkerSupervisor.ts`, `src/sessions/reconcile.ts`.

**Implementazione:** implementa la policy §5.2. Su crash: stato `worker_error`, evento `worker.crashed` con exit code, segnale e ultime righe di stderr, persistenza della diagnostica in `~/.piframe/journal/<id>/crash-<ts>.log`. Il respawn è **sempre** un'azione utente esplicita ("Riprendi sessione"), salvo il caso sicuro (crash in idle senza comandi in volo). Dopo il respawn: `switch_session` sul file originale + `get_entries` per riconciliare la proiezione, poi snapshot a tutti i client. **Mai** rinviare automaticamente un prompt.

**Test:** `fake-pi` scenario `crash-mid-stream` durante: prompt, tool execution, dialog extension, retry, idle. Cinque test distinti.

**Acceptance criteria:**
- [ ] Nessuna operazione duplicata dopo un recovery.
- [ ] La UI spiega cosa è successo e cosa può fare l'utente.
- [ ] Una UI request pendente al momento del crash viene chiusa con `ui.resolved{resolution:"cancelled"}` e non resta appesa.

**Output prodotto:** resilienza dei worker.

---

### Step 5.1 — Semantica di controllo: steer, follow-up, abort, Esc

**Obiettivo:** dare all'utente il controllo durante l'esecuzione, con le semantiche di Pi.

**Prerequisiti:** 2.8, 3.4.

**Componenti/file coinvolti:** `lib/features/composer/**`, `src/commands/mapping.ts`.

**Implementazione:**
- Il composer cambia comportamento in base ad `AgentStatus`: a riposo → **Invia** (`prompt`); durante l'esecuzione → azione primaria **Steer** e azione secondaria **Follow-up**, con spiegazione inline della differenza (*steer* = correggi ora, consegnato dopo i tool del turno corrente e prima della prossima chiamata al modello; *follow-up* = istruzione da eseguire quando avrà finito).
- `Esc` (e il pulsante Stop) → `agent.interrupt`: `clear_queue` + `abort`, con **ripristino nel composer** dei testi restituiti da `clear_queue`, come nel terminale.
- Visualizzazione della coda (`queue.changed`) con possibilità di svuotarla senza abortire.
- Stato "Interruzione in corso…" finché `abort` non risponde (Pi risponde solo quando la sessione è idle).

**Test:** integration steer durante tool execution; abort durante retry; clear queue con 3 messaggi in coda e verifica del ripristino nel composer.

**Acceptance criteria:**
- [ ] Steer e follow-up producono effetti distinti e osservabili.
- [ ] Dopo `Esc` il testo in coda ricompare nel composer e non viene perso.

**Output prodotto:** controllo dell'esecuzione.

---

### Step 5.2 — Modello, thinking, compaction, modalità di coda

**Obiettivo:** parità di controllo con il CLI su ciò che conta per la GUI.

**Prerequisiti:** 5.1.

**Componenti/file coinvolti:** `lib/features/context_panel/model_picker.dart`, `settings/`, `src/commands/mapping.ts`.

**Implementazione:** selettore modello (`get_available_models` → `set_model`), selettore livello di thinking (`get_available_thinking_levels` → `set_thinking_level`, con `off` come unico valore per modelli senza reasoning), toggle auto-retry e auto-compaction, compaction manuale con istruzioni opzionali e visualizzazione del risultato (token prima/dopo, costo), modalità steering/follow-up (`all` / `one-at-a-time`), indicatore di uso del contesto da `get_session_stats.contextUsage` (gestendo il caso documentato in cui è `null` subito dopo una compaction).

**Test:** unit sul mapping dei comandi; widget test del selettore con modello senza reasoning.

**Acceptance criteria:**
- [ ] Cambiare modello a metà sessione funziona e si riflette nello snapshot.
- [ ] La barra del contesto non mostra valori fasulli quando i dati sono `null`.

**Output prodotto:** pannello di controllo della sessione.

---

### Step 5.3 — Comandi, skill e prompt template

**Obiettivo:** rendere accessibili i comandi `/` dalla GUI.

**Prerequisiti:** 5.2.

**Componenti/file coinvolti:** `lib/features/composer/slash_menu.dart`, `command_palette/`.

**Implementazione:** `agent.getCommands` popola un menu di autocompletamento su `/` nel composer, con nome, descrizione, sorgente (extension/prompt/skill) e origine (user/project). I comandi extension vanno inviati con `prompt` (funzionano anche durante lo streaming), **mai** con `steer`/`follow_up` (Pi li rifiuta). Command palette `Cmd/Ctrl+K` per azioni dell'app + comandi di sessione.

**Test:** widget test dell'autocompletamento; test che un comando extension inviato durante lo streaming usi `prompt`.

**Acceptance criteria:**
- [ ] I comandi elencati corrispondono a `get_commands` di Pi.
- [ ] Nessun comando extension instradato su steer/follow-up.

**Output prodotto:** superficie comandi nella GUI.

---

### Step 5.4 — Pagina Impostazioni di PiFrame

**Obiettivo:** un unico posto dove l'utente controlla Pi, il daemon e le preferenze locali, senza mai dover editare un file a mano.

**Prerequisiti:** 2.9, 3.2.

**Componenti/file coinvolti:** `lib/features/settings/**`.

**Implementazione:** pagina con quattro sezioni:
- **Pi** — percorso rilevato (o override manuale con file picker), versione, esito dell'ultimo health check, pulsante "ricontrolla".
- **Daemon** — stato corrente (`ready`/`degraded`), versione, PID, uptime; controllo **timeout inattività worker** (stepper/slider in minuti, con opzione esplicita "mai"), che invia `daemon.setConfig{workerIdleTimeoutMs}` e mostra conferma quando arriva `daemon.configChanged`; pulsante "riavvia daemon" **disabilitato** se esistono worker in stato diverso da `idle`/`settled` (con tooltip che spiega perché).
- **Aspetto** — selezione del tema fra quelli scoperti da `ThemeRepository` (Step 6.1), toggle densità compatta/confortevole, anteprima live.
- **Privacy** — testo statico e non modificabile: *"PiFrame non invia alcun dato di utilizzo a server remoti. I log restano sul tuo computer; puoi esportarli manualmente dalla sezione Diagnostica per condividerli con chi ti assiste."* (coerente con D16 — nessun toggle di opt-in, perché non c'è nulla da attivare).

**API/interfacce:** consuma `daemon.getConfig`/`daemon.setConfig` (Step 2.9) e `ThemeRepository` (Step 6.1); nessuna nuova API.

**Test:** widget test che modifica il timeout e verifica l'invio del comando corretto; widget test che verifica l'assenza di qualunque controllo di telemetria/analytics nella pagina (assertion negativa, per evitare regressioni silenziose su D16).

**Acceptance criteria:**
- [ ] Il timeout impostato da UI persiste dopo il riavvio del daemon.
- [ ] Il pulsante "riavvia daemon" è disabilitato quando ci sono worker attivi, con spiegazione visibile.
- [ ] La sezione Privacy non contiene alcun controllo per abilitare raccolta dati: solo testo informativo.

**Output prodotto:** pagina Impostazioni completa.

---

### Step 6.1 — Theme engine JSON (milestone M3)

**Obiettivo:** temi custom definiti da file JSON, con hot reload.

**Prerequisiti:** 3.1.

**Componenti/file coinvolti:** `packages/pi_frame_theme/**`, `themes/*.json`, `themes/theme.schema.json`, `apps/pi_frame/assets/themes/`, `docs/theming.md`.

**Implementazione:**
1. Scrivi `theme.schema.json` (JSON Schema draft 2020-12) secondo la §6.2; pubblicalo anche come asset così gli editor possono validare i temi dell'utente tramite `$schema`.
2. `ThemeSpec` + `ThemeSpec.fromJson` **tollerante**: campi mancanti ⇒ ereditati; campi sconosciuti ⇒ ignorati con warning raccolto in una lista di diagnostica; colore malformato ⇒ warning + fallback, mai eccezione.
3. `ThemeSpec.merge` per la catena `extends` (max 3 livelli, rilevamento cicli).
4. `PiFrameTokens extends ThemeExtension<PiFrameTokens>` con `copyWith` e `lerp` completi (le transizioni di tema devono essere animate, non a scatto).
5. `ThemeSpec.toThemeData()`: `ColorScheme`, `TextTheme` (con fallback font se la famiglia dichiarata non è disponibile sul sistema), `CardTheme`, `InputDecorationTheme`, `ScrollbarTheme`, `DividerTheme`, `FocusTheme`.
6. `ThemeRepository`: discovery multi-sorgente (§6.3), watcher su desktop (`package:watcher`), fetch `GET /api/themes` su web, selezione persistita, evento di ricarica.
7. Due temi ufficiali completi: `piframe-dark`, `piframe-light`. Un terzo tema d'esempio minimale (`example-minimal.json`, 12 righe) che dimostra l'ereditarietà, incluso in `docs/theming.md`.
8. Lint custom che vieta `Color(0x…)` / `Colors.*` fuori dal package del tema.

**API/interfacce:** `ThemeSpec`, `PiFrameTokens`, `ThemeRepository.watch(): Stream<List<ThemeSpec>>`, `context.tokens`.

**Test:** parsing di tema completo/minimale/malformato/con ciclo di `extends`; test di contrasto AA su tutte le coppie testo/sfondo dei temi bundlati; golden test dei widget principali sotto i due temi; test di hot reload (scrittura file → evento entro 500 ms).

**Acceptance criteria:**
- [ ] Copiando un `.json` in `~/.piframe/themes/` il tema appare nelle impostazioni senza riavvio.
- [ ] Modificando quel file, l'app si aggiorna in < 500 ms.
- [ ] Un tema con un solo colore definito funziona (tutto il resto ereditato) e non rompe nulla.
- [ ] Un tema corrotto non impedisce l'avvio dell'app e mostra un errore leggibile.
- [ ] Nessun colore hard-coded nel codice dei widget (lint verde).

**Output prodotto:** sistema di theming completo e documentato.

---

### Step 6.2 — Transcript ricco: markdown, codice, diff

**Obiettivo:** leggibilità di livello Codex/Copilot.

**Prerequisiti:** 6.1, 3.4.

**Componenti/file coinvolti:** `lib/features/transcript/**`, `lib/ui/code/**`.

**Implementazione:** rendering markdown (titoli, liste, tabelle, link, inline code); blocchi di codice con syntax highlighting che usa i token `syntax` del tema, pulsante copia, indicazione del linguaggio; diff unificato colorato con i token `diff*`; immagini allegate; copia messaggio; ancore stabili per lo scroll durante lo streaming (l'altezza non deve saltare); "scorri in fondo" intelligente che si disattiva se l'utente ha scrollato in su.

**Test:** golden test su un transcript campione nei due temi; test di performance: 2.000 entry con streaming attivo devono mantenere ≥ 55 fps su desktop.

**Acceptance criteria:**
- [ ] Un transcript lungo resta fluido durante lo streaming.
- [ ] Il codice è leggibile e i colori provengono solo dal tema.

**Output prodotto:** transcript di qualità prodotto.

---

### Step 6.3 — Tool timeline

**Obiettivo:** tool execution strutturata e ispezionabile, non una stringa grezza.

**Prerequisiti:** 6.2.

**Componenti/file coinvolti:** `lib/features/tool_timeline/**`.

**Implementazione:** una card per `toolCallId` con: nome tool con icona, stato (queued/running/completed/failed/cancelled), argomenti formattati (per `read`/`write`/`edit` mostra il path in evidenza; per `bash` il comando), output progressivo (ricordando che `partialResult` è cumulativo → sostituzione), durata, errore evidenziato, collasso/espansione con memoria della preferenza per tipo di tool, output lunghi troncati con "mostra tutto". Tool paralleli resi correttamente in ordine di avvio. Output del comando `bash` diretto (`bash.output`) in un canale visivamente distinto dai tool del modello.

**Test:** widget test su tool paralleli, tool fallito, output da 5 MB (nessun blocco della UI).

**Acceptance criteria:**
- [ ] L'utente capisce a colpo d'occhio cosa sta facendo l'agente e su quali file.

**Output prodotto:** timeline dei tool.

---

### Step 6.4 — Thinking UI

**Obiettivo:** mostrare il reasoning quando c'è, senza assumerlo.

**Prerequisiti:** 6.2.

**Componenti/file coinvolti:** `lib/features/transcript/thinking_block.dart`.

**Implementazione:** blocco collassato di default con anteprima di una riga e contatore; espansione mostra il testo in streaming con stile distinto (token `thinking`); scompare completamente quando il livello di thinking è `off` o il modello non lo supporta. La UI deve funzionare identica nei 4 casi del brief (solo testo / testo+thinking / testo+tool / testo+thinking+tool).

**Test:** 4 golden test, uno per combinazione.

**Acceptance criteria:**
- [ ] Nessun contenitore vuoto quando il thinking non è disponibile.

**Output prodotto:** rendering del reasoning.

---

### Step 6.5 — Extension UI: dialog, claim, persistenza

**Obiettivo:** chiudere il ciclo `extension_ui_request` → utente → `extension_ui_response`.

**Prerequisiti:** 4.2.

**Componenti/file coinvolti:** `lib/features/dialogs/**`, `src/ui/UiRequestBroker.ts`.

**Implementazione:**
- Quattro dialog generiche guidate dai dati: `confirm`, `select`, `input`, `editor` (quest'ultima multi-riga con prefill, monospace, conferma/annulla).
- I metodi fire-and-forget diventano elementi non modali: `notify` → toast; `setStatus` → voce nella status bar; `setWidget` → pannello sopra/sotto il composer; `set_editor_text` → precompila il composer; `setTitle` → titolo finestra/tab. **Nessuna risposta** per questi.
- Claim: all'apertura, il client invia `ui.claim`; se non ottiene il lease, mostra la dialog in sola lettura con "Un altro client sta rispondendo".
- Persistenza: una request pendente compare nello snapshot, quindi riappare dopo il riavvio della GUI.
- Timeout: gestito da Pi; la GUI mostra un countdown se `timeoutMs` è presente e chiude la dialog su `ui.resolved{resolution:"timeout"}`.

**Test:** integration con `fake-pi` per tutti e quattro i metodi; scenario "dialog aperta → chiudo la GUI → riapro → la dialog è ancora lì e rispondendo l'agente riparte"; scenario due client con claim.

**Acceptance criteria:**
- [ ] Un'approvazione di comando pericoloso emessa da un'extension è rispondibile dalla GUI e sblocca l'agente.
- [ ] Due client non possono rispondere alla stessa request.
- [ ] Nessun `extension_ui_response` inviato per metodi fire-and-forget.

**Output prodotto:** integrazione completa con il sistema di extension di Pi.

---

### Step 7.1 — `WorkspaceService`: watcher e Git (sola lettura)

**Obiettivo:** conoscere lo stato del repository indipendentemente dagli eventi di Pi.

**Prerequisiti:** 2.5.

**Componenti/file coinvolti:** `src/workspace/{WorkspaceService.ts,gitClient.ts,watcher.ts}`.

**Implementazione:**
- Watcher (`chokidar`) sul `cwd` della sessione, con ignore di `.git`, `node_modules`, `build`, `.dart_tool`, target grandi; debounce 300 ms; limite al numero di file osservati con degrado a polling periodico nei repo enormi.
- Git via CLI (`git` nel PATH): `rev-parse --show-toplevel`, `branch --show-current`, `status --porcelain=v2`, `diff --numstat`, `diff -- <path>` per il diff di un singolo file. Timeout 5 s per invocazione; repo assente ⇒ stato `notARepository`, non un errore.
- Refresh anche dopo eventi Pi rilevanti (`tool.completed` per write/edit/bash, `run.settled`), perché i file cambiano anche da bash o da processi esterni.
- Cache per sessione + emissione di `workspace.changed` solo su differenza effettiva.
- **Sola lettura nell'MVP**: nessun `add`, `commit`, `checkout`, `stash`. La separazione read/write va mantenuta anche a livello di modulo per rendere sicura l'aggiunta futura.

**API/interfacce:** `WorkspaceService.snapshot(sessionId)`, `.getDiff(path)`, `.refresh()`.

**Test:** integration su un repo git temporaneo: modifica, aggiunta, rinomina, eliminazione, cambio branch, repo non-git, repo con 50k file (deve degradare senza bloccare).

**Acceptance criteria:**
- [ ] Un file modificato dal tool `edit` compare in "Changes" entro 1 s.
- [ ] Un file modificato da un editor esterno compare comunque.

**Output prodotto:** intelligenza sul workspace.

---

### Step 7.2 — Context panel

**Obiettivo:** terza colonna utile.

**Prerequisiti:** 7.1, 6.2.

**Componenti/file coinvolti:** `lib/features/context_panel/**`.

**Implementazione:** sezione Git (repo, branch, dirty, `+N -M`), lista file modificati con badge M/A/D/R, click → diff del file nel pannello principale o in un riquadro dedicato, sezione sessione (modello, thinking, contesto usato, token, costo), sezione workspace (cwd, file di sessione, pulsante "apri cartella").

**Test:** widget test con snapshot workspace finto.

**Acceptance criteria:**
- [ ] I file toccati dall'agente sono visibili e ispezionabili senza uscire dall'app.

**Output prodotto:** pannello di contesto.

---

### Step 8.1 — Session UX: indice, ricerca, filtri

**Obiettivo:** navigare decine o centinaia di sessioni come in Codex/Copilot.

**Prerequisiti:** 2.5, 6.1.

**Componenti/file coinvolti:** `lib/features/sessions_sidebar/**`, `src/sessions/SessionIndex.ts`.

**Implementazione:** raggruppamento per workspace/repository, ordinamento per ultima attività, badge live/inattiva/errore, anteprima dell'ultimo messaggio, ricerca per nome/cwd/branch/testo dell'anteprima, filtri (solo live, solo questo repo), rinomina inline (`set_session_name`), caricamento lazy e paginato.

**Test:** test dell'indice su 500 sessioni sintetiche (apertura sidebar < 200 ms); test di ricerca.

**Acceptance criteria:**
- [ ] 500 sessioni non rallentano l'avvio dell'app.
- [ ] Sessioni create dal CLI compaiono nella lista.

**Output prodotto:** navigazione delle sessioni.

---

### Step 8.2 — Fork, clone, tree, resume

**Obiettivo:** sfruttare il modello ad albero delle sessioni di Pi.

**Prerequisiti:** 8.1.

**Componenti/file coinvolti:** `lib/features/transcript/fork_actions.dart`, `lib/features/session_tree/**`.

**Implementazione:** azione "Riparti da qui" sui messaggi utente (`get_fork_messages` → `fork{entryId}`, con il testo restituito riproposto nel composer); "Duplica ramo" (`clone`); vista albero della sessione (`get_tree`) con evidenziazione del ramo attivo e del `leafId`; "Riprendi" su una sessione inattiva (spawn worker + `switch_session`). Gestisci esplicitamente `cancelled: true` (un'extension può annullare fork/clone/switch) mostrandolo all'utente.

**Test:** integration fork/clone su sessione reale; test su `cancelled: true`.

**Acceptance criteria:**
- [ ] Il fork crea una nuova sessione senza modificare l'originale.
- [ ] L'albero riflette la struttura restituita da `get_tree`.

**Output prodotto:** gestione dei rami di sessione.

---

### Step 9.1 — Packaging del daemon e lifecycle

**Obiettivo:** distribuire `pi-agentd` insieme alla GUI, mantenendolo separato.

**Prerequisiti:** M1 + F5 complete.

**Componenti/file coinvolti:** `apps/agentd/build/*`, script di build, `docs/install.md`.

**Implementazione:** bundle `esbuild` → single file → Node SEA per `macos-arm64`, `macos-x64`, `win-x64` (firmato/notarizzato su macOS; firmato su Windows). Il binario viene incluso nelle risorse dell'app Flutter. Avvio on-demand detached (D8) con lock, log rotativo in `~/.piframe/runtime/daemon.log` (5 file × 5 MB). Upgrade: la GUI confronta la versione del daemon in esecuzione con quella del bundle; se differiscono, chiede all'utente di riavviare il daemon quando non ci sono sessioni attive (mai a sorpresa). Disinstallazione documentata: rimuove app, binario, `~/.piframe/`; **non** tocca `~/.pi/`.

**Test:** test manuale di installazione pulita su Windows e macOS; test automatico che verifica che dopo la disinstallazione simulata `~/.pi/` sia intatto (checksum della directory prima/dopo).

**Acceptance criteria:**
- [ ] Prima esecuzione su macchina pulita: l'app avvia il daemon da sola.
- [ ] Nessuna modifica a `~/.pi/` in nessuna fase di install/uninstall.

**Output prodotto:** daemon distribuibile.

---

### Step 9.2 — Packaging desktop e hosting web

**Obiettivo:** artefatti installabili sulle tre piattaforme.

**Prerequisiti:** 9.1.

**Componenti/file coinvolti:** `apps/pi_frame/{macos,windows}/**`, `apps/agentd/src/server/static.ts`.

**Implementazione:** build macOS (.app + .dmg, hardened runtime, notarizzazione) e Windows (MSIX o installer); build Flutter Web servita dal daemon su `GET /` con header di sicurezza (`Content-Security-Policy` che consente solo `self` e la connessione WS locale, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`) e bootstrap del token via cookie `HttpOnly; SameSite=Strict` emesso solo per richieste da loopback.

**Test:** e2e browser (Playwright) contro il daemon locale; smoke test degli installer.

**Acceptance criteria:**
- [ ] `http://127.0.0.1:<port>/` offre l'esperienza completa nel browser.
- [ ] L'app desktop firmata si avvia senza avvisi di sicurezza.

**Output prodotto:** distribuzione multi-piattaforma.

---

### Step 10.1 — Fault injection suite

**Obiettivo:** dimostrare la robustezza, non affermarla.

**Prerequisiti:** F4–F9.

**Componenti/file coinvolti:** `tools/fault-proxy/`, `test/e2e/faults/*.spec.ts`.

**Implementazione:** proxy WS che inietta drop, latenza, riordino (per verificare che il client scarti/riordini correttamente), duplicazione, frame troncati. Scenari `fake-pi`: crash, riga malformata, stallo, output enorme. Più: riavvio del daemon con sessioni vive, client lento, comandi malformati, token errato a metà sessione, orologio di sistema che salta.

**Test:** un test per fault, tutti in CI.

**Acceptance criteria:**
- [ ] Nessun fault produce perdita silenziosa di messaggi, doppia esecuzione di un prompt o crash della UI.
- [ ] Ogni fault ha un messaggio utente comprensibile.

**Output prodotto:** suite di resilienza.

---

### Step 10.2 — Security review

**Obiettivo:** trattare il daemon per ciò che è: una API ad alto privilegio.

**Prerequisiti:** 9.2.

**Componenti/file coinvolti:** `docs/security.md`, test dedicati.

**Implementazione:** checklist verificata con test automatici dove possibile — binding solo loopback; token 256 bit con permessi corretti e rotazione a ogni avvio; confronto token a tempo costante; validazione `Origin` e rifiuto delle origin non in allowlist; nessun endpoint che esegua comandi senza auth; nessun token in URL, log o messaggi di errore; limiti di dimensione dei frame e rate limiting; path traversal impossibile negli endpoint di tema/blob; redazione dei segreti nei log. Documenta il modello di minaccia e ciò che è esplicitamente fuori scope nell'MVP (multi-utente, accesso remoto).

**Test:** test negativi per ogni voce della checklist.

**Acceptance criteria:**
- [ ] Tutti i test negativi passano.
- [ ] `docs/security.md` completo e revisionato.

**Output prodotto:** baseline di sicurezza.

---

### Step 10.3 — Osservabilità, compatibilità e release

**Obiettivo:** poter diagnosticare i problemi degli utenti e aggiornare senza rompere.

**Prerequisiti:** 10.1, 10.2.

**Componenti/file coinvolti:** `src/telemetry/**`, `lib/features/settings/diagnostics.dart`, `.github/workflows/release.yml`.

**Implementazione:** log strutturati con id di correlazione (`clientId`, `sessionId`, `commandId`, `seq`), **solo locali**; pannello Diagnostica nella GUI (versioni, percorso Pi, stato daemon, ultimi errori, "esporta bundle diagnostico" con redazione automatica dei segreti); metriche locali (eventi/s, lag, code di uscita, worker vivi), visibili solo nel pannello Diagnostica, mai trasmesse. Per D16: **zero telemetria remota, in nessuna forma, nemmeno opt-in** — nessuna chiamata di rete verso servizi di analytics/crash-reporting è ammessa in nessun punto del codice; una code review che introduca anche solo una dipendenza di questo tipo va respinta a prescindere dalla motivazione. Il bundle diagnostico è generato e condiviso **solo su azione esplicita dell'utente** (mai upload automatico). Matrice di compatibilità testata in CI: `protocol 1` × {`v0.85.0`, ultima Pi disponibile} × {GUI vecchia/daemon nuovo, GUI nuova/daemon vecchio} — la negoziazione deve degradare, non crashare.

**Test:** test di compatibilità incrociata; test di redazione dei segreti nell'export diagnostico; test statico/lint che fallisce la build se compare una chiamata di rete verso domini non presenti nell'allowlist locale (`127.0.0.1`/`localhost`) nel codice del daemon o dell'app.

**Acceptance criteria:**
- [ ] Una GUI più vecchia del daemon si connette e funziona con le capability comuni.
- [ ] Il bundle diagnostico non contiene mai il token e non viene mai inviato automaticamente.
- [ ] Nessuna chiamata di rete in uscita verso host diversi da `127.0.0.1`/`localhost` esiste nel codice sorgente (verificato dal lint dedicato).

**Output prodotto:** release candidate.

---

## 8. Dependency graph

```text
0.1 Recon ──┬─> 1.1 Spec PCP ──┬─> 1.2 pcp-ts ──┐
            │                  └─> 1.3 Dart ────┤
            ├─> 0.4 fake-pi ───────────────┐    │
0.2 Bootstrap ─> 0.3 ADR                   │    │
                                           ▼    ▼
                          2.1 config ─> 2.2 server ──┐
                          2.3 transport <── 0.1,0.4  │
                          2.4 discovery <── 2.3      │
                          2.5 registry  <── 2.3,2.4  │
                          2.6 adapter   <── 1.1,2.3  │
                          2.7 journal   <── 2.5,2.6  │
                          2.8 dispatcher<── 2.2,2.5,2.6
                                           │
        3.1 shell ─> 3.2 PcpClient <───────┘
                     3.3 reducer  <── 1.3, 2.6
                     3.4 UI minima <── 3.2, 3.3
                                  │
                                  ▼
                     ★ 3.5 PROOF OF ARCHITECTURE (M1) ★
                                  │
             ┌────────────────────┼────────────────────┐
             ▼                    ▼                    ▼
        4.1 replay          5.1 controllo          6.1 theming
        4.2 multi-client    5.2 modello/thinking   6.2 transcript
        4.3 crash recovery  5.3 comandi /          6.3 tool timeline
             │                                     6.4 thinking
             └──> 6.5 extension UI <────────────────┘
                        │
            7.1 workspace ─> 7.2 context panel
            8.1 indice ────> 8.2 fork/clone/tree
                        │
            9.1 packaging daemon ─> 9.2 desktop/web
                        │
            10.1 fault ─> 10.2 security ─> 10.3 release
```

Percorso critico: **0.1 → 1.1 → 2.3 → 2.5 → 2.7 → 2.8 → 3.2 → 3.3 → 3.5**. Tutto il resto è parallelizzabile dopo M1.

---

## 9. Milestones

| ID | Nome | Contenuto | Definition of done |
|---|---|---|---|
| **M0** | Contract freeze | F0 + F1 | Schema, fixture, ADR, compatibilità Pi documentata |
| **M1** | **Proof of architecture** | F2 + F3 | Step 3.5 verde 20/20 in CI e verificato a mano con Pi reale |
| **M2** | Sessione affidabile | F4 + F5 | Reconnect, multi-client, crash recovery, steer/abort/follow-up/Esc |
| **M3** | Prodotto presentabile | F6 | Theming JSON, transcript ricco, tool timeline, extension UI |
| **M4** | Contesto e navigazione | F7 + F8 | Git/file changed, indice sessioni, fork/clone/tree |
| **M5** | Distribuibile | F9 | Installer Windows/macOS + web locale |
| **M6** | Hardened | F10 | Fault injection, security review, matrice di compatibilità |

**MVP = M1 + M2 + M3 (ridotta: theming + transcript + tool + extension UI) + M5.**
Post-MVP: M4 completo, operazioni Git in scrittura, terminale integrato via PTY, transport remoto, temi marketplace, multi-utente.

---

## 10. Decisioni confermate dal committente (18 settembre 2026)

Le decisioni elencate qui **non sono più aperte**: l'agente implementatore le esegue così come specificato, senza fermarsi a chiedere conferma. Ogni riga rimanda all'ADR corrispondente nella §3 per il dettaglio tecnico completo (motivo, trade-off, alternative scartate) — questa tabella è solo il riepilogo decisionale.

| # | Decisione | Valore confermato | ADR |
|---|---|---|---|
| 1 | Avvio del daemon | **Non è un servizio permanente.** La GUI lo avvia da sola alla bisogna, quando l'health check (`GET /api/health`) fallisce. | D8 |
| 2 | Retention del journal | **2.000 eventi o 8 MB (il primo limite raggiunto), spill conservato 24 ore.** | D7 |
| 3 | Packaging del daemon | **Binario sidecar Node SEA**, incluso nel bundle dell'app: l'utente non installa nulla oltre PiFrame. | D14 |
| 4 | Idle timeout dei worker Pi | **30 minuti di default, regolabile dall'utente** nella pagina Impostazioni di PiFrame (Step 5.4), via `daemon.setConfig` (Step 2.9). `0` = mai. Mai applicato a un worker che sta lavorando. | D9 |
| 5 | Versione minima di Pi supportata | **`v0.85.0`.** Verificata (non scelta) allo Step 0.1. | D15 |
| 6 | Bootstrap del token per il client Web | **Cookie `HttpOnly; SameSite=Strict`** impostato automaticamente quando si apre `http://127.0.0.1:<porta>/` dal browser sulla stessa macchina — nessun incolla manuale nel caso standard. | D11 |
| 7 | Telemetria | **Zero raccolta dati remota, in nessuna forma, nemmeno opt-in.** Solo log/diagnostica locale, esportabile manualmente dall'utente. | D16 |
| 8 | Font | **Inter (UI) + JetBrains Mono (codice) bundlati** nell'app, sostituibili dai temi JSON. | D17 |
| 9 | Più GUI sulla stessa sessione | **Sì: tutte vedono lo streaming in broadcast; solo una alla volta può rispondere a una dialog dell'agente**, tramite un meccanismo di prenotazione (claim/lease da 30 s, Step 4.2). | D10 |

**Punto non toccato da queste decisioni, invariato rispetto alla proposta originale:** lo shutdown per inattività del **daemon stesso** (distinto dal timeout dei singoli worker, voce 4) resta disattivato di default nell'MVP — una volta avviato, il daemon rimane vivo finché non lo si ferma esplicitamente o non si riavvia la macchina (dettaglio in D8). Non è stato oggetto di una decisione esplicita del committente; può essere rivisto in futuro senza alcun impatto sul protocollo o sull'architettura.

---

## 11. Risk register

| Rischio | Prob. | Impatto | Mitigazione |
|---|---|---|---|
| Pi cambia il protocollo RPC | Alta | Alto | `PiEventAdapter` isolato + golden fixture + `tools/recon/verify.ts` in CI + matrice a 2 versioni + capability probe |
| Perdita eventi in disconnessione | Media | Alto | `seq` monotono, journal + spill, snapshot, `journal.gap` esplicito, riconciliazione via cursore `get_entries{since}` |
| Prompt duplicato dopo reconnect | Media | Alto | `commandId` stabile, record con TTL, stato `deduplicated`, mai re-invio automatico dopo crash del worker |
| GUI lenta rallenta l'agente | Media | Medio | code di uscita bounded per client, lettura di stdout mai sospesa, degrado a snapshot, chiusura `4009` |
| Crash di Pi a metà operazione | Media | Alto | supervisor con policy conservativa, `crashed_held`, riconciliazione dal file di sessione, nessun retry automatico dei prompt |
| Due client rispondono alla stessa UI request | Media | Medio | claim/lease server-side, arbitraggio nel `UiRequestBroker` |
| Abuso del daemon locale dal browser | Bassa | Molto alto | loopback, token rotante, origin allowlist, CSP, nessun endpoint non autenticato che esegua azioni |
| Il packaging rompe l'installazione di Pi | Bassa | Alto | discovery non distruttiva, nessuna scrittura in `~/.pi/`, test di integrità della directory in CI |
| Dipendenza prematura da `pi-protocol`/`pi-server` sperimentali | Media | Medio | MVP solo su RPC stdio stabile; `PiTransport` come punto di estensione unico |
| Framing JSONL implementato male (readline/U+2028) | **Alta se disattenti** | Alto | framer scritto a mano + test dedicato con U+2028 dentro una stringa; divieto esplicito di `readline` nel codice |
| `message_update` trattato come cumulativo | Alta | Medio | reducer testato su fixture reali; regola documentata in due punti del piano |
| `partialResult` concatenato invece che sostituito | Alta | Medio | golden test sui tool con output progressivo |
| Performance Flutter su transcript lunghi | Media | Medio | liste virtualizzate, chiavi stabili, budget di test a 2.000 entry, throttling dei rebuild sui delta (coalescing a 16 ms) |
| Deriva dei tipi TS ↔ Dart | Media | Medio | codegen unico + job CI `codegen-drift` + fixture condivise |
| Scope creep su Git in scrittura | Media | Medio | separazione di modulo read/write, fuori MVP per decisione esplicita |

---

## 12. Testing matrix

| Livello | Cosa | Dove | Quando |
|---|---|---|---|
| **Unit TS** | framer JSONL, adapter eventi, journal/seq, dispatcher/idempotency, auth/handshake, git parser | `apps/agentd/test` | ogni commit |
| **Unit Dart** | reducer, codec protocollo, ThemeSpec/merge/lerp, client state machine | `apps/pi_frame/test` | ogni commit |
| **Contract** | fixture PCP valide/invalide su schema, parità TS↔Dart | `packages/pcp-spec` | ogni commit |
| **Golden** | fixture Pi reali → eventi PCP → stato del reducer; golden widget nei due temi | TS + Dart | ogni commit |
| **Integration** | daemon + `fake-pi`: prompt, steer, abort, clear queue, tool, extension UI, crash, idle, multi-sessione | `apps/agentd/test/integration` | ogni PR |
| **Integration reale** | daemon + Pi reale: prompt breve, tool call, compaction | job CI opzionale con chiave | nightly |
| **E2E desktop** | GUI → daemon → Pi → GUI (`integration_test` Flutter) | `test/e2e` | ogni PR |
| **E2E browser** | Playwright contro il daemon locale | `test/e2e` | ogni PR |
| **E2E background** | chiudi GUI → l'agente continua → riapri → replay (Step 3.5) | `test/e2e` | ogni PR, 20 ripetizioni |
| **Fault injection** | drop WS, riavvio daemon, crash Pi, JSONL parziale, client lento, eventi ritardati/duplicati, comandi malformati | `test/e2e/faults` | ogni PR |
| **Performance** | 2.000 entry a ≥ 55 fps; 10.000 eventi nel journal; 500 sessioni nell'indice; output tool da 5 MB | benchmark | nightly |
| **Sicurezza** | test negativi §10.2 | `apps/agentd/test/security` | ogni PR |
| **Compatibilità** | Pi `v0.85.0` (minima) / ultima disponibile × GUI/daemon vecchio-nuovo | matrice CI | nightly |
| **Accessibilità** | contrasto AA dei temi bundlati, navigazione da tastiera, focus visibile | Dart test + checklist manuale | per release |
| **Manuale** | install pulita Win/macOS, `~/.pi/` intatto dopo disinstallazione, sessione lunga reale | checklist `docs/release-checklist.md` | per release |

---

## 13. Acceptance checklist finale

**Comunicazione**
- [ ] La UI principale non dipende da alcun PTY.
- [ ] `pi --mode rpc` è il transport verso Pi; il framing JSONL è strict LF e non usa `readline`.
- [ ] Il daemon legge stdout/stderr di Pi indipendentemente dallo stato dei client.
- [ ] Gli eventi arrivano in tempo reale (delta di testo visibili < 100 ms dall'emissione).
- [ ] Flutter riceve **eventi PCP normalizzati**, mai JSONL grezzo di Pi (salvo capability di debug).

**Lifecycle**
- [ ] Chiudere PiFrame non termina Pi.
- [ ] Una sessione attiva resta gestibile e osservabile dopo la chiusura della GUI.
- [ ] Riaprendo la GUI: reconnect + snapshot/replay senza buchi né duplicati.
- [ ] Il crash di un worker non duplica operazioni e non perde la sessione persistita.

**Sessioni**
- [ ] Sessioni multiple simultanee, un processo Pi per sessione live.
- [ ] Sessioni persistenti numerose con pochi worker vivi.
- [ ] Le sessioni restano pienamente compatibili con il CLI di Pi (aperte da entrambi).

**Streaming**
- [ ] Testo progressivo, thinking progressivo (quando presente), tool progressivo.
- [ ] `run.ended` e `run.settled` distinti e visibili nella UI.
- [ ] Retry, compaction e coda hanno uno stato visivo dedicato.

**Controllo**
- [ ] prompt · steer · follow-up · abort · clear queue · interrupt (Esc con ripristino del testo) · risposta a extension UI.
- [ ] Nessun comando non idempotente eseguito due volte.

**Workspace**
- [ ] File modificati rilevati (anche fuori dai tool di Pi).
- [ ] Git: branch, dirty, changed files, diff base.

**Theming e design**
- [ ] Temi custom JSON caricati da `~/.piframe/themes/` con hot reload.
- [ ] Un tema minimale (pochi token) funziona grazie all'ereditarietà.
- [ ] Tema corrotto ⇒ avviso, non crash.
- [ ] Nessun colore hard-coded nei widget.
- [ ] Layout responsive a 1/2/3 colonne; contrasto AA sui temi ufficiali.

**Installabilità**
- [ ] Pi installabile e aggiornabile in modo indipendente; la GUI lo rileva.
- [ ] Disinstallando PiFrame, `~/.pi/` e le sessioni restano intatte.

**Piattaforme**
- [ ] Windows · macOS · browser su `http://127.0.0.1:<port>/`.

**Sicurezza**
- [ ] Solo loopback, token rotante con permessi corretti, origin validata, nessun endpoint di comando non autenticato.
- [ ] Il client Web ottiene il token via cookie `HttpOnly` al primo accesso locale, senza copia-incolla manuale.
- [ ] **Zero telemetria remota**: nessuna chiamata di rete verso host diversi da `127.0.0.1`/`localhost` in tutto il codice sorgente (daemon + app); il bundle diagnostico non viene mai inviato automaticamente.

---

## 14. Future evolution

1. **Transport Pi remoto.** Quando `pi-protocol`/`pi-server` saranno stabili, si implementa `RemotePiTransport` dietro la stessa interfaccia `PiTransport`. Flutter **non cambia**: è la verifica finale che il confine è stato tracciato nel punto giusto.
2. **Daemon remoto.** PCP è già pensato per WSS + autenticazione più forte: aggiungere TLS, un auth provider e un modello di identità basta a supportare `Flutter Web → daemon su workstation remota`. Da non implementare prima che M6 sia chiusa.
3. **Terminale integrato via PTY.** Modalità secondaria (§4 del brief): utile per la TUI originale di Pi e per il debug, mai come transport principale.
4. **Git in scrittura.** Stage, commit, branch, revert dei file toccati dall'agente, riusando la separazione read/write già presente.
5. **Marketplace/condivisione di temi.** Il formato JSON versionato con `$schema` lo rende immediato; serve solo un importer con validazione e sandbox dei font.
6. **Multi-utente / team.** Fuori scope architetturale attuale: richiederebbe identità, autorizzazione per sessione e isolamento dei workspace nel daemon.
7. **Session diffing e replay temporale.** Il journal + l'albero delle entry di Pi rendono possibile uno "scrub" temporale della sessione.

---

## Appendice A — Riferimenti verificati su Pi

Verificati durante la stesura di questo piano contro `earendil-works/pi@main` (da riconfermare allo Step 0.1):

- Avvio: `pi --mode rpc`; opzioni utili `--provider`, `--model`, `--name/-n`, `--no-session`, `--session-dir`.
- Framing: JSONL con **LF come unico delimitatore**; accettare `\r\n` togliendo il `\r`; **non** usare `readline` di Node (splitta anche su U+2028/U+2029, legali dentro le stringhe JSON).
- Correlazione: campo `id` opzionale sui comandi, riportato nella `response`; `bash_execution_update` porta l'`id` del comando `bash` originario.
- Comandi: `prompt`, `steer`, `follow_up`, `abort`, `clear_queue`, `new_session`, `get_state`, `get_messages`, `set_model`, `cycle_model`, `get_available_models`, `set_thinking_level`, `cycle_thinking_level`, `get_available_thinking_levels`, `set_steering_mode`, `set_follow_up_mode`, `compact`, `set_auto_compaction`, `set_auto_retry`, `abort_retry`, `bash`, `abort_bash`, `get_session_stats`, `export_html`, `switch_session`, `fork`, `clone`, `get_fork_messages`, `get_entries`, `get_tree`, `get_last_assistant_text`, `set_session_name`, `get_commands`.
- `prompt` durante lo streaming **richiede** `streamingBehavior: "steer" | "followUp"`, altrimenti errore.
- `clear_queue` restituisce i testi rimossi (`steering`, `followUp`): è ciò che consente la semantica Esc del terminale (clear queue → abort → ripristino nel composer).
- `abort` risponde **solo** quando la sessione è tornata idle.
- Eventi: `agent_start`, `agent_end` (con `willRetry`), `agent_settled`, `turn_start`, `turn_end`, `message_start`, `message_update`, `message_end`, `bash_execution_update`, `tool_execution_start/update/end`, `queue_update`, `compaction_start/end`, `auto_retry_start/end`, `summarization_retry_scheduled/attempt_start/finished`, `extension_error`.
- `message_update` contiene `assistantMessageEvent` (`text_start|delta|end`, `thinking_start|delta|end`, `toolcall_start|delta|end`) e **non** un messaggio cumulativo; il client assembla per `contentIndex` e considera `message_end.message` autorevole.
- `tool_execution_update.partialResult` è **cumulativo** (sostituire, non concatenare); correlazione via `toolCallId`.
- Extension UI: dialog (`select`, `confirm`, `input`, `editor`) attendono `extension_ui_response` con `id` corrispondente; `notify`, `setStatus`, `setWidget`, `setTitle`, `set_editor_text` sono fire-and-forget. I `timeout` sono gestiti da Pi, non dal client.
- Sessioni: JSONL con entry ad albero (`id`/`parentId`, versione 3), in `~/.pi/agent/sessions/--<path>--/<timestamp>_<uuid>.jsonl`. `get_entries{since}` usa l'`entryId` come **cursore durevole** fra riavvii del client.

## Appendice B — Comandi rapidi per l'agente implementatore

```bash
make setup           # installa dipendenze Node + Flutter, genera i tipi
make codegen         # schema JSON -> tipi TS e Dart
make test            # unit + contract + integration (senza rete, usa fake-pi)
make test:e2e        # end-to-end desktop + browser
make run:daemon      # daemon in foreground con log verboso
make run:app         # app Flutter su desktop
PI_FRAME_PI_PATH=./tools/fake-pi/bin/fake-pi make run:daemon   # sviluppo senza API key
```

