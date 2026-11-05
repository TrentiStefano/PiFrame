import os
import subprocess
from PIL import Image, ImageDraw, ImageFilter, ImageFont

def make_recordly_backdrop(w=1280, h=720):
    """
    Creates Recordly's signature studio backdrop:
    Dark slate gradient with subtle radial illumination.
    """
    im = Image.new("RGBA", (w, h), (14, 18, 26, 255))
    draw = ImageDraw.Draw(im)
    
    # Vertical gradient
    for y in range(h):
        t = y / h
        r = int(13 + (22 - 13) * t)
        g = int(17 + (28 - 17) * t)
        b = int(25 + (39 - 25) * t)
        draw.line([(0, y), (w, y)], fill=(r, g, b, 255))
        
    return im

def draw_minimal_cursor(im, x, y, scale=1.0, clicking=False):
    """
    Renders Recordly's sleek minimal pointer with micro-press on click.
    Zero cheesy rings.
    """
    out = im.copy()
    draw = ImageDraw.Draw(out, "RGBA")
    
    # Cursor size
    base_s = 16 * scale
    if clicking:
        base_s *= 0.90 # subtle micro-tap compression
        
    pts = [
        (x, y),
        (x, y + base_s * 1.35),
        (x + base_s * 0.38, y + base_s * 1.05),
        (x + base_s * 0.72, y + base_s * 1.65),
        (x + base_s * 0.95, y + base_s * 1.50),
        (x + base_s * 0.62, y + base_s * 0.92),
        (x + base_s * 1.15, y + base_s * 0.92),
    ]
    
    # Soft drop shadow
    shadow_pts = [(px + 1.5, py + 2.0) for px, py in pts]
    draw.polygon(shadow_pts, fill=(0, 0, 0, 90))
    # Main white arrow with crisp dark border
    draw.polygon(pts, fill=(255, 255, 255, 255), outline=(28, 36, 50, 240))
    return out

def frame_window_on_backdrop(app_window_crop, backdrop_w=1280, backdrop_h=720, pad=48, radius=14):
    """
    Frames the pure application window onto the Recordly backdrop with
    rounded corners and soft diffuse shadow.
    """
    backdrop = make_recordly_backdrop(backdrop_w, backdrop_h)
    
    max_w = backdrop_w - pad * 2
    max_h = backdrop_h - pad * 2
    scale = min(max_w / app_window_crop.width, max_h / app_window_crop.height)
    new_w = int(app_window_crop.width * scale)
    new_h = int(app_window_crop.height * scale)
    
    scaled_win = app_window_crop.resize((new_w, new_h), Image.Resampling.LANCZOS).convert("RGBA")
    
    # Rounded mask
    mask = Image.new("L", (new_w, new_h), 0)
    draw_mask = ImageDraw.Draw(mask)
    draw_mask.rounded_rectangle([0, 0, new_w, new_h], radius=radius, fill=255)
    
    # Shadow
    shadow_pad = 28
    sw = new_w + shadow_pad * 2
    sh = new_h + shadow_pad * 2
    shadow = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    draw_s = ImageDraw.Draw(shadow)
    draw_s.rounded_rectangle(
        [shadow_pad, shadow_pad + 10, sw - shadow_pad, sh - shadow_pad + 14],
        radius=radius + 2,
        fill=(0, 0, 0, 130)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=16))
    
    pos_x = (backdrop_w - new_w) // 2
    pos_y = (backdrop_h - new_h) // 2
    
    backdrop.paste(shadow, (pos_x - shadow_pad, pos_y - shadow_pad), shadow)
    backdrop.paste(scaled_win, (pos_x, pos_y), mask)
    
    # 1px border
    draw_b = ImageDraw.Draw(backdrop)
    draw_b.rounded_rectangle(
        [pos_x, pos_y, pos_x + new_w - 1, pos_y + new_h - 1],
        radius=radius,
        outline=(65, 80, 105, 140),
        width=1
    )
    
    return backdrop, (pos_x, pos_y, new_w, new_h, scale)

print("Recordly engine helper module ready!")
