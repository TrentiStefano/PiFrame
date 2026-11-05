import os
import subprocess
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from recordly_engine import make_recordly_backdrop, draw_minimal_cursor, frame_window_on_backdrop

def create_clip1_states():
    # Base dark window (1920x1032, without taskbar)
    base_raw = Image.open("scratch/hyperv_now_live.png")
    app_base = base_raw.crop((0, 0, 1920, 1032)).convert("RGBA")
    
    # 1. State A: Question card open in transcript (Option 1 selected by default)
    stateA = app_base.copy()
    drawA = ImageDraw.Draw(stateA, "RGBA")
    
    # Question Card bounds in transcript (center pane: x=825 to 1520, y=480 to 760)
    card_x0, card_y0 = 845, 470
    card_w, card_h = 660, 270
    card_x1, card_y1 = card_x0 + card_w, card_y0 + card_h
    
    # Card background & border
    drawA.rounded_rectangle([card_x0, card_y0, card_x1, card_y1], radius=12, fill=(28, 36, 50, 255), outline=(95, 159, 197, 160), width=1)
    
    # Question Header
    drawA.text((card_x0 + 20, card_y0 + 18), "[Libreria] Quale libreria preferisci utilizzare?", fill=(248, 250, 252, 255))
    
    # Options Y coordinates
    opt_y = [card_y0 + 58, card_y0 + 98, card_y0 + 138, card_y0 + 178]
    opts_text = [
        "1. Axios — Leggero e performante",
        "2. Native Fetch — Standard browser, zero dipendenze",
        "3. TanStack Query — Query hook e caching automatico",
        "4. Type something..."
    ]
    
    for i, y in enumerate(opt_y):
        # Radio circle
        rx, ry = card_x0 + 26, y + 6
        drawA.ellipse([rx - 6, ry - 6, rx + 6, ry + 6], outline=(130, 150, 175, 200), width=2)
        if i == 0:
            # Option 1 checked
            drawA.ellipse([rx - 3, ry - 3, rx + 3, ry + 3], fill=(95, 159, 197, 255))
        drawA.text((card_x0 + 46, y), opts_text[i], fill=(225, 232, 240, 255) if i == 0 else (163, 178, 197, 255))
        
    # Buttons: Annulla & Invia
    btn_invia_x0, btn_invia_y0 = card_x1 - 100, card_y1 - 42
    drawA.text((card_x1 - 170, btn_invia_y0 + 6), "Annulla", fill=(134, 150, 171, 255))
    drawA.rounded_rectangle([btn_invia_x0, btn_invia_y0, card_x1 - 20, card_y1 - 12], radius=6, fill=(95, 159, 197, 255))
    drawA.text((btn_invia_x0 + 24, btn_invia_y0 + 6), "Invia", fill=(11, 17, 24, 255))
    
    # 2. State B: Option 2 (Native Fetch) clicked and selected
    stateB = app_base.copy()
    drawB = ImageDraw.Draw(stateB, "RGBA")
    drawB.rounded_rectangle([card_x0, card_y0, card_x1, card_y1], radius=12, fill=(28, 36, 50, 255), outline=(95, 159, 197, 160), width=1)
    drawB.text((card_x0 + 20, card_y0 + 18), "[Libreria] Quale libreria preferisci utilizzare?", fill=(248, 250, 252, 255))
    
    for i, y in enumerate(opt_y):
        rx, ry = card_x0 + 26, y + 6
        drawB.ellipse([rx - 6, ry - 6, rx + 6, ry + 6], outline=(95, 159, 197, 255) if i == 1 else (130, 150, 175, 200), width=2)
        if i == 1:
            # Option 2 checked!
            drawB.ellipse([rx - 3, ry - 3, rx + 3, ry + 3], fill=(95, 159, 197, 255))
        drawB.text((card_x0 + 46, y), opts_text[i], fill=(248, 250, 252, 255) if i == 1 else (163, 178, 197, 255))
        
    drawB.text((card_x1 - 170, btn_invia_y0 + 6), "Annulla", fill=(134, 150, 171, 255))
    drawB.rounded_rectangle([btn_invia_x0, btn_invia_y0, card_x1 - 20, card_y1 - 12], radius=6, fill=(129, 178, 207, 255))
    drawB.text((btn_invia_x0 + 24, btn_invia_y0 + 6), "Invia", fill=(11, 17, 24, 255))
    
    # 3. State C: Dialog resolves into transcript, showing user answer and assistant response
    stateC = app_base.copy()
    drawC = ImageDraw.Draw(stateC, "RGBA")
    
    # User message bubble in transcript
    u_x0, u_y0 = card_x0, card_y0
    drawC.rounded_rectangle([u_x0, u_y0, u_x0 + 480, u_y0 + 68], radius=10, fill=(33, 52, 74, 255), outline=(46, 60, 83, 200), width=1)
    drawC.text((u_x0 + 16, u_y0 + 12), "Tu", fill=(129, 178, 207, 255))
    drawC.text((u_x0 + 16, u_y0 + 34), "Scelta: 2. Native Fetch — Standard browser, zero dipendenze", fill=(248, 250, 252, 255))
    
    # Assistant response bubble
    a_x0, a_y0 = card_x0, u_y0 + 82
    drawC.rounded_rectangle([a_x0, a_y0, a_x0 + 600, a_y0 + 88], radius=10, fill=(28, 36, 50, 255), outline=(46, 60, 83, 200), width=1)
    drawC.text((a_x0 + 16, a_y0 + 12), "Assistente", fill=(161, 217, 176, 255))
    drawC.text((a_x0 + 16, a_y0 + 34), "Approccio confermato: implemento il client HTTP con Native Fetch.", fill=(248, 250, 252, 255))
    drawC.text((a_x0 + 16, a_y0 + 56), "Nessuna dipendenza npm aggiunta. Procedo con la stesura dei test.", fill=(163, 178, 197, 255))
    
    # Update status badge in stateC (Completato)
    drawC.rounded_rectangle([1400, 64, 1510, 92], radius=14, fill=(161, 217, 176, 40), outline=(161, 217, 176, 120), width=1)
    drawC.text((1426, 70), "Completato", fill=(161, 217, 176, 255))
    
    return stateA, stateB, stateC, (card_x0 + 46, opt_y[1] + 6, btn_invia_x0 + 40, btn_invia_y0 + 15)

def compile_clip1_gif():
    print("Compiling Clip 1: Domande interattive dell'agente (Recordly Style)...")
    stateA, stateB, stateC, (opt2_x, opt2_y, invia_x, invia_y) = create_clip1_states()
    
    # Frame full window onto 1280x720 Recordly backdrop
    framedA, meta = frame_window_on_backdrop(stateA, backdrop_w=1280, backdrop_h=720, pad=36)
    framedB, _ = frame_window_on_backdrop(stateB, backdrop_w=1280, backdrop_h=720, pad=36)
    framedC, _ = frame_window_on_backdrop(stateC, backdrop_w=1280, backdrop_h=720, pad=36)
    
    pos_x, pos_y, new_w, new_h, scale = meta
    
    # Translate click targets to canvas coordinates
    canvas_opt2_x = pos_x + int(opt2_x * scale)
    canvas_opt2_y = pos_y + int(opt2_y * scale)
    canvas_invia_x = pos_x + int(invia_x * scale)
    canvas_invia_y = pos_y + int(invia_y * scale)
    
    fps = 30
    frames = []
    
    # 1. Start state: cursor resting at composer (1.2s = 36 frames)
    cur_x = pos_x + int(1000 * scale)
    cur_y = pos_y + int(850 * scale)
    for _ in range(30):
        frames.append(draw_minimal_cursor(framedA, cur_x, cur_y, scale=1.0))
        
    # 2. Smooth movement to Option 2 (Native Fetch) over 0.7s (21 frames)
    for i in range(1, 22):
        t = i / 21
        t_ease = t * t * (3 - 2 * t)
        cx = int(cur_x + (canvas_opt2_x - cur_x) * t_ease)
        cy = int(cur_y + (canvas_opt2_y - cur_y) * t_ease)
        frames.append(draw_minimal_cursor(framedA, cx, cy, scale=1.0))
        
    cur_x, cur_y = canvas_opt2_x, canvas_opt2_y
    # 3. Micro-tap on Option 2 (3 frames pressed, then switch to framedB)
    for _ in range(4):
        frames.append(draw_minimal_cursor(framedA, cur_x, cur_y, scale=1.0, clicking=True))
        
    # 4. Hold Option 2 selected (0.8s = 24 frames)
    for _ in range(20):
        frames.append(draw_minimal_cursor(framedB, cur_x, cur_y, scale=1.0))
        
    # 5. Move to 'Invia' button over 0.6s (18 frames)
    for i in range(1, 19):
        t = i / 18
        t_ease = t * t * (3 - 2 * t)
        cx = int(cur_x + (canvas_invia_x - cur_x) * t_ease)
        cy = int(cur_y + (canvas_invia_y - cur_y) * t_ease)
        frames.append(draw_minimal_cursor(framedB, cx, cy, scale=1.0))
        
    cur_x, cur_y = canvas_invia_x, canvas_invia_y
    # 6. Micro-tap on 'Invia'
    for _ in range(4):
        frames.append(draw_minimal_cursor(framedB, cur_x, cur_y, scale=1.0, clicking=True))
        
    # 7. Smooth crossfade to State C (resolved answer) over 8 frames
    for i in range(1, 9):
        alpha = i / 9
        blended = Image.blend(framedB, framedC, alpha)
        frames.append(draw_minimal_cursor(blended, cur_x, cur_y, scale=1.0))
        
    # 8. Hold resolved state (1.8s = 54 frames)
    for _ in range(54):
        frames.append(draw_minimal_cursor(framedC, cur_x, cur_y, scale=1.0))
        
    # Compile GIF
    tmp_dir = "scratch/clip1_recordly_frames"
    os.makedirs(tmp_dir, exist_ok=True)
    for f in os.listdir(tmp_dir):
        os.remove(os.path.join(tmp_dir, f))
        
    for i, frame in enumerate(frames):
        # 960x540 for lightning-fast loading and high retina clarity
        small = frame.resize((960, 540), Image.Resampling.LANCZOS)
        small.convert("RGB").save(os.path.join(tmp_dir, f"f_{i:04d}.png"))
        
    out_gif = "website/assets/img/ui/feature-01-agent-questions.gif"
    cmd = [
        "ffmpeg", "-y",
        "-framerate", str(fps),
        "-i", os.path.join(tmp_dir, "f_%04d.png"),
        "-vf", "split[s0][s1];[s0]palettegen=max_colors=128:reserve_transparent=0[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3",
        out_gif
    ]
    subprocess.run(cmd, check=True)
    size_kb = os.path.getsize(out_gif) / 1024
    print(f"Generated Clip 1: {out_gif} ({len(frames)} frames, {size_kb:.1f} KB)")

# ==============================================================================
# CLIP 2: REVIEW CHANGES & 50/50 DIFF IN FULL APPSHELL (RECORDLY STYLE)
# ==============================================================================

def create_clip2_states():
    base_raw = Image.open("scratch/hyperv_now_live.png")
    app_base = base_raw.crop((0, 0, 1920, 1032)).convert("RGBA")
    
    # 1. State A: Right pane shows Git Changes desk with modified file 'lib/app_shell.dart'
    stateA = app_base.copy()
    drawA = ImageDraw.Draw(stateA, "RGBA")
    
    # Right pane bounds: x=1530 to 1910, y=55 to 1020
    pane_x0, pane_y0 = 1535, 55
    pane_w, pane_h = 375, 965
    pane_x1, pane_y1 = pane_x0 + pane_w, pane_y0 + pane_h
    
    # Clear inner pane area with dark surface
    drawA.rectangle([pane_x0, pane_y0 + 40, pane_x1, pane_y1], fill=(18, 23, 33, 255))
    
    # Header: Git Changes tab active
    drawA.rounded_rectangle([pane_x0 + 10, pane_y0 + 8, pane_x0 + 115, pane_y0 + 36], radius=6, fill=(28, 36, 50, 255), outline=(95, 159, 197, 200), width=1)
    drawA.text((pane_x0 + 22, pane_y0 + 14), "Git Changes", fill=(248, 250, 252, 255))
    
    # File row (lib/app_shell.dart +14, -3) with chevron '>'
    row_y0 = pane_y0 + 55
    drawA.rounded_rectangle([pane_x0 + 10, row_y0, pane_x1 - 10, row_y0 + 38], radius=8, fill=(28, 36, 50, 255), outline=(46, 60, 83, 200), width=1)
    # Chevron '>'
    drawA.text((pane_x0 + 22, row_y0 + 11), ">", fill=(95, 159, 197, 255))
    drawA.text((pane_x0 + 42, row_y0 + 11), "lib/app_shell.dart", fill=(248, 250, 252, 255))
    drawA.text((pane_x1 - 72, row_y0 + 11), "+14", fill=(161, 217, 176, 255))
    drawA.text((pane_x1 - 38, row_y0 + 11), "-3", fill=(241, 136, 122, 255))
    
    # 2. State B: Clicked chevron -> 50/50 two-column split diff expands!
    stateB = app_base.copy()
    drawB = ImageDraw.Draw(stateB, "RGBA")
    
    # Expand Review Changes across right pane (or split desk: x=1150 to 1910)
    desk_x0 = 1150
    drawB.rectangle([desk_x0, pane_y0 + 40, pane_x1, pane_y1], fill=(18, 23, 33, 255))
    drawB.line([(desk_x0, pane_y0 + 40), (desk_x0, pane_y1)], fill=(46, 60, 83, 255), width=1)
    
    # Active file row with chevron 'v'
    drawB.rounded_rectangle([desk_x0 + 12, row_y0, pane_x1 - 12, row_y0 + 38], radius=8, fill=(36, 46, 64, 255), outline=(95, 159, 197, 255), width=1)
    drawB.text((desk_x0 + 24, row_y0 + 11), "v", fill=(95, 159, 197, 255))
    drawB.text((desk_x0 + 44, row_y0 + 11), "lib/app_shell.dart (Revisione modifiche 50/50)", fill=(248, 250, 252, 255))
    drawB.text((pane_x1 - 76, row_y0 + 11), "+14", fill=(161, 217, 176, 255))
    drawB.text((pane_x1 - 40, row_y0 + 11), "-3", fill=(241, 136, 122, 255))
    
    # 50/50 Diff Container
    diff_y0 = row_y0 + 46
    diff_h = 480
    diff_mid = desk_x0 + 12 + (pane_x1 - desk_x0 - 24) // 2
    
    drawB.rounded_rectangle([desk_x0 + 12, diff_y0, pane_x1 - 12, diff_y0 + diff_h], radius=8, fill=(22, 28, 39, 255), outline=(46, 60, 83, 200), width=1)
    drawB.line([(diff_mid, diff_y0), (diff_mid, diff_y0 + diff_h)], fill=(46, 60, 83, 255), width=1)
    
    # Left Column Header: Original
    drawB.text((desk_x0 + 24, diff_y0 + 10), "ORIGINALE (HEAD)", fill=(163, 178, 197, 255))
    # Right Column Header: Modificato
    drawB.text((diff_mid + 16, diff_y0 + 10), "MODIFICATO (+14 / -3)", fill=(95, 159, 197, 255))
    drawB.line([(desk_x0 + 12, diff_y0 + 32), (pane_x1 - 12, diff_y0 + 32)], fill=(46, 60, 83, 255), width=1)
    
    # Left code lines (deletions)
    lines_left = [
        "13   Widget build(BuildContext context) {",
        "14 -   final bg = Color(0xFF232634);",
        "15 -   final accent = Color(0xFFCA9EE6);",
        "16     return Scaffold(",
        "17       backgroundColor: bg,",
        "18 -     body: Center(child: Text('PiFrame'));",
        "19     );",
        "20   }"
    ]
    # Right code lines (additions)
    lines_right = [
        "13   Widget build(BuildContext context) {",
        "14 +   final bg = FrameTokens.dark.background;",
        "15 +   final chassis = FrameTokens.dark.chassis;",
        "16 +   final accent = FrameTokens.dark.accent;",
        "17 +   final thinking = FrameTokens.dark.thinking;",
        "18 +   return BentoTriptychWorkspace(",
        "19 +     chat: TranscriptView(),",
        "20 +     diffReview: ReviewFileDiffViewer(),",
        "21 +   );"
    ]
    
    for idx, l in enumerate(lines_left):
        ly = diff_y0 + 44 + idx * 24
        is_del = "-" in l
        if is_del:
            drawB.rectangle([desk_x0 + 14, ly - 3, diff_mid - 2, ly + 21], fill=(241, 136, 122, 35))
        drawB.text((desk_x0 + 20, ly), l, fill=(241, 136, 122, 255) if is_del else (163, 178, 197, 255))
        
    for idx, l in enumerate(lines_right):
        ly = diff_y0 + 44 + idx * 24
        is_add = "+" in l
        if is_add:
            drawB.rectangle([diff_mid + 2, ly - 3, pane_x1 - 14, ly + 21], fill=(161, 217, 176, 35))
        drawB.text((diff_mid + 12, ly), l, fill=(161, 217, 176, 255) if is_add else (225, 232, 240, 255))
        
    return stateA, stateB, (pane_x0 + 26, row_y0 + 18, diff_mid + 80, diff_y0 + 120)

def compile_clip2_gif():
    print("Compiling Clip 2: Review changes & 50/50 diff (Recordly Style)...")
    stateA, stateB, (row_x, row_y, diff_x, diff_y) = create_clip2_states()
    
    framedA, meta = frame_window_on_backdrop(stateA, backdrop_w=1280, backdrop_h=720, pad=36)
    framedB, _ = frame_window_on_backdrop(stateB, backdrop_w=1280, backdrop_h=720, pad=36)
    
    pos_x, pos_y, new_w, new_h, scale = meta
    
    canvas_row_x = pos_x + int(row_x * scale)
    canvas_row_y = pos_y + int(row_y * scale)
    canvas_diff_x = pos_x + int(diff_x * scale)
    canvas_diff_y = pos_y + int(diff_y * scale)
    
    fps = 30
    frames = []
    
    # 1. State A: Whole workspace visible, cursor resting in center chat (1.0s = 30 frames)
    cur_x = pos_x + int(960 * scale)
    cur_y = pos_y + int(500 * scale)
    for _ in range(25):
        frames.append(draw_minimal_cursor(framedA, cur_x, cur_y, scale=1.0))
        
    # 2. Smooth movement to file row chevron over 0.7s (21 frames)
    for i in range(1, 22):
        t = i / 21
        t_ease = t * t * (3 - 2 * t)
        cx = int(cur_x + (canvas_row_x - cur_x) * t_ease)
        cy = int(cur_y + (canvas_row_y - cur_y) * t_ease)
        frames.append(draw_minimal_cursor(framedA, cx, cy, scale=1.0))
        
    cur_x, cur_y = canvas_row_x, canvas_row_y
    # 3. Micro-tap click to expand
    for _ in range(4):
        frames.append(draw_minimal_cursor(framedA, cur_x, cur_y, scale=1.0, clicking=True))
        
    # 4. Smooth expansion transition over 8 frames
    for i in range(1, 9):
        alpha = i / 9
        blended = Image.blend(framedA, framedB, alpha)
        frames.append(draw_minimal_cursor(blended, cur_x, cur_y, scale=1.0))
        
    # 5. Cursor moves to inspect code changes in the 50/50 diff over 0.8s (24 frames)
    for i in range(1, 25):
        t = i / 24
        t_ease = t * t * (3 - 2 * t)
        cx = int(cur_x + (canvas_diff_x - cur_x) * t_ease)
        cy = int(cur_y + (canvas_diff_y - cur_y) * t_ease)
        frames.append(draw_minimal_cursor(framedB, cx, cy, scale=1.0))
        
    cur_x, cur_y = canvas_diff_x, canvas_diff_y
    # 6. Hold expanded diff state showing code additions & deletions (2.0s = 60 frames)
    for _ in range(60):
        frames.append(draw_minimal_cursor(framedB, cur_x, cur_y, scale=1.0))
        
    # Compile GIF
    tmp_dir = "scratch/clip2_recordly_frames"
    os.makedirs(tmp_dir, exist_ok=True)
    for f in os.listdir(tmp_dir):
        os.remove(os.path.join(tmp_dir, f))
        
    for i, frame in enumerate(frames):
        small = frame.resize((960, 540), Image.Resampling.LANCZOS)
        small.convert("RGB").save(os.path.join(tmp_dir, f"f_{i:04d}.png"))
        
    out_gif = "website/assets/img/ui/feature-05-review-changes-50-50-diff.gif"
    cmd = [
        "ffmpeg", "-y",
        "-framerate", str(fps),
        "-i", os.path.join(tmp_dir, "f_%04d.png"),
        "-vf", "split[s0][s1];[s0]palettegen=max_colors=128:reserve_transparent=0[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3",
        out_gif
    ]
    subprocess.run(cmd, check=True)
    size_kb = os.path.getsize(out_gif) / 1024
    print(f"Generated Clip 2: {out_gif} ({len(frames)} frames, {size_kb:.1f} KB)")

if __name__ == "__main__":
    compile_clip1_gif()
    compile_clip2_gif()
