#!/usr/bin/env python3
"""Compares the Lua port with the original Rust CLI, pixel for pixel, and times it.

    python3 tests/parity.py path/to/spritefusion-palette-snapper

Generates test images (flat sprites with noise, smooth gradients, transparency),
runs the Rust CLI on them, then tests/parity.lua runs the port in Aseprite on the
same images and compares.
"""
import json
import os
import random
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASEPRITE = os.environ.get(
    "ASEPRITE",
    "/mnt/c/Program Files (x86)/Steam/steamapps/common/Aseprite/Aseprite.exe",
)
GAME_BOY = "#081820,#346856,#88c070,#e0f8d0"
SIXTEEN = ",".join(
    "#" + c
    for c in "1a1c2c 5d275d b13e53 ef7d57 ffcd75 a7f070 38b764 257179 "
    "29366f 3b5dc9 41a6f6 73eff7 f4f4f4 94b0c2 566c86 333c57".split()
)


def win(path: Path) -> str:
    return subprocess.run(
        ["wslpath", "-w", str(path)], capture_output=True, text=True, check=True
    ).stdout.strip()


def write_png(path: Path, width: int, height: int, pixel) -> None:
    rows = b"".join(
        b"\x00" + b"".join(bytes(pixel(x, y)) for x in range(width))
        for y in range(height)
    )

    def chunk(kind: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data)) + kind + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )

    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(rows, 6))
        + chunk(b"IEND", b"")
    )


def noisy_sprite(size: int, seed: int):
    """Flat regions with +-6 noise per channel, a transparent outside and a
    half-transparent ring: like an AI-generated or upscaled sprite."""
    rng = random.Random(seed)
    seeds = [
        (rng.randrange(size), rng.randrange(size),
         [rng.randrange(30, 226) for _ in range(3)])
        for _ in range(12)
    ]
    noise = [[rng.randint(-6, 6) for _ in range(3)] for _ in range(size * size)]
    centre = size / 2

    def pixel(x, y):
        d = ((x - centre) ** 2 + (y - centre) ** 2) ** 0.5
        if d > size * 0.48:
            return (0, 0, 0, 0)
        base = min(seeds, key=lambda s: (s[0] - x) ** 2 + (s[1] - y) ** 2)[2]
        n = noise[y * size + x]
        alpha = 128 if d > size * 0.45 else 255
        return tuple(max(0, min(255, base[i] + n[i])) for i in range(3)) + (alpha,)

    return pixel


def gradient(x, y):
    return (x * 255 // 199, y * 255 // 199, (x + y) * 255 // 398, 255)


def ramp(x, _y):
    return ((x * 4) % 256, (255 - x * 4) % 256, (x * 37) % 256, 255)


def main() -> None:
    cli = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="easy-palette-fixer-parity-") as tmp:
        tmp = Path(tmp)
        images = {
            "ramp": (60, 1, ramp),
            "noisy": (128, 128, noisy_sprite(128, 1)),
            "gradient": (200, 200, gradient),
            "big": (1024, 1024, noisy_sprite(1024, 2)),
        }
        for name, (w, h, pixel) in images.items():
            write_png(tmp / f"{name}.png", w, h, pixel)

        cases = [
            ("ramp", "reduce", [], {}),
            ("ramp", "reduce -c 8", ["-c", "8"], {"maxColors": 8}),
            ("ramp", "reduce -c 16 -t 0", ["-c", "16", "-t", "0"], {"maxColors": 16, "threshold": 0}),
            ("noisy", "reduce", [], {}),
            ("noisy", "reduce -c 8", ["-c", "8"], {"maxColors": 8}),
            ("noisy", "reduce -c none -t 0.05", ["-c", "none", "-t", "0.05"], {"maxColors": None, "threshold": 0.05}),
            ("gradient", "reduce", [], {}),
            ("gradient", "reduce -c 8", ["-c", "8"], {"maxColors": 8}),
            ("gradient", "reduce -c none -t 0.05", ["-c", "none", "-t", "0.05"], {"maxColors": None, "threshold": 0.05}),
            ("noisy", "snap nearest gameboy", ["-p", GAME_BOY], {"palette": GAME_BOY}),
            ("noisy", "snap lightness gameboy", ["-p", GAME_BOY, "-m", "lightness"], {"palette": GAME_BOY, "snapMode": "lightness"}),
            ("gradient", "snap nearest 16", ["-p", SIXTEEN], {"palette": SIXTEEN}),
            ("gradient", "snap lightness 16", ["-p", SIXTEEN, "-m", "lightness"], {"palette": SIXTEEN, "snapMode": "lightness"}),
            ("big", "reduce", [], {}),
            ("big", "snap nearest 16", ["-p", SIXTEEN], {"palette": SIXTEEN}),
        ]
        manifest = []
        for i, (image, label, args, opts) in enumerate(cases):
            out = tmp / f"rust-{i}.png"
            subprocess.run([str(cli), str(tmp / f"{image}.png"), "-o", str(out), *args], check=True)
            opts = {"mode": "snap" if "palette" in opts else "reduce", **opts}
            manifest.append({
                "name": f"{image}: {label}",
                "input": win(tmp / f"{image}.png"),
                "rust": win(out),
                "opts": opts,
            })
        (tmp / "cases.json").write_text(json.dumps(manifest))

        result = subprocess.run(
            [
                ASEPRITE, "-b",
                "--script-param", f"root={win(ROOT / 'extension')}",
                "--script-param", f"cases={win(tmp / 'cases.json')}",
                "--script", win(ROOT / "tests" / "parity.lua"),
            ],
            cwd="/mnt/c", capture_output=True, text=True, encoding="utf-8", errors="replace",
        )
        lines = [l for l in result.stdout.splitlines() if l.startswith(("same", "DIFF", "     ", "RESULT", "ERROR"))]
        print("\n".join(lines))
        summary = [l for l in lines if l.startswith("RESULT")]
        sys.exit(0 if summary and summary[-1].endswith(" 0 different") else 1)


if __name__ == "__main__":
    main()
