# Verifica locale prima di una pull request

Dopo il merge su `main` partono i workflow GitHub (`ci.yml` e `release.yml`). Se falliscono, hanno già consumato minuti di runner (Windows ×2, macOS ×10) e `main` è rotto. Questi due comandi eseguono gli stessi passi **sulla tua macchina**, prima della PR.

## Comandi

```bash
pnpm run verify            # verifica CI + validazione release
pnpm run pr                # verify + push del ramo + apertura della PR (gh pr create)
```

Opzioni (valgono per entrambi; con `pnpm` vanno dopo `--`):

| Opzione | Effetto |
|---|---|
| `--release` | aggiunge `flutter build web` e `flutter build` del desktop del tuo sistema, come nel job di build degli installer |
| `--e2e` | aggiunge il test iPhone emulato della web app remota (`tools/remote-e2e`, serve Playwright in `~/.pf-e2e`, vedi il suo README) |
| `--force` | ignora il risultato in cache e riesegue tutto |
| `--no-merge` | verifica solo `HEAD`, senza fare il merge di `origin/main` |
| `--keep` | non cancella il worktree temporaneo (debug) |
| `--verbose` | mostra l'output di ogni passo invece di salvarlo e mostrare solo gli errori |

`pnpm run pr` accetta anche gli argomenti di `gh pr create`, per esempio `pnpm run pr -- --title "fix: ..." --body "..."`. Senza titolo e corpo usa `--fill` (dai commit).

## Cosa controlla

`verify` controlla il **commit** corrente (`HEAD`) con dentro `origin/main`, in un worktree temporaneo accanto al repo (`<repo>-verify-<pid>`, non nella cartella temp del sistema: alcuni test falliscono se il repo sta lì). Così verifica ciò che `main` diventerà dopo il merge, non solo il tuo ramo. Se il merge con `origin/main` ha conflitti, si ferma e te lo dice.

Passi (nello stesso ordine dei workflow):

1. `pnpm install --frozen-lockfile`
2. `node tools/recon/verify.ts`
3. validazione degli schemi PCP
4. `pnpm -r run build` (compresa la build del bundle del daemon)
5. `pnpm -r run test`
6. `pnpm run check:notices`
7. `pnpm run check:version` (versioni sincronizzate)
8. `check:agentd-bundle` e `smoke:agentd-bundle`
9. test del nome della release Windows
10. `flutter analyze` e `flutter test` su `pi_frame_protocol`, `pi_frame_theme` e `pi_frame`
11. con `--release`: `flutter build web` e `flutter build <desktop>`
12. con `--e2e`: test iPhone emulato

L'output completo è in `.git/verify-ci/last.log`. Se un passo fallisce, lo script stampa le ultime righe e si ferma: con `pnpm run pr` non viene fatto nessun push e nessuna PR.

## Cache

Un risultato positivo vale per lo stesso contenuto (hash dell'albero), la stessa base (`origin/main`) e lo stesso livello. Rilanciarlo senza modifiche è istantaneo. Dopo un nuovo commit, o se `origin/main` è avanzato, si riesegue.

## Prerequisiti

- Albero di lavoro **pulito**: `verify` controlla ciò che hai committato, quindi fai prima il commit.
- `git`, `pnpm`, Node e Flutter (versioni dei workflow: vedi `.github/workflows/release.yml`; lo script avvisa se differiscono).
- Per `pnpm run pr`: GitHub CLI (`gh`) autenticato con `gh auth login`.

## Limiti

- Gira su un solo sistema operativo: i job Linux (`.deb`, screenshot con `xvfb`) e macOS (`.dmg`) dei workflow non sono riprodotti, e differenze di path o maiuscole/minuscole su Linux possono sfuggire.
- Alcuni test rigenerano screenshot tracciati (`docs/design-evidence`, `website/assets`). Non è un errore, ma se li vedi modificati nel tuo albero dopo aver lanciato i test a mano, **non committarli** (`git checkout -- docs/design-evidence website/assets/img/ui`). `verify` lavora in un worktree usa e getta, quindi non te li lascia.
- È un controllo locale: si può aggirare. Non sostituisce i workflow GitHub, li protegge dai fallimenti evitabili.

## Esempio

```text
$ pnpm run verify
Merged origin/main (2 commit(s)) into the verification worktree.
[1/13] Install dependencies (frozen lockfile) ... ok (4.1s)
...
[13/13] Flutter tests (all projects) ... ok (92.3s)
✔ All 13 steps passed in 6.8 min.  Result cached for this exact content (ci).
```
