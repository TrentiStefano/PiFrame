import subprocess
import os
from PIL import Image
from compile_recordly_gifs import make_recordly_frame

def build_hero_video():
    scenes = [
        ("docs/design-evidence/bento-triptych-fixture-dark-wide.png", 2.5),
        ("scratch/showcase_frames/f05_01.png", 2.5),
        ("scratch/showcase_frames/f11_01.png", 2.5),
        ("scratch/showcase_frames/f01_02.png", 2.5),
    ]
    
    tmp_dir = os.path.join("scratch", "hero_frames")
    os.makedirs(tmp_dir, exist_ok=True)
    for f in os.listdir(tmp_dir):
        os.remove(os.path.join(tmp_dir, f))
        
    fps = 30
    total_frames = 0
    canvas_w = 1280
    canvas_h = 720
    
    transition_len = 10  # frames for crossfade
    
    rendered_scenes = []
    for path, dur in scenes:
        img = Image.open(path)
        frame = make_recordly_frame(img, canvas_w=canvas_w, canvas_h=canvas_h, pad_x=48, pad_y=40, radius=16)
        rendered_scenes.append((frame, int(fps * dur)))
        
    all_frames = []
    for idx, (scene_frame, frame_count) in enumerate(rendered_scenes):
        next_frame, _ = rendered_scenes[(idx + 1) % len(rendered_scenes)]
        hold_count = frame_count - transition_len if idx < len(rendered_scenes) - 1 else frame_count
        
        for _ in range(hold_count):
            all_frames.append(scene_frame)
            
        if idx < len(rendered_scenes) - 1:
            for t in range(1, transition_len + 1):
                alpha = t / (transition_len + 1)
                blended = Image.blend(scene_frame, next_frame, alpha)
                all_frames.append(blended)
                
    # Ensure exactly 300 frames (10.0 seconds at 30 fps)
    all_frames = all_frames[:300]
    while len(all_frames) < 300:
        all_frames.append(all_frames[-1])
        
    print(f"Writing {len(all_frames)} frames for Hero Video...")
    for i, f in enumerate(all_frames):
        p = os.path.join(tmp_dir, f"hframe_{i:04d}.png")
        f.convert("RGB").save(p)
        
    # MP4 H.264
    mp4_out = "website/assets/video/hero-10s-piframe-showcase.mp4"
    cmd_mp4 = [
        "ffmpeg", "-y",
        "-framerate", "30",
        "-i", os.path.join(tmp_dir, "hframe_%04d.png"),
        "-c:v", "libx264",
        "-pix_fmt", "yuv420p",
        "-profile:v", "high",
        "-level", "4.0",
        "-crf", "18",
        "-movflags", "+faststart",
        mp4_out
    ]
    subprocess.run(cmd_mp4, check=True)
    print(f"Generated Hero MP4: {mp4_out}")
    
    # WebM VP9
    webm_out = "website/assets/video/hero-10s-piframe-showcase.webm"
    cmd_webm = [
        "ffmpeg", "-y",
        "-framerate", "30",
        "-i", os.path.join(tmp_dir, "hframe_%04d.png"),
        "-c:v", "libvpx-vp9",
        "-b:v", "1800k",
        "-crf", "24",
        webm_out
    ]
    subprocess.run(cmd_webm, check=True)
    print(f"Generated Hero WebM: {webm_out}")

if __name__ == "__main__":
    build_hero_video()
