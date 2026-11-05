import os
import subprocess
from PIL import Image, ImageDraw, ImageFilter
from recordly_engine import make_recordly_backdrop, draw_minimal_cursor, frame_window_on_backdrop

def compile_final_clip1():
    print("Compiling Final Clip 1: Domande interattive dell'agente (Exact Alignment)...")
    rawA = Image.open("scratch/master_c1_stateA.png").convert("RGBA")
    rawB = Image.open("scratch/master_c1_stateB.png").convert("RGBA")
    rawC = Image.open("scratch/master_c1_stateC.png").convert("RGBA")
    
    # Frame full 1920x1080 window onto 1280x720 Recordly studio backdrop
    framedA, meta = frame_window_on_backdrop(rawA, backdrop_w=1280, backdrop_h=720, pad=32, radius=12)
    framedB, _ = frame_window_on_backdrop(rawB, backdrop_w=1280, backdrop_h=720, pad=32, radius=12)
    framedC, _ = frame_window_on_backdrop(rawC, backdrop_w=1280, backdrop_h=720, pad=32, radius=12)
    
    pos_x, pos_y, new_w, new_h, scale = meta
    
    # Exact coordinates measured from pixel analysis:
    # Option 2 (Native Fetch) radio button center: (865, 867)
    canvas_opt2_x = pos_x + int(865 * scale)
    canvas_opt2_y = pos_y + int(867 * scale)
    
    # Invia button center: (1455, 935)
    canvas_invia_x = pos_x + int(1455 * scale)
    canvas_invia_y = pos_y + int(935 * scale)
    
    fps = 30
    frames = []
    
    # 1. State A: Question card active, cursor resting in chat (1.0s = 30 frames)
    cur_x = pos_x + int(1050 * scale)
    cur_y = pos_y + int(600 * scale)
    for _ in range(25):
        frames.append(draw_minimal_cursor(framedA, cur_x, cur_y, scale=1.0))
        
    # 2. Smooth natural movement to Option 2 radio button over 0.7s (21 frames)
    for i in range(1, 22):
        t = i / 21
        t_ease = t * t * (3 - 2 * t)
        cx = int(cur_x + (canvas_opt2_x - cur_x) * t_ease)
        cy = int(cur_y + (canvas_opt2_y - cur_y) * t_ease)
        frames.append(draw_minimal_cursor(framedA, cx, cy, scale=1.0))
        
    cur_x, cur_y = canvas_opt2_x, canvas_opt2_y
    # 3. Micro-press on Option 2 (3 frames)
    for _ in range(4):
        frames.append(draw_minimal_cursor(framedA, cur_x, cur_y, scale=1.0, clicking=True))
        
    # 4. State B: Option 2 is selected with blue radio dot! (0.8s = 24 frames)
    for _ in range(24):
        frames.append(draw_minimal_cursor(framedB, cur_x, cur_y, scale=1.0))
        
    # 5. Move to 'Invia' button over 0.6s (18 frames)
    for i in range(1, 19):
        t = i / 18
        t_ease = t * t * (3 - 2 * t)
        cx = int(cur_x + (canvas_invia_x - cur_x) * t_ease)
        cy = int(cur_y + (canvas_invia_y - cur_y) * t_ease)
        frames.append(draw_minimal_cursor(framedB, cx, cy, scale=1.0))
        
    cur_x, cur_y = canvas_invia_x, canvas_invia_y
    # 6. Micro-press on 'Invia' (3 frames)
    for _ in range(4):
        frames.append(draw_minimal_cursor(framedB, cur_x, cur_y, scale=1.0, clicking=True))
        
    # 7. Transition to State C (resolved answer in transcript) over 8 frames
    for i in range(1, 9):
        alpha = i / 9
        blended = Image.blend(framedB, framedC, alpha)
        frames.append(draw_minimal_cursor(blended, cur_x, cur_y, scale=1.0))
        
    # 8. Hold State C showing the assistant's confirmed response (2.0s = 60 frames)
    for _ in range(60):
        frames.append(draw_minimal_cursor(framedC, cur_x, cur_y, scale=1.0))
        
    tmp_dir = "scratch/final_clip1_frames"
    os.makedirs(tmp_dir, exist_ok=True)
    for f in os.listdir(tmp_dir):
        os.remove(os.path.join(tmp_dir, f))
        
    for i, frame in enumerate(frames):
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
    print(f"Clip 1 generated: {out_gif} ({len(frames)} frames @ 30fps, {size_kb:.1f} KB)")

def compile_final_clip2():
    print("Compiling Final Clip 2: Review changes & 50/50 diff (Pure Flutter Text)...")
    rawA = Image.open("scratch/master_c2_stateA.png").convert("RGBA")
    rawB = Image.open("scratch/master_c2_stateB.png").convert("RGBA")
    
    framedA, meta = frame_window_on_backdrop(rawA, backdrop_w=1280, backdrop_h=720, pad=32, radius=12)
    framedB, _ = frame_window_on_backdrop(rawB, backdrop_w=1280, backdrop_h=720, pad=32, radius=12)
    
    pos_x, pos_y, new_w, new_h, scale = meta
    
    # File row chevron in right pane: X=1620, Y=112
    canvas_file_x = pos_x + int(1620 * scale)
    canvas_file_y = pos_y + int(112 * scale)
    
    # Inspection point in the middle of 50/50 diff: X=1550, Y=250
    canvas_diff_x = pos_x + int(1550 * scale)
    canvas_diff_y = pos_y + int(250 * scale)
    
    fps = 30
    frames = []
    
    # 1. State A: Review changes desk open, 1 file modified (1.0s = 30 frames)
    cur_x = pos_x + int(1100 * scale)
    cur_y = pos_y + int(450 * scale)
    for _ in range(25):
        frames.append(draw_minimal_cursor(framedA, cur_x, cur_y, scale=1.0))
        
    # 2. Move smoothly to file chevron over 0.7s (21 frames)
    for i in range(1, 22):
        t = i / 21
        t_ease = t * t * (3 - 2 * t)
        cx = int(cur_x + (canvas_file_x - cur_x) * t_ease)
        cy = int(cur_y + (canvas_file_y - cur_y) * t_ease)
        frames.append(draw_minimal_cursor(framedA, cx, cy, scale=1.0))
        
    cur_x, cur_y = canvas_file_x, canvas_file_y
    # 3. Micro-press on file row (3 frames)
    for _ in range(4):
        frames.append(draw_minimal_cursor(framedA, cur_x, cur_y, scale=1.0, clicking=True))
        
    # 4. Smooth expansion transition over 10 frames
    for i in range(1, 11):
        alpha = i / 10
        blended = Image.blend(framedA, framedB, alpha)
        frames.append(draw_minimal_cursor(blended, cur_x, cur_y, scale=1.0))
        
    # 5. Move cursor to inspect code additions and deletions in the 50/50 split diff over 0.8s (24 frames)
    for i in range(1, 25):
        t = i / 24
        t_ease = t * t * (3 - 2 * t)
        cx = int(cur_x + (canvas_diff_x - cur_x) * t_ease)
        cy = int(cur_y + (canvas_diff_y - cur_y) * t_ease)
        frames.append(draw_minimal_cursor(framedB, cx, cy, scale=1.0))
        
    cur_x, cur_y = canvas_diff_x, canvas_diff_y
    # 6. Hold expanded 50/50 split diff state showing code additions and deletions (2.2s = 66 frames)
    for _ in range(66):
        frames.append(draw_minimal_cursor(framedB, cur_x, cur_y, scale=1.0))
        
    tmp_dir = "scratch/final_clip2_frames"
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
    print(f"Clip 2 generated: {out_gif} ({len(frames)} frames @ 30fps, {size_kb:.1f} KB)")

if __name__ == "__main__":
    compile_final_clip1()
    compile_final_clip2()
