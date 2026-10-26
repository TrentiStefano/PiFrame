# Installazione, Ciclo di Vita e Disinstallazione di PiFrame

Questa guida documenta la distribuzione, l'avvio on-demand, la gestione degli aggiornamenti e la procedura di disinstallazione sicura di **PiFrame**.

---

## 1. Architettura di Distribuzione (D8, D14)

PiFrame è progettato come un'applicazione desktop a doppio componente:
1. **Interfaccia Grafica (Flutter App)**: app desktop per Windows, macOS e Linux; Web locale resta disponibile da sorgente.
2. **Daemon di Runtime (`pi-agentd`)**: sidecar Node.js incluso negli installer insieme al runtime Node. Gestisce la connessione con Pi (`pi --mode rpc`), il journal degli eventi e lo stato delle sessioni.
3. **Pi CLI Originale**: l'installazione di Pi (`v0.85.0+`) rimane completamente esterna ed intatta in `~/.pi/`. PiFrame **non modifica, non sposta e non sovrascrive mai** file all'interno di `~/.pi/`.

---

## 2. Requisiti di Sistema

- **Sistemi Operativi supportati**:
  - macOS 12+ (Apple Silicon `arm64` e Intel `x64`)
  - Windows 10/11 (`x64`)
  - Linux x64 (distribuzioni Debian/Ubuntu con GTK 3)
- **Node.js**:
  - Gli installer includono runtime Node e bundle `pi-agentd`; non serve installare Node separatamente.
  - Per sviluppo o esecuzione da sorgenti: Node.js ≥ 22.19.0.
- **Pi Coding Agent** (non incluso nell'installer): versione minima **v0.85.0**, da installare e tenere su `PATH`; l'installazione npm richiede Node.js/npm (`npm install -g @earendil-works/pi-coding-agent`).

### MCP Dart/Flutter per Pi

PiFrame usa il server ufficiale integrato Dart/Flutter configurato a livello utente in `~/.pi/agent/mcp.json` (`dart mcp-server`, esposizione differita). Serve Flutter/Dart SDK su `PATH`. Da root del progetto, verifica con `pi mcp list`; lo stato atteso è `dart · connected`. PiFrame avvia worker RPC con la workspace come `cwd`, quindi il server si aggancia al progetto attivo senza richiedere trust locale. Gli strumenti sono scoperti on demand tramite `tool_search`.

---

## 3. Installazione

Scarica l'installer più recente dalla [pagina GitHub Releases](https://github.com/TrentiStefano/piframe/releases/latest). I commit Conventional (`fix`, `feat`, `BREAKING CHANGE`) aggiornano il PR di release SemVer; quando il PR viene unito, GitHub Actions pubblica installer Windows, macOS Intel/Apple silicon e Linux x64 con screenshot aggiornato.

### macOS
1. Apri il DMG e trascina `PiFrame.app` in `/Applications`.
2. Al primo avvio, PiFrame avvia `pi-agentd` usando il runtime Node incluso.
3. Build non firmate/notarizzate possono richiedere **Control-click → Open** al primo avvio.

### Windows
1. Avvia `PiFrame-Setup-…-windows-x64.exe`.
2. L'installer aggiunge collegamenti nel menu Start; icona desktop è facoltativa.
3. PiFrame include e avvia `pi-agentd` con Node incluso. Installer non firmato può mostrare l'avviso SmartScreen.

> [!TIP]
> **Finestra bianca o rendering bloccato?** In presenza di driver di schermi virtuali (es. `USB Mobile Monitor`, `IddSampleDriver`) o configurazioni multi-GPU, consulta la guida [**docs/troubleshooting.md**](troubleshooting.md) per le istruzioni di risoluzione rapida.

### Linux (Debian / Ubuntu)
Installa il pacchetto `.deb` scaricato:

```bash
sudo apt install ./PiFrame-…-linux-amd64.deb
```

Il pacchetto aggiunge PiFrame al menu applicazioni e include daemon e runtime Node.

### Web Locale (`http://127.0.0.1:<porta>/`)
1. Il daemon `pi-agentd` include un server statico HTTP integrato per gli asset web di Flutter.
2. Aprendo `http://127.0.0.1:<porta>/` da browser locale, il server imposta automaticamente un cookie `HttpOnly; SameSite=Strict` contenente il token di autenticazione PCP (`pcp_token`), consentendo l'accesso immediato senza configurazione manuale.

### Build Manuale da Sorgente (Eseguibile Standalone)
Se compili manualmente l'eseguibile desktop da sorgenti anziché utilizzare l'installer (ad es. `flutter build windows --release`):
1. Assicurati di compilare il daemon: `pnpm build:all` (o `pnpm build:agentd`).
2. Per consentire all'applicazione di avviare il sidecar automaticamente all'avvio, copia `apps/agentd/dist/pi-agentd.cjs` e l'eseguibile `node.exe` nella cartella di output del runner (es. `apps/pi_frame/build/windows/x64/runner/Release/`).
3. Per i dettagli operativi o in caso di anomalie di blocco file (`EBUSY`), fai riferimento a [**docs/troubleshooting.md**](troubleshooting.md#4-daemon-non-raggiungibile-o-errore-di-connessione-con-build-da-sorgente).

---

## 4. Ciclo di Vita del Daemon (D8, D9)

- **Avvio on-demand**: Il daemon non è un servizio di sistema persistente. La GUI controlla `GET http://127.0.0.1:<porta>/api/health`; se non attivo, avvia il bundle `pi-agentd.cjs` con il runtime Node incluso in modalità `detached`.
- **Lock e Token**:
  - File di runtime: `~/.piframe/runtime/daemon.json` (porta e PID).
  - File di lock: `~/.piframe/runtime/daemon.lock` per prevenire istanze duplicate.
  - Token di autenticazione: generato a 256 bit in `~/.piframe/runtime/daemon.token` con permessi ristretti (0600).
- **Log Rotativo**:
  - File di log: `~/.piframe/runtime/daemon.log`.
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

La rimozione di PiFrame è pulita, confinata e reversibile:

1. **Rimuovi l'applicazione GUI**:
   - macOS: Sposta `PiFrame.app` nel Cestino.
   - Windows: Elimina la cartella dell'applicazione o disinstalla da Impostazioni Applicazioni.
2. **Arresta il daemon** (se attivo):
   - Termina il processo `pi-agentd` dal task manager o tramite `kill <PID>`.
3. **Elimina i dati locali di PiFrame**:
   ```bash
   # macOS / Linux
   rm -rf ~/.piframe

   # Windows PowerShell
   Remove-Item -Recurse -Force "$HOME\.piframe"
   ```

### Garanzia di Integrità per `~/.pi/`
> [!IMPORTANT]
> PiFrame opera rigorosamente con approccio non invasivo. La directory di Pi (`~/.pi/`), contenente la cronologia delle sessioni, le credenziali e le estensioni, **non viene toccata né rimossa**.
> Tutte le sessioni originali rimangono pienamente utilizzabili dal CLI ufficiale di Pi anche dopo la disinstallazione di PiFrame.
