"""LAYOUT_SCALE / convert-gfx bitmap scale factors (480x272 design baseline = 1.0)."""

from __future__ import annotations

# Base colorlcd reference: 800x480 landscape, bitmap/LAYOUT scale 1.375 at that size.
_TX16_REF_W = 800
_TX16_REF_H = 480
_TX16_REF_SCALE = 1.375

# Stock radio tiers (match etx_lv_theme.h / upstream BITMAPS_DIR).
_STOCK_SCALES: dict[str, float] = {
    "320x240": 0.8,
    "480x272": 1.0,
    "800x480": 1.375,
}

_STD_FONT_PX: dict[str, int] = {
    "XXS": 9,
    "XS": 13,
    "STD": 16,
    "L": 24,
    "XL": 32,
    "LXL": 48,
    "XXL": 64,
    "BL": 16,
}


def _infer_height(lcd_w: int) -> int:
    return max(240, round(lcd_w * _TX16_REF_H / _TX16_REF_W))


def bitmap_scale_factor(lcd_w: int, lcd_h: int | None = None) -> float:
    """UI/bitmap scale for compile-time EDGE_TX_DISPLAY.

    Landscape COLORLCD uses **height** so the same vertical resolution (e.g. 1440)
    yields the same on-screen icon and font size; extra width is letterbox / layout only.
    """
    if lcd_h is None:
        lcd_h = _infer_height(lcd_w)

    key = f"{lcd_w}x{lcd_h}"
    if key in _STOCK_SCALES:
        return _STOCK_SCALES[key]

    # Height-based density (same H => same on-screen UI size)
    if lcd_h >= 240 and lcd_w > lcd_h:
        return _TX16_REF_SCALE * lcd_h / _TX16_REF_H

    return 1.0


def layout_scale_px(value: int, lcd_w: int, lcd_h: int | None = None) -> int:
    """Same integer math as LAYOUT_SCALE() in etx_lv_theme.h (must stay in sync)."""
    if lcd_h is None:
        lcd_h = _infer_height(lcd_w)

    key = f"{lcd_w}x{lcd_h}"
    if key == "320x240":
        return (value * 8 + 5) // 10
    if key in _STOCK_SCALES and key != "800x480":
        # 480x272 design baseline: identity
        if key == "480x272":
            return value
        return max(1, round(value * _STOCK_SCALES[key]))

    if lcd_h >= 480 and lcd_w > lcd_h:
        # round(value * 1.375 * H / 480) via integer: (11*value*H + 1920) / 3840
        return (value * 11 * lcd_h + 1920) // (8 * 480)

    return max(1, round(value * bitmap_scale_factor(lcd_w, lcd_h)))


def font_sizes(lcd_w: int, lcd_h: int | None = None) -> dict[str, int]:
    # Keep font px in sync with LAYOUT_SCALE-style rounding (not Python banker's round).
    return {name: max(1, layout_scale_px(px, lcd_w, lcd_h)) for name, px in _STD_FONT_PX.items()}


def font_dir_name(lcd_w: int, lcd_h: int | None = None) -> str:
    """Font directory: stock tiers for official BITMAPS_DIR, else disp{W} (generated)."""
    if lcd_h is None:
        lcd_h = _infer_height(lcd_w)
    if lcd_w <= 320 and lcd_h <= 240:
        return "sml"
    if lcd_w == 480 and lcd_h == 272:
        return "std"
    if lcd_w == 800 and lcd_h == 480:
        return "lrg"
    return f"disp{lcd_w}"


def font_tier(lcd_w: int, lcd_h: int | None = None) -> str:
    return font_dir_name(lcd_w, lcd_h)


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 3:
        print("usage: edge_tx_display_scale.py scale|sizes|font_dir LCD_W [LCD_H]", file=sys.stderr)
        raise SystemExit(1)
    cmd, w = sys.argv[1], int(sys.argv[2])
    h = int(sys.argv[3]) if len(sys.argv) > 3 else None
    if cmd == "scale":
        print(bitmap_scale_factor(w, h))
    elif cmd == "sizes":
        for k, v in font_sizes(w, h).items():
            print(f"{k}={v}")
    elif cmd == "font_dir":
        print(font_dir_name(w, h))
    else:
        raise SystemExit(1)
