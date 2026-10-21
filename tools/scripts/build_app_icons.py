#!/usr/bin/env python3
"""
Build and package production icons for PiFrame across all platforms.
Generates:
- Windows multi-resolution .ico (16, 24, 32, 48, 64, 128, 256)
- macOS AppIcon.appiconset (16, 32, 64, 128, 256, 512, 1024)
- Web favicon and PWA icons (192, 512, maskable)
- Flutter branding assets (SVG, 512, 1024)
- Release assets (SVG, 1024 PNG, ICO)
"""

import os
import shutil
import base64
from pathlib import Path
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]

DARK_PNG_SRC = REPO_ROOT / "scratch" / "new_icons" / "piframe-dark-1024.png"
LIGHT_PNG_SRC = REPO_ROOT / "scratch" / "new_icons" / "piframe-light-1024.png"

def make_svg_from_png(png_path: Path, svg_path: Path):
    with open(png_path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode("ascii")
    svg_content = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="100%" height="100%">
  <image width="1024" height="1024" href="data:image/png;base64,{b64}"/>
</svg>
'''
    with open(svg_path, "w", encoding="utf-8") as f:
        f.write(svg_content)
    print(f"Generated SVG: {svg_path}")

def create_ico(source_png: Path, output_ico: Path):
    img = Image.open(source_png).convert("RGBA")
    sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    output_ico.parent.mkdir(parents=True, exist_ok=True)
    img.save(output_ico, format="ICO", sizes=sizes)
    print(f"Generated ICO: {output_ico} with sizes {sizes}")

def main():
    print(f"Building PiFrame production icons from:\n  {DARK_PNG_SRC}\n  {LIGHT_PNG_SRC}")

    dark_img = Image.open(DARK_PNG_SRC).convert("RGBA")
    light_img = Image.open(LIGHT_PNG_SRC).convert("RGBA")

    # 1. Release Assets
    rel_icons = REPO_ROOT / "release-assets" / "icons"
    rel_icons.mkdir(parents=True, exist_ok=True)
    shutil.copy2(DARK_PNG_SRC, rel_icons / "piframe-dark-1024.png")
    shutil.copy2(LIGHT_PNG_SRC, rel_icons / "piframe-light-1024.png")
    make_svg_from_png(DARK_PNG_SRC, rel_icons / "piframe-dark.svg")
    make_svg_from_png(LIGHT_PNG_SRC, rel_icons / "piframe-light.svg")
    create_ico(DARK_PNG_SRC, rel_icons / "piframe.ico")

    # 2. Windows Runner Resources
    win_res = REPO_ROOT / "apps" / "pi_frame" / "windows" / "runner" / "resources"
    win_res.mkdir(parents=True, exist_ok=True)
    create_ico(DARK_PNG_SRC, win_res / "app_icon.ico")

    # 3. macOS AppIcon.appiconset
    mac_icons = REPO_ROOT / "apps" / "pi_frame" / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    mac_icons.mkdir(parents=True, exist_ok=True)
    mac_sizes = [16, 32, 64, 128, 256, 512, 1024]
    for s in mac_sizes:
        resized = dark_img.resize((s, s), Image.Resampling.LANCZOS)
        resized.save(mac_icons / f"app_icon_{s}.png", format="PNG")
        print(f"Saved macOS icon: app_icon_{s}.png")

    # 4. Web Icons & Favicon
    web_dir = REPO_ROOT / "apps" / "pi_frame" / "web"
    web_icons_dir = web_dir / "icons"
    web_icons_dir.mkdir(parents=True, exist_ok=True)

    favicon = dark_img.resize((32, 32), Image.Resampling.LANCZOS)
    favicon.save(web_dir / "favicon.png", format="PNG")

    for s in [192, 512]:
        pwa_icon = dark_img.resize((s, s), Image.Resampling.LANCZOS)
        pwa_icon.save(web_icons_dir / f"Icon-{s}.png", format="PNG")
        pwa_icon.save(web_icons_dir / f"Icon-maskable-{s}.png", format="PNG")
        print(f"Saved Web PWA icon: Icon-{s}.png & maskable")

    # 5. Flutter App Branding Assets
    branding_dir = REPO_ROOT / "apps" / "pi_frame" / "assets" / "branding"
    branding_dir.mkdir(parents=True, exist_ok=True)
    make_svg_from_png(DARK_PNG_SRC, branding_dir / "app_icon_dark.svg")
    make_svg_from_png(LIGHT_PNG_SRC, branding_dir / "app_icon_light.svg")
    shutil.copy2(DARK_PNG_SRC, branding_dir / "app_icon_dark_1024.png")
    shutil.copy2(LIGHT_PNG_SRC, branding_dir / "app_icon_light_1024.png")

    dark_512 = dark_img.resize((512, 512), Image.Resampling.LANCZOS)
    dark_512.save(branding_dir / "app_icon_dark_512.png", format="PNG")

    light_512 = light_img.resize((512, 512), Image.Resampling.LANCZOS)
    light_512.save(branding_dir / "app_icon_light_512.png", format="PNG")

    # 6. Documentation Evidence Icons
    docs_icons = REPO_ROOT / "docs" / "design-evidence" / "icons"
    docs_icons.mkdir(parents=True, exist_ok=True)
    shutil.copy2(DARK_PNG_SRC, docs_icons / "piframe-dark-1024.png")
    shutil.copy2(LIGHT_PNG_SRC, docs_icons / "piframe-light-1024.png")
    make_svg_from_png(DARK_PNG_SRC, docs_icons / "piframe-dark.svg")
    make_svg_from_png(LIGHT_PNG_SRC, docs_icons / "piframe-light.svg")
    # Also save concept
    light_img.convert("RGB").save(docs_icons / "piframe-concept.jpg", "JPEG")

    print("\nAll PiFrame production icon assets successfully generated across all platforms!")

if __name__ == "__main__":
    main()
