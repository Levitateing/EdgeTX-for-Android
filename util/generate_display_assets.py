#!/usr/bin/env python3
"""
Generate COLORLCD bitmap PNGs for compile-time EDGE_TX_DISPLAY.

All outputs stay under radio/src/targets/android/generated/bitmaps/.
Upstream radio/src/bitmaps/img-src (SVG) and 800x480 stock PNGs are read-only.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("generate_display_assets: Pillow required (pip install pillow)", file=sys.stderr)
    sys.exit(1)

from edge_tx_display_scale import bitmap_scale_factor

BITMAP_CMAKE = """
set(BITMAP_SIZE_ARGS --size-format 2)
set(BITMAP_LZ4_ARGS ${{BITMAP_SIZE_ARGS}} --lz4)
set(MASK_LZ4_ARGS ${{BITMAP_SIZE_ARGS}} --lz4)

set(_EDGE_TX_ANDROID_BM_DIR "${{CMAKE_SOURCE_DIR}}/radio/src/targets/android/generated/bitmaps/{rel}")

add_bitmaps_target(bm_{w}_{h}_bmps "${{_EDGE_TX_ANDROID_BM_DIR}}/bmp_*.png" "4/4/4/4" "${{BITMAP_LZ4_ARGS}}")
add_bitmaps_target(bm_{w}_{h}_masks "${{_EDGE_TX_ANDROID_BM_DIR}}/mask_*.png" 8bits "${{MASK_LZ4_ARGS}}")

add_custom_target(bm_{w}_{h}_bitmaps)

add_dependencies(bm_{w}_{h}_bitmaps
  bm_{w}_{h}_bmps
  bm_{w}_{h}_masks
  )
"""


def layout_paths() -> tuple[Path, Path, Path, Path, Path, Path]:
    util_dir = Path(__file__).resolve().parent
    android_root = util_dir.parent
    repo = android_root.parent.parent.parent.parent
    generated_bitmaps = android_root / "generated" / "bitmaps"
    ref_bitmaps = repo / "radio" / "src" / "bitmaps"
    hw_defs = (
        android_root / "firmware" / "patches" / "radio" / "src" / "boards" / "hw_defs"
    )
    convert_gfx = repo / "tools" / "convert-gfx.py"
    return repo, android_root, generated_bitmaps, ref_bitmaps, hw_defs, convert_gfx


def find_resvg(android_root: Path) -> str | None:
    for candidate in [
        shutil.which("resvg"),
        Path(os.environ.get("EDGE_TX_RESVG", "")),
        android_root / ".tools" / "resvg" / "resvg.exe",
    ]:
        if candidate and Path(candidate).is_file():
            return str(candidate)
    return None


def write_bitmap_cmake(out_dir: Path, rel: str, lcd_w: int, lcd_h: int) -> None:
    text = BITMAP_CMAKE.format(w=lcd_w, h=lcd_h, rel=rel.replace("\\", "/"))
    (out_dir / "CMakeLists.txt").write_text(text, encoding="utf-8")


def patch_hw_json(base: Path, out: Path, lcd_w: int, lcd_h: int) -> None:
    with open(base, encoding="utf-8") as f:
        data = json.load(f)
    display = data.setdefault("display", {})
    display["lcd_w"] = lcd_w
    display["lcd_h"] = lcd_h
    display["lcd_phys_w"] = lcd_w
    display["lcd_phys_h"] = lcd_h
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def parse_resolution(text: str) -> tuple[int, int]:
    m = re.fullmatch(r"(\d+)x(\d+)", text.strip())
    if not m:
        raise ValueError(f"invalid resolution '{text}'")
    w, h = int(m.group(1)), int(m.group(2))
    if w < 320 or h < 240 or w > 3840 or h > 2160:
        raise ValueError(f"resolution {w}x{h} out of range")
    if w <= h:
        raise ValueError("landscape width must exceed height")
    return w, h


def run_convert_gfx(
    repo: Path,
    convert_gfx: Path,
    resolution: str,
    resvg: str,
    spill_dir: Path,
    util_dir: Path,
) -> bool:
    env = os.environ.copy()
    resvg_dir = str(Path(resvg).parent)
    env["PATH"] = resvg_dir + os.pathsep + env.get("PATH", "")
    env["PYTHONPATH"] = str(util_dir) + os.pathsep + env.get("PYTHONPATH", "")
    env.setdefault("PYTHONIOENCODING", "utf-8")
    env.setdefault("PYTHONUTF8", "1")
    cmd = [sys.executable, str(convert_gfx), "make", resolution, "--resvg"]
    print("Running:", " ".join(cmd))
    subprocess.run(cmd, cwd=repo, env=env)
    probe = spill_dir / "mask_icon_edgetx.png"
    return probe.is_file()


def move_spill_to_generated(spill_dir: Path, out_dir: Path) -> None:
    """If convert-gfx wrote into upstream radio/src/bitmaps, relocate into Android/generated."""
    if not spill_dir.is_dir():
        return
    if spill_dir.resolve() == out_dir.resolve():
        return
    out_dir.parent.mkdir(parents=True, exist_ok=True)
    if out_dir.exists():
        shutil.rmtree(out_dir)
    shutil.move(str(spill_dir), str(out_dir))
    print(f"Moved bitmaps -> {out_dir}")


def fix_shutdown_masks_from_stock(repo: Path, out_dir: Path, lcd_h: int) -> None:
    """resvg mishandles mix-blend-mode in shutdown circle SVGs (opaque squares).
    Rebuild those masks by scaling known-good 800x480 PNGs."""
    stock = repo / "radio" / "src" / "bitmaps" / "800x480"
    if not stock.is_dir():
        return
    # 800x480 circle is 103px; target matches LAYOUT_SCALE(75) @ this LCD_H
    circle = max(1, (103 * lcd_h + 240) // 480)
    mapping = [
        ("mask_info_shutdown_circle0.png", circle, circle),
        ("mask_info_shutdown_circle1.png", circle, circle),
        ("mask_info_shutdown_circle2.png", circle, circle),
        ("mask_info_shutdown_circle3.png", circle, circle),
        ("mask_info_shutdown.png", None, None),
    ]
    for name, tw, th in mapping:
        src = stock / name
        if not src.is_file():
            continue
        im = Image.open(src).convert("RGB")
        if tw is None:
            tw = max(1, (im.width * lcd_h + 240) // 480)
            th = max(1, (im.height * lcd_h + 240) // 480)
        out = im.resize((tw, th), Image.Resampling.LANCZOS)
        out.save(out_dir / name)
        print(f"  fixed shutdown mask {name} -> {out.size}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("resolution", nargs="?")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--hw-json-out", type=Path)
    parser.add_argument("--base-hw-json", default="android.json")
    args = parser.parse_args()

    if not args.resolution:
        parser.error("resolution required e.g. 2400x1440")
    lcd_w, lcd_h = parse_resolution(args.resolution)
    if lcd_w == 800 and lcd_h == 480:
        print("800x480 uses stock upstream colorlcd assets")
        return 0

    repo, android_root, generated_root, ref_bitmaps, hw_defs_dir, convert_gfx = layout_paths()
    res_name = f"{lcd_w}x{lcd_h}"
    out_dir = generated_root / res_name
    spill_dir = ref_bitmaps / res_name
    rel = res_name
    probe = out_dir / "mask_icon_edgetx.png"

    if probe.is_file() and not args.force:
        print(f"Bitmaps present: {out_dir}")
    else:
        resvg = find_resvg(android_root)
        if not resvg:
            print("generate_display_assets: resvg not found (run ensure-resvg.ps1)", file=sys.stderr)
            return 1
        if not convert_gfx.is_file():
            print(f"generate_display_assets: missing {convert_gfx}", file=sys.stderr)
            return 1
        ok = run_convert_gfx(
            repo, convert_gfx, res_name, resvg, spill_dir, util_dir=Path(__file__).resolve().parent
        )
        if ok:
            move_spill_to_generated(spill_dir, out_dir)
        if not probe.is_file():
            print(
                "generate_display_assets: convert-gfx failed; "
                "800x480 stock assets and img-src SVGs are required upstream",
                file=sys.stderr,
            )
            return 1

    fix_shutdown_masks_from_stock(repo, out_dir, lcd_h)

    write_bitmap_cmake(out_dir, rel, lcd_w, lcd_h)

    if args.hw_json_out:
        base_json = hw_defs_dir / args.base_hw_json
        if not base_json.is_file():
            base_json = hw_defs_dir / "android.json"
        patch_hw_json(base_json, args.hw_json_out, lcd_w, lcd_h)
        print(f"Patched hw json -> {args.hw_json_out}")

    if probe.is_file():
        with Image.open(probe) as im:
            print(f"mask_icon_edgetx: {im.size} scale={bitmap_scale_factor(lcd_w, lcd_h):.4f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
