# Guida al Theming di PiFrame

PiFrame supporta un motore di temi basato su file JSON (`version: 1`), con ricaricamento a caldo su desktop (ogni file `.json` modificato viene riletto), ereditarietà ad albero (tramite `extends`) e tolleranza agli errori.

## Struttura della directory dei temi

I temi vengono ricercati in tre posizioni:
1. **Temi integrati (Asset):** `piframe-dark.json`, `piframe-light.json`.
2. **Temi utente globali:** `~/.piframe/themes/*.json`.
3. **Temi di workspace:** `<workspace>/.piframe/themes/*.json`.

I temi creati o modificati in queste directory vengono rilevati automaticamente senza necessità di riavviare l'applicazione.

## Esempio minimale con ereditarietà (`example-minimal.json`)

Per creare una variante di un tema esistente, basta definire `extends` con l'ID del tema base ed esporre solo i token che si desidera personalizzare:

```json
{
  "$schema": "https://pi-frame.dev/theme.schema.json",
  "schemaVersion": 1,
  "id": "amber-accent-dark",
  "name": "Amber Accent Dark",
  "author": "Tu",
  "version": "1.0.0",
  "variant": "dark",
  "extends": "piframe-dark",
  "colors": {
    "accent": "#FFB84D",
    "focusRing": "#FFB84D"
  }
}
```

Tutti i token non specificati (colori di sfondo, superfici, font, spaziature, sintassi, ecc.) vengono ereditati dal tema genitore `piframe-dark`.

## Validazione ed Editor Support

Specificando `$schema: "https://pi-frame.dev/theme.schema.json"`, editor come VS Code o IDE basati su LSP offrono autocompletamento, validazione della sintassi e suggerimenti per ogni proprietà del tema.

## Token di colore: `inputBorder` e `focusRing`

- `inputBorder` è il contorno di campi di testo, composer e campi di ricerca. Deve avere almeno **3:1** di contrasto rispetto a `surface` (contrasto non testuale WCAG). Il contorno `border` resta per i compartimenti.
- `focusRing` deve avere anch'esso almeno **3:1** rispetto a `surface`. Il test in `apps/pi_frame/test/design_tokens_test.dart` verifica sia `inputBorder` sia `focusRing` sui temi ufficiali `piframe-dark` e `piframe-light`; un tema utente non è controllato da quel test.
- I temi ufficiali `piframe-dark` e `piframe-light` dichiarano `inputBorder` esplicitamente (`#627699` su scuro, `#7d8aa0` su chiaro), e il test ne verifica il contrasto 3:1 su `surface`.
- Un tema che non dichiara `inputBorder` lo ricava automaticamente: parte da `borderStrong` e si avvicina a `textPrimary` finché raggiunge 3:1 su `surface`.

## Token di spaziatura, dimensione, tipografia e movimento

Questi valori non dipendono dal tema e sono costanti Dart nel pacchetto `pi_frame_theme`.

| Token | Valori | Accesso |
|---|---|---|
| Spaziatura | `x1`=4, `x2`=8, `x3`=12, `x4`=16, `x6`=24, `x8`=32, `x12`=48 (gutter di pagina su layout ampi) | `FrameSpace.x4` |
| Dimensioni | `rowList`=28, `rowForm`=40, `hitMin`=28, `iconSm`=14, `icon`=16, `iconLg`=20, `paneHeader`=40. `iconSm` solo per chip e barre dense; il resto usa `icon` | `FrameSize.rowList` |
| Tipografia | `caption` 11/16, `label` 12/16 (w500), `body` 13/20, `bodyLarge` 14/20, `title` 16/22 (w600), `heading` 20/26 (w600), `display` 28/32 (w600), `mono` 12/18, `monoBody` 13/20 | `FrameText.of(context).label` |
| Raggi | `radiusSm`=6, `radiusMd`=10, `radiusLg`=14, `radiusPill`=999 | `FrameTokens.radiusSm` (tema, per tema) |
| Movimento | `instant`=0, `micro`=120, `smallExit`=120, `small`=160, `panel`=240, `panelExit`=180, `dialog`=180, `dialogExit`=120, `firstRun`=300, `stagger`=100, `crossFade`=120, `debounce`=300, `tooltipWait`=300, `pulseLoop`=1400, `shimmerLoop`=3600, `launchReveal`=620 ms (`pulseLoop` e `shimmerLoop` sono fermi con *Riduci animazioni*); curve `enterCurve`=`Cubic(0.23, 1, 0.32, 1)`, `panelCurve`=`Cubic(0.32, 0.72, 0, 1)` | `FrameMotion.panel` (app) o `FrameMotionTokens.panel` (tema) |

- **Tipografia:** i ruoli UI usano `uiFontFamily` (Schibsted Grotesk), i ruoli `mono` usano `monoFontFamily` (Source Code Pro). Barlow Condensed (`headingFontFamily`) è riservato a marchio e intestazioni di pannello e non compare in questi ruoli. La dimensione minima è 11 px. `FrameText` è registrato come `ThemeExtension` in ogni `ThemeData` costruito dal tema.
- **Movimento:** `FrameMotionTokens` è l'unica fonte. `FrameTokens.pressDuration`, `panelDuration`, `enterCurve` e `panelCurve` leggono le stesse costanti di `FrameMotion`, quindi non possono divergere.
