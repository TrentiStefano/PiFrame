# Guida al Theming di PiFrame

PiFrame supporta un motore di temi basato su file JSON (`version: 1`), con ricaricamento in tempo reale (< 500 ms) su desktop, ereditarietà ad albero (tramite `extends`) e tolleranza agli errori.

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
