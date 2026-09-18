# Baseline di Sicurezza e Modello di Minaccia di Pi-Crust

Questo documento descrive l'architettura di sicurezza, le difese implementate e il modello di minaccia per il runtime **Pi-Crust** e il daemon `pi-agentd`.

---

## 1. Modello di Minaccia e Confini di Fiducia

Il daemon `pi-agentd` è un servizio locale ad alto privilegio in grado di interagire con il filesystem e invocare il CLI di Pi (`pi --mode rpc`). Pertanto, la superficie di attacco deve essere rigorosamente contenuta all'utente locale della macchina.

### Confine di Rete
- **Solo Loopback (`127.0.0.1`)**: il server HTTP e WebSocket effettua il binding esclusivamente su `127.0.0.1`. Nessuna interfaccia pubblica (`0.0.0.0` o IP LAN) viene mai aperta.
- **Nessun Accesso Remoto nell'MVP**: l'MVP non consente connessioni da macchine esterne o tramite tunneling non autenticato.

---

## 2. Autenticazione e Gestione del Token (D11)

- **Entropia del Token**: All'avvio di ogni istanza del daemon viene generato un token crittografico randomico a 256 bit (`crypto.randomBytes(32).toString('hex')`).
- **File di Runtime**:
  - Il token è memorizzato in `~/.pi-crust/runtime/daemon.token`.
  - Sui sistemi operativi che supportano permessi POSIX, il file è creato con permessi `0600` (leggibile e scrivibile solo dall'utente proprietario).
- **Confronto a Tempo Costante**: La verifica del token utilizza `crypto.timingSafeEqual` (`timingSafeEqualStrings`) per prevenire attacchi di tipo *timing attack* sulla stringa del token.
- **Divieto di Token in URL o Query String**: Il token non viaggia mai come parametro di query (evitando leak nei log HTTP o header Referer).

---

## 3. Sicurezza del Protocollo PCP e WebSocket (F2, F4)

- **Handshake Autenticato**:
  - Qualsiasi connessione WebSocket che non completi l'handshake `hello` con il token corretto entro 5 secondi viene terminata con codice di chiusura `4003`.
- **Validazione dell'Origin**:
  - I client Web da browser inviano l'header `Origin`. Il daemon valida che l'origine sia autorizzata (matching con `http://127.0.0.1:<port>` o domini in allowlist esplicita). Connessioni con `Origin` non autorizzato vengono respinte immediatamente.
  - I client nativi desktop (Flutter Desktop) non inviano `Origin` e vengono identificati come client locali.
- **Rate Limiting e DoS Protection**:
  - Max 20 tentativi falliti di `hello` al minuto per IP.
  - Max 200 comandi al secondo per connessione WebSocket.
  - Dimensione massima del frame: 4 MiB. Frame di dimensione superiore provocano l'immediata disconnessione (`4009`).

---

## 4. Hosting Web Locale e Protezione dai Path Traversal (D13, Step 9.2)

- **Content Security Policy (CSP)**:
  Tutte le risposte statiche HTML includono policy CSP restrittive:
  ```http
  Content-Security-Policy: default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; connect-src 'self' ws://127.0.0.1:* http://127.0.0.1:* ws://localhost:* http://localhost:*; img-src 'self' data: blob:; font-src 'self' data:;
  ```
- **Header Anti-Clickjacking e MIME Sniffing**:
  - `X-Frame-Options: DENY`
  - `Referrer-Policy: no-referrer`
  - `X-Content-Type-Options: nosniff`
- **Cookie Bootstrap su Loopback**:
  - La richiesta da browser su `http://127.0.0.1:<port>/` riceve un cookie con flag:
    `Set-Cookie: pcp_token=<token>; Path=/; HttpOnly; SameSite=Strict`
- **Prevenzione Path Traversal**:
  - Il gestore dei file statici normalizza i percorsi e verifica che `path.relative(staticDir, targetPath)` non inizi con `..`.
  - Gli endpoint blob (`/api/blobs/:blobId`) utilizzano esclusivamente `path.basename` per garantire che non vengano letti percorsi arbitrari sul filesystem.

---

## 5. Privacy e Divieto di Telemetria Remota (D16)

- **Zero Raccolta Dati Remota**:
  - Pi-Crust non include alcun SDK o endpoint di telemetria, analytics o crash reporting verso server di terzi.
  - Tutti i log rimangono confinati nel filesystem locale dell'utente (`~/.pi-crust/runtime/daemon.log`).
- **Redazione Automatica dei Segreti**:
  - Qualsiasi funzionalità di esportazione di log o diagnostica redige automaticamente token di autenticazione e chiavi API sostituendoli con `[REDACTED]`.

---

## 6. Fuori Scope nell'MVP
- Accesso remoto non autenticato o multi-tenancy su stessa macchina non isolata.
- Esposizione su reti pubbliche senza reverse proxy TLS/VPN.
