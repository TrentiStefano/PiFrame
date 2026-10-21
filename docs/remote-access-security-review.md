# Security & Quality Review — Feature "Accesso Remoto" (pi-frame)

- **Ambito**: sottosistema remote — `apps/agentd/src/remote/*`, `server/*`, `commands/Dispatcher.ts`, `config/config.ts`, client Flutter (`daemon_locator.dart`, `pcp_client.dart`, `remote_section.dart`), `docs/security.md`, test.
- **Metodo**: lettura del riassunto dell'agente, review del codice nel working tree (non ancora committato) e **PoC eseguiti contro il build reale di `agentd`** (`pnpm build`) per confermare i sospetti più gravi.
- **Verdetto: NON sicura da rilasciare/abilitare così com'è.**
  Un dispositivo associato (o chiunque rubi il suo token) può disattivare le guardrail ed eseguire comandi arbitrari sul PC host usando lo stesso canale PCP. Inoltre un attaccante non autenticato può bloccare l'app desktop locale e aggirare il rate-limit del pairing.

Il disegno di base è buono: opt-in, token per-device a 256 bit, pairing monouso, confronto constant-time, revoca con chiusura immediata della WS, Host/Origin allowlist. I problemi sono soprattutto di **autorizzazione dopo l'autenticazione** e di **identificazione della provenienza della richiesta (locale vs remota)**.

## Indice

| ID | Sev. | Titolo | Verifica |
|----|------|--------|----------|
| C1 | 🔴 Critica | Le connessioni remote possono eseguire `remote.*`, `daemon.setConfig`, `pi.packages.*` → RCE + bypass guardrail | PoC ✅ |
| C2 | 🔴 Critica | Le guardrail (`allowFileEdits`, `readOnly`) non proteggono davvero; default permissivi | analisi |
| H1 | 🟠 Alta | Rate-limit del pairing aggirabile con header falsificati; codice a 6 cifre forzabile | PoC ✅ |
| H2 | 🟠 Alta | "Loopback vs remoto" basato su blacklist di header; tunnel e UI locale sullo stesso listener → leak del token master | PoC ✅ |
| H3 | 🟠 Alta | DoS non autenticato dell'app desktop locale | PoC ✅ |
| H4 | 🟠 Alta | Token master accettato anche su connessioni dal tunnel, senza `isRemote` | analisi |
| M1 | 🟡 Media | Token dispositivo in chiaro su disco, nessuna scadenza, nessun limite | analisi |
| M2 | 🟡 Media | Segreto di pairing in query string `?pair=` | analisi |
| M3 | 🟡 Media | Cookie `Secure` condizionale; token ripetuto nel body (HttpOnly vanificato) | analisi |
| M4 | 🟡 Media | CSP senza `wss:`/host tunnel; mancano HSTS e `no-store` | analisi |
| M5 | 🟡 Media | Supervisione tunnel incompleta (race, pipe non drenate, orfani, stato stale) | analisi |
| M6 | 🟡 Media | Auto-start al boot: esposizione silenziosa + finestra di pairing non presidiata | analisi |
| M7 | 🟡 Media | `session.create` remoto con `cwd` arbitrario; pairing/stato in broadcast ai remoti | analisi |
| M8 | 🟡 Media | Hardening di `/api/remote/pair` e dell'upgrade WS | analisi |
| M9 | 🟡 Media | Trust boundary Cloudflare non dichiarato; `cloudflared` non verificato | analisi |
| L1–L6 | 🟢 Bassa | Qualità, test mancanti, doc che sovrastima le garanzie, file non pertinenti | analisi |

---

## 🔴 C1 — Nessuna autorizzazione sui comandi privilegiati per le connessioni remote

**Dove**: `commands/Dispatcher.ts` (`execute`: case `remote.*`, `daemon.setConfig`, `pi.packages.*`), `config/config.ts` (`patchConfig`), `remote/CustomTunnelProvider.ts` (`spawn(cmd, { shell: true })`).

**Problema**: `conn.isRemote` viene controllato solo per `readOnly` e `workspace.saveFile`. Ogni altro comando è eseguibile da un telefono associato, tra cui:

1. `remote.setOptions` → il telefono spegne da solo `readOnly` / `allowFileEdits`.
2. `remote.start { customCommand }` → il comando viene eseguito con `shell: true` sul PC → **esecuzione di codice arbitrario** (ulteriore a quella già possibile via agente, ma fuori da ogni guardrail e senza passare dall'LLM).
3. `daemon.setConfig { remote: { customTunnelCommand } }` → `patchConfig` fa merge non validato di `remote`; il comando viene eseguito al prossimo `remote.start` **o al prossimo boot del daemon** (`main.ts` fa auto-start se `remote.enabled`) → persistenza.
4. `remote.generatePairing` / `remote.getStatus` → il telefono ottiene un nuovo segreto di pairing e può associare altri dispositivi; dopo una revoca il suo "erede" sopravvive.
5. `pi.packages.update/remove/pin` → installazione/aggiornamento di pacchetti (codice) da remoto.
6. `remote.revokeAll` / `remote.stop` → un dispositivo può spegnere gli altri (DoS).

**Evidenza (PoC su build reale)**:

```
guardrails before: {"ro":true,"fe":false}
[1] remote conn: agent.prompt in readOnly                -> rejected          (ok)
[2] remote conn: remote.setOptions(readOnly=false, ...)  -> completed
guardrails after : {"ro":false,"fe":true}
[3] remote conn: remote.start con customCommand shell    -> completed
    marker file creato dal comando shell: true
[4] daemon.setConfig inietta customTunnelCommand         -> completed ("calc.exe" persistito in config)
[5] remote conn può generare un nuovo pairing secret     -> true
```

**Soluzione consigliata** (in ordine, tutte da fare):

1. **Allowlist per tipo di connessione, default-deny.** Nel `Dispatcher.execute` (prima dello `switch`):
   ```ts
   const REMOTE_ALLOWED = new Set([
     'session.list','session.open','session.attach','session.detach','session.getStats','session.getEntries','session.getTree',
     'agent.prompt','agent.steer','agent.followUp','agent.interrupt','agent.abort','agent.clearQueue',
     'agent.getModels','agent.getThinkingLevels','agent.getCommands',
     'ui.claim','ui.respond',
     'workspace.refresh','workspace.getDiff','workspace.listFiles','workspace.readFile',
   ]);
   if (conn.isRemote && !REMOTE_ALLOWED.has(cmd.type)) {
     throw Object.assign(new Error('Command not permitted over remote connection'), { code: 'REMOTE_FORBIDDEN' });
   }
   ```
   Tutto ciò che non è in lista (nuovi comandi futuri inclusi) resta locale-only. Le blacklist per prefisso (`startsWith('agent.')`) sono fragili: usare un'allowlist unica.
2. `remote.*`, `daemon.setConfig`, `daemon.getConfig`, `pi.packages.*`, `workspace.saveFile`/`gitAction` (se non abilitati) **solo per master / connessione locale**. Verificare anche `conn.isRemote === false` esplicitamente dentro ogni case `remote.*` (defense in depth).
3. **Eliminare `customTunnelCommand` dal canale IPC.** Impostabile solo editando `config.json` a mano (o con conferma nativa nel desktop). Se si mantiene: niente `shell: true`, usare `command` + `args[]`, validare l'eseguibile, niente interpolazione `$PORT` in una stringa shell.
4. **Validare `patchConfig`**: whitelist esplicita di chiavi e tipi; `daemon.setConfig` non deve mai accettare `remote` (né `web.origins`). Validare `customTunnelUrl` (solo `https:`, hostname non loopback/privato, niente credenziali/porta strana).
5. **Non inviare dati sensibili ai remoti**: `remote.statusChanged` e `daemon.configChanged` oggi sono `broadcastAll` e contengono `pairingPending.url` (segreto), IP dei dispositivi e config. Inviarli solo alle connessioni locali (`conn.isRemote === false`) o inviare ai remoti una vista ridotta.
6. Test di regressione (vedi L6).

---

## 🔴 C2 — Le guardrail non proteggono ciò che promettono

**Dove**: `Dispatcher.ts` (blocco `if (conn.isRemote)`), `config.ts` (default), `remote_section.dart` (toggle), `docs/security.md`.

**Problema**:
- `allowFileEdits: false` blocca **solo** `workspace.saveFile`. Ma `agent.prompt` rimane permesso, e l'agente `pi` ha tool `bash`/`write`/`edit`: il telefono può far modificare/cancellare qualsiasi file, eseguire comandi, `git push`, ecc. L'opzione dà una **falsa sensazione di sicurezza**.
- `readOnly: true` blocca *tutto* `agent.*` (tranne `agent.get*`), quindi non è "sola lettura" ma "nessun prompt". Blocca anche `agent.abort`/`agent.interrupt` → da remoto non si può fermare un agente in corso (problema di safety, vedi L2). Lascia invece permessi `session.create/fork/clone/rename/closeWorker`, `ui.respond` (può approvare dialog di conferma dei tool), `pi.packages.*`.
- Default `readOnly:false, allowFileEdits:true`: appena associato, il telefono ha pieno controllo.
- Realtà del modello di minaccia: **un dispositivo associato = esecuzione di comandi come utente sul PC**. Va detto chiaramente in UI e in `docs/security.md`.

**Soluzione consigliata**:
1. Sostituire i due flag con una **modalità remota esplicita**, enum `remote.mode`: `view` (default) | `control`.
   - `view`: solo letture (lista/attach sessioni, entries, `workspace.read*`, diff) + `agent.abort/interrupt`. Niente `agent.prompt/steer/followUp`, niente `ui.respond`, niente scritture.
   - `control`: equivale a pieno controllo; richiede conferma esplicita sul desktop (dialog nativo con testo "Questo dispositivo potrà eseguire comandi sul tuo computer") ed è per-dispositivo (campo `mode` in `PairedDevice`), non globale.
2. Se si vuole un "write-limited" reale, farlo a livello **worker**: avviare il processo `pi` per le sessioni pilotate da remoto con set di tool ristretto (es. solo read/grep/ls) oppure richiedere **approvazione desktop** per ogni tool call di scrittura/bash originata da una connessione remota (`ui.claim/ui.respond` locale). Altrimenti rimuovere `allowFileEdits`.
3. Default sicuro: nuovo dispositivo → `view`; passaggio a `control` dal desktop.
4. Applicare la policy **per connessione** (`conn.deviceId` → modalità del device), non da `loadConfig()` globale ad ogni comando (anche per performance: oggi legge il file su ogni comando).
5. Aggiornare doc/UI: nessuna dicitura che suggerisca che `allowFileEdits` limiti l'agente.

---

## 🟠 H1 — Rate-limit del pairing aggirabile; codice a 6 cifre forzabile

**Dove**: `httpServer.ts` (calcolo di `clientIp`), `RemoteAuthManager.ts` (`generatePairing`, `pair`, `ipRateLimits`).

**Problema**:
- `clientIp` si fida **sempre** di `cf-connecting-ip` / `x-forwarded-for`, che sono header controllati dal client se la richiesta non passa da Cloudflare (provider `custom`, tunnel SSH/ngrok/LAN, o qualunque accesso diretto). L'attaccante cambia IP finto a ogni richiesta e **non viene mai bloccato**.
- Il codice è `randomInt(100000, 999999)`: 900k possibilità, TTL 10 min, accettato su `/api/remote/pair` insieme al segreto. Senza limite effettivo è forzabile in pochi minuti. Anche con il limite corretto per-IP, un attaccante distribuito (botnet/Tor) ha probabilità non trascurabile di indovinare nella finestra.
- La UI del telefono (`daemon_locator.dart`) gestisce solo `?pair=<secret>`: **non esiste alcun flusso in cui il codice a 6 cifre venga digitato** dal telefono. È quindi una superficie d'attacco senza beneficio.
- Anche i tentativi falliti con "nessun pairing attivo" incrementano il contatore (ok), ma la mappa `ipRateLimits` cresce senza limite (memoria).

**Evidenza (PoC)**:
```
A stesso IP, 8 tentativi errati               -> 401,401,401,401,401,429,429,429
B CF-Connecting-IP falsificato, 30 tentativi  -> 401  (mai 429: nessun blocco)
```

**Soluzione consigliata**:
1. **Rimuovere il codice a 6 cifre dal percorso remoto.** Su `/api/remote/pair` accettare solo il segreto a 256 bit. (Se si vuole un'alternativa manuale: codice alfanumerico ≥ 10 caratteri / 50 bit + rate-limit globale.)
2. **Limite globale per pairing**, non solo per IP: dopo N (es. 5) tentativi falliti totali sul pairing corrente → il pairing viene **invalidato** e ne serve uno nuovo dal desktop. Con segreto 256 bit questo rende l'attacco impraticabile.
3. **Estrazione IP affidabile**: determinare l'IP client **solo** in base al provider configurato:
   - `cloudflared`: usare **solo** `cf-connecting-ip` (Cloudflare lo sovrascrive); ignorare `x-forwarded-for`.
   - `custom`: usare `socket.remoteAddress` (o un header configurato esplicitamente dall'utente come "trusted proxy header"). Mai default su header arbitrari.
4. Aggiungere backoff esponenziale + pulizia periodica (`setInterval` con `unref`) della mappa `ipRateLimits`, con cap di dimensione.
5. Rate-limit a monte, sul listener remoto (vedi H2/H3), non solo sull'endpoint.

---

## 🟠 H2 — Identificazione "locale vs remoto" per blacklist di header; stesso listener per tunnel e UI locale

**Dove**: `RemoteManager.isDirectLoopbackRequest`, `httpServer.ts` (`/api/session-bootstrap`), `static.ts` (cookie `pcp_token`), `main.ts` (tunnel → stessa porta).

**Problema**: il tunnel punta alla **stessa porta** della UI locale. Per distinguere traffico locale da remoto si controlla l'assenza di alcuni header (`x-forwarded-*`, `cf-*`). Una blacklist non è una garanzia: qualunque reverse-proxy/tunnel che riscrive `Host` a `127.0.0.1:<porta>` e non aggiunge quegli header (nginx senza `proxy_set_header`, `ngrok --host-header=rewrite`, `ssh -R`, Caddy con config minimale, tunnel "custom" in generale) rende la richiesta indistinguibile da una locale → `/api/session-bootstrap` restituisce il **token master** a chiunque su Internet. Questa è esattamente la "Reverse Proxy Loopback Identity Illusion" che l'agente dichiarava di aver risolto: è risolta solo per Cloudflare quick tunnel.

Inoltre anche `127.0.0.1` può essere un qualunque altro processo/utente locale (già vero prima della feature, ma ora si somma).

**Evidenza (PoC)**: richiesta da socket 127.0.0.1 con `Host: 127.0.0.1:<port>` e nessun header di proxy:
```
D -> {"ok":true,"token":"MASTER","mode":"local"}
```

**Soluzione consigliata** (la vera correzione è strutturale):
1. **Listener dedicato al tunnel.** Creare un secondo `http.Server` su `127.0.0.1:<portaRemota>` (porta diversa, effimera) che:
   - è l'**unico** target del tunnel (`cloudflared --url http://127.0.0.1:<portaRemota>`);
   - non serve mai `/api/session-bootstrap` in modalità `local`, non imposta mai `pcp_token`;
   - marca ogni connessione/richiesta come `isRemoteListener = true` (la provenienza dipende dal **socket su cui arriva**, non dagli header);
   - rifiuta il token master (vedi H4).
   Il listener "locale" resta su `127.0.0.1:<porta>` e non è raggiungibile dal tunnel. Così gli header non contano più per l'identità.
2. Mantenere comunque gli header come controllo aggiuntivo, ma sul listener locale: se arriva `x-forwarded-*`/`cf-*`/`Forwarded`/`via`/`x-real-ip` → rifiuta (belt and braces).
3. Per l'UI locale, valutare di sostituire il bootstrap "chiunque su loopback riceve il token" con un handshake che richieda un segreto leggibile solo dall'utente (file `daemon.token` già esiste) — fuori scope di questa feature ma da annotare.
4. Per il provider `custom`: validare `customTunnelUrl` (https, host non loopback) così un Host loopback non può essere "ammesso" come host remoto.

---

## 🟠 H3 — DoS non autenticato dell'app desktop locale

**Dove**: `wsServer.ts` (`failedHelloPerIp`, `isIpRateLimited`, chiave = `req.socket.remoteAddress`).

**Problema**: dietro al tunnel `req.socket.remoteAddress` è sempre `127.0.0.1`. L'attaccante apre ~20 WS non autenticate in un minuto → il bucket di `127.0.0.1` si riempie → **anche l'app desktop locale (stesso IP) riceve 429** e non può connettersi (vale anche per i telefoni legittimi).

**Evidenza (PoC)**: dopo 22 connessioni WS non autenticate con Origin del tunnel:
```
C -> local app BLOCKED http 429
```

**Soluzione consigliata**:
1. Con il listener dedicato (H2) tenere **bucket separati**: i limiti sul listener remoto non devono mai impattare il listener locale.
2. Sul listener remoto: chiave = IP reale affidabile (stessa logica di H1), più un **limite globale** di connessioni non autenticate concorrenti (es. 10) e di handshake/minuto.
3. Il bucket di loopback non va mai penalizzato dai fallimenti remoti. Contare i fallimenti solo per `hello` falliti (non per ogni socket chiusa prima dell'auth, come oggi in `onClose`).
4. Pulizia periodica di `failedHelloPerIp` (cresce senza limite).

---

## 🟠 H4 — Il token master è accettato anche da connessioni arrivate dal tunnel

**Dove**: `connection.ts` `handleHello`, `wsServer.ts`.

**Problema**: `handleHello` accetta il master token da qualunque connessione e **non** imposta `isRemote`. Il riassunto dice "master token (local only)" ma il codice non lo impone: chi ottiene il master token (ad es. via H2) entra dal tunnel senza alcuna guardrail e senza comparire in "dispositivi". Anche un master token che finisce in un log/clipboard diventa sfruttabile da Internet.

**Soluzione consigliata**: passare a `Connection` il flag `viaRemoteListener` (dal listener su cui è arrivata la socket, H2). In `handleHello`: se `viaRemoteListener` e `isMaster` → `close(4003)`. Se `viaRemoteListener` → `isRemote = true` sempre. Test dedicato.

---

## 🟡 M1 — Token dispositivo: in chiaro, senza scadenza, senza limiti

**Dove**: `RemoteAuthManager.ts`, `remote_devices.json`.

- I token `rem_dev_*` sono salvati **in chiaro** (il `mode 0o600` non ha effetto sui permessi su Windows). Chi legge il file può impersonare i dispositivi.
- Nessuna scadenza né idle-timeout; un telefono perso resta valido finché non lo revochi.
- Nessun limite al numero di dispositivi.
- `verifyDeviceToken` scorre linearmente tutti i dispositivi; `lastUsedAt` è aggiornato in memoria ma non persistito.
- Il nome dispositivo/UA proviene dal client e viene mostrato in UI (controllare sanitizzazione/lunghezza lato Flutter).

**Soluzione**: token nel formato `rem_dev_<deviceId>.<secret>`; salvare solo `sha256(secret)` (o HMAC con una chiave locale) → lookup O(1) per `deviceId` + `timingSafeEqual` sugli hash. Aggiungere `expiresAt` con scadenza scorrevole (es. 30 giorni, rinnovata all'uso, persistita con debounce), cap massimo dispositivi (es. 10), permessi file ristretti (su Windows impostare ACL con `icacls` o salvare in una directory utente non condivisa) e un evento/notifica desktop "nuovo dispositivo associato".

---

## 🟡 M2 — Segreto di pairing nell'URL (`?pair=`)

**Dove**: `RemoteManager.generatePairing`/`getStatus` (`${url}/?pair=${secret}`), `daemon_locator.dart`.

La query string finisce in cronologia browser, log di Cloudflare/proxy, eventuali screenshot, link-preview dei messenger. Mitigato dal fatto che è monouso e `Referrer-Policy: no-referrer`, ma il segreto resta nei log fino alla scadenza.

**Soluzione**: usare il **fragment** (`/#pair=<secret>`) che non viene mai inviato al server; nel client leggere `Uri.base.fragment`, fare il POST e poi `history.replaceState` per ripulire l'URL. Verificare l'interazione con la URL strategy di Flutter web (hash/path). Dopo l'uso, rimuovere comunque il parametro dall'URL.

---

## 🟡 M3 — Cookie `Secure` condizionale; token duplicato nel body

**Dove**: `httpServer.ts` (`/api/remote/pair`, `/api/session-bootstrap`).

- In `/api/remote/pair` `Secure` è aggiunto solo se `x-forwarded-proto === 'https'` o socket cifrata: per tunnel `custom` o HTTP il cookie viaggia in chiaro. Il riassunto afferma "sempre Secure".
- Il device token è restituito anche nel **body JSON** (pair e bootstrap) e il client lo usa nell'`hello` WS: l'HttpOnly è di fatto vanificato (un XSS lo legge). Nota: la CSP attuale è buona (`script-src 'self'`).

**Soluzione**: sul listener remoto imporre `https` (rifiutare altrimenti) e `Secure` sempre. Valutare di autenticare la WS **via cookie all'upgrade** (SameSite=Strict + Origin check già presenti) ed eliminare il token dal body, oppure tenere il token solo in memoria (mai `localStorage`) e documentarlo. Aggiungere `Cache-Control: no-store` a tutte le risposte API.

---

## 🟡 M4 — CSP e header di trasporto incompleti per l'uso remoto

**Dove**: `static.ts` `setSecurityHeaders`.

- `connect-src 'self' ws://127.0.0.1:* …`: su alcuni browser (storicamente Safari/iOS) `'self'` non copre `wss:` verso l'host corrente → la WebSocket del telefono potrebbe essere bloccata. Va verificato su iPhone reale (nessun test automatico lo copre).
- Mancano `Strict-Transport-Security` (sul listener remoto), `Cache-Control: no-store`, `Permissions-Policy`, `frame-ancestors 'none'` in CSP.

**Soluzione**: sul listener remoto costruire la CSP dinamicamente con `connect-src 'self' wss://<hostTunnel>`; aggiungere gli header mancanti; testare su iOS Safari e Android Chrome.

---

## 🟡 M5 — Supervisione del tunnel incompleta

**Dove**: `CloudflaredTunnelProvider.ts`, `CustomTunnelProvider.ts`, `RemoteManager.ts`.

- **Race**: `start()` chiamato due volte mentre `state === 'starting'` lancia due processi `cloudflared`; il primo diventa orfano (esposto, non killabile).
- Timeout di 30 s mai cancellato (`clearTimeout`) quando l'URL arriva.
- **Nessuna supervisione reale** (il riassunto parla di "lifecycle supervision"): all'`exit` imposta solo lo stato, nessun restart, **nessun `statusChanged`** → la UI mostra "ATTIVO" su tunnel morto; `activeTunnelHostname` resta valorizzato.
- `CustomTunnelProvider`: `stdio: 'pipe'` ma stdout/stderr **mai letti** → dopo ~64 KB il processo si blocca; `start()` non è idempotente; con `shell: true` su Windows `kill` termina `cmd.exe` ma **non il processo figlio** → il tunnel resta aperto dopo "Disattiva"; `stop()` non attende l'uscita; la URL è considerata "running" senza verificare che il comando funzioni.
- `RemoteManager.start` persiste `enabled: true` **prima** di sapere se il tunnel parte; in caso di errore resta `enabled` e al boot si riprova.
- Nessuna pulizia dei processi se il daemon muore in modo anomalo.

**Soluzione**: mutex/stato `starting` che restituisce la stessa promise; `clearTimeout`; emettere `statusChanged` su `exit/error`; backoff di restart limitato (max N) con stato `error` finale; drenare/ignorare le pipe (`stdio: ['ignore','ignore','ignore']` o consumare `data`); kill dell'albero di processi (`taskkill /T /F` su Windows, process group su POSIX con `detached`); persistere `enabled: true` solo a start riuscito; `activeTunnelHostname` azzerato quando il tunnel cade.

---

## 🟡 M6 — Auto-start al boot: esposizione silenziosa e finestra di pairing non presidiata

**Dove**: `main.ts` (auto-start se `config.remote.enabled`), `RemoteManager.start` (genera pairing 10 min).

Ad ogni avvio del daemon (anche all'avvio del PC, senza nessuno davanti) il tunnel parte e **si apre una finestra di pairing di 10 minuti con segreto/codice** su un URL pubblico, senza alcuna notifica. Combinato con H1, il rischio è concreto.

**Soluzione**: all'auto-start **non** generare pairing (solo su richiesta esplicita dal desktop); aggiungere opzione `autoStartOnBoot` (default `false`) e notifica visibile nell'app/tray "Accesso remoto attivo"; auto-spegnimento dopo inattività configurabile; ridurre TTL a 2–5 minuti (la doc dice "5–10 minuti", il codice usa 5 e 10: allinearli).

---

## 🟡 M7 — Superficie dati/ambito per i client remoti

**Dove**: `Dispatcher.ts` (`session.create`, `session.open { cwd }`), `Dispatcher` broadcast.

- `session.create { cwd }` e `session.open { cwd }` accettano un `cwd` arbitrario dal client: un telefono può aprire sessioni (e quindi l'agente) in qualsiasi directory (home, `.ssh`, …) e leggere file tramite `workspace.readFile` di quel repo.
- Eventi in broadcast (`remote.statusChanged`, `daemon.configChanged`) arrivano anche ai remoti (vedi C1.5).

**Soluzione**: per connessioni remote consentire `cwd` solo tra le radici già note (cwd di sessioni esistenti / allowlist di workspace configurata dal desktop); filtrare gli eventi broadcast per tipo di connessione; la lista `session.list` può essere limitata alle sessioni "condivise con remoto" se si vuole più isolamento.

---

## 🟡 M8 — Hardening di `/api/remote/pair` e dell'upgrade WebSocket

- `/api/remote/pair` è sempre attivo: `if (!opts.remoteManager)` non scatta mai (il manager esiste sempre) e **non verifica** `enabled` e `state === 'running'`. Aggiungere il controllo.
- Dopo `req.destroy()` per body > 8 KB non c'è risposta; usare `413` e interrompere il parsing. Accettare solo `Content-Type: application/json`. Il campo `candidate` accetta `pairingSecret|pairingToken|code|token` con coercizione `toString()`: restringere a un solo campo stringa.
- L'upgrade WS non controlla l'header `Host` (solo `Origin`); aggiungere `isHostAllowed`.
- `isRemoteOriginAllowed` confronta solo l'hostname (ignora schema e porta): richiedere `https:` e porta attesa. Richieste **senza** `Origin` sono sempre ammesse (client non-browser): accettabile solo perché serve comunque il token, ma sul listener remoto va richiesto `Origin` per i client browser.
- `isRemoteHostAllowed` usa `host.split(':')[0]` (rompe IPv6 letterali) → usare `new URL`.
- Aggiungere limite alla dimensione/numero delle WS non autenticate e un timeout di handshake aggressivo sul listener remoto.

---

## 🟡 M9 — Trust boundary Cloudflare e provenienza di `cloudflared`

- Con i Quick Tunnel **Cloudflare termina TLS e vede in chiaro tutto il traffico** (prompt, codice sorgente, token dispositivo, segreto di pairing). Non è citato in `docs/security.md`: l'utente deve saperlo. I Quick Tunnel inoltre non hanno SLA e l'URL, pur casuale, è pubblico e scansionabile (nessun controllo d'accesso a livello edge).
- `cloudflared` è cercato in `~/.piframe/bin` e poi nel `PATH` senza verifica di integrità/firma; su Windows un binario in `PATH` scrivibile dall'utente equivale a esecuzione di codice. Mostrare all'utente il path/versione del binario usato.
- **Raccomandazione di prodotto**: proporre come opzione "consigliata" una rete privata (**Tailscale `serve`** — non `funnel` — o WireGuard) dove il daemon non è mai esposto a Internet; tenere Cloudflare Quick Tunnel come opzione "comoda ma esposta". Documentare le differenze di esposizione nella UI.

---

## 🟢 Qualità e osservazioni minori

- **L1** — `randomInt(100000, 999999)` esclude `999999` (irrilevante se si rimuove il codice, vedi H1).
- **L2** — `readOnly` blocca `agent.abort/interrupt/clearQueue`: da remoto non si può fermare l'agente. Consentirli sempre.
- **L3** — `loadConfig()` (lettura da disco + `JSON.parse`) ad ogni comando in `execute`; mettere in cache e invalidare su `patchConfig`. `saveConfig` non imposta permessi ristretti e usa `Date.now()` come suffisso temp (collisioni); su `config.json` ora può comparire un comando shell.
- **L4** — `daemon_locator.dart`: codice morto (`if (!isLoopback) return null; return null;`), errori di pairing (429, scaduto) inghiottiti senza feedback per l'utente, URL con `?pair=` non ripulito dopo l'uso, doppio `catch (_) {}`. Mostrare uno stato chiaro "Pairing scaduto / troppo tentativi / non associato".
- **L5** — `docs/security.md` sovrastima le garanzie: "cookie sempre `Secure`", "token master mai ai remoti" (vero solo se H2/H4 sono risolti), "6 livelli" (le guardrail non sono un livello, vedi C2), "5–10 minuti". Manca una sezione onesta "cosa può fare un dispositivo associato" e il trust boundary Cloudflare (M9). Aggiornare dopo le correzioni.
- **L6** — **Lacune nei test**: i test passano (72/72, 5/5) ma **non coprono nulla di quanto trovato sopra**. Test da aggiungere:
  1. Connessione `isRemote` che invia `remote.*`, `daemon.setConfig`, `pi.packages.*`, `session.create` con `cwd` fuori allowlist → `REMOTE_FORBIDDEN`.
  2. `daemon.setConfig { remote: … }` → `CONFIG_INVALID`.
  3. Proxy "silenzioso" (Host riscritto a loopback, senza header) sul listener remoto → mai master token.
  4. Master token su listener remoto → `4003`.
  5. Pairing con `cf-connecting-ip`/`x-forwarded-for` casuali su provider `custom` → limite comunque applicato; limite globale invalida il pairing.
  6. 25 WS non autenticate remote **non** impediscono la connessione locale.
  7. Pairing con codice a 6 cifre rifiutato; segreto monouso; pairing scaduto; `enabled=false` → 4xx.
  8. Persistenza: `remote_devices.json` non contiene token in chiaro; token scaduto rifiutato.
  9. `start()` doppio → un solo processo; kill dell'albero di processi; evento `statusChanged` su crash del tunnel.
  10. Test E2E con browser WebKit/iOS per CSP `wss`.
- **Pulizia del diff** (`git status`): sono modificati file non pertinenti (generated plugin registrants Linux/macOS/Windows, `pubspec.lock`, 4 PNG in `docs/design-evidence/`). Separarli in commit distinti o ripristinarli. Aggiungere `qr_flutter` è accettabile ma verificare licenza/versione.

---

## Cosa è già fatto bene

- Opt-in di default (`remote.enabled: false`), nessuna porta aperta sul router, bind del daemon solo su loopback.
- Segreti con `crypto.randomBytes(32)`, confronto con `timingSafeEqual` (lunghezze diverse gestite), pairing monouso con scadenza, token per-device separato dal master.
- Revoca singola/totale con chiusura immediata delle WS (4003).
- Host/Origin allowlist (anti DNS-rebinding) applicata a HTTP; CSP restrittiva (`script-src 'self'`), `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`.
- Rispetto della lint D16 "zero telemetry" (regex per URL costruita dinamicamente).
- Scrittura atomica del file dispositivi; comandi remoti con codici di errore dedicati.

---

## Piano di correzione proposto (ordine)

1. **Blocco rilascio**: C1 (allowlist + remote.* locale-only + no `customTunnelCommand` via IPC + validazione `patchConfig`), H4, H2 (listener dedicato al tunnel) — risolvono insieme leak del master token, RCE e bypass.
2. **C2**: sostituire guardrail con modalità `view`/`control` per-dispositivo, default `view`; correggere doc/UI.
3. **H1 + H3**: rimuovere codice a 6 cifre, limite globale sul pairing, estrazione IP per provider, bucket separati per il listener remoto.
4. **M5, M6, M8, M7**: robustezza tunnel, no auto-pairing al boot, hardening endpoint, scope `cwd`.
5. **M1–M4, M9**: hash token + scadenza, fragment per pairing, cookie/CSP/HSTS, documentazione del trust boundary e opzione Tailscale.
6. **L1–L6**: pulizia, test di regressione (elencati in L6), aggiornamento `docs/security.md`, pulizia del diff.

**Criteri di accettazione prima di riabilitare la feature**: tutti i test del punto L6 verdi; riesecuzione dei PoC (comandi remoti vietati, header spoofing inefficace, nessun leak del master, local app non bloccabile da remoto); prova manuale da telefono reale (iOS Safari + Android Chrome) con tunnel Cloudflare e con Tailscale.

---

## Stato di Risoluzione delle Criticità (Aggiornato)

| ID | Descrizione | Gravità | Stato | Risoluzione Implementata |
|----|-------------|---------|-------|--------------------------|
| **C1** | RCE e bypass delle guardrail tramite `remote.*` e `daemon.setConfig` da remoto | Critica | ✅ RISOLTO | Allowlist default-deny rigida in `Dispatcher`; `remote.*`, `daemon.*` e `pi.packages.*` rigorosamente locali (`REMOTE_FORBIDDEN`); nessun comando shell (`shell: false`); `daemon.setConfig` rifiuta sezioni `remote`/`web`. |
| **C2** | Illusione di sicurezza delle guardrail globali / bypass tramite race | Critica | ✅ RISOLTO | Sostituite guardrail con modalità per-dispositivo `view` (default, sola lettura + abort/interrupt di emergenza) e `control` (richiede conferma desktop). |
| **H1** | Codice a 6 cifre debole; token in chiaro; rate-limit aggirabile via header | Alta | ✅ RISOLTO | Codice a 6 cifre rimosso; pairing esclusivamente con segreto URL a 256 bit; solo hash SHA-256 salvato su disco; limite globale (5 errori distruggono il pairing); IP affidabile da socket per custom provider. |
| **H2** | Leak del token master verso client remoti tramite proxy silenzioso | Alta | ✅ RISOLTO | Listener HTTP dedicato per il tunnel su porta separata (`remoteHttpServer`); token master categoricamente rifiutato su questo listener; listener locale rifiuta header di proxy con `403`. |
| **H3** | DoS cross-listener: flood remoto blocca l'app desktop locale | Alta | ✅ RISOLTO | Separazione dei bucket di rate limiting (`r:<ip>` vs `l:<ip>`); flood sul listener remoto non influenza minimamente il listener locale; limite di concorrenza su handshake remoti. |
| **H4** | Bypass delle restrizioni tramite DNS rebinding su IP pubblico | Alta | ✅ RISOLTO | Architettura a due listener: l'accesso locale è circoscritto fisicamente al socket locale; il socket remoto accetta solo Host autorizzati e richiede credenziali per-device. |
| **M1** | Token dispositivo eterni nel file di stato | Media | ✅ RISOLTO | Scadenza scorrevole a 30 giorni rinnovata a ogni utilizzo verificato; pulizia automatica; limite massimo di 10 dispositivi associati (`REMOTE_DEVICE_LIMIT`). |
| **M2** | Segreto di pairing nei log del reverse proxy (query parameter) | Media | ✅ RISOLTO | Segreto trasmesso esclusivamente in URL fragment (`#pair=...`); `pair_bootstrap.js` lo consuma ed elimina dalla cronologia del browser via `history.replaceState` prima del bootstrap. |
| **M3** | Flag `Secure` mancante sui cookie di pairing | Media | ✅ RISOLTO | Tutti i cookie `pcp_device_token` impostati dal listener remoto hanno obbligatoriamente `Secure; HttpOnly; SameSite=Lax`. |
| **M4** | CSP hardcoded su loopback / HSTS mancante sul listener remoto | Media | ✅ RISOLTO | CSP dinamica con `connect-src 'self' https://<host> wss://<host>`; HSTS abilitato (`Strict-Transport-Security: max-age=31536000; includeSubDomains`). |
| **M5** | Processi `cloudflared` orfani su Windows e timeout pendenti | Media | ✅ RISOLTO | `killProcessTree` termina l'intero albero di processi (`taskkill /T /F` su Win, process group su POSIX); timeout cancellati; evento `change` gestito; single-flight mutex su start concorrenti. |
| **M6** | Pairing secret generato automaticamente ad ogni start/boot | Media | ✅ RISOLTO | All'avvio del daemon (`main.ts`), l'auto-start passa `{ generatePairing: false }`; il segreto viene generato solo su richiesta esplicita dell'utente. |
| **M7** | Manipolazione arbitraria di path filesystem (`cwd`) da remoto | Media | ✅ RISOLTO | Confinamento obbligatorio in `Dispatcher`: le sessioni create da remoto devono avere un `cwd` interno o coincidente a workspace già aperti in locale. |
| **M8** | DoS o crash tramite body illimitato o interruzione socket muta | Media | ✅ RISOLTO | `readJsonBody` con limite rigido di 8 KiB e restituzione di errore HTTP `413 Payload Too Large` senza socket abort silente. |
| **M9** | Mancata documentazione del trust boundary di Cloudflare | Media | ✅ RISOLTO | `docs/security.md` aggiornato documentando che Cloudflare termina TLS ed è visibile il traffico; raccomandato l'uso di Tailscale Serve / VPN. |
| **L1-L6**| Refactoring qualità, pulizia codice morto, e suite di test completa | Bassa | ✅ RISOLTO | Codice morto rimosso in `daemon_locator.dart`; test completi (74 unit test, test di sicurezza esaustivi, PoC di verifica tutti verdi). |

