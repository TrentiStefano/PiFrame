# Baseline di Sicurezza e Modello di Minaccia di PiFrame

Questo documento descrive l'architettura di sicurezza, le difese implementate e il modello di minaccia per il runtime **PiFrame** e il daemon `pi-agentd`.

---

## 1. Modello di Minaccia e Confini di Fiducia

Il daemon `pi-agentd` è un servizio locale ad alto privilegio in grado di interagire con il filesystem e invocare il CLI di Pi (`pi --mode rpc`). Pertanto, la superficie di attacco deve essere rigorosamente contenuta all'utente locale della macchina e ai dispositivi remoti esplicitamente autorizzati.

### Confine di Rete
- **Solo Loopback (`127.0.0.1`)**: entrambi i server HTTP e WebSocket (locale e remoto) effettuano il binding esclusivamente su `127.0.0.1`. Nessuna interfaccia pubblica (`0.0.0.0` o IP LAN) viene mai aperta dal daemon.
- **Architettura a Due Listener Fisici**:
  - **Local Listener** (`httpServer`): riservato all'applicazione desktop Flutter e all'interfaccia web aperta su loopback.
  - **Dedicated Remote Listener** (`remoteHttpServer`): listener separato su porta dedicata al quale è reindirizzato il tunnel (Cloudflare o Custom). La provenienza remota è determinata dal socket su cui arriva la connessione e non da header HTTP falsificabili.

---

## 2. Autenticazione e Gestione del Token (D11)

- **Entropia del Token Master**: All'avvio di ogni istanza del daemon viene generato un token crittografico randomico a 256 bit (`crypto.randomBytes(32).toString('hex')`).
- **Segregazione Rigorosa del Token Master (H2)**:
  - Il token master è accettato **esclusivamente** sul listener locale (`127.0.0.1:<localPort>`).
  - Sul listener remoto dedicato, qualsiasi tentativo di autenticazione con il token master viene rifiutato con chiusura immediata della connessione WebSocket (`4003`) o `401 Unauthorized` su HTTP.
  - L'endpoint `/api/session-bootstrap` sul listener remoto non restituisce mai il token master.
- **File di Runtime**:
  - Il token master è memorizzato in `~/.piframe/runtime/daemon.token` con permessi owner-only (`0600`).
- **Confronto a Tempo Costante**: La verifica del token utilizza `crypto.timingSafeEqual` (`timingSafeEqualStrings`) per prevenire attacchi di tipo *timing attack*.
- **Divieto di Token in URL o Query String**: I token e i segreti non viaggiano mai come parametri di query HTTP (prevenendo leak nei log di server/proxy e header Referer).

---

## 3. Sicurezza del Protocollo PCP e WebSocket (F2, F4)

- **Handshake Autenticato**:
  - Qualsiasi connessione WebSocket che non completi l'handshake `hello` con credenziali valide entro 5 secondi viene terminata con codice `4001` o `4003`.
- **Isolamento dei Bucket di Rate Limiting (H3)**:
  - I fallimenti di autenticazione su listener remoto (`r:<ip>`) e locale (`l:<ip>`) sono memorizzati in bucket separati.
  - Attacchi di forza bruta o flood di connessioni WebSocket non autenticate sul tunnel remoto non possono in alcun caso bloccare o rallentare l'applicazione desktop locale.
- **Validazione di Host e Origin**:
  - Sul listener locale: l'header `Host` deve corrispondere tassativamente a loopback; qualsiasi header di reverse proxy (`X-Forwarded-For`, `CF-Connecting-IP`, `Via`, ecc.) provoca un `403 Forbidden` immediato.
  - Sul listener remoto: l'header `Host` e l'eventuale `Origin` devono corrispondere all'hostname autorizzato del tunnel attivo.
- **Limiti di Concorrenza e Frame**:
  - Coda di autenticazione remota limitata a max 10 connessioni concorrenti in fase di handshake.
  - Max 200 comandi al secondo per connessione WebSocket.
  - Dimensione massima del frame WebSocket: 4 MiB (superamenti chiusi con `4009`).

---

## 4. Hosting Web e Content Security Policy (D13)

- **Content Security Policy Dinamica (M4)**:
  - Sul listener locale: CSP restrittiva con connessioni permesse solo su loopback (`ws://127.0.0.1:*`, `http://127.0.0.1:*`).
  - Sul listener remoto: CSP con `connect-src 'self' https://<tunnelHost> wss://<tunnelHost>`, `Strict-Transport-Security: max-age=31536000; includeSubDomains`.
- **Header di Sicurezza**:
  - `X-Frame-Options: DENY` (anti-clickjacking)
  - `Referrer-Policy: no-referrer`
  - `X-Content-Type-Options: nosniff`
  - `Cache-Control: no-store` su tutte le risposte API
- **Cookie Bootstrap**:
  - Listener locale: `Set-Cookie: pcp_token=<token>; Path=/; HttpOnly; SameSite=Strict`.
  - Listener remoto: cookie dispositivo `Set-Cookie: pcp_device_token=<token>; Path=/; HttpOnly; SameSite=Lax; Secure`. Nessun cookie master viene mai rilasciato sul listener remoto.
- **Prevenzione Path Traversal**:
  - Il gestore dei file statici normalizza i percorsi e verifica che `path.relative(staticDir, targetPath)` non inizi con `..`.
  - Gli endpoint blob (`/api/blobs/:blobId`) utilizzano `path.basename`.

---

## 5. Privacy e Divieto di Telemetria Remota (D16)

- **Zero Raccolta Dati Remota**:
  - PiFrame non include alcun SDK o endpoint di telemetria, analytics o crash reporting verso server di terzi.
  - Tutti i log rimangono confinati nel filesystem locale dell'utente (`~/.piframe/runtime/daemon.log`).
- **Redazione Automatica dei Segreti**:
  - Qualsiasi funzionalità di esportazione redige automaticamente token e chiavi API (`[REDACTED]`).

---

## 6. Accesso Remoto Sicuro & Associazione Dispositivi (Safe Remote Access)

L'accesso remoto consente di interagire con il daemon PiFrame dallo smartphone o dal browser esterno adottando un'architettura rigorosamente blindata:

### 1. Opt-in per Default
Nessun listener remoto, processo di tunneling o porta viene avviata se l'utente non abilita esplicitamente l'opzione nelle impostazioni. All'avvio del sistema, l'auto-start non genera segreti di associazione effimeri finché l'utente non li richiede.

### 2. Associazione One-Time via URL Fragment (#pair=...)
- **Segreto ad Alta Entropia**: Il pairing genera un segreto randomico a 256 bit (`pair_tok_<base64url>`). Nessun codice PIN numerico corto a 6 cifre è utilizzato, eliminando il rischio di attacchi brute-force o ingegneria sociale.
- **URL Fragment (M2)**: Il segreto viaggia nell'hash del link (`https://tunnel.example.com/#pair=<secret>`), garantendo che non venga mai inviato ai server web/proxy come query string e non compaia nei log HTTP.
- **Script di Bootstrap Web Dedicato (`pair_bootstrap.js`)**: Il client web legge il fragment prima di inizializzare l'applicazione, ripulisce istantaneamente la barra degli indirizzi e la cronologia del browser via `history.replaceState`, e scambia il segreto via POST JSON `/api/remote/pair`.
- **Distruzione Globale su Tentativi Multipli**: Dopo 5 tentativi errati da parte di qualsiasi client o IP, l'intero segreto di associazione viene distrutto e revocato (anti-brute force globale).
- **Rate Limiting per IP**: 5 tentativi falliti da un IP comportano il blocco per 15 minuti.

### 3. Gestione Credenziali Dispositivo & Hashing
- **Nessun Token in Chiaro su Disco (H1)**: Il database dei dispositivi (`remote_devices.json`) memorizza esclusivamente l'hash SHA-256 del segreto del dispositivo. Il file è creato con permessi `0600`.
- **Scadenza Scorrevole e Limite Dispositivi**: I token dispositivo hanno una durata di 30 giorni rinnovata a ogni utilizzo verificato. È applicato un limite massimo di 10 dispositivi contemporaneamente registrati.
- **Revoca Istantanea**: La revoca di un dispositivo da parte dell'utente desktop comporta la chiusura immediata delle connessioni WebSocket aperte con codice `4003`.

### 4. Modello dei Permessi: Modalità View vs Control (C2)
Ogni dispositivo associato opera secondo una modalità assegnata dal desktop:
- **Modalità `view` (Predefinita e Consigliata)**:
  - Consente esclusivamente l'ispezione dello stato: consultazione sessioni, statistiche, albero di conversazione, diff del workspace e lettura file.
  - **Permessi di Emergenza**: Include `agent.abort` e `agent.interrupt` per permettere all'utente di bloccare l'agente da mobile in caso di necessità.
  - **Blocco Scrittura**: Qualsiasi comando di scrittura (`agent.prompt`, `agent.steer`, `workspace.saveFile`, `workspace.gitAction`, continuazione sessione) è respinto con `REMOTE_FORBIDDEN`.
- **Modalità `control`**:
  - Richiede un'esplicita conferma con dialog di avviso da parte dell'utente desktop.
  - **Nota di Rischio**: Un dispositivo in modalità `control` ha la facoltà di inviare prompt ed eseguire comandi con i privilegi dell'utente del sistema operativo.

### 5. Allowlist Default-Deny nel Dispatcher (C1)
Tutti i comandi amministrativi e di configurazione sono rigorosamente interdetti alle connessioni remote:
- `remote.*` (inclusi `remote.start`, `remote.setOptions`, `remote.generatePairing`, `remote.revokeDevice`) -> `REMOTE_FORBIDDEN`.
- `daemon.getConfig` e `daemon.setConfig` -> `REMOTE_FORBIDDEN`.
- `pi.packages.*` -> `REMOTE_FORBIDDEN`.
- `daemon.setConfig` impedisce la modifica diretta delle sezioni `remote` e `web` anche da locale (`CONFIG_INVALID`).

### 6. Confinamento del Filesystem per Comandi Remoti (M7)
La creazione di nuove sessioni da remoto (`session.create` o `session.open {cwd}`) impone che il `cwd` appartenga rigorosamente alla directory di un workspace già noto e aperto in locale.

### 7. Esecuzione Sicura dei Provider Tunnel (M5, M8)
- Il comando del tunnel custom (`customTunnelCommand`) viene eseguito **senza shell** (`shell: false`), con parsing manuale degli argomenti (argv) ed eliminando qualsiasi rischio di shell injection (`&`, `|`, `;`).
- L'URL custom (`customTunnelUrl`) è convalidato rigorosamente: deve utilizzare `https://`, non può contenere credenziali e non può puntare a indirizzi di loopback.
- Alla terminazione, l'intero albero dei processi del tunnel viene abbattuto in modo pulito (`taskkill /T /F` su Windows, signal process group su POSIX).

---

## 7. Limitazioni Residue e Raccomandazioni Operative

- **Trust Boundary Cloudflare**: Quando si utilizzano i tunnel rapidi gratuiti di Cloudflare (`cloudflared`), il traffico TLS termina sui server edge di Cloudflare prima di raggiungere il daemon locale. Per una crittografia end-to-end senza intermediari commerciali terzi, si raccomanda l'uso di **Tailscale Serve** o VPN privata all'interno della propria rete Mesh.
- **Dispositivi in Modalità Control**: Concedere la modalità `control` a un dispositivo equivale a concedere l'accesso da terminale come utente locale. Mantenere i dispositivi in modalità `view` a meno che non sia strettamente necessario interagire in mobilità.
