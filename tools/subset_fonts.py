#!/usr/bin/env python
"""Subset the bundled fonts down to only the glyphs the game uses.

Two families, because one cannot do both jobs:

* **UI / bold** — Noto Sans TC. The interface and all explanatory text are
  Traditional Chinese, and a Japanese face has no 讀/錄/產/擊 at all.
* **display** — Zen Kaku Gothic New Black. 104 kana in heavy weight is the hero
  image of the game, and it wants a strong Japanese gothic.

Scans every ``.gd`` / ``.gdshader`` / ``.tscn`` string literal (comments are
stripped first), unions the result with a safety base set, then writes compact
TTFs into ``assets/fonts``. Reports any glyph a face cannot draw so it can be
swapped for one that can.

Usage::

    python tools/subset_fonts.py            # subset and write
    python tools/subset_fonts.py --check    # only report coverage
"""

from __future__ import annotations

import argparse
import re
import sys
import unicodedata
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "assets" / "fonts"

# Pristine upstream faces live here (downloaded once, kept out of the repo).
CACHE = Path.home() / ".cache" / "kana-run-fonts"

# name -> (source file, instance axis value or None, chars needed)
FACES = {
    "ui": (CACHE / "NotoSansTC-VF.ttf", 400, "all"),
    "bold": (CACHE / "NotoSansTC-VF.ttf", 700, "all"),
    "display": (CACHE / "ZenKakuGothicNew-Black.ttf", None, "kana"),
}

OUTPUTS = {
    "ui": OUT_DIR / "ui.ttf",
    "bold": OUT_DIR / "bold.ttf",
    "display": OUT_DIR / "display.ttf",
}

SCAN_SUFFIXES = {".gd", ".tscn", ".tres", ".gdshader", ".md"}
SKIP_FILES = {"project.godot"}          # config text, never rendered
SKIP_DIRS = {".git", ".godot", "__pycache__", "build", "assets"}

# Always keep in the UI face: printable ASCII, the CJK punctuation we actually
# use, fullwidth latin, and the in-game symbols.
BASE = set(chr(c) for c in range(0x20, 0x7F))
BASE |= set(chr(c) for c in range(0x3041, 0x3095))   # hiragana
BASE |= set(chr(c) for c in range(0x30A1, 0x30FF))   # katakana
BASE |= set("、。「」『』〜・々〆〇ヶ")               # CJK punctuation
BASE |= set(chr(c) for c in range(0xFF01, 0xFF5E))   # fullwidth ASCII
BASE |= set("×÷°…—–¥©®←↑→↓※★☆♪♥◆◇■□●○")

# The display face only ever draws kana and romaji.
KANA_ONLY = set(chr(c) for c in range(0x20, 0x7F))
KANA_ONLY |= set(chr(c) for c in range(0x3041, 0x3095))
KANA_ONLY |= set(chr(c) for c in range(0x30A1, 0x30FF))

# GDScript / GLSL string literal (single, double, or triple quoted).
STRING_RE = re.compile(r'"""(?:.|\n)*?"""|"(?:[^"\\\n]|\\.)*"|\'(?:[^\'\\\n]|\\.)*\'')


def strip_comments(text: str) -> str:
    """Remove ``#`` and ``//`` comments so their glyphs never inflate the subset.

    Walks the text tracking quote state so a ``#`` inside a string survives.
    """
    out: list[str] = []
    in_str: str | None = None
    in_line_comment = False
    in_block_comment = False
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if in_line_comment:
            if ch == "\n":
                in_line_comment = False
                out.append(ch)
        elif in_block_comment:
            if ch == "\n":
                out.append(ch)
            if ch == "*" and nxt == "/":
                in_block_comment = False
                i += 1
        elif in_str is not None:
            out.append(ch)
            if ch == "\\" and in_str != '"""':
                if i + 1 < n:
                    out.append(text[i + 1])
                    i += 1
            elif in_str == '"""' and text[i:i + 3] == '"""':
                out.append(text[i + 1:i + 3])
                i += 2
                in_str = None
            elif in_str != '"""' and ch == in_str:
                in_str = None
        else:
            if ch == "#" or (ch == "/" and nxt == "/"):
                in_line_comment = True
            elif text[i:i + 3] == '"""':
                in_str = '"""'
                out.append('"""')
                i += 2
            elif ch in ('"', "'"):
                in_str = ch
                out.append(ch)
            else:
                out.append(ch)
        i += 1
    return "".join(out)


def collect() -> tuple[set[str], dict[str, list[str]]]:
    """Return (glyph set, glyph -> [file:line]) for in-game string literals."""
    chars: set[str] = set(BASE)
    where: dict[str, list[str]] = {}

    def add(ch: str, loc: str) -> None:
        if ord(ch) <= 0x7E:
            return
        chars.add(ch)
        where.setdefault(ch, [])
        if loc not in where[ch] and len(where[ch]) < 6:
            where[ch].append(loc)

    for path in sorted(ROOT.rglob("*")):
        if not path.is_file() or path.suffix not in SCAN_SUFFIXES:
            continue
        if path.name in SKIP_FILES or path.name == Path(__file__).name:
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        try:
            raw = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        rel = path.relative_to(ROOT).as_posix()
        for lineno, line in enumerate(strip_comments(raw).splitlines(), start=1):
            for match in STRING_RE.finditer(line):
                loc = f"{rel}:{lineno}"
                for ch in match.group(0):
                    add(ch, loc)
    return chars, where


def face_cmap(path: Path) -> set[int]:
    font = TTFont(path, fontNumber=0, lazy=True)
    cmap = set(font.getBestCmap().keys())
    font.close()
    return cmap


def open_face(name: str, weight: int | None) -> TTFont:
    src, wght, _ = FACES[name]
    font = TTFont(src, fontNumber=0)
    if wght is not None and "fvar" in font:
        font = instancer.instantiateVariableFont(font, {"wght": wght}, inplace=True)
    return font


def wanted(name: str, chars: set[str]) -> set[str]:
    _, _, scope = FACES[name]
    if scope == "kana":
        # keep only the kana / latin that actually appears
        keep = set(KANA_ONLY) & chars
        return keep | KANA_ONLY & set("・")
    return chars


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="report only, write nothing")
    args = ap.parse_args()

    missing_sources = [p for _, (p, _, _) in FACES.items() if not p.exists()]
    if missing_sources:
        print("Missing source fonts:", file=sys.stderr)
        for p in sorted(set(missing_sources)):
            print(f"  {p}", file=sys.stderr)
        print(f"\nDownload them into {CACHE} first.", file=sys.stderr)
        return 2

    chars, where = collect()
    print(f"Glyphs referenced by in-game strings: {len(chars)}")

    problems = 0
    for name, (src, _, scope) in FACES.items():
        have = face_cmap(src)
        need = wanted(name, chars)
        missing = sorted(c for c in need if ord(c) not in have)
        if missing:
            problems += len(missing)
            print(f"\n!! {name}: {len(missing)} glyph(s) this face cannot draw")
            for ch in missing:
                try:
                    label = unicodedata.name(ch)
                except ValueError:
                    label = "?"
                print(f"   U+{ord(ch):04X}  {ch!r}  {label}")
                for loc in where.get(ch, [])[:4]:
                    print(f"        {loc}")
        else:
            print(f"OK {name}: full coverage of {len(need)} glyphs")

    if args.check:
        return 1 if problems else 0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, (_, wght, _) in FACES.items():
        dst = OUTPUTS[name]
        options = subset.Options()
        options.layout_features = ["kern", "liga", "palt", "halt", "vrt2", "vert"]
        options.name_IDs = ["*"]
        options.name_legacy = True
        options.name_languages = ["*"]
        options.notdef_outline = True
        options.recalc_bounds = True
        options.drop_tables = []
        options.desubroutinize = True
        font = open_face(name, wght)
        subsetter = subset.Subsetter(options=options)
        subsetter.populate(text="".join(sorted(wanted(name, chars))))
        subsetter.subset(font)
        subset.save_font(font, str(dst), options)
        font.close()
        print(f"  wrote {dst.relative_to(ROOT)}  ({dst.stat().st_size:,} bytes)")

    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
