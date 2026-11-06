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

## Pannello Agenti e Workflow

Quando l'agente principale avvia sottoagenti in background (`Agent`) o workflow (`SubagentWorkflow` di `@tintinweb/pi-subagents`), a destra della chat si apre il pannello **Agenti**. Quando il pannello si apre, anche entrando in una sessione dove era già aperto o con agenti al lavoro, il pannello Git Changes/Browser viene minimizzato; durante una review resta visibile. Chiuso, il pannello resta una striscia verticale con il numero di agenti attivi; un clic lo riapre. Il pannello non compare sotto i 900 px di larghezza.

Il pannello mostra gli agenti come un albero che parte dalla **Sessione principale**:

- **Workflow**: nome, stato, durata, una barra con un segmento per agente (verde finito, colorato al lavoro, rosso errore) e le fasi dichiarate in `meta`. Sotto il workflow sono agganciate le sue sessioni figlie, cioè gli agenti avviati mentre il workflow era attivo. Il percorso dello script non viene mostrato. Espanso, mostra descrizione e risultato finale; se il daemon non fornisce le sessioni figlie, sull'app desktop usa il journal `<runId>.workflow.jsonl`.
- **Agenti**: compito (per gli agenti di workflow, la prima riga del prompt che non condividono con gli altri, per esempio `COMPITO: …`), tipo, modello, costo (o `N/D`), durata e attività corrente: lo strumento in uso con il suo argomento principale mentre lavora, l'ultima riga della risposta quando ha finito. I rami attivi hanno un anello animato e una scintilla che scorre lungo il collegamento. Espanso, un agente mostra l'output; gli agenti `Agent` hanno anche guida (steer) e interruzione.

Il daemon legge l'attività dai file di sessione delle sessioni figlie (`~/.pi/agent/sessions`). Una sessione figlia senza attività per 10 minuti è considerata terminata. Lo stato finale degli agenti usa anche i record `subagents:record` salvati da pi-subagents. Serve un daemon aggiornato: con un daemon precedente il pannello mostra solo nome e stato.

Nel menu `/agents`, la voce **Workflows (N)** apre questo pannello invece della vista TUI, che non è disponibile in RPC. Nella barra Sessioni, una sessione resta segnata come in corso finché i suoi sottoagenti o workflow in background non terminano.

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

---

## 8. Navigazione e Cambio Branch Git nel Workspace

Il runtime di PiFrame (`pi-agentd`) include il supporto nativo per l'ispezione e il cambio controllato dei rami Git (`workspace.listBranches` e `workspace.switchBranch`):
- **Enumerazione e Tracking**: restituisce tutti i rami locali con indicatore del ramo corrente, stato di tracking upstream (`ahead` / `behind`), data dell'ultimo commit e rilevamento di HEAD staccata (detached HEAD).
- **Protezione Anti-Sovrascrittura**: il cambio ramo rifiuta working tree sporchi (`onDirty: 'block'`, predefinito) segnalando il numero esatto di file modificati e non tracciati. Con `onDirty: 'stash'`, le modifiche pendenti vengono archiviate in modo sicuro nello stash Git (`piframe: before switching to <name> (<iso time>)`) prima dello switch, con ripristino automatico via `git stash pop` in caso di fallimento del checkout.
- **Isolamento e Sicurezza**: i comandi sono rigorosamente confinati al repository della sessione corrente, eseguiti senza shell (`shell: false`) con argomenti array, protetti da injection su nomi di ramo non validi e respinti per sessioni in sola lettura o mentre l'agente sta lavorando.
- **Interfaccia Utente (Branch Picker & Gestione Modifiche)**: nel pannello Git Changes, il ramo corrente è visualizzato come chip interattivo (con icona e commit SHA in caso di HEAD detached). Cliccandolo si apre un selettore rapido con ricerca, navigazione da tastiera (frecce, Invio, Esc) e stato di tracking (↑n ↓m). Se vi sono file non salvati, una finestra di dialogo di sicurezza blocca il cambio e richiede la conferma esplicita per archiviare nello stash o annullare, mostrando notifiche e dettagli chiari in caso di errori o recupero stash.

---

## 9. Raggruppamento dei Passaggi Intermedi (Step Grouping)

PiFrame organizza in modo compatto e leggibile i passaggi intermedi eseguiti dall'assistente durante un turno di conversazione (blocchi di ragionamento / thinking, chiamate agli strumenti / tool calls e testi intermedi), lasciando in risalto la risposta finale:

- **Modalità di raggruppamento (Step Grouping Modes)**:
  - **Con ragionamento (`withThinking`, predefinita)**: raggruppa automaticamente i turni che contengono blocchi di ragionamento (sia storici sia durante lo streaming).
  - **Sempre (`always`)**: raggruppa qualsiasi turno che presenti almeno un passaggio intermedio (thinking, chiamata a tool o testo intermedio).
  - **Disattivato (`off`)**: disattiva il raggruppamento; ogni messaggio, tool call e blocco di ragionamento viene visualizzato singolarmente nel flusso normale della chat con rendering pixel-identico alla visualizzazione classica.
- **Compressione automatica (Auto-collapse, attiva per impostazione predefinita)**:
  - Al termine di un turno o all'apertura della sessione, i passaggi intermedi raggruppati vengono compressi automaticamente mostrando un header sintetico con il conteggio dei tool usati, il tempo trascorso e l'estratto del ragionamento.
  - Cliccando sull'header o premendo Invio/Spazio con il focus, la fisarmonica si espande o comprime istantaneamente con animazione fluida.
  - La preferenza utente (modalità di raggruppamento e auto-collapse) viene salvata nelle preferenze locali e ricordata tra le sessioni.
- **Elenco compatto dei passaggi**: un gruppo espanso occupa al massimo metà dell'altezza della finestra. Se i passaggi sono di più, l'elenco scorre al suo interno (durante l'esecuzione segue l'ultimo passaggio, se sei già in fondo). In basso, il pulsante **Mostra tutti i passaggi (N)** espande l'elenco a tutta altezza. Quando il gruppo viene compresso (a mano o a fine turno) e poi riaperto, torna l'elenco compatto.
- **Stato del turno**: un turno che arriva alla risposta finale mostra *Completati N passaggi*, con un'icona di avviso se qualche passaggio è fallito. *Interrotto con errori* compare solo se il turno stesso è terminato in errore; *Interrotto dopo N passaggi* se l'utente lo ha fermato. La risposta finale resta sempre fuori dal gruppo.

---

## 10. Gestione Subagenti e Limiti di Contesto (Subagents Settings)

PiFrame include il supporto nativo per l'ispezione e la configurazione dei subagenti (`pi.agents.get` e `pi.agents.update`):
- **Auto-Discovery dei Pacchetti e Profili**: rileva automaticamente i pacchetti di subagenti installati (`pi-subagents` di nicobailon e `@tintinweb/pi-subagents`), gli agenti nativi, gli agenti definiti dall'utente in `~/.pi/agent/agents/` e gli agenti di progetto in `.pi/agents/`.
- **Risoluzione Valori Effettivi**: calcola con precisione il modello e il livello di thinking effettivi per ciascun agente tracciandone l'origine esatta (`override`, `frontmatter`, `default` o `none`) e la disponibilità con le credenziali attive.
- **Limiti di Contesto Dedicati**: consente di impostare limiti di finestra di contesto (tier di costo) specifici per ciascun subagente. Il daemon genera un'estensione leggera e isolata in `~/.piframe/runtime/subagent-context-limit.mjs` agganciata tramite `subagentOnlyExtensions`, che adatta la finestra di contesto del modello solo all'avvio del subagente specificato senza interferire con la sessione principale o i binari installati. *(Nota: prima di disinstallare PiFrame o rimuovere `~/.piframe`, azzera i limiti di contesto nella scheda Agenti o rimuovi il percorso da `~/.pi/agent/settings.json` in `subagents.agentOverrides.<name>.subagentOnlyExtensions` per evitare errori `ERR_MODULE_NOT_FOUND` al successivo avvio dei subagenti in Pi CLI).*
- **Scrittura Sicura e Lock Compatibile**: le modifiche a `settings.json` avvengono con lock compatibile con `proper-lockfile` di Pi (rilevamento stale lock a 10 secondi), backup automatico `settings.json.piframe-backup` e scrittura atomica, rifiutando file JSON non validi (`AGENTS_CONFIG_UNREADABLE`) e impedendo qualsiasi mutazione da dispositivi remoti (`REMOTE_FORBIDDEN`).
- **Interfaccia Utente (Scheda Impostazioni 'Agenti')**:
  - **Header e Pacchetti**: visualizzazione dinamica dei pacchetti rilevati con versione (`pi-subagents`, `@tintinweb/pi-subagents`). Se nessun pacchetto è installato, viene mostrato un banner esplicativo con istruzioni per l'installazione via CLI (`pi install pi-subagents`) o dalla scheda Pacchetti, senza liste inventate. Eventuali avvisi di configurazione dal daemon sono riportati in evidenza. Una nota ricorda che le modifiche si applicano globalmente a Pi (anche da terminale) e alle nuove sessioni ed esecuzioni di sottoagenti.
  - **Card Default per nuove sessioni**: selezione del modello predefinito per le sessioni primarie Pi (il dropdown include solo i modelli disponibili con avviso in caso di credenziali assenti) e del livello di thinking (limitato a `off` se il modello non supporta il reasoning). Tasto *Reimposta* dedicato per rimuovere il default.
  - **Card Default sottoagenti**: configurazione dei default globali dei sottoagenti (modello e thinking per `pi-subagents` o agente di fallback per `@tintinweb/pi-subagents`), con tasti di reset e avvisi per modelli non disponibili.
  - **Elenco Agenti**: visualizzazione dettagliata di tutti gli agenti scoperti, con badge della sorgente (`builtin`, `user`, `project`, `package`), descrizione, modello effettivo con badge d'origine (`override`, `frontmatter`, `default`), thinking effettivo e selettore tier di contesto (es. `272k`, `1.05M (full)`) solo se supportato (altrimenti `n/d` con tooltip *Model has a single context tier*). Gli agenti non modificabili (es. runner CLI esterni, progetti o tintinweb) appaiono disabilitati con tooltip che riporta la `readOnlyReason`. Ogni campo dispone di tasto *Reset* che invia `null` per cancellare l'override.
  - **Barra di Salvataggio e Sicurezza Remota**: pulsante *Salva modifiche* (abilitato solo quando lo stato è sporco / dirty), pulsante *Annulla* per scartare le modifiche locali, visualizzazione inline degli errori di validazione per campo (`AGENTS_VALIDATION_FAILED`), notifica snackbar di successo e blocco con avviso in sola lettura in caso di accesso remoto (`REMOTE_FORBIDDEN`).

---

## 11. Conversazioni Laterali Read-Only (Side Conversations)

PiFrame introduce il supporto per conversazioni laterali effimere e di sola lettura (`side.open`, `side.prompt`, `side.abort`, `side.close`):
- **Assistente di Consultazione Read-Only**: permette di porre domande di approfondimento o chiarimento ("Spiega questa funzione", "Rivedi i test", "Quali vincoli sono emersi?") operando su uno snapshot immutabile della conversazione principale e consentendo all'assistente di consultare i file del workspace.
- **Isolamento Matematico del Transcript e della Sessione**:
  - Il file della sessione principale in `~/.pi/agent/sessions/` non viene mai alterato o riscritto ed è byte-per-byte identico prima, durante e dopo ogni operazione laterale.
  - Nessun evento della conversazione laterale inquina il journal degli eventi della sessione principale.
  - Gli eventi della conversazione laterale sono veicolati su un flusso dedicato (`streamId = side_<ulid>`) e trattenuti esclusivamente in un buffer in memoria ad anello confinato al ciclo di vita del daemon per consentire la riconnessione dei client, senza mai eseguire spill su disco.
- **Strumenti Rigidamente Confinati (`read, grep, find, ls`)**: il worker della conversazione laterale è avviato con `--tools read,grep,find,ls`, `--no-mcp`, `--no-extensions` e `--no-skills`. Gli strumenti di scrittura e mutazione (`bash`, `edit`, `write`) sono tassativamente esclusi e qualsiasi tentativo di invocazione RPC differente da `prompt`, `abort` o `get_state` viene interdetto dal daemon (`SIDE_RPC_BLOCKED`). Se all'avvio il worker esponesse strumenti non consentiti, viene abbattuto all'istante con `SIDE_UNSAFE_TOOLS`.
- **Snapshot Criterioso e Pulizia Automatica**:
  - Lo snapshot della conversazione attiva viene serializzato con preambolo di guardrail in `~/.piframe/runtime/side/<sideId>/context.md` (directory con permessi `0700` e file `0600`) e passato via `--append-system-prompt`.
  - Lo snapshot è cappato a ~120.000 caratteri preservando le interazioni più recenti e includendo una notifica esplicita di troncamento se la soglia viene raggiunta.
  - La directory temporanea viene distrutta all'atto della chiusura della conversazione laterale o all'arresto del daemon.
- **Regole di Concorrenza e Sicurezza**:
  - Massimo 1 thread laterale attivo per ciascuna sessione genitore (chiamate successive restituiscono il thread esistente).
  - Massimo 4 thread laterali contemporaneamente attivi sull'intero host (`SIDE_LIMIT_REACHED`).
  - Timeout di inattività a 10 minuti (`reason: 'idle'`) con arresto automatico del worker.
  - Terminazione immediata in caso di chiusura della sessione genitore (`reason: 'parentClosed'`).
  - Connessioni remote: l'apertura e l'invio di prompt richiedono la modalità `control` (`REMOTE_FORBIDDEN` in `view`), mentre abort e chiusura sono permesse anche in modalità `view`. Qualsiasi comando estraneo indirizzato allo stream laterale viene respinto con `SIDE_STREAM_READ_ONLY`.
- **Interfaccia Utente & Comandi Client (Flutter)**:
  - **Comandi Slash Built-in**: `/side [domanda]` e `/btw [domanda]` gestiti localmente dal composer (mai inviati come prompt all'agente principale). Presenti nel menu slash con la descrizione *"Conversazione laterale in sola lettura"*.
  - **Scorciatoia da Tastiera & Command Palette**:
    - Scorciatoia globale: `Ctrl+Shift+B` (Linux/Windows) o `Cmd+Shift+B` (macOS) per aprire/chiudere il pannello laterale nella sessione corrente.
    - Voce dedicata nella Command Palette (`Ctrl+K` / `Cmd+K`): *"Conversazione laterale (Ctrl+Shift+B)"*.
  - **Pannello Laterale Agganciato (Side Panel)**:
    - Drawer/pannello ancorato sulla destra del transcript con token semantici `pi_frame_theme` e stringhe localizzate `AppStrings`.
    - Intestazione con badge `Side · read-only`, chip del modello attivo e nota *"Non fa parte della conversazione principale"*.
    - Mini transcript che riusa i componenti `RichContent`, `ThinkingBlock` e `ToolCard`.
    - Mini composer per domande di follow-up con gestione della preferenza Enter-to-send.
    - Pulsante **Stop** (`side.abort`) per interrompere l'elaborazione in corso e pulsante **Chiudi** (`side.close`) con dialogo di conferma che attesta che nessun dato andrà perso dalla conversazione principale.
    - Azione **"Inserisci nel composer"** per ciascuna risposta dell'assistente che appende il testo alla bozza del composer principale esclusivamente su click esplicito.
    - Gestione delle causali di chiusura thread (`idle`, `parentClosed`, `error`, `user`) con banner di notifica dedicato.




