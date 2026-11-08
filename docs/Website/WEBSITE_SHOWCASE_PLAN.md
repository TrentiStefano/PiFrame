# PiFrame — Feature Showcase, Promo Video & Website Plan (v2)

> Stato: **Completato** (clip, promo, sito). Fase 0 — selezione: **1, 2, 7, 8, 9, 10, 13, 15, 17, 18**.
> #18 (Remote) in forma semplificata: screenshot della pagina impostazioni Remote affiancato allo screenshot dell'app mobile in cornice iPhone.
> Registrazione **sull'host** (nessuna VM Hyper-V disponibile) in ambiente isolato (vedi §3).

Obiettivo: mostrare le **10 feature migliori** di PiFrame con clip reali registrate con
[Recordly](https://github.com/webadderallorg/recordly), produrre un **video promo** con la skill
[`brag`](https://github.com/latent-spaces/brag) e integrare tutto in `website/` fino a un livello
degno di Awwwards.

## 1. Regole non negoziabili

| Regola | Applicazione |
|---|---|
| **Solo UI reale** (AGENTS.md §1) | Ogni frame viene dall'app Flutter reale, ultima build. Niente mockup HTML/CSS/canvas dell'interfaccia. Le grafiche del promo (titoli, transizioni) sono *intorno* alle clip, mai al posto della UI. |
| **Nessun dato personale** | Niente repo dell'utente, niente path `C:\Users\Stefano`, niente email, account, tailnet, hostname o cronologia reale. Si registra in VM con utente `demo`, repo demo dedicati e sessioni create apposta. |
| **Metriche autentiche** (AGENTS.md §2) | Nessuna stella, download o numero utenti inventato. Claim solo verificabili nel codice (es. daemon disconnect-safe, zero telemetria D16). |
| **Modello reale** | Le risposte dell'agente vengono da un modello vero (default configurato in Pi nella VM). Nessun transcript finto. |
| **Ultima versione** | Build da `main_bugfix` HEAD (o ultima release) installata nella VM prima delle registrazioni. |

## 2. Fase 0 — 20 feature candidate (scegline 10)

Valutazione "wow per sviluppatori": ★ = interessante, ★★★ = memorabile/unica.

| # | Feature | Perché colpisce uno sviluppatore | Clip proposta (5–8 s) | Wow |
|---|---|---|---|---|
| **1** | **Disconnect-safe daemon** | Chiudi la finestra durante lo stream, riapri: l'agente ha continuato e la UI recupera ogni token senza buchi. Nessun'altra GUI lo fa così. | Prompt lungo → stream → chiusura app → riapertura → stream che riprende in corsa. | ★★★ |
| **2** | **Agents & Workflows live tree** | Albero animato di subagent/workflow con stato, modello, costo, attività corrente e scintille lungo i rami. | Prompt che lancia 3 subagent → il pannello si apre → rami che si accendono e completano. | ★★★ |
| **3** | **Steer queue in-flight** | Correggi l'agente mentre lavora: accodi, modifichi, riordini istruzioni senza fermare lo stream. | Stream attivo → digita steer → modifica in coda → l'agente lo applica. | ★★★ |
| **4** | **Domande strutturate dell'agente** | L'agente chiede, tu scegli un'opzione in un dialog nativo invece di scrivere. | Domanda con 3 opzioni → selezione → l'agente prosegue. | ★★ |
| **5** | **Step grouping dei turni** | Thinking e tool call collassati in un blocco "Completati N passaggi"; la risposta finale resta pulita. | Turno con molti tool → gruppo che scorre → collapse automatico → espansione. | ★★ |
| **6** | **Side conversation `/side`** | Domanda laterale read-only (Ctrl+Shift+B) senza sporcare la sessione principale; "Inserisci nel composer". | Agente al lavoro → `/side spiega X` → risposta nel pannello → inserisci nel composer. | ★★★ |
| **7** | **Bento workspace flessibile** | Tre aree co-visibili, splitter ridimensionabili, pannelli collassabili, companion tabs. | Resize splitter → collapse sidebar → tab File/Git/Browser/Terminal. | ★★ |
| **8** | **Review changes 50/50 diff** | Diff side-by-side sincronizzato dentro la chat, toggle unified. | Fine turno → Review changes → click file → split 50/50. | ★★★ |
| **9** | **Git desk: staging, commit e branch switch sicuro** | Stage per file, commit box, branch picker con ricerca e stash automatico se il tree è sporco. | Stage 2 file → commit → branch picker → switch con dialog stash. | ★★ |
| **10** | **Repository explorer → "Add to chat"** | Ricerca file, selezione righe, aggiunta del range `L14–L28` al prompt; render nativo `.md`. | Cerca file → seleziona righe → Add to chat → chip nel composer. | ★★ |
| **11** | **Browser Chromium integrato** | WebView2 reale nel pannello destro, multi-motore di ricerca, invio pagina all'agente. | Apri docs → "invia al composer" → prompt che la usa. | ★★ |
| **12** | **Terminale integrato (PowerShell/WSL)** | Terminale nativo nel workspace, anche WSL. | Apri terminale → `npm test` → output reale. | ★ |
| **13** | **Controllo modello, thinking e contesto** | Picker modello/thinking, tier contesto (272k/1M), limite custom e margine di compattazione per sessione. | Chip modello → thinking high → tier 1M → slider custom. | ★★ |
| **14** | **Todo list live dell'agente** | Checklist che si spunta in tempo reale mentre l'agente lavora. | Piano a 5 step → spunte progressive. | ★★ |
| **15** | **Composer potente** | `@` file mention, `/` slash (anche built-in Pi), drag & drop file/immagini, lightbox, composer espanso. | `@` → file → drag immagine → `/` menu. | ★★ |
| **16** | **Command palette & session tree (fork/clone)** | Ctrl+K per tutto; albero della sessione con fork da un messaggio precedente. | Ctrl+K → "Session tree" → fork da un nodo. | ★★ |
| **17** | **Theme editor + import VS Code + light/dark live** | Editor token con preview live, import tema VS Code JSON, switch light/dark istantaneo. | Switch light → editor → cambia accent → preview live. | ★★★ |
| **18** | **Remote dal telefono (Tailscale, QR)** | Controlla l'agente dal telefono con layout mobile dedicato. | QR pairing (dati demo/oscurati) → app su telefono che riceve lo stream. | ★★★ |
| **19** | **Pi ecosystem: MCP, pacchetti, update** | Toggle server MCP, pacchetti Pi con version pinning, update di Pi/estensioni/app dalle impostazioni. | Card MCP → toggle → Pacchetti → pin versione. | ★★ |
| **20** | **Generatore `AGENTS.md` con Pi** | Il dialog genera le istruzioni del repo con l'agente, poi le modifichi in-app. | Apri dialog → Genera → file scritto → editor. | ★★ |

Menzioni (utilizzabili come B-roll nel promo, non come card): animazione di avvio con assemblaggio logo, Nerd stats nella title bar, quick launch delle ultime sessioni, notifiche di sistema, costo multi-modello.

**Selezione dell'utente:** `[1, 2, 7, 8, 9, 10, 13, 15, 17, 18]`

## 3. Fase 1 — Ambiente di registrazione

1. **Host con profilo demo isolato** (nessuna VM). PiFrame viene avviato con `USERPROFILE=C:\demo\home`: app Flutter, daemon `pi-agentd` (porta casuale, runtime separato) e Pi leggono solo `C:\demo\home\.piframe` e `C:\demo\home\.pi`. Le sessioni, i repo e le impostazioni reali dell'utente non compaiono mai.
   - `C:\demo\home\.pi\agent`: copia di `bin` e `install` di Pi, `auth.json` solo con il provider del modello di default, `settings.json` minimale, pacchetti demo (`pi-subagents`, `rpiv-ask-user-question`, `rpiv-todo`).
   - Registrazione **solo della finestra** PiFrame (Windows Graphics Capture di Recordly): nessuna taskbar, nessun'altra app. Recordly compone la finestra su uno sfondo neutro con padding, angoli arrotondati e ombra, come nei video del sito di Tailscale.
2. **PiFrame ultima versione**: `pnpm build:all` + `flutter build windows --release` da HEAD di `main_bugfix`, eseguita da `apps/pi_frame/build/windows/x64/runner/Release/`.
3. **Pi + modello**: modello di default reale (`anthropic/claude-haiku-5-5`).
4. **Repo demo** (creati da script, mai repo dell'utente), in `C:\demo\`:
   - `orbit-api` — piccolo servizio TypeScript con test (feature agent, diff, git, todo, subagent).
   - `pixel-notes` — app web minimale (browser integrato, markdown, AGENTS.md).
   - Git config locale: `user.name "PiFrame Demo"`, `user.email demo@example.invalid`.
5. **Recordly ultima release** (Windows x64) installata nel guest; preset: sfondo gradiente scuro PiFrame, padding 6 %, angoli 14 px, ombra morbida, cursore smussato con click ring, auto-zoom attivo, 60 fps.
6. **Tool host**: `ffmpeg` (winget `Gyan.FFmpeg`), Node 22, skill `brag` (`npx skills add latent-spaces/brag`) e una skill Awwwards (`juliobsz/skills` o equivalente) dopo verifica del contenuto.
7. Reset dello stato demo tramite script (`tools/showcase/reset-demo.ps1`) prima di ogni clip.

## 4. Fase 2 — Registrazione automatizzata con Recordly

### Pipeline per ogni clip

```
restore snapshot → seed stato (sessioni/file demo) → avvia PiFrame (finestra 1600×1000 centrata)
 → Recordly: start recording (finestra PiFrame, cursore on)
 → driver UI esegue lo script della clip (tempi umani, easing del mouse)
 → Recordly: stop → editor: auto-zoom + rifinitura zoom manuali + trim
 → export MP4 1080p60 (master) → ffmpeg: WebM/AV1 + MP4 H.264 per web, poster AVIF, GIF solo per README
```

### Driver UI
- **Primario: Windows UI Automation** sull'albero di accessibilità che Flutter espone su Windows (`Semantics`). Script Python `pywinauto` (backend `uia`) che trova i controlli per nome: niente coordinate fragili.
- **Fallback:** coordinate relative alla finestra (non allo schermo) con `SendInput`, movimento del mouse con easing smoothstep su 400–700 ms, digitazione a 35–60 ms per carattere con jitter.
- Ogni script clip è in `tools/showcase/clips/<id>.py` con: precondizioni, azioni, pause "di lettura" (≥ 800 ms dopo ogni cambio di stato), postcondizioni verificate via UIA.
- Avvio/stop di Recordly via scorciatoia globale configurata in Recordly (es. `Ctrl+Shift+F9`) inviata dal driver, così inizio e fine sono deterministici.

### Regole di regia
- 5–8 s per clip, una sola idea per clip, primo frame già leggibile (vale come poster).
- Massimo 2 zoom per clip; zoom 1.6–2.0× sul punto d'azione, ritorno al wide prima della fine per il loop.
- Loop pulito: ultimo frame ≈ primo frame (crossfade 300 ms in ffmpeg se serve).
- Tema PiFrame Dark per tutte, salvo la clip del theme switch.
- Le risposte del modello sono reali ma i prompt sono scelti per essere brevi e prevedibili; si registrano 2–3 take e si tiene il migliore.

### Output per clip (`website/assets/showcase/<nn>-<slug>/`)
| File | Uso | Target |
|---|---|---|
| `master.mp4` | Sorgente per brag | 1920×1080, 60 fps, CRF 16 |
| `clip.webm` (AV1/VP9) + `clip.mp4` (H.264) | Sito | ≤ 1.5 MB, 30–60 fps |
| `poster.avif` + `poster.jpg` | Poster/LCP | ≤ 120 KB |
| `clip.gif` | README GitHub | ≤ 4 MB, 960 px, 24 fps |
| `project.recordly` | Riedizione | — |

## 5. Fase 3 — Video promo con `brag`

- Esegui `brag` sul repo con override: **usa solo le clip master registrate** come media della UI; la skill aggiunge titoli, ritmo, musica e SFX.
- Durata 20–30 s, 1920×1080 + versione 1080×1350 per social.
- Struttura: hook (2 s, feature più forte) → 5–6 beat sulle feature scelte (2–3 s ciascuno, una frase per beat) → claim architetturale verificabile (disconnect-safe, zero telemetria, nativo Flutter) → logo + URL release.
- Output: `website/assets/video/piframe-promo.{webm,mp4}`, poster, sottotitoli `.vtt`; `brag-output/brag-plan.md` aggiornato.
- Controllo: nessun frame con dati personali (verifica frame-by-frame a 2 fps).

## 6. Fase 4 — Sito Awwwards

Partenza: `website/index.html` (858 righe), `css/style.css`, `js/main.js`. Si mantiene HTML/CSS/JS statico (deploy semplice), con librerie leggere: GSAP + ScrollTrigger, Lenis.

Struttura narrativa:
1. **Hero** — titolo forte, promo in loop muto a pieno stage, CTA download (link reali alle release).
2. **Manifesto** — 3 claim verificabili con micro-animazioni tipografiche.
3. **10 feature** — sezione pinned con scroll-scrub: testo a sinistra, clip a destra che cambia per capitolo; su mobile diventa sequenza di card.
4. **Architettura** — diagramma daemon/GUI/Pi (illustrazione dell'architettura, non della UI).
5. **Temi** — before/after light/dark con clip reale.
6. **Download / FAQ / footer**.

Requisiti qualità:
- LCP < 2.5 s, video lazy (`preload="none"` fuori viewport, play via `IntersectionObserver`), `prefers-reduced-motion` → poster statici.
- Accessibilità: contrasto AA, controllo play/pause sui video, testi alternativi.
- Verifica con Lighthouse (≥ 90 performance/accessibility) e screenshot a 375 / 768 / 1440 / 2560 px.
- Iterazione con la skill Awwwards (giudizio "jury") finché design, usabilità, creatività e contenuto sono ≥ 8/10.

## 7. Sequenza operativa e checkpoint

| Fase | Output | Checkpoint utente |
|---|---|---|
| 0 Selezione | 10 feature scelte | ✅ obbligatorio |
| 1 Ambiente | VM pronta, snapshot `PiFrame-Showcase-Ready` | — |
| 2 Registrazione | 10 clip + poster | Revisione clip (consigliata) |
| 3 Promo | `piframe-promo` | ✅ revisione video |
| 4 Sito | `website/` aggiornato | ✅ revisione finale |
| Docs | `docs/install.md` / `docs/troubleshooting.md` se servono | — |

## 8. Stato finale e come rigenerare

Completato:
- **Clip reali** (Recordly 1.4.0, finestra PiFrame su sfondo neutro, UI in inglese) in `website/assets/showcase/<slug>/` (`clip.webm`, `clip.mp4`, `poster.jpg`): 01, 02, 07, 08, 09, 10, 13, 15, 17.
- **#18 Remote**: `settings.png` (indirizzo tailnet e hostname sfocati) e `iphone.png` (UI web reale in cornice iPhone).
- **Promo** (skill `brag` + HyperFrames, solo clip reali): `website/assets/video/piframe-promo.{mp4,webm}` e poster; master in `brag-output/`. Musica: Sascha Ende, CC BY 4.0.
- **App**: interfaccia localizzata in inglese (prima solo Impostazioni), lingua salvata anche nel client web, output LF del terminale integrato corretto.

Rigenerare:
1. `python tools/showcase/launch.py` (reset demo, 2560x1440 al 125 %, finestra 2400x1350).
2. `python tools/showcase/clips.py <clip>` per 02, 07, 08, 09, 10, 13, 15, 17; `python tools/showcase/clip01.py` per 01. Recordly va avviato da script (`--remote-debugging-port=9333`); l'export usa la modalità smoke-export di Recordly.
3. `python tools/showcase/post.py` (montaggio, encode web, poster).
4. `node brag-output/render-promo.mjs --clips-dir <cartella con master 1080p30> --skip-check`, poi `delogo` sull'angolo in basso a destra se un ad blocker locale inietta un'icona nel render.

Note: la cattura di Recordly su Windows registra la regione della finestra, quindi finestre sovrapposte compaiono nel video. Il drag & drop della clip 15 parte da una finestra di Esplora file fuori dall'area registrata.

## 9. Rischi

| Rischio | Mitigazione |
|---|---|
| Flutter non espone un controllo via UIA | Fallback a coordinate relative alla finestra, ricavate da screenshot del tema fisso. |
| Risposte del modello variabili | Prompt brevi e vincolati, più take, nessun montaggio che altera il contenuto. |
| Feature Remote (#18) mostra dati del tailnet | Tailnet demo dedicato oppure blur di QR/indirizzi; se non sicuro, si esclude. |
| Recordly senza CLI | Avvio/stop con scorciatoia globale; editing e export nell'app. |
| Peso dei video | AV1/VP9 + poster, lazy load, max 1.5 MB per clip. |
