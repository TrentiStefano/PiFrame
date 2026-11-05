import os
import subprocess
from PIL import Image, ImageDraw, ImageFilter

def make_recordly_frame(inner_img, canvas_w=960, canvas_h=580, bg_color=(18, 23, 33), pad_x=40, pad_y=36, radius=14):
    """
    Renders an authentic UI capture inside a Recordly presentation frame:
    - Sleek wallpaper background
    - Smooth rounded corners on the app window
    - Multi-layer drop shadow
    """
    canvas = Image.new("RGBA", (canvas_w, canvas_h), (*bg_color, 255))
    
    # Scale inner_img to fit within available space preserving aspect ratio
    max_w = canvas_w - pad_x * 2
    max_h = canvas_h - pad_y * 2
    
    scale = min(max_w / inner_img.width, max_h / inner_img.height)
    new_w = int(inner_img.width * scale)
    new_h = int(inner_img.height * scale)
    scaled_img = inner_img.resize((new_w, new_h), Image.Resampling.LANCZOS).convert("RGBA")
    
    # Create rounded corner mask
    mask = Image.new("L", (new_w, new_h), 0)
    draw_mask = ImageDraw.Draw(mask)
    draw_mask.rounded_rectangle([0, 0, new_w, new_h], radius=radius, fill=255)
    
    # Create shadow
    shadow_pad = 24
    shadow_w = new_w + shadow_pad * 2
    shadow_h = new_h + shadow_pad * 2
    shadow_img = Image.new("RGBA", (shadow_w, shadow_h), (0, 0, 0, 0))
    draw_shadow = ImageDraw.Draw(shadow_img)
    draw_shadow.rounded_rectangle(
        [shadow_pad - 2, shadow_pad + 6, shadow_w - shadow_pad + 2, shadow_h - shadow_pad + 10],
        radius=radius + 2,
        fill=(0, 0, 0, 140)
    )
    shadow_img = shadow_img.filter(ImageFilter.GaussianBlur(radius=14))
    
    # Place on canvas
    pos_x = (canvas_w - new_w) // 2
    pos_y = (canvas_h - new_h) // 2
    
    canvas.paste(shadow_img, (pos_x - shadow_pad, pos_y - shadow_pad), shadow_img)
    canvas.paste(scaled_img, (pos_x, pos_y), mask)
    
    # Subtle border outline
    draw_canvas = ImageDraw.Draw(canvas)
    draw_canvas.rounded_rectangle(
        [pos_x, pos_y, pos_x + new_w - 1, pos_y + new_h - 1],
        radius=radius,
        outline=(71, 90, 119, 120),
        width=1
    )
    
    return canvas

def generate_multi_state_gif(frames_list, output_path, fps=15, duration_per_frame_s=1.2, transition_frames=6):
    """
    Creates a fluid animated GIF transitioning between real Flutter UI states.
    """
    tmp_dir = os.path.join("scratch", "gif_temp")
    os.makedirs(tmp_dir, exist_ok=True)
    for f in os.listdir(tmp_dir):
        os.remove(os.path.join(tmp_dir, f))
        
    all_rendered_frames = []
    
    # If single state, generate a subtle 2-second hold with pulse
    if len(frames_list) == 1:
        base_f = make_recordly_frame(frames_list[0])
        total_f = int(fps * 2.0)
        for i in range(total_f):
            all_rendered_frames.append(base_f)
    else:
        for idx in range(len(frames_list)):
            curr_img = frames_list[idx]
            next_img = frames_list[(idx + 1) % len(frames_list)]
            
            curr_f = make_recordly_frame(curr_img)
            next_f = make_recordly_frame(next_img)
            
            # Hold current state
            hold_count = int(fps * duration_per_frame_s)
            for _ in range(hold_count):
                all_rendered_frames.append(curr_f)
                
            # Crossfade to next state
            for t in range(1, transition_frames + 1):
                alpha = t / (transition_frames + 1)
                blended = Image.blend(curr_f, next_f, alpha)
                all_rendered_frames.append(blended)
                
    # Save frames to disk
    for i, frame in enumerate(all_rendered_frames):
        p = os.path.join(tmp_dir, f"frame_{i:04d}.png")
        frame.convert("RGB").save(p)
        
    # Use ffmpeg to compile high-quality palette-optimized GIF
    cmd = [
        "ffmpeg", "-y",
        "-framerate", str(fps),
        "-i", os.path.join(tmp_dir, "frame_%04d.png"),
        "-vf", "split[s0][s1];[s0]palettegen=max_colors=128:reserve_transparent=0[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3",
        output_path
    ]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    print(f"Generated GIF: {output_path} ({len(all_rendered_frames)} frames @ {fps}fps)")

os.makedirs("website/assets/img/ui", exist_ok=True)

# 1. Feature 01: Agent Questions to User (State 1: Options -> State 2: Selected option 1)
img_f01_1 = Image.open("scratch/showcase_frames/f01_01.png")
img_f01_2 = Image.open("scratch/showcase_frames/f01_02.png")
generate_multi_state_gif([img_f01_1, img_f01_2], "website/assets/img/ui/feature-01-agent-questions.gif", duration_per_frame_s=1.4)

# 2. Feature 04: File Drag & Drop + Attach Chips
img_f04 = Image.open("scratch/showcase_frames/f04_01.png")
generate_multi_state_gif([img_f04], "website/assets/img/ui/feature-04-file-drag-drop-attach.gif")

# 3. Feature 05: 50/50 Split Diff Review
img_f05 = Image.open("scratch/showcase_frames/f05_01.png")
generate_multi_state_gif([img_f05], "website/assets/img/ui/feature-05-review-changes-50-50-diff.gif")

# 4. Feature 06: Git Changes Desk & Staging
img_f06 = Image.open("scratch/showcase_frames/f06_01.png")
generate_multi_state_gif([img_f06], "website/assets/img/ui/feature-06-git-changes-staging.gif")

# 5. Feature 07: Integrated Web Browser Pane
img_f07 = Image.open("scratch/showcase_frames/f07_01.png")
generate_multi_state_gif([img_f07], "website/assets/img/ui/feature-07-web-browser-pane.gif")

# 6. Feature 08: Repository Workspace & Add to Chat
img_f08 = Image.open("scratch/showcase_frames/f08_01.png")
generate_multi_state_gif([img_f08], "website/assets/img/ui/feature-08-repo-search-add-to-chat.gif")

# 7. Feature 09: Pane Resize & Integrated Terminal
img_f09 = Image.open("scratch/showcase_frames/f09_01.png")
generate_multi_state_gif([img_f09], "website/assets/img/ui/feature-09-pane-resize-and-terminal.gif")

# 8. Feature 10: Session Renaming & Pinning
img_f10 = Image.open("scratch/showcase_frames/f10_01.png")
generate_multi_state_gif([img_f10], "website/assets/img/ui/feature-10-rename-and-pin-session.gif")

# 9. Feature 11: Light Mode & Pane Visibility (Dark Mode -> Light Mode!)
img_dark = Image.open("docs/design-evidence/bento-triptych-fixture-dark-wide.png")
img_light = Image.open("scratch/showcase_frames/f11_01.png")
generate_multi_state_gif([img_dark, img_light], "website/assets/img/ui/feature-11-light-mode-pane-checklist.gif", duration_per_frame_s=1.6)

# 10. Feature 18: In-Chat File Link to Explorer
img_f18 = Image.open("scratch/showcase_frames/f18_01.png")
generate_multi_state_gif([img_f18], "website/assets/img/ui/feature-18-click-file-open-explorer.gif")

# 11. Feature 20: AGENTS.md Instruction Generator
img_f20 = Image.open("scratch/showcase_frames/f20_01.png")
generate_multi_state_gif([img_f20], "website/assets/img/ui/feature-20-generate-repo-instructions.gif")

print("All Recordly-style feature animations successfully generated from authentic Flutter widgets!")
