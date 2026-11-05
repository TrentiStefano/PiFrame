import os
import subprocess
from PIL import Image, ImageDraw

def draw_cursor(im, x, y, clicking=False, click_color=(95, 159, 197)):
    out = im.copy()
    draw = ImageDraw.Draw(out, "RGBA")
    
    if clicking:
        for r in range(12, 26, 3):
            draw.ellipse([x - r, y - r, x + r, y + r], outline=(*click_color, 180), width=2)
            
    points = [
        (x, y),
        (x, y + 20),
        (x + 6, y + 16),
        (x + 10, y + 24),
        (x + 13, y + 22),
        (x + 9, y + 15),
        (x + 16, y + 15)
    ]
    shadow_pts = [(px + 1, py + 1) for px, py in points]
    draw.polygon(shadow_pts, fill=(0, 0, 0, 100))
    draw.polygon(points, fill=(255, 255, 255, 255), outline=(20, 20, 20, 255))
    return out

def compile_clip2():
    img_collapsed = Image.open("scratch/review_frame_collapsed.png").convert("RGBA")
    img_expanded = Image.open("scratch/review_frame_expanded.png").convert("RGBA")
    
    fps = 30
    frames = []
    
    # 1. State 1 (Collapsed file list, holds 1.0s = 30 frames)
    cur_x, cur_y = 650, 400
    for i in range(25):
        frames.append(draw_cursor(img_collapsed, cur_x, cur_y))
        
    # 2. Cursor moves to file row chevron (X: 180, Y: 185) over 0.7s (21 frames)
    target_x, target_y = 180, 185
    for i in range(1, 22):
        t = i / 21
        t_ease = t * t * (3 - 2 * t)
        cx = int(cur_x + (target_x - cur_x) * t_ease)
        cy = int(cur_y + (target_y - cur_y) * t_ease)
        frames.append(draw_cursor(img_collapsed, cx, cy))
        
    # 3. Click to expand (click ripple 6 frames)
    for i in range(6):
        frames.append(draw_cursor(img_collapsed, target_x, target_y, clicking=True))
        
    cur_x, cur_y = target_x, target_y
    
    # 4. Smooth expansion transition over 10 frames
    for i in range(1, 11):
        alpha = i / 10
        blended = Image.blend(img_collapsed, img_expanded, alpha)
        frames.append(draw_cursor(blended, cur_x, cur_y))
        
    # 5. Cursor inspects 50/50 diff: moves down to the diff lines (X: 520, Y: 420) over 0.8s (24 frames)
    target_x, target_y = 520, 420
    for i in range(1, 25):
        t = i / 24
        t_ease = t * t * (3 - 2 * t)
        cx = int(cur_x + (target_x - cur_x) * t_ease)
        cy = int(cur_y + (target_y - cur_y) * t_ease)
        frames.append(draw_cursor(img_expanded, cx, cy))
        
    cur_x, cur_y = target_x, target_y
    # 6. Hold expanded state showing the 50/50 additions and deletions (2.0s = 60 frames)
    for i in range(60):
        frames.append(draw_cursor(img_expanded, cur_x, cur_y))
        
    print(f"Total Clip 2 frames: {len(frames)} @ {fps}fps")
    
    tmp_dir = "scratch/clip2_frames"
    os.makedirs(tmp_dir, exist_ok=True)
    for f in os.listdir(tmp_dir):
        os.remove(os.path.join(tmp_dir, f))
        
    for i, frame in enumerate(frames):
        small = frame.resize((800, 544), Image.Resampling.LANCZOS)
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
    print(f"Successfully generated Clip 2: {out_gif} ({size_kb:.1f} KB)")

if __name__ == "__main__":
    compile_clip2()
