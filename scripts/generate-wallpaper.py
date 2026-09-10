"""Center-crop (cover) source wallpaper to compile resolution, save as background_WxH.png."""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image


def cover_crop_resize(img: Image.Image, target_w: int, target_h: int) -> Image.Image:
    src_w, src_h = img.size
    target_ratio = target_w / target_h
    src_ratio = src_w / src_h

    if src_ratio > target_ratio:
        crop_w = int(round(src_h * target_ratio))
        left = (src_w - crop_w) // 2
        box = (left, 0, left + crop_w, src_h)
    else:
        crop_h = int(round(src_w / target_ratio))
        top = (src_h - crop_h) // 2
        box = (0, top, src_w, top + crop_h)

    cropped = img.crop(box)
    return cropped.resize((target_w, target_h), Image.Resampling.LANCZOS)


def main() -> int:
    if len(sys.argv) != 5:
        print(
            "Usage: generate-wallpaper.py <source.png> <theme_dir> <width> <height>",
            file=sys.stderr,
        )
        return 2

    src_path = Path(sys.argv[1])
    theme_dir = Path(sys.argv[2])
    width = int(sys.argv[3])
    height = int(sys.argv[4])

    if not src_path.is_file():
        print(f"Source wallpaper not found: {src_path}", file=sys.stderr)
        return 1

    theme_dir.mkdir(parents=True, exist_ok=True)
    out_path = theme_dir / f"background_{width}x{height}.png"

    with Image.open(src_path) as opened:
        img = opened.convert("RGBA")
        result = cover_crop_resize(img, width, height)
        result.save(out_path, format="PNG", optimize=True)

    print(f"OK: {out_path} ({width}x{height}, from {img.size[0]}x{img.size[1]})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
