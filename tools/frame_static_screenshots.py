from PIL import Image
import os
from compile_recordly_gifs import make_recordly_frame

static_features = [
    ("website/assets/img/ui/feature-02-composer-pickers.png", "website/assets/img/ui/feature-02-composer-pickers.png"),
    ("website/assets/img/ui/feature-03-workarea-context-limits.png", "website/assets/img/ui/feature-03-workarea-context-limits.png"),
    ("website/assets/img/ui/feature-12-in-app-update-flow.png", "website/assets/img/ui/feature-12-in-app-update-flow.png"),
    ("website/assets/img/ui/feature-13-theme-editor.png", "website/assets/img/ui/feature-13-theme-editor.png"),
    ("website/assets/img/ui/feature-14-tailscale-remote-phone.png", "website/assets/img/ui/feature-14-tailscale-remote-phone.png"),
    ("website/assets/img/ui/feature-15-pi-cli-settings-update.png", "website/assets/img/ui/feature-15-pi-cli-settings-update.png"),
    ("website/assets/img/ui/feature-16-mcp-servers-toggle.png", "website/assets/img/ui/feature-16-mcp-servers-toggle.png"),
    ("website/assets/img/ui/feature-17-packages-version-pinning.png", "website/assets/img/ui/feature-17-packages-version-pinning.png"),
    ("website/assets/img/ui/feature-19-markdown-file-preview.png", "website/assets/img/ui/feature-19-markdown-file-preview.png"),
]

for src, dst in static_features:
    if os.path.exists(src):
        img = Image.open(src)
        framed = make_recordly_frame(img, canvas_w=960, canvas_h=580)
        framed.convert("RGB").save(dst, "PNG", optimize=True)
        print("Framed:", dst)

print("All static screenshots framed successfully!")
