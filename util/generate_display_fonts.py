#!/usr/bin/env python3
"""Generate LVGL fonts for EDGE_TX_DISPLAY — outputs under radio/src/targets/android/generated/fonts/."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

from edge_tx_display_scale import font_dir_name, font_sizes

ANDROID_ROOT = Path(__file__).resolve().parent.parent
RADIO_SRC = ANDROID_ROOT.parent.parent
LVGL = RADIO_SRC / "fonts" / "lvgl"
GENERATED_FONTS = ANDROID_ROOT / "generated" / "fonts" / "lvgl"
TOOL_BUILD = ANDROID_ROOT / ".tools" / "font-tools" / "build"
TRANSLATIONS = RADIO_SRC / "translations" / "i18n"
THIRDPARTY = RADIO_SRC / "thirdparty"
LZ4_FONT_CPP = LVGL / "lz4_font.cpp"

SYMBOLS_FONT_REL = "../../thirdparty/lvgl/scripts/built_in_font/FontAwesome5-Solid+Brands+Regular.woff"
SYMBOLS = (
    "61441,61448,61451,61452,61453,61457,61459,61461,61465,61468,61473,61478,61479,61480,"
    "61502,61507,61512,61515,61516,61517,61521,61522,61523,61524,61543,61544,61550,61552,"
    "61553,61556,61559,61560,61561,61563,61587,61589,61636,61637,61639,61641,61664,61671,"
    "61674,61683,61724,61732,61787,61931,62016,62017,62018,62019,62020,62087,62099,62212,"
    "62189,62810,63426,63650"
)
EXTRA_FONT = "EdgeTX/extra.ttf"
EXTRA_SYM = "0x88-0x96"
ARROWS_FONT = "EdgeTX/OpenArrow-Regular.woff"
ARROWS = "0x21E8=>0x80,0x21E6=>0x81,0x21E7=>0x82,0x21E9=>0x83"
LATIN_FONT = "Roboto/Roboto-Regular.ttf"
LATIN_FONT_BOLD = "Roboto/Roboto-Bold.ttf"
ASCII = "0x20-0x7F"
DEGREE = "0xB0"
BULLET = "0x2022"
LATIN1 = "0xC0-0xFF,0x100-0x17F"
COMPARE = "0x2265"
BL_SYMBOLS = "61671,63650,63426,61453,61787,61452,61931,62087"
EN_RANGES = f"{ASCII},{DEGREE},{BULLET},{COMPARE},{LATIN1}"
EN_BOLD_RANGES = f"{ASCII},{DEGREE},{BULLET},{COMPARE},{LATIN1}"


def find_lv_font_conv(_repo: Path) -> list[str]:
    tools = ANDROID_ROOT / ".tools"
    node = tools / "node-portable" / "node.exe"
    js = tools / "font-tools" / "node_modules" / "lv_font_conv" / "lv_font_conv.js"
    if node.is_file() and js.is_file():
        return [str(node), str(js)]
    for name in ("lv_font_conv.cmd", "lv_font_conv", "lv_font_conv.exe"):
        p = tools / "font-tools" / "node_modules" / ".bin" / name
        if p.is_file():
            return [str(p)]
    found = shutil.which("lv_font_conv")
    if found:
        return [found]
    raise RuntimeError("lv_font_conv not found; run radio/src/targets/android/scripts/ensure-font-tools.ps1")


def find_zig(_repo: Path) -> Path:
    zig = ANDROID_ROOT / ".tools" / "zig" / "zig.exe"
    if zig.is_file():
        return zig
    raise RuntimeError("zig not found; expected radio/src/targets/android/.tools/zig/zig.exe")


def build_lz4_tool(repo: Path, no_kern: bool = False) -> Path:
    """Build lz4_font host tool; artifacts stay under Android/.tools/."""
    zig = find_zig(repo)
    TOOL_BUILD.mkdir(parents=True, exist_ok=True)
    suffix = "_nokern" if no_kern else ""
    exe = TOOL_BUILD / f"lz4_font{suffix}.exe"
    lz4_o = TOOL_BUILD / f"lz4{suffix}.o"
    lz4hc_o = TOOL_BUILD / f"lz4hc{suffix}.o"
    font_o = TOOL_BUILD / f"lz4_font{suffix}.o"
    flags = ["-DLV_FONT_FMT_TXT_LARGE=1"]
    if no_kern:
        flags.append("-DNO_KERN")
    subprocess.run(
        [str(zig), "cc", "-O2", f"-I{THIRDPARTY}", str(THIRDPARTY / "lz4" / "lz4.c"), "-c", "-o", str(lz4_o)],
        check=True,
    )
    subprocess.run(
        [str(zig), "cc", "-O2", f"-I{THIRDPARTY}", str(THIRDPARTY / "lz4" / "lz4hc.c"), "-c", "-o", str(lz4hc_o)],
        check=True,
    )
    subprocess.run(
        [
            str(zig), "c++", "-std=c++17", "-O2", f"-I{THIRDPARTY}", *flags,
            str(LZ4_FONT_CPP), "-c", "-o", str(font_o),
        ],
        check=True,
    )
    subprocess.run([str(zig), "c++", str(font_o), str(lz4_o), str(lz4hc_o), "-o", str(exe)], check=True)
    return exe


def compress_font(out_dir: Path, repo: Path, stem: str, no_kern: bool = False) -> None:
    inc_src = LVGL / "lv_font.inc"
    if not inc_src.is_file():
        raise RuntimeError(f"lv_font.inc missing before compressing {stem}")
    shutil.copy2(inc_src, out_dir / "lv_font.inc")
    exe = build_lz4_tool(repo, no_kern=no_kern)
    subprocess.run([str(exe), stem], check=True, cwd=out_dir)
    (out_dir / "lv_font.inc").unlink(missing_ok=True)


def char_range(script: str, header: Path) -> str:
    if not header.is_file():
        return ""
    result = subprocess.run(
        [sys.executable, str(LVGL / script), str(header)],
        capture_output=True,
        text=True,
        cwd=LVGL,
    )
    return result.stdout.strip()


def run_conv(lv_cmd: list[str], args: list[str]) -> None:
    subprocess.run([*lv_cmd, *args], check=True, cwd=LVGL)


def conv_base(bpp: int, size: int) -> list[str]:
    return [
        "--no-prefilter",
        "--bpp",
        str(bpp),
        "--size",
        str(size),
        "--format",
        "lvgl",
        "--force-fast-kern-format",
        "--no-compress",
    ]


def en_latin_extras() -> list[str]:
    return [
        "--font",
        EXTRA_FONT,
        "-r",
        EXTRA_SYM,
        "--font",
        ARROWS_FONT,
        "-r",
        ARROWS,
        "--font",
        SYMBOLS_FONT_REL,
        "-r",
        SYMBOLS,
    ]


def _assert_font_metrics(path: Path, label: str) -> None:
    import re

    text = path.read_text(encoding="utf-8", errors="replace")
    m_lh = re.search(r"\.line_height\s*=\s*(\d+)", text)
    m_bl = re.search(r"\.base_line\s*=\s*(\d+)", text)
    if not m_lh or not m_bl:
        raise RuntimeError(f"{label}: missing line_height/base_line in {path}")
    lh = int(m_lh.group(1))
    bl = int(m_bl.group(1))
    if bl > lh:
        raise RuntimeError(
            f"{label}: invalid metrics line_height={lh} base_line={bl} "
            f"(base_line > line_height usually means uint8 overflow; rebuild lz4_font)"
        )


def generate_english(lv_cmd: list[str], out_dir: Path, sz: dict[str, int], repo: Path) -> None:
    run_conv(
        lv_cmd,
        [
            *conv_base(1, sz["BL"]),
            "--no-compress",
            "--font",
            "../Roboto/Roboto-Regular-BL.ttf",
            "-r",
            ASCII,
            "--font",
            SYMBOLS_FONT_REL,
            "-r",
            BL_SYMBOLS,
            "-o",
            str(out_dir / "lv_font_bl.c"),
        ],
    )

    def en_to_inc(size: int, bold: bool, with_extras: bool) -> None:
        ttf = f"../{LATIN_FONT_BOLD if bold else LATIN_FONT}"
        ranges = EN_BOLD_RANGES if bold else EN_RANGES
        args = [
            *conv_base(4, size),
            "--font",
            ttf,
            "-r",
            ranges,
            "-o",
            "lv_font.inc",
        ]
        if with_extras:
            args.extend(en_latin_extras())
        run_conv(lv_cmd, args)

    def en_direct(size: int, bold: bool, out_name: str, with_extras: bool) -> None:
        ttf = f"../{LATIN_FONT_BOLD if bold else LATIN_FONT}"
        ranges = EN_BOLD_RANGES if bold else EN_RANGES
        args = [
            *conv_base(4, size),
            "--font",
            ttf,
            "-r",
            ranges,
            "-o",
            str(out_dir / f"{out_name}.c"),
        ]
        if with_extras:
            args.extend(en_latin_extras())
        run_conv(lv_cmd, args)

    for size, bold, fname, with_extras in [
        (sz["LXL"], True, "lv_font_en_bold_LXL", False),
        (sz["XXL"], True, "lv_font_en_bold_XXL", False),
        (sz["XXS"], False, "lv_font_en_XXS", True),
        (sz["XS"], False, "lv_font_en_XS", True),
        (sz["STD"], True, "lv_font_en_bold_STD", True),
        (sz["L"], False, "lv_font_en_L", True),
        (sz["XL"], True, "lv_font_en_bold_XL", False),
    ]:
        print(f"  compress {fname} (size={size})")
        en_to_inc(size, bold, with_extras)
        compress_font(out_dir, repo, fname)
        _assert_font_metrics(out_dir / f"{fname}.c", fname)

    print("  lv_font_en_STD (uncompressed)")
    en_direct(sz["STD"], False, "lv_font_en_STD", True)


def generate_lang(
    lv_cmd: list[str],
    out_dir: Path,
    sz: dict[str, int],
    name: str,
    ttf_n: str,
    ttf_b: str,
    chars: str,
    no_kern: bool,
    repo: Path,
) -> None:
    if not chars:
        print(f"Skip {name}")
        return
    print(f"Language {name}")

    for sfx, size in (("XXS", sz["XXS"]), ("XS", sz["XS"]), ("L", sz["L"])):
        fname = f"lv_font_{name}_{sfx}"
        run_conv(
            lv_cmd,
            [
                *conv_base(4, size),
                "--font",
                f"../{ttf_n}",
                "-r",
                chars,
                "-o",
                "lv_font.inc",
            ],
        )
        compress_font(out_dir, repo, fname, no_kern=no_kern)

    run_conv(
        lv_cmd,
        [
            *conv_base(4, sz["STD"]),
            "--font",
            f"../{ttf_n}",
            "-r",
            chars,
            "-o",
            str(out_dir / f"lv_font_{name}_STD.c"),
            "--lv-fallback",
            "lv_font_en_STD",
        ],
    )

    for out_suffix, size, bold_ttf in (
        ("bold_STD", sz["STD"], ttf_b),
        ("bold_XL", sz["XL"], ttf_b),
    ):
        fname = f"lv_font_{name}_{out_suffix}"
        run_conv(
            lv_cmd,
            [
                *conv_base(4, size),
                "--font",
                f"../{bold_ttf}",
                "-r",
                chars,
                "-o",
                "lv_font.inc",
            ],
        )
        compress_font(out_dir, repo, fname, no_kern=no_kern)


def fonts_look_valid(out_dir: Path) -> bool:
    required = (
        "lv_font_en_STD.c",
        "lv_font_en_bold_STD.c",
        "lv_font_en_XS.c",
        "lv_font_bl.c",
    )
    for name in required:
        if not (out_dir / name).is_file():
            return False
    std_text = (out_dir / "lv_font_en_STD.c").read_text(encoding="utf-8", errors="replace")
    bold_text = (out_dir / "lv_font_en_bold_STD.c").read_text(encoding="utf-8", errors="replace")
    xs_text = (out_dir / "lv_font_en_XS.c").read_text(encoding="utf-8", errors="replace")
    bl_text = (out_dir / "lv_font_bl.c").read_text(encoding="utf-8", errors="replace")
    if "lv_font_en_STD" not in std_text:
        return False
    if "lv_font_bl" not in bl_text:
        return False
    if "const etxLz4Font" not in bold_text or "const etxLz4Font" not in xs_text:
        return False
    if ".cmap_num = 6," not in bold_text:
        return False
    if ".cmap_num = 6," not in xs_text:
        return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("lcd_w", type=int)
    parser.add_argument("--lcd-h", type=int, default=None)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    repo = RADIO_SRC.parent.parent
    font_dir = font_dir_name(args.lcd_w, args.lcd_h)
    out_dir = GENERATED_FONTS / font_dir
    out_std = out_dir / "lv_font_en_STD.c"
    sz = font_sizes(args.lcd_w, args.lcd_h)

    if out_std.is_file() and not args.force:
        count = len(list(out_dir.glob("lv_font_*.c")))
        if count >= 40 and fonts_look_valid(out_dir):
            print(f"Fonts present: {out_dir} ({count} files, STD={sz['STD']}px)")
            return 0
        if count >= 40:
            print(f"Regenerating {out_dir}: fonts missing LZ4 compression")

    out_dir.mkdir(parents=True, exist_ok=True)
    lv_cmd = find_lv_font_conv(repo)
    print(f"Generating {font_dir} -> {out_dir} (STD={sz['STD']}px)")

    generate_english(lv_cmd, out_dir, sz, repo)

    langs = [
        ("tw", "Noto/NotoSansCJKsc-Regular.otf", "Noto/NotoSansCJKsc-Bold.otf", "get_char_ck.py", "tw.h", True),
        ("cn", "Noto/NotoSansCJKsc-Regular.otf", "Noto/NotoSansCJKsc-Bold.otf", "get_char_ck.py", "cn.h", True),
        ("jp", "Noto/NotoSansCJKsc-Regular.otf", "Noto/NotoSansCJKsc-Bold.otf", "get_char_jp.py", "jp.h", False),
        ("he", "Arimo/Arimo-Regular.ttf", "Arimo/Arimo-Bold.ttf", "get_char_he.py", "he.h", True),
        ("ru", "Arimo/Arimo-Regular.ttf", "Arimo/Arimo-Bold.ttf", "get_char_cyrillic.py", "ru.h", False),
        ("ua", "Arimo/Arimo-Regular.ttf", "Arimo/Arimo-Bold.ttf", "get_char_cyrillic.py", "ua.h", False),
        ("ko", "Nanum/NanumBarunpenR.ttf", "Nanum/NanumBarunpenB.ttf", "get_char_ko.py", "ko.h", True),
    ]
    for lang_args in langs:
        chars = char_range(lang_args[3], TRANSLATIONS / lang_args[4])
        generate_lang(lv_cmd, out_dir, sz, *lang_args[:3], chars, lang_args[5], repo)

    inc = LVGL / "lv_font.inc"
    if inc.exists():
        inc.unlink()
    print(f"Done: {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
