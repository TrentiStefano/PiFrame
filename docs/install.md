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

## Comandi slash di Pi nella chat

Nel composer digita `/` per vedere anche i comandi integrati di Pi, oltre a quelli forniti da estensioni, prompt e skill. PiFrame esegue nella GUI i comandi con un'azione equivalente; i comandi della TUI non disponibili via RPC mostrano un avviso e non vengono inviati al modello. Aggiorna PiFrame per ricevere il catalogo e l'instradamento aggiornati.

## Modelli abilitati e limiti di contesto

In **Area di lavoro → Sessione → Dimensione Contesto** scegli un tier oppure **Custom**. Per GPT-6 Luna le opzioni sono `Custom`, `272k (Tier base)` e `1M (Max / Tier esteso)`, salvo soglie diverse dichiarate dal catalogo del provider. Solo Custom mostra lo slider della finestra massima: **100.000–1.000.000 token**, a passi di **50.000**. Il massimo viene sempre ridotto alla capacità del modello e alla griglia disponibile; sotto 100k Custom non è disponibile. I tier del provider mantengono il loro valore esatto, anche se non sono multipli di 50k.

Il chip contesto nella chat apre lo stesso selettore, con tier e Custom sincronizzati con Area di lavoro. Se il catalogo non era ancora disponibile al primo avvio, il click lo ricarica; un errore viene mostrato, non ignorato. Gli slider mostrano il valore durante il trascinamento e lo applicano al rilascio, evitando richieste per ogni movimento.

Lo slider **Margine per compattazione (%)** va da **0,5% a 25%**, a passi di **0,5%**. Indica la quota da lasciare libera, non la quota da riempire:
- 200.000 token, margine predefinito 2,5% → soglia 195.000 token.
- 1.000.000 token, margine 5% → soglia 950.000 token.

PiFrame applica la soglia al runtime Pi, anche fra le continuazioni con strumenti; al termine di un turno compatta se la soglia è stata raggiunta. Non ci sono più controlli separati all'80% nella GUI. La compattazione automatica disabilitata in Pi resta disabilitata. Attendi la fine del turno prima di modificare questi valori. Limite e margine sono salvati per sessione in `~/.piframe/context/`, ripristinati alla riapertura e copiati nelle duplicazioni. Quando passi a un modello più piccolo, il limite viene ridotto al suo massimo.

Il controllo usa un'estensione interna caricata solo nei worker PiFrame; non installa `max-context` e non modifica le impostazioni o le credenziali in `~/.pi/`. Richiede l'API estensioni `getSettings` di Pi; verificato con **Pi 1.4.0**. Se la versione non la supporta, l'app segnala che il limite non è stato applicato: aggiorna Pi e riavvia il worker.

Come [max-context](https://github.com/indie-arch/max-context), è un controllo preventivo basato sull'uso/stima dei token: non una garanzia contabile sul costo. Un singolo input, output di strumento o risposta può superare il margine prima della successiva verifica; anche la richiesta di riepilogo usa token. Usa un margine più ampio per strumenti con output grandi. Limiti molto bassi possono non contenere prompt di sistema, strumenti e messaggi recenti conservati da Pi.

Il picker GitHub Copilot verifica il catalogo autenticato e le policy dell'organizzazione prima di applicare gli eventuali filtri locali `enabledModels`. Non abilita modelli e non cambia policy GitHub. Se la verifica fallisce, i modelli Copilot non verificati restano nascosti e compare un avviso; gli altri provider restano disponibili. Una verifica riuscita viene memorizzata brevemente: una modifica delle policy può richiedere fino a un minuto per apparire.

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

---

## 7. Paginazione e Caricamento On-Demand della Cronologia

Nelle sessioni con cronologia molto estesa (migliaia di messaggi o log di tool voluminosi):
1. **Snapshot iniziale leggero**: all'apertura, il demone trasferisce una finestra recente delimitata ai 100 messaggi più recenti, garantendo un caricamento istantaneo e azzerando la pressione sulla memoria RAM e sui buffer WebSocket.
2. **Caricamento a ritroso on-demand**: in cima alla chat, il pulsante dinamico *"Carica altri messaggi dalla cronologia"* consente di recuperare blocchi incrementali di messaggi precedenti tramite il comando `session.getHistory`, preservando la posizione di scorrimento senza salti visivi.
3. **Integrità assoluta**: l'intero archivio storico resta conservato su disco in `~/.pi/agent/sessions/` e può essere sfogliato progressivamente a ritroso fino al primissimo messaggio della sessione.

