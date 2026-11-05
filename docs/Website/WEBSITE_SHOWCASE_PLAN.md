# PiFrame Website & Feature Showcase Master Plan

Piano strategico per l'aggiornamento del sito web ufficiale di **PiFrame** (`website/index.html`), introducendo il nuovo set di 20 funzionalità attraverso un mix ottimizzato di **Hero Video (10s)**, **clip video brevi/GIF (Recordly)** e **screenshot ad alta fedeltà dell'interfaccia Flutter reale**.

---

## 1. Strumenti e Installazioni Configurate

| Strumento | Scopo | Stato | Posizione / Riferimento |
|---|---|---|---|
| **VM Hyper-V Win11** | Macchina virtuale isolata Windows 11 con Pi, PiFrame (login Antigravity attivo) e punto di ripristino dedicato **`PiFrame`**. Usata per navigare la vera app e registrare video/screenshot senza interferire con la sessione di lavoro sull'host. | Operativa / Snapshot pronto | VM: `Win11`, Snapshot: `PiFrame`, Credenziali: `User` / `password`. Guida: `docs/VM_RECORDLY_SHOWCASE_GUIDE.md` |
| **Recordly** (`webadderall/Recordly`) | Registrazione video/GIF ad alta risoluzione con auto-zoom, cursor spotlight, smooth panning ed esportazione hardware WGC a 60 FPS per le feature interattive. | Installato nel guest/host | `C:\Program Files\Recordly\resources\app.asar.unpacked\electron\native\bin\win32-x64\wgc-capture.exe` |
| **brag** (`latent-spaces/brag`) | Skill specializzata per la regia e composizione del video di lancio **Hero (10s)**: ritmo serrato, beat-sync, visual hook e claim architetturali (120fps, zero telemetria, demone disconnesso). | Installato localmente nel repo | `.agents/skills/brag/` e `.agents/skills/brag-slim/` |
| **FFmpeg** (v2025-04) | Conversione flussi raw, trimming frame-perfect, compressione H.264/WebM e generazione GIF a palette ottimizzata con Bayer dithering (30 FPS reali, < 500 KB). | Disponibile nel path di sistema | `ffmpeg` CLI |
| **Hyper-V WMI Frame Capture** | Acquisizione del framebuffer a livello VMBus (`GetVirtualSystemThumbnailImage`) per catture e sequenze senza perdite di focus. | Script di sistema | `tools/test_hyperv_screen.ps1` |

---

## 2. Matrice di Presentazione delle 20 Feature

Tutte le 20 feature richieste sono mappate nel formato visuale più efficace, registrate ed estratte direttamente dall'applicazione reale in esecuzione nella **macchina virtuale Hyper-V Win11** (consultare `docs/VM_RECORDLY_SHOWCASE_GUIDE.md` per le procedure operative di cattura e coordinate):
- **Hero Video (10s via /brag)**: Panoramica dell'app completa registrata nella VM (Bento triptych, prompt streaming, diff split, terminal, light/dark).
- **Brevi Video / GIF interattive (via Recordly WGC & FFmpeg)**: Per azioni dinamiche multi-step registrate dall'app reale (domande agente con selezione, review changes con espansione diff 50/50, drag&drop, ecc.).
- **Screenshot Reali UI (1200+ px)**: Estratti dalla vera interfaccia Flutter per pannelli densi di impostazioni, selettori modali e controlli precisi.

| # | Funzionalità | Formato Visuale Primario | Strumento di Acquisizione | Destinazione Asset (`website/assets/`) |
|---|---|---|---|---|
| **0** | **App Full Walkthrough (Hero Video 10s)** | Video WebM/MP4 looping (10s) | `/brag` + Recordly WGC stitch (VM Win11) | `website/assets/video/hero-10s-piframe-showcase.mp4` |
| **1** | **Agent questions to the user** (domande interattive dell'agente) | Breve Video / GIF (5.2s, 30 FPS) | VM Win11 + Recordly (dialog reale, selezione opzione 3, invio risposta) | `website/assets/img/ui/feature-01-agent-questions.gif` |
| **2** | **Model, Thinking effort & Context size tier pickers** | Screenshot reale catturato | VM Win11 (`Composer` popover selettore modelli) | `website/assets/img/ui/feature-02-composer-pickers.png` |
| **3** | **Work Area panel**: Custom context limit & compaction limit | Screenshot reale catturato | VM Win11 (`ContextPanel` slider limite contesto e compattazione) | `website/assets/img/ui/feature-03-workarea-context-limits.png` |
| **4** | **File drag-and-drop & Attach button** | Breve Video / GIF (3s, 30 FPS) | VM Win11 + Recordly (`ChatDropTarget` overlay e chip) | `website/assets/img/ui/feature-04-file-drag-drop-attach.gif` |
| **5** | **Review changes 50/50 view with diff** | Breve Video / GIF (4.8s, 30 FPS) | VM Win11 + Recordly (click riga file, espansione diff split 50/50) | `website/assets/img/ui/feature-05-review-changes-50-50-diff.gif` |
| **6** | **Git changes pane with staging and commit** | Breve Video / GIF (4s, 30 FPS) | VM Win11 + Recordly (click stage `+`, commit box) | `website/assets/img/ui/feature-06-git-changes-staging.gif` |
| **7** | **Web browser integration** | Breve Video / GIF (4s, 30 FPS) | VM Win11 + Recordly (tab browser nativo con URL e preview) | `website/assets/img/ui/feature-07-web-browser-pane.gif` |
| **8** | **Repository pane**: search file, open & "Add to chat" lines | Breve Video / GIF (4s, 30 FPS) | VM Win11 + Recordly (ricerca file, selezione righe, context menu) | `website/assets/img/ui/feature-08-repo-search-add-to-chat.gif` |
| **9** | **Resizing panes, hiding session/git panes & terminal** | Breve Video / GIF (4s, 30 FPS) | VM Win11 + Recordly (resize splitters e terminale OS) | `website/assets/img/ui/feature-09-pane-resize-and-terminal.gif` |
| **10** | **Rename session (double click) & pin in sessions pane** | Breve Video / GIF (3s, 30 FPS) | VM Win11 + Recordly (doppio click inline, pin badge in cima) | `website/assets/img/ui/feature-10-rename-and-pin-session.gif` |
| **11** | **Switch to light mode & hide Repo pane from checklist** | Breve Video / GIF (4s, 30 FPS) | VM Win11 + Recordly (transizione PiFrame Light e checklist) | `website/assets/img/ui/feature-11-light-mode-pane-checklist.gif` |
| **12** | **Update button & Update from settings** | Screenshot reale catturato | VM Win11 (`UpdatesSection` e banner release) | `website/assets/img/ui/feature-12-in-app-update-flow.png` |
| **13** | **Theme editor in settings** | Screenshot reale ad alta fedeltà | VM Win11 (`ThemeEditorDialog` token e swatches) | `website/assets/img/ui/feature-13-theme-editor.png` |
| **14** | **Remote connection via Tailscale & phone** | Screenshot reale con QR | VM Win11 (`RemoteSection` Tailscale connesso e QR pairing) | `website/assets/img/ui/feature-14-tailscale-remote-phone.png` |
| **15** | **Pi CLI settings**: update Pi agent & extensions | Screenshot reale catturato | VM Win11 (`PiCliSection` comandi rapidi aggiornamento) | `website/assets/img/ui/feature-15-pi-cli-settings-update.png` |
| **16** | **Enable/disable MCP servers** | Screenshot reale del modal | VM Win11 (`McpServersDialog` switch on/off server MCP) | `website/assets/img/ui/feature-16-mcp-servers-toggle.png` |
| **17** | **View installed packages & pin package version** | Screenshot reale catturato | VM Win11 (`PiCliSection` pacchetti e version pinning) | `website/assets/img/ui/feature-17-packages-version-pinning.png` |
| **18** | **Agent answer mentioning file**: click to open in OS Explorer | Breve Video / GIF (3s, 30 FPS) | VM Win11 + Recordly (click su link file nel markdown) | `website/assets/img/ui/feature-18-click-file-open-explorer.gif` |
| **19** | **Render .md files when opening it** | Screenshot reale split / render | VM Win11 (`CodeBlock` render nativo markdown) | `website/assets/img/ui/feature-19-markdown-file-preview.png` |
| **20** | **Generate repository instructions directly with Pi agent** | Breve Video / GIF (4s, 30 FPS) | VM Win11 + Recordly (`InstructionFileDialog` con AGENTS.md) | `website/assets/img/ui/feature-20-generate-repo-instructions.gif` |

---

## 3. Storyboard Hero Video 10 Secondi (`/brag`)

Video ultra-dinamico, sincrono su ritmo 120-130 BPM, risoluzione 1920x1080 @ 60fps, esportato per il browser (`autoplay`, `loop`, `muted`, `playsinline`):

- **0.0s - 1.5s (The Hook)**:
  - Macro zoom sul Bento Triptych in tema PiFrame Dark (#161c27).
  - Stream di token assistente e reasoning a 120fps (zero jank).
  - Titolo a schermo: *Fluid 120fps AI Coding Ergonomics*.
- **1.5s - 3.5s (Interactive Agent & Steer)**:
  - Comparsa dialog con domanda strutturata dell'agente ("agent questions to user").
  - Modifica in-flight della coda di steer senza bloccare i token.
- **3.5s - 5.5s (Deep Workspace & Code Control)**:
  - Repository pane: ricerca file istantanea, click destro *"Add to chat [L14-L28]"*.
  - Apertura split 50/50 Review Diff con evidenziazione sintattica.
- **5.5s - 7.5s (Terminal, Web & Panes Flexibility)**:
  - Apertura terminale integrato Powershell/WSL nel terzo compartimento.
  - Tab switch immediato verso il Web Browser interno.
  - Resize fluido dei divisori e scomparsa delle sidebar.
- **7.5s - 9.0s (Light Switch & Extensibility)**:
  - Toggle istantaneo a PiFrame Light (#f1f3f7) senza ricaricamento.
  - Flash rapido di MCP servers attivi e Theme Editor.
- **9.0s - 10.0s (Outro & CTA)**:
  - Logo PiFrame iconico + *"Zero Telemetry. Disconnect-Safe. Native Flutter."*
  - Badge: *Get PiFrame for Windows, macOS, Linux*.

---

## 4. Architettura delle Sezioni del Sito Web (`website/index.html`)

Il sito viene riorganizzato con una struttura narrativa e gerarchica moderna, mantenendo la palette **PiFrame Dark & Light** e la griglia Bento:

### Sezione 1: Hero & Centerpiece Stage
- Titolo & Badge: *Native Flutter GUI for Pi-Coding Agent*.
- **Hero Video Player (10s)** al centro dello stage con toggle per passare ai singoli screenshot applicativi.
- Tab bar interattiva: *10s Showcase*, *Bento Dark*, *Bento Light*, *50/50 Diff Review*, *Steer Queue*, *Theme Customizer*.

### Sezione 2: Bento Grid 4x4 — Le 4 Aree Chiave
1. **Agent Intelligence & Dialogue**:
   - Domande interattive dell'agente (`feature-01`).
   - Selettori Model, Thinking & Context Tiers nel composer (`feature-02`).
   - Generazione guidata di istruzioni di repository `AGENTS.md` (`feature-20`).
   - File link cliccabili con salto all'OS Explorer (`feature-18`).
2. **Ergonomia dello Spazio di Lavoro (Bento Triptych)**:
   - Resize dei pannelli, checklist visibilità e terminale integrato (`feature-09`).
   - Repository explorer, fuzzy file search e "Add lines to chat" (`feature-08`).
   - Integrazione Web Browser live (`feature-07`).
   - Markdown viewer integrato con render nativo (`feature-19`).
3. **Controllo del Contesto & Revisione Git**:
   - Pannello Work Area con limiti di contesto e compaction personalizzati (`feature-03`).
   - Revisione modifiche 50/50 side-by-side con unified diff toggle (`feature-05`).
   - Git changes con staging a livello di file e commit box (`feature-06`).
   - Drag-and-drop di file e pulsante attach avanzato (`feature-04`).
4. **Sistema, Personalizzazione & Connettività**:
   - Palette PiFrame Dark & Light e Theme Editor avanzato (`feature-11`, `feature-13`).
   - Connessione remota via Tailscale & smartphone (`feature-14`).
   - Gestione MCP Servers on/off (`feature-16`).
   - Gestione pacchetti Pi, aggiornamenti ed estensioni con version pinning (`feature-15`, `feature-17`).
   - Auto-aggiornamento da banner e impostazioni (`feature-12`).
   - Gestione sessioni: rinomina con doppio click e pinning in cima alla lista (`feature-10`).

### Sezione 3: Deep Dive Interattivo con Schede Tabbed & Modal Preview
- Selettore interattivo per categoria che permette allo sviluppatore di filtrare le feature e visualizzare la clip Recordly o lo screenshot ad alta risoluzione a schermo intero.

### Sezione 4: Tabella Comparativa & Architettura Decoupled
- Comparativa prestazionale (120fps vs Electron, 0% telemetria, demone disconnesso).

---

## 5. Piano Operativo di Esecuzione (Passo dopo Passo)

1. **Step 1 - Scrittura della nuova struttura HTML (`website/index.html`)**:
   - Aggiungere il player video HTML5 per l'Hero Video (`<video>` con fallback poster, autoplay, loop, muted).
   - Aggiungere la griglia bento arricchita con tutte le 20 feature raggruppate nei 4 cluster.
   - Collegare gli attributi data per il filtro rapido e l'ingrandimento delle card.
2. **Step 2 - Aggiornamento Stili CSS (`website/css/style.css`)**:
   - Stili per il contenitore video con cornice metallica smussata (Bento aesthetics).
   - Stili per i badge interattivi (GIF / Clip / Video tag).
   - Ottimizzazione layout responsive (mobile, tablet, desktop wide) per visualizzazione fluida su schermi retina.
3. **Step 3 - Integrazione Script Interattivi (`website/js/main.js`)**:
   - Gestione del player video hero (pausa se fuori viewport con `IntersectionObserver`).
   - Switcher avanzato per tab video/screenshot.
   - Lightbox modal ad alta risoluzione per ispezionare le singole feature in dettaglio.
4. **Step 4 - Generazione & Assegnazione degli Asset Visuali (Tramite VM Hyper-V)**:
   - Utilizzare esclusivamente la macchina virtuale Hyper-V `Win11` (snapshot `PiFrame`, credenziali `User` / `password`), seguendo i passi di `docs/VM_RECORDLY_SHOWCASE_GUIDE.md`.
   - Nessuna interferenza con l'istanza PiFrame attiva sull'host: le registrazioni avvengono dentro il guest via `wgc-capture.exe` e cattura WMI video.
   - Posizionare i video/GIF registrati e gli screenshot in `website/assets/img/ui/` e `website/assets/video/`.
   - Compilare il video Hero 10s tramite lo script di composizione `/brag` unendo le scene reali registrate nella VM.
5. **Step 5 - Verifica Finale**:
   - Test di caricamento locale e performance.
   - Controllo contrasti sia in dark mode che light mode.
