import os
import subprocess
from PIL import Image, ImageDraw, ImageFilter

def draw_cursor(im, x, y, clicking=False, click_color=(95, 159, 197)):
    out = im.copy()
    draw = ImageDraw.Draw(out, "RGBA")
    
    # Click ripple ring if clicking
    if clicking:
        for r in range(12, 24, 3):
            draw.ellipse([x - r, y - r, x + r, y + r], outline=(*click_color, 160), width=2)
            
    # Draw arrow cursor
    # Pointer polygon
    points = [
        (x, y),
        (x, y + 18),
        (x + 5, y + 14),
        (x + 9, y + 22),
        (x + 12, y + 20),
        (x + 8, y + 13),
        (x + 14, y + 13)
    ]
    # Shadow
    shadow_pts = [(px + 1, py + 1) for px, py in points]
    draw.polygon(shadow_pts, fill=(0, 0, 0, 100))
    # Main cursor
    draw.polygon(points, fill=(255, 255, 255, 255), outline=(20, 20, 20, 255))
    return out

def compile_clip1():
    img_state1 = Image.open("scratch/hyperv_question_arrived.png").convert("RGBA")
    img_state2 = Image.open("scratch/hyperv_after_clip1_recorded.png").convert("RGBA")
    img_state3 = Image.open("scratch/hyperv_after_invia_click.png").convert("RGBA")
    
    fps = 30
    frames = []
    
    # 1. State 1 (Question appears, holds 1.0s = 30 frames)
    cur_x, cur_y = 280, 480
    for i in range(25):
        frames.append(draw_cursor(img_state1, cur_x, cur_y))
        
    # 2. Cursor moves to Option 3 (TanStack Query: X=120, Y=610) over 0.7s (21 frames)
    target_x, target_y = 120, 610
    for i in range(1, 22):
        t = i / 21
        # Smooth cubic ease
        t_ease = t * t * (3 - 2 * t)
        cx = int(cur_x + (target_x - cur_x) * t_ease)
        cy = int(cur_y + (target_y - cur_y) * t_ease)
        frames.append(draw_cursor(img_state1, cx, cy))
        
    # 3. Click Option 3 (click ripple 6 frames, then switch to state 2)
    for i in range(6):
        frames.append(draw_cursor(img_state1, target_x, target_y, clicking=True))
        
    cur_x, cur_y = target_x, target_y
    # Hold state 2 with Option 3 selected (0.8s = 24 frames)
    for i in range(20):
        frames.append(draw_cursor(img_state2, cur_x, cur_y))
        
    # 4. Cursor moves to 'Invia' button (X=518, Y=657) over 0.6s (18 frames)
    target_x, target_y = 518, 657
    for i in range(1, 19):
        t = i / 18
        t_ease = t * t * (3 - 2 * t)
        cx = int(cur_x + (target_x - cur_x) * t_ease)
        cy = int(cur_y + (target_y - cur_y) * t_ease)
        frames.append(draw_cursor(img_state2, cx, cy))
        
    # 5. Click 'Invia' (click ripple 6 frames)
    for i in range(6):
        frames.append(draw_cursor(img_state2, target_x, target_y, clicking=True))
        
    cur_x, cur_y = target_x, target_y
    # 6. Smooth crossfade to State 3 (dialog dismissed, assistant answer in transcript) over 8 frames
    for i in range(1, 9):
        alpha = i / 9
        blended = Image.blend(img_state2, img_state3, alpha)
        frames.append(draw_cursor(blended, cur_x, cur_y))
        
    # 7. Hold state 3 showing answer (1.8s = 54 frames)
    for i in range(54):
        frames.append(draw_cursor(img_state3, cur_x, cur_y))
        
    print(f"Total frames generated: {len(frames)} @ {fps}fps")
    
    # Save frames to scratch
    tmp_dir = "scratch/clip1_frames"
    os.makedirs(tmp_dir, exist_ok=True)
    for f in os.listdir(tmp_dir):
        os.remove(os.path.join(tmp_dir, f))
        
    for i, frame in enumerate(frames):
        # Resize to crisp 960x720 or 800x600 for web performance
        small = frame.resize((800, 600), Image.Resampling.LANCZOS)
        small.convert("RGB").save(os.path.join(tmp_dir, f"f_{i:04d}.png"))
        
    # Compile with ffmpeg
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
    print(f"Successfully generated Clip 1: {out_gif} ({size_kb:.1f} KB)")

if __name__ == "__main__":
    compile_clip1()
