# Risoluzione Problemi e Casi Noti (Troubleshooting & Known Issues)

Questo documento raccoglie diagnosi, cause radice e soluzioni per anomalie note legate all'ambiente di esecuzione desktop e web di **PiFrame**.

---

## Modelli Copilot non autorizzati o tier di contesto ignorato

**Cause corrette:** il picker filtrava solo `enabledModels` locale, senza verificare le policy GitHub. Il limite di contesto era conservato in PiFrame ma non applicato a Pi; i controlli duplicati nella GUI e nel daemon usavano una soglia fissa all'80% e potevano ignorare gli errori.

**Comportamento attuale:** il daemon verifica le abilitazioni Copilot e rifiuta la selezione di un modello non autorizzato. Area di lavoro espone massimo personalizzato e margine percentuale; il worker applica la soglia alla compattazione nativa di Pi. Gli errori di applicazione non vengono più accettati come successo.

- Se il chip contesto nella chat mostra un tier ma non apre nulla, usa la build aggiornata: prima il composer poteva conservare un catalogo vuoto caricato prima della connessione al daemon. Ora ricarica i modelli al click e segnala esplicitamente i dati mancanti. Chat e Area di lavoro usano lo stesso selettore.
- Lo slider del massimo è nascosto finché non scegli **Custom** in Dimensione Contesto. I tier esatti (per esempio 272k) restano selezionabili; Custom usa passi di 50k. Il margine usa passi di 0,5%, da 0,5% a 25%.
- Se manca un modello Copilot, verifica account e abilitazione nella tua organizzazione. In caso di avviso di verifica, controlla rete e autenticazione con Pi; PiFrame non ripiega sul catalogo statico completo. La cache delle verifiche riuscite dura al massimo un minuto.
- Se compare **Pi non ha applicato il limite di contesto**, aggiorna Pi e riavvia il worker. Il controllo richiede `getSettings` nell'API estensioni; il test con runtime reale usa Pi 1.4.0.
- 5% significa compattare al **95%** del massimo scelto. Il valore predefinito 2,5% porta 200k a una soglia di 195k.
- Se non parte la compattazione, verifica che la compattazione automatica di Pi sia attiva. Modifica limite e margine a turno fermo.
- Se la compattazione fallisce o non riduce abbastanza il contesto, aumenta il limite o riduci il contesto conservato nelle impostazioni Pi. Un limite preventivo non può garantire un tetto di fatturazione: output singoli e richieste di riepilogo consumano token.

Verifica ripetibile da sorgente, senza chiamate a provider a pagamento: compila il daemon e avvia `node tools/scripts/smoke-context-policy.mjs`. Il test usa Pi reale con modello HTTP locale e directory temporanee isolate.

---

## 1. Windows: Finestra Bianca o Vuota all'Avvio (Blank / White Screen on Windows)

### Sintomi
All'avvio dell'applicazione desktop su Windows:
- La finestra di PiFrame si apre (con o senza cornice), il processo è attivo nel Task Manager e consuma memoria regolare.
- L'area di rendering (client area) rimane **completamente bianca** o **completamente nera**.
- L'applicazione non si blocca né genera eccezioni Dart nei log di sistema o nella console di debug (`flutter run`).
- **Comportamento identico su app vergini**: un'applicazione Flutter pulita generata con `flutter create` presenta lo stesso identico problema di rendering bianco.

### Causa Radice (Root Cause)
Il framework Flutter su piattaforma Windows si appoggia al backend grafico **ANGLE (Almost Native Graphics Layer Engine)** su Direct3D 11 (`EGL_PLATFORM_ANGLE_TYPE_D3D11_ANGLE`) e all'engine **Impeller / Skia**.

In presenza di:
1. **Driver di display virtuale o schermi secondari USB**:
   - `USB Mobile Monitor Virtual Display` (`ROOT\DISPLAY\0000`)
   - `IddSampleDriver`
   - Spacedesk, Duet Display, DisplayLink o monitor virtuali RDP/VNC
2. **Configurazioni ibride multi-GPU** (es. GPU integrata AMD Radeon/Intel + GPU dedicata NVIDIA GeForce RTX)
3. **Stato del Desktop Window Manager (DWM) corrotto** a seguito di uno spegnimento improvviso, crash di sistema (es. Evento 41 Kernel-Power) o risveglio da sospensione/ibernazione con perdita di contesto DirectX

Il Desktop Window Manager di Windows non finalizza la presentazione dello swapchain DirectX (`SwapChain11::present` o `EGLSurface`) verso la finestra figlia `FLUTTERVIEW`, lasciando visualizzato il background iniziale di sistema (bianco solido o nero trasparente) anche se l'albero dei widget e il motore di rasterizzazione di Flutter funzionano regolarmente.

*Riferimenti ufficiali alla issue di Flutter*:
- [flutter/flutter#149709: Flutter windows desktop screen comes up blank with 2 monitors connected to laptop](https://github.com/flutter/flutter/issues/149709)
- [flutter/flutter#160948: Impeller GPU calls fail to render on Windows (GLES)](https://github.com/flutter/flutter/issues/160948)
- [flutter/flutter#137321: Launching the app from a non-main monitor shows a white screen on Windows](https://github.com/flutter/flutter/issues/137321)

---

### Soluzioni e Risoluzione Rapida (Workarounds & Fixes)

#### Soluzione 1: Riavvio Pulito del Sistema (Clean Reboot)
Se l'anomalia compare dopo un crash, un aggiornamento driver o uno standby:
1. Riavvia Windows in modo completo (**Menu Start → Riavvia il sistema**, evitando l'avvio rapido "Fast Startup").
2. Al riavvio, il sottosistema DirectX / DWM ricrea i contesti EGL/ANGLE in modo pulito e l'interfaccia si avvia regolarmente.

#### Soluzione 2: Disabilitare o Scollegare i Display Virtuali / Secondari
Se il problema persiste dopo il riavvio:
1. Apri **Gestione Dispositivi** (`devmgmt.msc`).
2. Espandi la voce **Schede video** (Display adapters).
3. Se è presente un dispositivo virtuale (ad esempio `USB Mobile Monitor Virtual Display`, `IddSampleDriver` o simili):
   - Fai clic destro sul dispositivo virtuale e seleziona **Disabilita dispositivo** (o scollega l'applicazione di mirroring dello smartphone).
4. Avvia nuovamente PiFrame.

#### Soluzione 3: Assegnare la GPU Dedicata (Impostazioni Grafica Windows)
In sistemi con grafica integrata e scheda grafica dedicata (es. AMD + NVIDIA):
1. Apri **Impostazioni di Windows → Sistema → Schermo → Grafica**.
2. Aggiungi l'eseguibile `PiFrame.exe` (situato in `C:\Program Files\PiFrame\` o nella directory di installazione).
3. Fai clic su **Opzioni** e seleziona **Prestazioni elevate** (NVIDIA GeForce RTX) per forzare l'uso dell'adattatore D3D11 primario anziché il fallback software o integrato.

---

## 2. Connessione Remota: Pagina Fallback "Il daemon locale è attivo"

### Sintomi
Scansionando il QR code con lo smartphone o aprendo l'URL Tailscale / Cloudflare:
- Sul telefono appare una pagina con un riquadro statico recante il titolo *"PiFrame Daemon"* e il testo *"Il daemon locale è attivo e operativo su loopback"*, senza caricare l'interfaccia interattiva di PiFrame.

### Causa
Il daemon `pi-agentd` non trovava la directory compilata della web app Flutter (`apps/pi_frame/build/web`), attivando la pagina di cortesia statica di emergenza.

### Risoluzione
1. I percorsi di ricerca del daemon sono stati estesi per cercare automaticamente `apps/pi_frame/build/web`, `~/.piframe/web/` e la cartella `web/` adiacente all'eseguibile.
2. La web app compilata viene sincronizzata in `~/.piframe/web/` e inclusa negli installer di rilascio.
3. Se esegui da sorgenti, compila la versione web con:
   ```bash
   cd apps/pi_frame
   flutter build web --no-web-resources-cdn
   ```
   e copia i file generati in `~/.piframe/web/`.

## 3. Web App: Browser Integrato nel Browser

### Caso d'uso
Nella versione web di PiFrame visualizzata da smartphone o browser remoto, il pulsante e il pannello del *Web Browser integrato* sono stati intenzionalmente rimossi:
- Su dispositivi remoti (es. iPhone, Android, browser esterno), aprire un browser all'interno di una webview incorporata è ridondante e WebView2 è una tecnologia nativa desktop Windows.
- La modalità remota web espone unicamente le aree di lavoro pertinenti: **Chat**, **File Explorer** e **Git Changes**.

---

## 4. Daemon Non Raggiungibile o Errore di Connessione con Build da Sorgente

### Sintomi
Avviando l'eseguibile `PiFrame.exe` compilato manualmente da sorgenti (ad esempio da `apps/pi_frame/build/windows/x64/runner/Release/PiFrame.exe`):
- L'applicazione si avvia ma mostra l'errore che non riesce a raggiungere o avviare il daemon di runtime (`pi-agentd`).
- Se avviato manualmente da terminale (`pnpm run:daemon`), l'applicazione si connette regolarmente.

### Causa
A differenza dell'installer ufficiale che pacchettizza automaticamente il sidecar, una build manuale di Flutter (`flutter build windows`) genera unicamente i binari dell'interfaccia grafica. L'app cerca il daemon sidecar (`pi-agentd.cjs` e `node.exe`) nella directory adiacente a `PiFrame.exe`.

### Risoluzione
1. Compila il bundle del daemon dalla radice del monorepo:
   ```powershell
   pnpm build:all
   # oppure: pnpm build:agentd
   ```
2. Copia il bundle del daemon e l'interprete Node nella cartella di release di Flutter:
   ```powershell
   $releaseDir = "apps/pi_frame/build/windows/x64/runner/Release"
   Copy-Item "apps/agentd/dist/pi-agentd.cjs" $releaseDir -Force
   Copy-Item (Get-Command node).Source (Join-Path $releaseDir "node.exe") -Force
   ```
   In questo modo `PiFrame.exe` sarà in grado di avviare il daemon in background in autonomia ogni volta che viene aperto.

---

## 5. Installazione Dipendenze: Errore `EBUSY: resource busy or locked, symlink` (Windows)

### Sintomi
Eseguendo `pnpm install` o `pnpm build:all` su Windows, l'installazione fallisce con:
```text
EBUSY: resource busy or locked, symlink ...
"tsc" non è riconosciuto come comando interno o esterno
```

### Causa
Un processo attivo (un'istanza di `PiFrame.exe` in esecuzione, il daemon `pi-agentd` o il terminale) mantiene bloccate le cartelle dei pacchetti del monorepo mentre `pnpm` tenta di creare i collegamenti simbolici. Di conseguenza l'installazione delle dipendenze viene interrotta prima di collegare il compilatore TypeScript (`tsc`).

### Risoluzione
1. Termina eventuali istanze dell'app o del daemon:
   ```powershell
   Stop-Process -Name "pi-agentd","pi-frame","PiFrame" -ErrorAction SilentlyContinue
   ```
2. Riesegui l'installazione delle dipendenze e la build:
   ```powershell
   pnpm install
   pnpm build:all
   ```

---

## 6. CI/Release: Test Flutter, GitHub Pages o bundle Windows

### Messaggio utente duplicato nella chat

L'interfaccia mostra subito il messaggio inviato. Quando il daemon riceve la conferma da Pi, riconcilia l'evento con la voce ottimistica invece di aggiungere una seconda riga. Se l'invio fallisce, la bolla conserva testo e allegati: usa **Riprova** oppure fai doppio clic sulla bolla per modificarla nel composer. Per verificare questa logica, esegui:

```bash
cd apps/pi_frame && flutter test test/session_reducer_test.dart test/failed_message_flow_test.dart
```

### Test Flutter falliti in CI

Il test `resolvePathForOsExplorer correctly resolves WSL and Windows paths` copre l'output di Windows/WSL, prodotto solo quando `Platform.isWindows` è vero. Linux usa la risoluzione POSIX: il test Windows viene saltato lì e un test POSIX separato verifica quel comportamento. Se il test fallisce, esegui prima il test mirato e poi la stessa suite Flutter e analisi usate dalla CI:

```bash
cd apps/pi_frame && flutter test test/transcript_rich_test.dart
```

Dalla radice del repository, esegui i wrapper per tutti i test Flutter e l'analisi Flutter:

```bash
node tools/scripts/test-flutter.js
node tools/scripts/lint-flutter.js
```

### GitHub Pages restituisce 404

In **Repository Settings → Pages**, imposta **Build and deployment → Source** su **GitHub Actions**. Se la configurazione Pages fallisce, il job ora segnala il fallimento invece di nasconderlo; controlla il relativo step e i permessi del repository.

### Release Windows segnala l'eseguibile mancante

CMake produce `PiFrame.exe` e l'installer usa lo stesso nome. Il controllo del bundle nella workflow Release deve cercare `PiFrame.exe` (non `pi_frame.exe`). Verifica la coerenza localmente con:

```bash
node --test tools/scripts/test-windows-release-name.test.mjs
```

### Build Linux fallisce perché manca WebKitGTK

Se CMake segnala `None of the required 'webkit2gtk-4.1;webkit2gtk-4.2;webkit2gtk-4.3' found`, manca la libreria di sviluppo richiesta dal plugin `webview_win_floating`. Su Ubuntu 24.04 installa:

```bash
sudo apt-get install libwebkit2gtk-4.1-dev
```

La workflow Release installa questo pacchetto sia nella validazione sia nella build Linux. Il `.deb` dichiara anche `libwebkit2gtk-4.1-0` come dipendenza runtime: installalo con `sudo apt install ./PiFrame-<version>-linux-amd64.deb` per risolvere le dipendenze.

Verifica le dichiarazioni dalla radice del repository:

```bash
node --test tools/scripts/test-windows-release-name.test.mjs
```

Per distribuire anche la dipendenza runtime corretta, crea una nuova release che includa questo fix. **Actions → Release → Run workflow** dal ramo `main` con un tag precedente (per esempio `v1.1.0`) usa le dipendenze di build della workflow aggiornata, ma lo script di packaging rimane quello del vecchio tag: il `.deb` così ricostruito non include la nuova dichiarazione runtime. Rieseguire soltanto il vecchio run usa ancora la workflow priva del fix.

### Build Linux fallisce perché manca libnotify

Il plugin notifier di Flutter per Linux richiede che `pkg-config` trovi `libnotify`. Installa il pacchetto di sviluppo prima della build:

```bash
sudo apt-get install libnotify-dev
```

I pacchetti Debian installati richiedono anche la dipendenza runtime `libnotify4`. La CI di release installa `libnotify-dev` per la validazione e la build Linux; il pacchetto `.deb` dichiara `libnotify4`.

---

## 4. Disconnessione Continua WebSocket (Code 4009) e Accumulo Snapshot nel Giornale

### Sintomi
- PiFrame continua a disconnettersi e riconnettersi all'infinito ("Client too slow / backpressure buffer exceeded 128MB", close code `4009`) all'apertura o all'avvio dell'applicazione con sessioni pinnate molto grandi (es. > 100 MB).
- Lo spazio su disco nella cartella del giornale (`~/.piframe/journal/<sessionId>/`) cresce progressivamente fino a decine di gigabyte (es. 30 GB con centinaia di file `snapshot.<seq>.json`).

### Cause Radice
1. **Trascritto non vincolato nello snapshot**: all'attach della sessione, `SnapshotBuilder.build()` serializzava l'intero storico dei messaggi nel payload snapshot WebSocket. Per sessioni con migliaia di messaggi e output di tool voluminosi (es. 130-145 MB), il frame superava la soglia di backpressure di sicurezza di 128 MB implementata in `connection.ts`, provocando la chiusura della connessione con codice 4009. Poiché le sessioni pinnate vengono riattaccate in automatico all'avvio, l'applicazione entrava in un loop continuo di riconnessione.
2. **Assenza di retention policy negli snapshot del demone**: `EventJournal` genera un checkpoint di snapshot ogni 500 eventi per consentire il resume rapido senza rileggere l'intero log eventi. `Spill.ts` serializzava gli snapshot con indentazione estesa (`null, 2`) e non implementava alcuna rotazione o pulizia dei file storici, nonostante il caricamento (`loadLatestSnapshot()`) legga esclusivamente il file snapshot più recente.

### Risoluzione Implementata
1. **Finestra vincolata per lo snapshot (`SnapshotBuilder.ts`)**:
   - `SnapshotBuilder` delimita il numero di messaggi inclusi nel frame snapshot iniziale ai 100 più recenti (`MAX_SNAPSHOT_ENTRIES = 100`).
   - I singoli campi testuali anomali (es. dump di file massicci nei tool) sono protetti con un limite di sicurezza (`MAX_ENTRY_TEXT_BYTES = 256 KB`), riducendo la dimensione del payload da oltre 130 MB a circa 1.6 MB ed eliminando qualsiasi rischio di congestione WebSocket o freeze dell'interfaccia.
2. **Pulizia automatica e retention (`Spill.ts`)**:
   - Gli snapshot vengono scritti come JSON compatto senza indentazione inutile.
   - La funzione `pruneOldSnapshots(retainCount = 2)` mantiene solo i due snapshot più recenti e viene eseguita sia a ogni nuovo checkpoint sia all'inizializzazione del giornale (`init`), eliminando automaticamente tutti i checkpoint orfani accumulati e liberando lo spazio disco occupato.

---

## 5. Scrollbar a Scatti / Saltellante al Caricamento dei Messaggi Storici

### Sintomi
- Dopo aver cliccato "Carica altri messaggi dalla cronologia", il thumb della scrollbar si muove in modo scattoso ed errato, saltando su e giù anche se l'utente continua a scorrere fluidamente nella stessa direzione.
- Il pulsante caricava una quantità limitata di messaggi (35 alla volta), costringendo a ripetuti click per navigare trascrizioni lunghe.

### Cause Radice
1. **Stima dinamica instabile delle estensioni (`estimateMaxScrollOffset`)**: Flutter calcola `maxScrollExtent` per `ListView.builder` stimando l'altezza totale sulla media dei soli elementi attualmente visibili a schermo. In un'interfaccia di chat/log in cui un messaggio breve occupa 40px e un blocco di codice o tool diff occupa 800px, l'altezza stimata del totale variava bruscamente (es. da 10.000px a oltre 100.000px) tra un frame di scroll e l'altro, facendo rimbalzare la posizione relativa del cursore.
2. **Salto post-caricamento arbitrario (`jumpTo(oldOffset + diff)`)**: al caricamento dei messaggi storici in testa alla lista, l'applicazione tentava un salto proporzionale a una differenza di `maxScrollExtent` priva di layout reale, proiettando il cursore a offset non validi o fuori scala.
3. **Rebuild completi dell'albero dei widget durante lo scroll**: il listener di notifica scroll invocava `setState` su `_userScrolledUp` su ogni aggiornamento di scroll, invalidando l'intera vista trascritta durante il trascinamento.
4. **Doppio incremento di `_visibleCount`**: sia il callback del bottone che il ciclo di `build()` incrementavano il contatore di visibilità in risposta all'inserimento dei nuovi messaggi.

### Risoluzione Implementata
1. **Aumento quantitativo di caricamento a 250 messaggi (~7x)**:
   - In `Dispatcher.ts`, la soglia massima per `session.getHistory` è stata alzata fino a 1000 elementi con default a 250.
   - Nel frontend (`daemon_providers.dart` e `transcript_view.dart`), il pulsante carica 250 messaggi per click, mentre l'apertura iniziale mantiene 35 messaggi rapidi e performanti.
2. **`SmartTranscriptChildDelegate` e cache altezze per ID**:
   - Implementato un delegate personalizzato con cache persistente delle dimensioni effettive dei widget (`_MeasureSize`), indicizzata per ID messaggio stabile.
   - La stima di scorrimento (`estimateMaxScrollOffset`) utilizza la somma degli elementi già misurati più la media storica stabile per quelli ancora fuori viewport, rendendo la progressione della scrollbar strettamente monotona e priva di oscillazioni.
3. **Ancoraggio e preservazione della posizione di lettura**:
   - Al click su 'Carica altri messaggi', l'applicazione traccia la coordinata a schermo del primo messaggio visibile tramite `_anchorKey` e calcola l'altezza dei messaggi inseriti sopra.
   - Viene applicata una compensazione dell'offset pari all'altezza aggiunta con rifinitura sub-pixel al post-frame callback: il messaggio che l'utente stava leggendo rimane perfettamente immobile nella stessa identica posizione sullo schermo, evitando di saltare all'inizio dello storico. I messaggi precedenti rimangono consultabili scorrendo verso l'alto.
   - Estesa la cache dei widget a 2000px (`ScrollCacheExtent.pixels(2000.0)`) per evitare continue distruzioni e ricreazioni di elementi di grandi dimensioni.
4. **`ValueNotifier<bool>` per il floating button**:
   - La comparsa e scomparsa del pulsante per tornare in fondo alla chat è reattiva tramite `ValueListenableBuilder`, evitando qualsiasi `setState` globale dell'intera vista durante lo scroll.

---

## 6. Menu Modello Multipli, Messaggio "Non Consegnato" Errato, Domanda dell'Agente Bloccata

### Sintomi
- Cliccando più volte sul selettore del modello mentre il menu non è ancora comparso, si aprivano più popup.
- Il primo messaggio dopo la riapertura di una sessione risultava "Invio non riuscito" anche se Pi lo aveva ricevuto e l'agente rispondeva (solo più tardi).
- Una domanda a scelta dell'agente (card sopra il composer) non permetteva di premere "Invia" né di interagire, bloccando la chat.

### Cause Radice e Risoluzione
1. **Selettore modello/thinking**: il catalogo veniva caricato in modo asincrono prima di `showMenu`, quindi ogni tap lanciava un nuovo menu. `composer.dart` ora ignora i tap mentre un selettore è in apertura/aperto (`_guardPicker`) e il caricamento ha un timeout di 10s, così il selettore non resta mai bloccato.
2. **Consegna falsa negativa**: Pi conferma `prompt` solo dopo il preflight (es. compattazione pre-prompt di una sessione grande, hook di estensioni), che può superare i 30s del daemon. `StdioPiTransport` ora considera un `prompt` con ack lento come accettato (`disposition: pending`); un eventuale rifiuto tardivo di Pi arriva come `worker.diagnostic`. Gli altri comandi mantengono il timeout con errore.
3. **Card domanda bloccata** (`extension_ui_dialog.dart` + `composer.dart`):
   - corpo (messaggio e opzioni) scrollabile con altezza massima: pulsanti Annulla/Invia sempre visibili anche con molte opzioni o testo lungo;
   - i pulsanti non dipendono più dall'esito del claim: solo "già in uso da un altro client" blocca la card; claim lento, fallito o offline non la disabilita (il daemon arbitra comunque la risposta);
   - dopo risposta, scadenza del timeout o richiesta non più presente sul daemon (`Request not found`) la card viene chiusa localmente, senza attendere l'evento `ui.resolved`;
   - la risposta ha un timeout di 15s con errore visibile e pulsanti riabilitati;
   - selezione singola con indicatori radio invece di checkbox.

