#!/usr/bin/env python3
"""Packs the extension/ folder into dist/EasyPaletteFixer.aseprite-extension.

An .aseprite-extension is a plain zip with package.json at its root.
Everything in extension/ is included.
"""
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "extension"
OUT = ROOT / "dist" / "EasyPaletteFixer.aseprite-extension"

OUT.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as zf:
    for path in sorted(SRC.rglob("*")):
        if path.is_file():
            zf.write(path, path.relative_to(SRC).as_posix())

print(OUT)
