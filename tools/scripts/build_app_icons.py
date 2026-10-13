#!/usr/bin/env python3
"""
Build and package production icons for Pi-Crust across all platforms.
Renders SVG to high-res PNG using Chrome headless, then generates:
- Windows multi-resolution .ico (16, 24, 32, 48, 64, 128, 256)
- macOS AppIcon.appiconset (16, 32, 64, 128, 256, 512, 1024)
- Web favicon and PWA icons (192, 512, maskable)
- Flutter branding assets (SVG, 512, 1024)
- Release assets (SVG, 1024 PNG, ICO)
"""

import os
import subprocess
import shutil
import tempfile
from pathlib import Path
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]
CHROME_PATH = r"C:\Program Files\Google\Chrome\Application\chrome.exe"

DARK_SVG_SRC = REPO_ROOT / "release-assets" / "icons" / "pi-crust-dark.svg"
LIGHT_SVG_SRC = REPO_ROOT / "release-assets" / "icons" / "pi-crust-light.svg"

def render_svg_to_png(svg_path: Path, output_png: Path, size: int = 1024):
    with open(svg_path, "r", encoding="utf-8") as f:
        svg_content = f.read()

    html_content = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
html, body {{
  width: {size}px;
  height: {size}px;
  overflow: hidden;
  background: transparent;
}}
svg {{
  width: {size}px;
  height: {size}px;
  display: block;
}}
</style>
</head>
<body>
{svg_content}
</body>
</html>"""

    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8") as tmp:
        tmp.write(html_content)
        tmp_path = tmp.name

    try:
        cmd = [
            CHROME_PATH,
            "--headless=new",
            "--disable-gpu",
            "--force-device-scale-factor=1",
            f"--window-size={size},{size}",
            "--default-background-color=00000000",
            f"--screenshot={output_png}",
            f"file:///{tmp_path.replace(os.sep, '/')}"
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        print(f"Rendered: {output_png} ({size}x{size})")
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)

def create_ico(source_png: Path, output_ico: Path):
    img = Image.open(source_png).convert("RGBA")
    sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    img.save(output_ico, format="ICO", sizes=sizes)
    print(f"Generated ICO: {output_ico} with sizes {sizes}")

def generate_resized_pngs(source_png: Path, target_dir: Path, name_prefix: str, sizes: list[int]):
    img = Image.open(source_png).convert("RGBA")
    target_dir.mkdir(parents=True, exist_ok=True)
    for s in sizes:
        resized = img.resize((s, s), Image.Resampling.LANCZOS)
        out_path = target_dir / f"{name_prefix}_{s}.png"
        resized.save(out_path, format="PNG")
        print(f"Saved: {out_path} ({s}x{s})")

def main():
    print(f"Building Pi-Crust production icons from:\n  {DARK_SVG_SRC}\n  {LIGHT_SVG_SRC}")
    work_dir = REPO_ROOT / "build" / "icon_staging"
    work_dir.mkdir(parents=True, exist_ok=True)

    dark_1024 = work_dir / "dark_1024.png"
    light_1024 = work_dir / "light_1024.png"

    render_svg_to_png(DARK_SVG_SRC, dark_1024, 1024)
    render_svg_to_png(LIGHT_SVG_SRC, light_1024, 1024)

    # 1. Release Assets
    rel_icons = REPO_ROOT / "release-assets" / "icons"
    rel_icons.mkdir(parents=True, exist_ok=True)
    if DARK_SVG_SRC.resolve() != (rel_icons / "pi-crust-dark.svg").resolve():
        shutil.copy2(DARK_SVG_SRC, rel_icons / "pi-crust-dark.svg")
    if LIGHT_SVG_SRC.resolve() != (rel_icons / "pi-crust-light.svg").resolve():
        shutil.copy2(LIGHT_SVG_SRC, rel_icons / "pi-crust-light.svg")
    shutil.copy2(dark_1024, rel_icons / "pi-crust-dark-1024.png")
    shutil.copy2(light_1024, rel_icons / "pi-crust-light-1024.png")
    create_ico(dark_1024, rel_icons / "pi-crust.ico")

    # 2. Windows Runner Resources
    win_res = REPO_ROOT / "apps" / "pi_crust" / "windows" / "runner" / "resources"
    win_res.mkdir(parents=True, exist_ok=True)
    create_ico(dark_1024, win_res / "app_icon.ico")

    # 3. macOS AppIcon.appiconset
    mac_icons = REPO_ROOT / "apps" / "pi_crust" / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    mac_icons.mkdir(parents=True, exist_ok=True)
    mac_sizes = [16, 32, 64, 128, 256, 512, 1024]
    dark_img = Image.open(dark_1024).convert("RGBA")
    for s in mac_sizes:
        resized = dark_img.resize((s, s), Image.Resampling.LANCZOS)
        resized.save(mac_icons / f"app_icon_{s}.png", format="PNG")
        print(f"Saved macOS icon: app_icon_{s}.png")

    # 4. Web Icons & Favicon
    web_dir = REPO_ROOT / "apps" / "pi_crust" / "web"
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
    branding_dir = REPO_ROOT / "apps" / "pi_crust" / "assets" / "branding"
    branding_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(DARK_SVG_SRC, branding_dir / "app_icon_dark.svg")
    shutil.copy2(LIGHT_SVG_SRC, branding_dir / "app_icon_light.svg")
    shutil.copy2(dark_1024, branding_dir / "app_icon_dark_1024.png")
    shutil.copy2(light_1024, branding_dir / "app_icon_light_1024.png")

    dark_512 = dark_img.resize((512, 512), Image.Resampling.LANCZOS)
    dark_512.save(branding_dir / "app_icon_dark_512.png", format="PNG")

    light_img = Image.open(light_1024).convert("RGBA")
    light_512 = light_img.resize((512, 512), Image.Resampling.LANCZOS)
    # Clean up staging directory
    shutil.rmtree(work_dir, ignore_errors=True)

    print("\nAll production icon assets successfully generated across all platforms!")

if __name__ == "__main__":
    main()
