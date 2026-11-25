#!/usr/bin/env python3
"""Runs tests/run.lua in Aseprite's batch mode, from WSL.

Set ASEPRITE to the path of Aseprite.exe if it isn't the Steam one.
Exits with 1 when a test fails.
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASEPRITE = os.environ.get(
    "ASEPRITE",
    "/mnt/c/Program Files (x86)/Steam/steamapps/common/Aseprite/Aseprite.exe",
)


def win(path: Path) -> str:
    return subprocess.run(
        ["wslpath", "-w", str(path)], capture_output=True, text=True, check=True
    ).stdout.strip()


with tempfile.TemporaryDirectory(prefix="easy-palette-fixer-") as tmp:
    result = subprocess.run(
        [
            ASEPRITE, "-b",
            "--script-param", f"root={win(ROOT / 'extension')}",
            "--script-param", f"tests={win(ROOT / 'tests')}",
            "--script-param", f"tmp={win(Path(tmp))}",
            "--script", win(ROOT / "tests" / "run.lua"),
        ],
        cwd="/mnt/c",
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )

# Keep the tests' lines; other extensions may print noise when Aseprite starts.
lines = [
    line for line in result.stdout.splitlines()
    if line.startswith(("ok", "FAIL", "      ", "RESULT")) or "error" in line.lower()
]
print("\n".join(lines))
if result.stderr.strip():
    print(result.stderr, file=sys.stderr)
summary = [line for line in lines if line.startswith("RESULT")]
sys.exit(0 if summary and summary[-1].endswith(" 0 failures") else 1)
