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
- **Pi Coding Agent** (non incluso nell'installer): versione minima **v0.85.0**, da installare e tenere su `PATH`. Può essere installato direttamente dall'interfaccia di primo avvio di PiFrame oppure tramite i comandi ufficiali:
    - macOS / Linux: `curl -fsSL https://pi.dev/install.sh | sh`
    - Windows: `powershell -c "irm https://pi.dev/install.ps1 | iex"`
    - Via npm: `npm install -g @earendil-works/pi-coding-agent`

### MCP Dart/Flutter per Pi

PiFrame usa il server ufficiale integrato Dart/Flutter configurato a livello utente in `~/.pi/agent/mcp.json` (`dart mcp-server`, esposizione differita). Serve Flutter/Dart SDK su `PATH`. Da root del progetto, verifica con `pi mcp list`; lo stato atteso è `dart · connected`. PiFrame avvia worker RPC con la workspace come `cwd`, quindi il server si aggancia al progetto attivo senza richiedere trust locale. Gli strumenti sono scoperti on demand tramite `tool_search`.

---

## 3. Installazione

Scarica l'installer più recente dalla [pagina GitHub Releases](https://github.com/TrentiStefano/piframe/releases/latest). I commit Conventional (`fix`, `feat`, `BREAKING CHANGE`) aggiornano il PR di release SemVer; quando il PR viene unito, GitHub Actions pubblica installer Windows, macOS Intel/Apple silicon e Linux x64 con screenshot aggiornato.

### macOS
1. Apri il file `.dmg` e trascina `PiFrame.app` nella cartella `/Applications` (la finestra del DMG include direttamente la guida `LEGGIMI - Come aprire l'app.txt` / `README - How to open.txt` con le istruzioni immediate passo-passo).
2. Al primo avvio, PiFrame avvia automaticamente `pi-agentd` sfruttando il runtime Node integrato nel pacchetto.
3. **Avviso di sicurezza Gatekeeper (Apple Developer ID e Notarizzazione):**
   - Poiché Apple richiede un abbonamento annuale a pagamento all'**Apple Developer Program ($99 USD/anno)** per rilasciare certificati *Developer ID Application* e consentire la notarizzazione tramite `notarytool`, le release open-source distribuite gratuitamente non possono essere notarizzate senza costo.
   - Il binario viene regolarmente firmato in modalità ad-hoc (`codesign --force --deep --sign -`) nella pipeline di build GitHub Actions per garantire la corretta esecuzione architetturale su Apple Silicon (`arm64`) e Intel (`x64`).
   - Quando scarichi l'applicazione dal browser, macOS vi associa l'attributo di quarantena `com.apple.quarantine`. Per avviarla la prima volta puoi procedere in due modi:
     - **Da Impostazioni di Sistema (macOS 14 Sonoma / 15 Sequoia):** apri PiFrame (verrà mostrato il messaggio di Gatekeeper), recati in **Impostazioni di Sistema → Privacy e sicurezza**, scorri fino alla sezione **Sicurezza** e fai clic su **Apri comunque**, confermando con password o Touch ID.
     - **Da Terminale (metodo rapido a riga di comando):**
       ```bash
       xattr -cr /Applications/PiFrame.app
       ```
       Questo comando rimuove i flag di quarantena dal bundle di PiFrame consentendone l'apertura diretta con doppio clic.

### Windows
1. Avvia `PiFrame-Setup-…-windows-x64.exe`.
2. L'installer aggiunge collegamenti nel menu Start; icona desktop è facoltativa.
3. PiFrame include e avvia `pi-agentd` con Node integrato e i runtime Microsoft Visual C++ CRT (`msvcp140.dll`, `vcruntime140.dll`, ecc.) in modalità app-local per funzionare anche su installazioni pulite di Windows. Installer non firmato può mostrare l'avviso SmartScreen.

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
1. Dalla radice del monorepo, aggiorna prima il daemon: `pnpm build:agentd` (o `pnpm build:all`). La build Windows rifiuta un bundle assente o privo dell'indice rapido e della risposta da snapshot cache.
2. Compila l'app Flutter. CMake copia `apps/agentd/dist/pi-agentd.cjs` accanto all'eseguibile. Copia anche `node.exe` nella stessa cartella se il runtime Node non è già presente.
3. Se il daemon gira già, lascia terminare i worker attivi e usa **Impostazioni → Riavvia Daemon** per caricare il bundle aggiornato. Ricompilare l'app non arresta un daemon già in esecuzione.
4. Per i dettagli o in caso di anomalie di blocco file (`EBUSY`), consulta [**docs/troubleshooting.md**](troubleshooting.md#4-daemon-non-raggiungibile-o-errore-di-connessione-con-build-da-sorgente).

### Generazione Locale dell'Installer Windows (Setup Inno Setup)
Per compilare e generare l'installer completo per Windows (`dist/PiFrame-Setup-<versione>-windows-x64.exe`) esattamente come avviene nella pipeline CI/CD di GitHub Actions:
1. Assicurati che **Inno Setup 6** sia installato (es. via `winget install JRSoftware.InnoSetup`).
2. Dalla radice del monorepo, esegui il comando:
   ```powershell
   pnpm run package:windows
   ```
   oppure direttamente con PowerShell:
   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/scripts/package-windows-installer.ps1
   ```
   Lo script esegue l'intera sequenza: compila i pacchetti TypeScript, crea il bundle del daemon (`pi-agentd.cjs`), compila l'app Flutter Windows e l'app Web per l'accesso remoto, predispone il runtime Node con le licenze e compila il setup `.exe` in `dist/`. Per ri-impacchettare senza ricompilare Flutter, puoi passare il flag `-SkipBuild`.

### Generazione Locale dell'Installer macOS (DMG)
Per compilare e generare l'immagine disco installer per macOS (`dist/PiFrame-<versione>-macos-<arch>.dmg`) in locale o completamente offline:
> [!NOTE]
> La compilazione nativa dell'applicazione macOS (`.app`) e la creazione del `.dmg` compresso tramite l'utility di sistema `hdiutil` richiedono l'esecuzione su un sistema macOS (con Xcode Command Line Tools, Flutter SDK e Node.js). Apple non rende disponibili gli SDK proprietari Cocoa/Metal su Windows o Linux.

1. Da un computer macOS, posizionati nella radice del monorepo ed esegui:
   ```bash
   pnpm run package:macos
   ```
   oppure direttamente tramite lo script bash:
   ```bash
   bash tools/scripts/package-macos-dmg.sh
   ```
2. Lo script esegue automaticamente tutta la sequenza:
   - Compila il pacchetto `@piframe/pcp-ts` e il bundle del daemon (`pi-agentd.cjs`).
   - Compila la Web App Flutter (`flutter build web --release`).
   - Compila l'applicazione macOS (`flutter build macos --release`).
   - Confeziona il bundle `PiFrame.app` con il runtime Node integrato, licenze e web assets.
   - Applica la firma ad-hoc (`codesign`).
   - Include il symlink per `/Applications` e le guide `LEGGIMI - Come aprire l'app.txt` / `README - How to open.txt`.
   - Crea il file compresso `dist/PiFrame-<versione>-macos-<arch>.dmg` tramite `hdiutil` (100% offline).
3. **Opzioni utili dello script:**
   - `--skip-build`: riutilizza i binari già compilati e rigenera solo il DMG.
   - `--build`: forza la ricompilazione completa di tutti i componenti anche se i binari esistono già.
   - Parametri opzionali: `bash tools/scripts/package-macos-dmg.sh [versione] [architettura] [--skip-build]`.

---

## Comandi slash di Pi nella chat

Nel composer digita `/` per vedere anche i comandi integrati di Pi, oltre a quelli forniti da estensioni, prompt e skill. `/login` e `/logout` mostrano il selettore dei provider e usano il flusso di autenticazione Pi; i campi per chiavi e token sono mascherati. Le credenziali restano nel deposito Pi e queste richieste sono disponibili solo nell’app locale, non dai client remoti. Gli altri comandi TUI non ancora disponibili via RPC mostrano un avviso e non vengono inviati al modello. Aggiorna PiFrame per ricevere il catalogo e l'instradamento aggiornati.

## Invio dei messaggi con Enter (Invia con Enter)

Nelle **Impostazioni** (sezione **Aspetto → Composer**) è disponibile l'opzione **Invia con Enter** (disattivata per impostazione predefinita):
- **Disattivato (default)**: premendo `Ctrl+Invio` (o `Cmd+Invio` su macOS) viene inviato il messaggio o applicato lo steer; premendo `Invio` viene inserita una nuova riga nel composer.
- **Attivo**: premendo `Invio` (o `Invio` da tastierino numerico) senza modificatori viene inviato il messaggio (o applicato lo steer se l'agente sta rispondendo); `Ctrl+Invio` / `Cmd+Invio` continua a inviare; premendo `Shift+Invio` viene inserita una nuova riga nel composer.
- Durante la composizione attiva con caratteri IME (es. input CJK), il tasto `Invio` conferma il testo senza inviare la richiesta in entrambe le modalità.
- Le preferenze vengono salvate in locale in `~/.piframe/composer_settings.json`.

## Statistiche nerd (Nerd stats) e monitoraggio delle risorse

Nelle **Impostazioni** (sezione **Aspetto → Statistiche nerd**, IT: *Statistiche nerd*, EN: *Nerd stats*) è disponibile l'opzione per abilitare la telemetria di sistema in tempo reale nella barra del titolo dell'applicazione (disattivata per impostazione predefinita):
- **Disattivato (default)**: la barra del titolo non mostra metriche hardware né contatori di frame; nessun comando di sottoscrizione viene inviato al daemon.
- **Attivo**: mostra un riquadro compatto a caratteri monospace nella barra superiore nel formato:
  `CPU 12.3% · RAM 48% · DISK 62% · GPU n/d · 60 FPS`
  Passando il cursore sopra il widget, un tooltip dettagliato espone l'utilizzo esatto della memoria RAM (usata / totale e percentuale), lo spazio disco sul volume principale dell'utente (usato / totale e percentuale), l'utilizzo GPU con VRAM e sorgente di rilevamento, nonché il frame rate di rendering.
- **Soglie di avviso**: se una risorsa supera l'85% di utilizzo, la relativa percentuale assume il colore di warning del tema attivo.
- **Dati non disponibili o obsoleti (`n/d`)**: se un sensore hardware o una metrica non è disponibile sul sistema host, oppure se nessun campionamento viene ricevuto dal daemon per oltre 5 secondi (o se la connessione cade), il valore viene mostrato come `n/d` senza mai inventare dati fittizi.
- **Contatore FPS (Frame per secondo)**: misurato lato client tramite i timing di rendering di Flutter (`SchedulerBinding.instance.addTimingsCallback`). Quando l'applicazione è inattiva o non necessita di ridisegno, il motore grafico non esegue rendering superfluo e il contatore riporta giustamente un valore basso o zero frame renderizzati nell'ultimo secondo; la frequenza di aggiornamento della UI delle statistiche è limitata a 1 Hz per prevenire rebuild continui.
- **Comportamento su Web**: nell'interfaccia Web (`http://127.0.0.1:<porta>/`), per motivi di sicurezza e assenza di accesso hardware diretto dal browser, il blocco delle metriche di sistema (CPU, RAM, disco, GPU) resta completamente nascosto e viene mostrato **esclusivamente il segmento FPS** locale del rendering client.
- **Supporto GPU per piattaforma (Daemon `pi-agentd`)**:
  - **NVIDIA**: supportata universalmente tramite `nvidia-smi` (Windows, Linux, macOS).
  - **Windows (DirectX / GPU engine)**: supportata tramite contatori di prestazioni `typeperf` (esclusivamente con locale di sistema inglese; su installazioni Windows con altre lingue o contatori localizzati dove i nomi dei contatori differiscono, la GPU mostra `n/d`).
  - **Linux (AMD)**: supportata tramite `sysfs` (`/sys/class/drm/card*/device/gpu_busy_percent`).
  - **macOS (Apple Silicon / Metal)**: supportata tramite `ioreg` (`PerformanceStatistics`).
  - **Altre schede o ambienti senza probe supportati**: mostra `n/d`.
- **Zero telemetria (Strict Local-Only)**: Il campionamento delle risorse avviene esclusivamente in locale tramite il protocollo PCP (`system.metrics.subscribe` e `system.metrics`) tra il daemon `pi-agentd` locale e il client Flutter. Nessun dato di metrica o telemetria viene memorizzato permanentemente o inviato all'esterno. Le preferenze vengono salvate localmente in `~/.piframe/nerd_stats_settings.json`.

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

