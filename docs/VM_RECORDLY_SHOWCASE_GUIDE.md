# Guida Operativa: Registrazione Showcase PiFrame con VM Hyper-V e Recordly

Questa guida documenta l'esatta procedura end-to-end per qualsiasi agente o sviluppatore che debba registrare video, clip animate (GIF) e screenshot ad altissima fedeltà dell'interfaccia reale di **PiFrame**, utilizzando la macchina virtuale **Hyper-V Win11** e il motore nativo di **Recordly**, **senza interferire con la sessione di lavoro attiva sull'host**.

---

## 1. Architettura dell'Ambiente

| Componente | Valore / Percorso | Dettagli |
|---|---|---|
| **Macchina Virtuale** | `Win11` (Hyper-V Generation 2) | Windows 11 Enterprise/Pro |
| **Punto di Ripristino** | `PiFrame` | Snapshot pulito con Pi e PiFrame installati e login Antigravity attivo |
| **Credenziali Guest** | Utente: `User` / Password: `password` | Sessione console interattiva: `SessionId 1` |
| **Eseguibile PiFrame** | `C:\Users\User\AppData\Local\Programs\PiFrame\PiFrame.exe` | Eseguibile Flutter Impeller Desktop |
| **Engine Recordly** | `C:\Program Files\Recordly\resources\app.asar.unpacked\electron\native\bin\win32-x64\wgc-capture.exe` | Motore Windows Graphics Capture (WGC) hardware H.264 @ 60 FPS |
| **DLL Dipendenze WGC** | `SDL2.dll`, `ggml.dll`, `ggml-base.dll`, `ggml-cpu.dll`, `whisper.dll` | Da copiare in `C:\Users\User\` per esecuzione standalone |

---

## 2. Ciclo di Vita della VM e Ripristino

Prima di registrare una nuova feature o sessione pulita, ripristinare sempre lo snapshot `PiFrame`:

```powershell
# 1. Arresto immediato della VM
Stop-VM -VMName "Win11" -TurnOff

# 2. Ripristino dello snapshot pulito 'PiFrame'
Restore-VMSnapshot -VMName "Win11" -Name "PiFrame" -Confirm:$false

# 3. Avvio della VM
Start-VM -Name "Win11"

# 4. Abilitazione del Guest Service Interface per il trasferimento file
Enable-VMIntegrationService -VMName "Win11" -Name "Interfaccia servizio guest"
```

---

## 3. Login Automatico e Disattivazione Sleep Schermo

Windows 11 disattiva lo schermo dopo breve inattività. Eseguire questi comandi per mantenere la sessione sempre attiva:

```powershell
$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

# 1. Disattivazione monitor timeout e sleep
Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    powercfg /change monitor-timeout-ac 0
    powercfg /change monitor-timeout-dc 0
    powercfg /change standby-timeout-ac 0
    powercfg /change standby-timeout-dc 0
}

# 2. Login alla schermata di blocco tramite Msvm_Keyboard (senza rubare focus all'host)
$vm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='Win11'"
$keyboard = Get-CimAssociatedInstance -InputObject $vm -ResultClassName Msvm_Keyboard

# Sveglia lo schermo con Enter
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 13 }
Start-Sleep -Milliseconds 500

# Digita 'password' direttamente nel campo di login
Invoke-CimMethod -InputObject $keyboard -MethodName TypeText -Arguments @{ asciiText = "password" }
Start-Sleep -Milliseconds 400

# Invia Enter
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 13 }
```

Verificare il login con:
```powershell
Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock { quser }
# Output atteso: user  console  1  Active
```

---

## 4. Cattura Schermo Diretta dall'Hypervisor (Zero Focus Theft)

Non usare software di screenshot che richiedono finestre attive. Hyper-V espone l'API WMI `GetVirtualSystemThumbnailImage` che estrae il framebuffer direttamente dal VMBus video:

```powershell
# tools/test_hyperv_screen.ps1
$vm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='Win11'"
$vsms = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_VirtualSystemManagementService

$res = Invoke-CimMethod -InputObject $vsms -MethodName GetVirtualSystemThumbnailImage -Arguments @{
    TargetSystem = $vm
    WidthPixels = 1024
    HeightPixels = 768
}
[System.IO.File]::WriteAllBytes("scratch/hyperv_screen.raw", $res.ImageData)
```

Conversione da raw RGB565 a PNG via Python:
```python
from PIL import Image
data = open('scratch/hyperv_screen.raw', 'rb').read()
raw_pixels = data[4:] if len(data) == 1572868 else data
im = Image.frombytes('RGB', (1024, 768), raw_pixels, 'raw', 'BGR;16')
im.save('scratch/hyperv_screen.png')
```

---

## 5. Controllo Tastiera e Scorciatoie Hardware (WMI)

`Msvm_Keyboard` inietta eventi tastiera a livello bus virtuale. È immune da perdite di focus.

| Azione | Key Codes | Codice PowerShell |
|---|---|---|
| **Alt + Tab** (Ripristina / Focus PiFrame) | Alt (18), Tab (9) | `TypeKey(18)` + `TypeKey(9)` |
| **Ctrl + K** (Command Palette) | Ctrl (17), K (75) | `PressKey(17)` + `TypeKey(75)` + `ReleaseKey(17)` |
| **Ctrl + Enter** (Invia prompt) | Ctrl (17), Enter (13) | `PressKey(17)` + `TypeKey(13)` + `ReleaseKey(17)` |
| **Esc** (Chiudi dialog / palette) | Esc (27) | `TypeKey(27)` |
| **Spazio / Enter** (Attiva controllo) | Spazio (32), Enter (13) | `TypeKey(32)` o `TypeKey(13)` |
| **Digita testo ASCII** | - | `Invoke-CimMethod -InputObject $keyboard -MethodName TypeText -Arguments @{ asciiText = "testo" }` |

---

## 6. Automazione Mouse e Click Nativi nella VM

Per eseguire click del mouse dentro la VM senza minimizzare la finestra:
1. Usare uno script PowerShell guest (`C:\Users\User\click.ps1`) che imposta `Cursor.Position` e invoca `user32.dll::mouse_event`.
2. Eseguirlo in modo totalmente trasparente tramite `wscript.exe run_silent.vbs` attivato con `Win + R`.

### Modello script guest (`tools/click_template.ps1`):
```powershell
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinMouse {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
}
"@

$p = Get-Process -Name PiFrame -ErrorAction SilentlyContinue | Select-Object -First 1
if ($p -and $p.MainWindowHandle -ne 0) {
    [WinMouse]::SetForegroundWindow($p.MainWindowHandle)
    Start-Sleep -Milliseconds 150
}

# Sposta il cursore alle coordinate desiderate
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($TargetX, $TargetY)
Start-Sleep -Milliseconds 150

# Click sinistro
[WinMouse]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero) # DOWN
Start-Sleep -Milliseconds 80
[WinMouse]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero) # UP
```

### Launcher VBS invisibile (`tools/run_silent.vbs`):
```vbs
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Users\User\click.ps1", 0, False
```

Copia nel guest tramite host:
```powershell
Copy-VMFile -VMName "Win11" -SourcePath "tools/click_template.ps1" -DestinationPath "C:\Users\User\click.ps1" -CreateFullPath -FileSource Host -Force
Copy-VMFile -VMName "Win11" -SourcePath "tools/run_silent.vbs" -DestinationPath "C:\Users\User\run_silent.vbs" -CreateFullPath -FileSource Host -Force
```

---

## 7. Registrazione con Recordly Nativo (`wgc-capture.exe`)

`wgc-capture.exe` cattura il desktop a 60 FPS in hardware senza watermark né cali di framerate.

### Script di registrazione guest (`C:\Users\User\record.ps1`):
```powershell
# Avvia WGC capture su display 0
$wgc = Start-Process -FilePath "C:\Users\User\wgc-capture.exe" -ArgumentList '{"displayId":0,"outputPath":"C:/Users/User/clip_output.mp4","fps":60}' -PassThru -NoNewWindow

# ... esegui l'interazione desiderata (click, digitazione, scroll) ...

# Arresta cattura
Stop-Process -Id $wgc.Id -Force
```

---

## 8. Post-Processing: Cursore, Framing e Compilazione GIF (30 FPS)

Per ottenere una resa professionale conforme agli standard visivi del sito:

1. **Interpolazione cursore**:
   Usare un'equazione di easing cubica `t * t * (3 - 2 * t)` su 20-25 frame per muovere il puntatore in modo fluido verso il target.
2. **Click ripple ring**:
   Disegnare cerchi concentrici azzurri (`#5f9fc5` / `rgba(95, 159, 197, 180)`) attorno alle coordinate di click per 6 frame.
3. **Compilazione GIF ottimizzata con FFmpeg**:
   ```bash
   ffmpeg -y -framerate 30 -i scratch/clip_frames/f_%04d.png \
     -vf "split[s0][s1];[s0]palettegen=max_colors=128:reserve_transparent=0[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3" \
     website/assets/img/ui/feature-XX-nome.gif
   ```
   Dimensione target: **< 500 KB per clip**, 30 FPS reali, zero artefatti da slideshow.

---

## 9. Mappatura Coordinate Schermo (Risoluzione 1024x768)

| Elemento UI | Coordinate Pixel (X, Y) | Metodo di Attivazione Consigliato |
|---|---|---|
| **Titlebar: Settings (Gear)** | `(853, 32)` | Click o `Space` quando focused |
| **Titlebar: Theme (Moon/Sun)** | `(830, 32)` | Click |
| **Titlebar: Review Changes `[ \| ]`** | `(775, 32)` | Click |
| **Titlebar: Comandi (`Ctrl+K`)** | `(780, 32)` | Scorciatoia `Ctrl+K` |
| **Settings: Back Arrow `←`** | `(44, 112)` | Click `Point(44, 112)` o `Alt+Left` |
| **Landing: Quick Launch Card** | `(715, 395)` | Click `Point(715, 395)` |
| **Landing: `+ Nuova sessione`** | `(128, 695)` | Click |
| **Composer: Input Text Area** | `(150, 615)` | Click `Point(150, 615)` + `TypeText` |
| **Composer: Send Button (Blue)** | `(530, 675)` | Click `Point(530, 675)` o `Ctrl+Enter` |
| **Question Dialog: Opzione 1** | `(120, 548)` | Click `Point(120, 548)` |
| **Question Dialog: Opzione 2** | `(120, 580)` | Click `Point(120, 580)` |
| **Question Dialog: Opzione 3** | `(120, 610)` | Click `Point(120, 610)` |
| **Question Dialog: Pulsante Invia** | `(518, 657)` | Click `Point(518, 657)` |
| **Right Pane: Tab `[ FILE ]`** | `(635, 105)` | Click |
| **Right Pane: Tab `[ Git Changes ]`** | `(720, 105)` | Click |
| **Right Pane: Pulsante Reload `↻`** | `(938, 105)` | Click |
