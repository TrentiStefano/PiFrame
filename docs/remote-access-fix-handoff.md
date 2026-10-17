# Handoff — Fix sicurezza "Accesso Remoto" (pi-crust)

Riferimento: la review è in `docs/remote-access-security-review.md` (ID C1, C2, H1–H4, M1–M9, L1–L6). Questo file dice **cosa è già stato fatto, cosa manca e come farlo**. Il codice è nel working tree, non committato.

## ⚠️ Stato del build
`apps/agentd` **NON compila** finché non finisci `RemoteManager.ts` e `Dispatcher.ts` (usano ancora `readOnly`/`allowFileEdits`, `code` del pairing, `isDirectLoopbackRequest`, ecc.). È atteso. Verifica con `cd apps/agentd && npx tsc --noEmit`.

## Trappole dell'ambiente (leggere!)
- I file preesistenti sono **CRLF** (autocrlf); i file nuovi in `remote/` sono LF. Il tool `edit` può fallire sui CRLF. Usa lo script helper `C:/Users/Stefano/AppData/Local/Temp/p.mjs` (`patch(file, [[vecchio, nuovo], ...])`, preserva gli EOL) oppure riscrivi il file intero con `write`.
- **Non usare heredoc bash per codice con backslash** (regex): i `\\` vengono mangiati. Scrivi gli script con il tool `write`.
- Non c'è Python. `/tmp` di bash ≠ `/tmp` di node: usa `C:/Users/Stefano/AppData/Local/Temp`.
- Test: `apps/agentd` esegue `node --test dist/**/*.test.js` dopo `pnpm build` (tsc). I PoC della review sono in `C:/Users/Stefano/AppData/Local/Temp/poc/poc.mjs` e `poc2.mjs` (importano da `apps/agentd/dist`): vanno riscritti/riesauriti alla fine e devono mostrare gli attacchi **bloccati**.

## ✅ Fatto
1. `apps/agentd/src/config/config.ts`
   - `RemoteConfig` = `{ enabled, tunnelProvider, customTunnelCommand?, customTunnelUrl?, defaultMode: 'view'|'control' }` (rimossi `allowFileEdits`/`readOnly`). Default `defaultMode: 'view'`.
   - `validateRemotePatch` (whitelist chiavi/tipi, lancia `CONFIG_INVALID`), `validateCustomTunnelUrl` (solo https, no credenziali, no loopback; ritorna `origin`), `validateCustomTunnelCommand`. `patchConfig` valida `partial.remote`; `loadConfig` sanifica `remote` da disco (ignora chiavi legacy). `saveConfig` scrive con mode 0600 e tmp con pid.
   - **Da aggiungere**: `listenerPort?: number` opzionale (1024–65535) in `RemoteConfig` + validazione, per avere una porta stabile del listener remoto (utile con tunnel custom/Tailscale). In alternativa 0 = casuale.
2. `remote/types.ts`: nuovi tipi `PairedDevice` (con `tokenHash`, `mode`, `expiresAt`), `PublicPairedDevice`, `PairingSecret {secret, expiresAt}` (**niente più `code` a 6 cifre**), `RemoteStatus` (`pairingPending {expiresAt,url}`, `options {defaultMode}`). **Da aggiungere a `RemoteStatus`: `localPort: number`** (porta del listener remoto, da mostrare per tunnel custom).
3. `remote/RemoteAuthManager.ts` riscritto: token `rem_dev_<ulid>.<secret>`, salva solo SHA-256; scadenza scorrevole 30 giorni; max 10 dispositivi (`REMOTE_DEVICE_LIMIT`); `lastUsedAt` persistito con debounce (`flush()`); `pair(candidate, ua, ip, mode)` accetta **solo** il segreto 256 bit; limite globale: 5 fallimenti → il pairing viene distrutto; rate-limit per IP con pulizia/cap; `getDevice(id)`, `setDeviceMode`, `revokeDevice`, `revokeAll`, `getPairedDevices`; file legacy con token in chiaro scartati. Costruttore: `(devicesFile?, clock?)`.
4. `remote/TunnelProvider.ts`: `BaseTunnelProvider` (EventEmitter, evento `'change'`, `start()` condiviso = niente doppi processi), `killProcessTree` (taskkill /T su Windows, process group su POSIX), `parseCommandLine` (argv senza shell).
5. `remote/CloudflaredTunnelProvider.ts` e `remote/CustomTunnelProvider.ts` riscritti: emettono `'change'` su exit/errore, timeout cancellato, stdio drenato/ignorato, **no `shell:true`**, kill dell'albero di processi, URL custom validato.

## ❌ Da fare (in ordine consigliato)

### A. `remote/RemoteManager.ts` (riscrivere)
- `setListenerPort(port)` / `getListenerPort()` (il tunnel punta al **listener remoto dedicato**, non alla porta locale).
- `start(options?, behavior?: { generatePairing?: boolean })`: mutex `startPromise`; valida le opzioni con `validateRemotePatch` **prima** di toccare lo stato; crea il provider, si sottoscrive a `'change'`; persiste `enabled: true` **solo dopo** start riuscito; genera il pairing (TTL 5 min) solo se `generatePairing !== false`. In `main.ts` l'auto-start al boot deve passare `{ generatePairing: false }` (M6).
- `onProviderChange`: se il provider non è più `running` → azzera `expectedHost`, `clearActivePairing()`, emette `'tunnelDown'` e `statusChanged`.
- `stop()`: `enabled:false`, stop provider, azzera host/pairing, emette `'stopped'` (il ws server chiude tutte le connessioni remote), `statusChanged`.
- Allowlist: `expectedHost = new URL(tunnelUrl).host.toLowerCase()`. `isRemoteHostAllowed(host)` richiede `enabled && state==='running'`, parsa `new URL('https://'+host)` (niente username, regex di caratteri ammessi) e confronta `.host`. `isRemoteOriginAllowed(origin)`: `https:` + stesso host.
- `getTrustedClientIp(req)`: per `cloudflared` usa **solo** `cf-connecting-ip` se `net.isIP`; altrimenti `req.socket.remoteAddress` (normalizza `::ffff:`). Mai `x-forwarded-for`.
- `pair()`: richiede `enabled && running` (`REMOTE_NOT_ACTIVE`), usa `config.remote.defaultMode`, `emitStatus()` in `finally`. `generatePairing()` richiede running; URL = `${url}/#pair=${secret}` (**fragment, non query**).
- `setDeviceMode(deviceId, mode)` (emette `deviceModeChanged` + status), `setOptions({defaultMode})` validato, `revokeDevice`/`revokeAll` (emettono `deviceRevoked`/`allDevicesRevoked`), `getStatus()` secondo i nuovi tipi.
- **Rimuovere `isDirectLoopbackRequest`** (sostituita dal listener dedicato, vedi B).

### B. Listener dedicato al tunnel (H2/H3/H4) — cuore del fix
- `server/origin.ts`: aggiungere `hasProxyHeaders(req)` (x-forwarded-*, forwarded, via, x-real-ip, cf-*). `isHostAllowed`/`isOriginOrRemoteAllowed` restano per compatibilità ma i due listener usano regole diverse.
- `server/httpServer.ts`: `createHttpServer({ ..., listener?: 'local'|'remote' })`.
  - **local** (default): Host solo loopback; richieste con proxy headers → 403; comportamento attuale (bootstrap con token master, cookie `pcp_token`). Le richieste con Host del tunnel NON sono più accettate qui.
  - **remote**: Host deve passare `remoteManager.isRemoteHostAllowed`, altrimenti 403; mai `Set-Cookie pcp_token`; mai token master; `/api/health` minimale `{ok:true}`; `/api/session-bootstrap` solo con device token valido (cookie `pcp_device_token` **sempre `Secure`**); `POST /api/remote/pair` (Content-Type json, body ≤ 8 KB → 413 senza `destroy` muto, un solo campo `pairingSecret`, richiede remote attivo, IP da `getTrustedClientIp`); `/api/remote/status` solo ridotto; `POST /api/blobs` solo per device in modalità `control`; 404 per il resto; static file serviti (UI web). Header: `Cache-Control: no-store` sulle API, HSTS, CSP con `connect-src 'self' wss://<hostTunnel>`.
  - Rimuovere `getAuthorizedIdentity` basato su candidati misti: sul listener remoto accetta solo device token (Bearer o cookie `pcp_device_token`).
- `server/static.ts`: nessun cookie master sul listener remoto; CSP dinamica (M4); `opts.listener`.
- `server/wsServer.ts`: `createWsServer({ httpServer, remoteHttpServer?, ... })`; funzione `attach(server, isRemoteListener)` che registra `'upgrade'`; segnare le request remote (WeakSet) e passare `viaRemoteListener` a `Connection`. Rate-limit con **bucket separati** (`'r:'+trustedIp` vs `'l:'+socketIp`): il bucket locale non è mai penalizzato dai fallimenti remoti (H3); su remoto: limite di connessioni non autenticate concorrenti (~10); verificare `Host` anche all'upgrade; pulizia periodica (`setInterval` + `unref`) di `failedHelloPerIp`. Aggiungere `ConnectionManager.broadcastLocal()` (solo `!conn.isRemote`). Su `deviceRevoked`/`allDevicesRevoked`/`stopped`/`tunnelDown` chiudere le connessioni remote (4003). Contare come fallimento locale solo l'`hello` fallito (nuovo flag `conn.authFailed`).
- `server/connection.ts`: nuova opzione `viaRemoteListener`. In `handleHello`: se `viaRemoteListener` → il token master è **rifiutato** (4003) e `isRemote=true` sempre; se arrivato su listener locale con device token → `isRemote=true`. Aggiungere `authFailed`.
- `main.ts`: creare un secondo server `remoteHttpServer = createHttpServer({listener:'remote', ...})` in ascolto su `127.0.0.1:<config.remote.listenerPort||0>`, `remoteManager.setListenerPort(porta)`, passarlo a `createWsServer`, chiudere entrambi allo shutdown, `remoteManager.flush()` allo shutdown, auto-start con `{generatePairing:false}`.

### C. `commands/Dispatcher.ts` (C1, C2, M7)
- Rimuovere il blocco `readOnly/allowFileEdits` e il `loadConfig()` per comando.
- **Allowlist default-deny per `conn.isRemote`** (prima dello `switch`). Se `conn.deviceId` non corrisponde a un device attivo (`authManager.getDevice`) → `conn.close(4003)` + errore.
  - Modalità `view` (default): `session.list`, `session.open` (senza `continue`), `session.attach/detach`, `session.getStats/getEntries/getTree`, `agent.getModels/getThinkingLevels/getCommands`, **`agent.abort`, `agent.interrupt`**, `workspace.refresh/getDiff/listFiles/readFile`.
  - Modalità `control`: tutto `view` + `agent.*` (prompt/steer/followUp/clearQueue/compact/set*), `ui.claim/respond`, `session.create/rename/fork/clone/closeWorker`, `session.open` con `continue`, `workspace.saveFile/gitAction`.
  - **Sempre solo locali** (anche difesa in profondità dentro ogni case): `remote.*`, `daemon.getConfig`, `daemon.setConfig`, `pi.packages.*`. Errore `REMOTE_FORBIDDEN` (il prefisso `REMOTE_` è già mappato a `rejected`).
- `session.create` / `session.open {cwd}` da remoto: `cwd` consentito solo se uguale o dentro a un cwd di sessione già nota (`registry.listSessions`); `cwd` assente → rifiutato.
- `daemon.setConfig`: rifiutare le chiavi `remote` e `web` (`CONFIG_INVALID`, "usa remote.*"); nessun merge cieco.
- Nuovo comando `remote.setDeviceMode {deviceId, mode}`; `remote.setOptions {defaultMode}`; `remote.start` accetta `{tunnelProvider, customCommand, customUrl}` validati.
- `remote.statusChanged` e `daemon.configChanged` → `broadcastLocal` (mai ai remoti: contengono segreto di pairing, IP, config).

### D. Schema / tipi / client Flutter
- `packages/pcp-spec/schema/command.schema.json` e `packages/pcp-ts/src/types.ts`: aggiungere `remote.setDeviceMode`; aggiornare payload `remote.setOptions` (`defaultMode`) e il tipo di `remote.statusChanged` (no `code`, `mode` per device, `expiresAt`, `localPort`). Controllare se esiste un test di sync schema↔tipi.
- `apps/pi_crust/lib/data/daemon/pcp_client.dart`: `setRemoteOptions({defaultMode})`, `setRemoteDeviceMode(deviceId, mode)`.
- **Pairing via fragment (M2)**: Flutter web in hash-mode tratterebbe `#pair=...` come rotta. Soluzione prevista: nuovo file `apps/pi_crust/web/pair_bootstrap.js` (la CSP vieta gli script inline), caricato da `web/index.html` **prima** di Flutter: legge `location.hash` (`#pair=...`), fa `fetch('/api/remote/pair', {method:'POST', credentials:'same-origin', body: {pairingSecret}})` (il server imposta il cookie HttpOnly), poi `history.replaceState(null,'',location.pathname)` e **solo dopo** inietta dinamicamente `flutter_bootstrap.js` (controllare come è caricato in `index.html`). In `daemon_locator.dart` rimuovere la gestione `?pair=` e il codice morto `if (!isLoopback) return null; return null;`; il bootstrap via cookie resta; su 401 `needsPairing` mostrare uno stato "dispositivo non associato / pairing scaduto".
- `apps/pi_crust/lib/features/settings/remote_section.dart`: via codice a 6 cifre e toggle `allowFileEdits/readOnly`; mostrare QR/URL + countdown, selettore `defaultMode`, per ogni dispositivo la modalità (`view`/`control`) con **dialog di conferma** per passare a `control` ("potrà eseguire comandi sul tuo computer"), scadenza dispositivo, `localPort` per il provider custom, campo comando custom con avviso "eseguito senza shell, `$PORT`". Aggiornare `test/remote_section_test.dart`, `test/pcp_client_test.dart`, `test/settings_view_test.dart`.

### E. Test (L6) — i vecchi test vanno aggiornati e ne servono di nuovi
Esistenti da riscrivere: `remote/test/RemoteAuthManager.test.ts`, `remote/test/RemoteServer.test.ts` (ora due server: local + remote), la parte remote di `commands/test/Dispatcher.test.ts`, `test/e2e/src/remote_connection_e2e.spec.ts`, e `server/test/*` se toccati.
Nuovi (tutti da avere verdi): (1) connessione `isRemote` che invia `remote.*`, `daemon.getConfig/setConfig`, `pi.packages.*`, `session.create` con cwd fuori allowlist → `REMOTE_FORBIDDEN`; in `view` anche `agent.prompt`/`workspace.saveFile` bloccati, `agent.abort` permesso; (2) `daemon.setConfig {remote|web}` → `CONFIG_INVALID`; (3) proxy "silenzioso" (Host riscritto a loopback, senza header) sul listener remoto → mai token master; (4) token master su listener remoto → 4003; (5) header `cf-connecting-ip`/`x-forwarded-for` casuali con provider custom non aggirano il limite; 5 fallimenti globali distruggono il pairing; (6) 25 WS non autenticate sul listener remoto non bloccano la connessione locale; (7) codice a 6 cifre rifiutato, segreto monouso/scaduto, pairing con remote disattivo → errore; (8) `remote_devices.json` senza token in chiaro, device scaduto rifiutato, limite 10 dispositivi; (9) `validateCustomTunnelUrl` (http, loopback, credenziali) e `parseCommandLine`; (10) start doppio → un solo processo; `statusChanged` su crash del tunnel. Lint D16: `apps/agentd/src/test/telemetryLint.test.ts` deve restare verde (niente URL esterni letterali nei sorgenti).

### F. Documentazione e chiusura
- Aggiornare `docs/security.md` (sezioni 6–7): modello a due listener, modalità `view`/`control` per dispositivo (**un dispositivo in `control` equivale a esecuzione di comandi come utente**), trust boundary Cloudflare (vede il traffico in chiaro), raccomandare Tailscale `serve` (non `funnel`), pairing senza codice, scadenza 30 giorni, TTL 5 min, cookie sempre Secure. Togliere ogni affermazione non più vera.
- Aggiungere in fondo a `docs/remote-access-security-review.md` una tabella "stato fix" per ID.
- Ripulire il diff: `git status` mostra file non pertinenti (generated plugin registrants linux/macos/windows, `pubspec.lock` se non necessario, 4 PNG in `docs/design-evidence/`) → ripristinarli o separarli. Non committare gli script in Temp.
- Verifica finale: `cd apps/agentd && pnpm build && pnpm test`; e2e in `test/e2e`; `flutter analyze` + `flutter test` in `apps/pi_crust`; rieseguire i PoC (devono fallire per l'attaccante). Test manuale da iPhone/Android con tunnel reale (CSP `wss`, pairing da QR) se possibile.

## Criteri di accettazione
Tutti i punti E verdi; PoC C1/H1/H2/H3 non più riproducibili; nessun comando `remote.*`/`daemon.setConfig`/`pi.packages.*` eseguibile da una connessione remota; il token master non esce mai dal listener locale; app locale non bloccabile da remoto; nessun token in chiaro su disco.

## Checklist todo (tool `todo` della sessione, tutti ancora "pending" nel tool)
1. Config + modalità → **quasi fatto** (manca `listenerPort`).
2. RemoteAuthManager → **fatto**.
3. Tunnel providers → **fatto**; `RemoteManager` → **da fare** (A).
4. Listener dedicato (B) → **da fare**.
5. Dispatcher (C) → **da fare**.
6. Schema/Flutter (D) → **da fare**.
7. Test/doc/verifica (E, F) → **da fare**.
