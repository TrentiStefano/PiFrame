# Installazione, Ciclo di Vita e Disinstallazione di Pi-Crust

Questa guida documenta la distribuzione, l'avvio on-demand, la gestione degli aggiornamenti e la procedura di disinstallazione sicura di **Pi-Crust**.

---

## 1. Architettura di Distribuzione (D8, D14)

Pi-Crust è progettato come un'applicazione desktop a doppio componente:
1. **Interfaccia Grafica (Flutter App)**: l'ambiente visuale reattivo (disponibile per macOS, Windows e Web locale).
2. **Daemon di Runtime (`pi-agentd`)**: processo sidecar Node.js / Node SEA autonomo, che gestisce la connessione con Pi (`pi --mode rpc`), mantiene il journal degli eventi serializzato e gestisce lo stato persistente delle sessioni.
3. **Pi CLI Originale**: l'installazione di Pi (`v0.85.0+`) rimane completamente esterna ed intatta in `~/.pi/`. Pi-Crust **non modifica, non sposta e non sovrascrive mai** file all'interno di `~/.pi/`.

---

## 2. Requisiti di Sistema

- **Sistemi Operativi supportati**:
  - macOS 12+ (Apple Silicon `arm64` e Intel `x64`)
  - Windows 10/11 (`x64`)
- **Node.js**:
  - Nella versione distribuita con binario Node SEA (Single Executable Application), Node.js è incluso nel binario sidecar.
  - Per ambienti di sviluppo o esecuzione da sorgenti: Node.js ≥ 22.0.0.
- **Pi Coding Agent**:
  - Versione minima supportata: **v0.85.0**.
  - Installabile globalmente tramite `npm install -g @earendil-works/pi-coding-agent`.

---

## 3. Installazione

### macOS
1. Scarica `Pi-Crust.dmg`.
2. Trascina l'applicazione `Pi-Crust.app` nella cartella `/Applications`.
3. Al primo avvio, l'applicazione individua o avvia automaticamente il daemon sidecar `pi-agentd`.

### Windows
1. Scarica l'installer o il pacchetto zip `Pi-Crust-win-x64.zip`.
2. Estrai ed esegui `pi_crust.exe`.
3. L'applicazione si avvia associandosi al daemon locale su loopback.

### Web Locale (`http://127.0.0.1:<porta>/`)
1. Il daemon `pi-agentd` include un server statico HTTP integrato per gli asset web di Flutter.
2. Aprendo `http://127.0.0.1:<porta>/` da browser locale, il server imposta automaticamente un cookie `HttpOnly; SameSite=Strict` contenente il token di autenticazione PCP (`pcp_token`), consentendo l'accesso immediato senza configurazione manuale.

---

## 4. Ciclo di Vita del Daemon (D8, D9)

- **Avvio on-demand**: Il daemon non è un servizio di sistema persistente né un daemon di background permanente non desiderato. La GUI controlla la salute su `GET http://127.0.0.1:<porta>/api/health`; se non attivo, spawna il binario sidecar in modalità `detached`.
- **Lock e Token**:
  - File di runtime: `~/.pi-crust/runtime/daemon.json` (porta e PID).
  - File di lock: `~/.pi-crust/runtime/daemon.lock` per prevenire istanze duplicate.
  - Token di autenticazione: generato a 256 bit in `~/.pi-crust/runtime/daemon.token` con permessi ristretti (0600).
- **Log Rotativo**:
  - File di log: `~/.pi-crust/runtime/daemon.log`.
  - Rotazione automatica a 5 file da 5 MB ciascuno.
- **Inattività dei Worker (D9)**:
  - Timeout di inattività configurabile (default 30 minuti, regolabile da Impostazioni).
  - I worker in esecuzione (`working`, `retrying`, `compacting`, `awaiting_user`) non vengono **mai** arrestati per inattività.

---

## 5. Aggiornamenti (Upgrade)

- All'avvio, la GUI legge la versione del daemon attivo tramite `GET /api/health` e la confronta con la versione del binario incluso nel bundle.
- Qualora le versioni differiscano, la GUI notifica l'utente e propone il riavvio controllato del daemon solo quando non vi sono worker in stato attivo.

---

## 6. Disinstallazione

La rimozione di Pi-Crust è pulita, confinata e reversibile:

1. **Rimuovi l'applicazione GUI**:
   - macOS: Sposta `Pi-Crust.app` nel Cestino.
   - Windows: Elimina la cartella dell'applicazione o disinstalla da Impostazioni Applicazioni.
2. **Arresta il daemon** (se attivo):
   - Termina il processo `pi-agentd` dal task manager o tramite `kill <PID>`.
3. **Elimina i dati locali di Pi-Crust**:
   ```bash
   # macOS / Linux
   rm -rf ~/.pi-crust

   # Windows PowerShell
   Remove-Item -Recurse -Force "$HOME\.pi-crust"
   ```

### Garanzia di Integrità per `~/.pi/`
> [!IMPORTANT]
> Pi-Crust opera rigorosamente con approccio non invasivo. La directory di Pi (`~/.pi/`), contenente la cronologia delle sessioni, le credenziali e le estensioni, **non viene toccata né rimossa**.
> Tutte le sessioni originali rimangono pienamente utilizzabili dal CLI ufficiale di Pi anche dopo la disinstallazione di Pi-Crust.
