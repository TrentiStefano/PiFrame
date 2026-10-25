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

---

## 3. Web App: Browser Integrato nel Browser

### Caso d'uso
Nella versione web di PiFrame visualizzata da smartphone o browser remoto, il pulsante e il pannello del *Web Browser integrato* sono stati intenzionalmente rimossi:
- Su dispositivi remoti (es. iPhone, Android, browser esterno), aprire un browser all'interno di una webview incorporata è ridondante e WebView2 è una tecnologia nativa desktop Windows.
- La modalità remota web espone unicamente le aree di lavoro pertinenti: **Chat**, **File Explorer** e **Git Changes**.
