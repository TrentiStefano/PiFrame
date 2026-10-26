# Risoluzione Problemi e Casi Noti (Troubleshooting & Known Issues)

Questo documento raccoglie diagnosi, cause radice e soluzioni per anomalie note legate all'ambiente di esecuzione desktop e web di **PiFrame**.

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

### Build Linux fallisce perché manca libnotify

Il plugin notifier di Flutter per Linux richiede che `pkg-config` trovi `libnotify`. Installa il pacchetto di sviluppo prima della build:

```bash
sudo apt-get install libnotify-dev
```

I pacchetti Debian installati richiedono anche la dipendenza runtime `libnotify4`. La CI di release installa `libnotify-dev` per la validazione e la build Linux; il pacchetto `.deb` dichiara `libnotify4`.
