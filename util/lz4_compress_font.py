#!/usr/bin/env python3
"""Convert uncompressed lv_font_conv output to EdgeTX etxLz4Font .c files."""

from __future__ import annotations

import argparse
import re
import struct
import sys
from pathlib import Path

try:
    import lz4.block
except ImportError:
    print("pip install lz4", file=sys.stderr)
    raise

# LVGL 8.x sizes with LV_FONT_FMT_TXT_LARGE=1 on 64-bit (matches lz4_font.cpp host build).
LV_FONT_T_SIZE = 48
LV_FONT_FMT_TXT_DSC_T_SIZE = 56
LV_FONT_FMT_TXT_GLYPH_CACHE_T_SIZE = 16
LV_FONT_FMT_TXT_CMAP_T_SIZE = 40
LV_FONT_FMT_TXT_KERN_CLASSES_T_SIZE = 32

CMAP_TYPE = {
    "LV_FONT_FMT_TXT_CMAP_FORMAT0_FULL": 0,
    "LV_FONT_FMT_TXT_CMAP_SPARSE_FULL": 1,
    "LV_FONT_FMT_TXT_CMAP_FORMAT0_TINY": 2,
    "LV_FONT_FMT_TXT_CMAP_SPARSE_TINY": 3,
}

GLYPH_DSC_RE = re.compile(
    r"\{\.bitmap_index\s*=\s*(\d+),\s*\.adv_w\s*=\s*(\d+),\s*"
    r"\.box_w\s*=\s*(\d+),\s*\.box_h\s*=\s*(\d+),\s*"
    r"\.ofs_x\s*=\s*(-?\d+),\s*\.ofs_y\s*=\s*(-?\d+)\}"
)

CMAP_RE = re.compile(
    r"\{\s*\.range_start\s*=\s*(\d+),\s*\.range_length\s*=\s*(\d+),\s*"
    r"\.glyph_id_start\s*=\s*(\d+),\s*"
    r"\.unicode_list\s*=\s*(NULL|\w+),\s*\.glyph_id_ofs_list\s*=\s*(NULL|\w+),\s*"
    r"\.list_length\s*=\s*(\d+),\s*\.type\s*=\s*(\w+)"
)

def parse_hex_array(body: str) -> bytes:
    vals = []
    for tok in re.findall(r"0x[0-9a-fA-F]+|-?\d+", body):
        if tok.startswith("0x"):
            vals.append(int(tok, 16) & 0xFF)
        else:
            vals.append(int(tok) & 0xFF)
    return bytes(vals)


def parse_uint16_array(body: str) -> list[int]:
    vals = []
    for tok in re.findall(r"0x[0-9a-fA-F]+|\d+", body):
        vals.append(int(tok, 16) if tok.startswith("0x") else int(tok))
    return vals


def parse_int8_array(body: str) -> bytes:
    vals = []
    for tok in re.findall(r"-?\d+", body):
        vals.append(int(tok) & 0xFF)
    return bytes(vals)


def extract_braced_body(text: str, start: int) -> tuple[str, int]:
    """Return body inside {...} starting at text[start] == '{'."""
    assert text[start] == "{"
    depth = 0
    i = start
    while i < len(text):
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1 : i], i + 1
        i += 1
    raise ValueError("unterminated array")


def parse_named_arrays(text: str) -> dict[str, bytes | list[int]]:
    out: dict[str, bytes | list[int]] = {}
    for kind, pattern, parser in (
        ("u8", r"static\s+(?:LV_ATTRIBUTE_LARGE_CONST\s+)?const\s+uint8_t\s+(\w+)\[\]\s*=\s*\{", parse_hex_array),
        ("u16", r"static\s+const\s+uint16_t\s+(\w+)\[\]\s*=\s*\{", parse_uint16_array),
        ("i8", r"static\s+const\s+int8_t\s+(\w+)\[\]\s*=\s*\{", parse_int8_array),
    ):
        for m in re.finditer(pattern, text):
            body, _ = extract_braced_body(text, m.end() - 1)
            out[m.group(1)] = parser(body)
    return out


def parse_int_field(text: str, name: str, default: int = 0) -> int:
    m = re.search(rf"\.{name}\s*=\s*(\d+)", text)
    return int(m.group(1)) if m else default


def parse_font_fields(text: str) -> dict:
    font_m = re.search(
        r"const lv_font_t\s+(\w+)\s*=\s*\{[^}]*\.line_height\s*=\s*(\d+),[^}]*"
        r"\.base_line\s*=\s*(\d+),[^}]*\.subpx\s*=\s*(\w+),[^}]*"
        r"\.underline_position\s*=\s*(-?\d+),[^}]*\.underline_thickness\s*=\s*(-?\d+)",
        text,
        re.DOTALL,
    )
    if not font_m:
        raise ValueError("lv_font_t block not found")
    subpx = 0 if "NONE" in font_m.group(4) else 0
    return {
        "symbol": font_m.group(1),
        "line_height": int(font_m.group(2)),
        "base_line": int(font_m.group(3)),
        "subpx": subpx,
        "underline_position": int(font_m.group(5)),
        "underline_thickness": int(font_m.group(6)),
        "kern_scale": parse_int_field(text, "kern_scale"),
        "cmap_num": parse_int_field(text, "cmap_num"),
        "bpp": parse_int_field(text, "bpp"),
        "kern_classes": parse_int_field(text, "kern_classes"),
        "bitmap_format": parse_int_field(text, "bitmap_format"),
        "left_class_cnt": parse_int_field(text, "left_class_cnt"),
        "right_class_cnt": parse_int_field(text, "right_class_cnt"),
    }


def pack_glyph_dsc(entries: list[tuple[int, ...]]) -> bytes:
    blob = bytearray()
    for bitmap_index, adv_w, box_w, box_h, ofs_x, ofs_y in entries:
        blob.extend(struct.pack("<IIHHhh", bitmap_index, adv_w, box_w, box_h, ofs_x, ofs_y))
    return bytes(blob)


def lvgl_font_buf_size(uncomp_size: int, cmap_num: int, kern_classes: int) -> int:
    size = uncomp_size + LV_FONT_T_SIZE + LV_FONT_FMT_TXT_DSC_T_SIZE + LV_FONT_FMT_TXT_GLYPH_CACHE_T_SIZE
    size += cmap_num * LV_FONT_FMT_TXT_CMAP_T_SIZE
    if kern_classes:
        size += LV_FONT_FMT_TXT_KERN_CLASSES_T_SIZE
    return size


def compress_lvgl_font_c(text: str) -> tuple[str, dict]:
    arrays = parse_named_arrays(text)
    if "glyph_bitmap" not in arrays or "glyph_dsc" not in text:
        raise ValueError("not an uncompressed lvgl font .c file")

    fields = parse_font_fields(text)
    glyph_entries = [tuple(map(int, m.groups())) for m in GLYPH_DSC_RE.finditer(text)]
    if not glyph_entries:
        raise ValueError("glyph_dsc empty")

    cmaps_raw = []
    for m in CMAP_RE.finditer(text):
        cmaps_raw.append(
            {
                "range_start": int(m.group(1)),
                "range_length": int(m.group(2)),
                "glyph_id_start": int(m.group(3)),
                "unicode_list": None if m.group(4) == "NULL" else m.group(4),
                "glyph_id_ofs_list": None if m.group(5) == "NULL" else m.group(5),
                "list_length": int(m.group(6)),
                "type": CMAP_TYPE.get(m.group(7), 0),
            }
        )

    uncomp = bytearray()
    uncomp.extend(pack_glyph_dsc(glyph_entries))

    etx_cmaps = []
    for cmap in cmaps_raw:
        entry = dict(cmap)
        entry["unicode_list_off"] = 0
        entry["glyph_id_ofs_list_off"] = 0
        if cmap["unicode_list"]:
            data = arrays.get(cmap["unicode_list"])
            if not isinstance(data, list):
                raise ValueError(f"missing unicode list {cmap['unicode_list']}")
            entry["unicode_list_off"] = len(uncomp)
            uncomp.extend(struct.pack(f"<{len(data)}H", *data))
        if cmap["glyph_id_ofs_list"]:
            data = arrays.get(cmap["glyph_id_ofs_list"])
            if not isinstance(data, (bytes, list)):
                raise ValueError(f"missing glyph_id_ofs_list {cmap['glyph_id_ofs_list']}")
            if isinstance(data, list):
                data = bytes(data)
            entry["glyph_id_ofs_list_off"] = len(uncomp)
            uncomp.extend(data)
        etx_cmaps.append(entry)

    glyph_bitmap = arrays["glyph_bitmap"]
    if not isinstance(glyph_bitmap, bytes):
        raise ValueError("glyph_bitmap missing")
    glyph_bitmap_off = len(uncomp)
    uncomp.extend(glyph_bitmap)

    class_pair_values = left_class_mapping = right_class_mapping = 0
    if fields["kern_classes"]:
        for key, attr in (
            ("kern_class_values", "class_pair_values"),
            ("kern_left_class_mapping", "left_class_mapping"),
            ("kern_right_class_mapping", "right_class_mapping"),
        ):
            data = arrays.get(key)
            if not isinstance(data, bytes):
                raise ValueError(f"missing {key}")
            off = len(uncomp)
            uncomp.extend(data)
            if attr == "class_pair_values":
                class_pair_values = off
            elif attr == "left_class_mapping":
                left_class_mapping = off
            else:
                right_class_mapping = off

    uncomp_bytes = bytes(uncomp)
    compressed = lz4.block.compress(uncomp_bytes, mode="high_compression", compression=12)

    meta = {
        **fields,
        "uncomp_size": len(uncomp_bytes),
        "comp_size": len(compressed),
        "glyph_bitmap_off": glyph_bitmap_off,
        "class_pair_values": class_pair_values,
        "left_class_mapping": left_class_mapping,
        "right_class_mapping": right_class_mapping,
        "cmaps": etx_cmaps,
        "compressed": compressed,
        "lvglFontBufSize": lvgl_font_buf_size(
            len(uncomp_bytes), fields["cmap_num"], fields["kern_classes"]
        ),
    }
    return meta["symbol"], meta


def write_etx_font(path: Path, symbol: str, meta: dict) -> None:
  lines = [
      '#include "definitions.h"',
      '#include "lz4_fonts.h"',
      "",
      "static const uint8_t lz4FontData[] __FLASH = {",
  ]
  comp = meta["compressed"]
  row = []
  for i, b in enumerate(comp):
      row.append(f"0x{b:02x}")
      if len(row) == 16:
          lines.append(",".join(row) + ",")
          row = []
  if row:
      lines.append(",".join(row) + ",")
  lines.append("};")
  lines.append("")

  if meta["cmaps"]:
      lines.append("static const etxFontCmap cmaps[] __FLASH = {")
      for c in meta["cmaps"]:
          lines.append(
              "{ .range_start = %(range_start)d, .range_length = %(range_length)d, "
              ".glyph_id_start = %(glyph_id_start)d, .list_length = %(list_length)d, "
              ".type = %(type)d, .unicode_list = %(unicode_list_off)d, "
              ".glyph_id_ofs_list = %(glyph_id_ofs_list_off)d }," % c
          )
      lines.append("};")
      lines.append("")

  lines.append(f"const etxLz4Font {symbol} __FLASH = {{")
  lines.append(f".uncomp_size = {meta['uncomp_size']},")
  lines.append(f".comp_size = {meta['comp_size']},")
  lines.append(f".line_height = {meta['line_height']},")
  lines.append(f".base_line = {meta['base_line']},")
  lines.append(f".subpx = {meta['subpx']},")
  lines.append(f".underline_position = {meta['underline_position']},")
  lines.append(f".underline_thickness = {meta['underline_thickness']},")
  lines.append(f".kern_scale = {meta['kern_scale']},")
  lines.append(f".cmap_num = {meta['cmap_num']},")
  lines.append(f".bpp = {meta['bpp']},")
  lines.append(f".kern_classes = {meta['kern_classes']},")
  lines.append(f".bitmap_format = {meta['bitmap_format']},")
  lines.append(f".left_class_cnt = {meta['left_class_cnt']},")
  lines.append(f".right_class_cnt = {meta['right_class_cnt']},")
  lines.append(f".glyph_bitmap = {meta['glyph_bitmap_off']},")
  lines.append(f".class_pair_values = {meta['class_pair_values']},")
  lines.append(f".left_class_mapping = {meta['left_class_mapping']},")
  lines.append(f".right_class_mapping = {meta['right_class_mapping']},")
  lines.append(".cmaps = cmaps," if meta["cmaps"] else ".cmaps = nullptr,")
  lines.append(".compressed = lz4FontData,")
  lines.append(f".lvglFontBufSize = {meta['lvglFontBufSize']},")
  lines.append("};")
  lines.append("")
  path.write_text("\n".join(lines), encoding="utf-8")


def should_compress(path: Path) -> bool:
    name = path.name
    if name == "lv_font_bl.c":
        return False
    if name.endswith("_STD.c") and not name.endswith("_bold_STD.c"):
        return False
    return True


def convert_file(path: Path) -> None:
    text = path.read_text(encoding="utf-8", errors="replace")
    if "const etxLz4Font" in text:
        print(f"skip (already lz4): {path.name}")
        return
    if "const lv_font_t" not in text:
        print(f"skip (unknown): {path.name}")
        return
    symbol, meta = compress_lvgl_font_c(text)
    write_etx_font(path, symbol, meta)
    print(f"compressed {path.name}: {meta['uncomp_size']} -> {meta['comp_size']} bytes")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path, help="font .c file or directory")
    args = parser.parse_args()
    path = args.path
    if path.is_dir():
        for f in sorted(path.glob("lv_font_*.c")):
            if should_compress(f):
                convert_file(f)
    else:
        convert_file(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
