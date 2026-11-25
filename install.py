#!/usr/bin/env python3
"""Installs (or updates) the extension in the Windows Aseprite, from WSL.

Copies extension/ to %APPDATA%/Aseprite/extensions/EasyPaletteFixer and writes
the __info.json Aseprite uses to uninstall it.
Aseprite must be restarted to load the new version.
"""
import json
import shutil
import subprocess
from pathlib import Path

NAME = "EasyPaletteFixer"
SRC = Path(__file__).resolve().parent / "extension"


def windows_appdata() -> Path:
    win = subprocess.run(
        ["cmd.exe", "/c", "echo %APPDATA%"],
        cwd="/mnt/c", capture_output=True, text=True, check=True,
    ).stdout.strip()
    unix = subprocess.run(
        ["wslpath", "-u", win], capture_output=True, text=True, check=True,
    ).stdout.strip()
    return Path(unix)


dest = windows_appdata() / "Aseprite" / "extensions" / NAME
assert dest.parent.name == "extensions" and dest.name == NAME, dest

if dest.exists():
    shutil.rmtree(dest)
shutil.copytree(SRC, dest)

installed = []
for path in sorted(SRC.rglob("*")):
    rel = path.relative_to(SRC).as_posix()
    installed.append(rel + "/" if path.is_dir() else rel)
(dest / "__info.json").write_text(json.dumps({"installedFiles": installed}))

print(f"Installed in {dest}")
print("Restart Aseprite to load this version.")
