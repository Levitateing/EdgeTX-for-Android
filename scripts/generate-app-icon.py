from PIL import Image
from pathlib import Path
import sys

src_path = Path(sys.argv[1])
out_root = Path(sys.argv[2])
src = Image.open(src_path).convert("RGBA")

densities = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}

# Logo margin as fraction of icon size (0 = no margin, logo fills canvas).
LOGO_MARGIN_RATIO = 0

for name, size in densities.items():
    margin = int(size * LOGO_MARGIN_RATIO)
    inner = size - 2 * margin
    thumb = src.copy()
    thumb.thumbnail((inner, inner), Image.Resampling.LANCZOS)
    x = (size - thumb.width) // 2
    y = (size - thumb.height) // 2
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    icon.paste(thumb, (x, y), thumb)
    mipmap_dir = out_root / f"mipmap-{name}"
    mipmap_dir.mkdir(parents=True, exist_ok=True)
    icon.save(mipmap_dir / "ic_launcher.png")
    icon.save(mipmap_dir / "ic_launcher_round.png")

print("OK: launcher icons generated")
