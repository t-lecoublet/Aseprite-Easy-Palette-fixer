# Easy Palette Fixer

An Aseprite extension that reduces a sprite's colors or snaps it to a palette.
It's a Lua port of [Sprite Fusion Palette Snapper](https://github.com/Hugo-Dz/spritefusion-palette-snapper)
(Hugo Duprez, MIT license, see `extension/snapper/LICENSE.txt`) and gives the same pixels as the original.

## Usage

**Sprite → Easy Palette Fixer...** opens a window that stays open:

- **Reduce colors**: similar colors (OKLab threshold, 0.03 by default) merge into the most frequent one, then the
  closest keep merging down to the maximum (32 by default). No color is invented.
- **Snap to a palette**: the active sprite's palette, an **Aseprite preset** (a searchable list showing each palette's
  colors, like the Presets tab), a file (`.hex`, `.txt`, `.gpl`, `.json`, `.pal`, `.act`, `.col`, `.ase` or an image
  of swatches) or typed hex colors. *Nearest color* or *by lightness* matching. The chosen palette is shown as a
  strip of colors.
- **Target**: the active sprite, the selected cels, all open sprites (one undo step per sprite), or every image in a
  folder (output beside it as `name_snapped`, in a `snapped/` subfolder, or replacing the originals).
- **Before / after preview**: the current frame (or the active cel, or the chosen image of the folder) before and
  after, with color counts and the result's colors. Updated after each setting change, frame change or edit. The
  mouse wheel zooms (both sides together), dragging moves, double-click fits again.

RGB and Indexed sprites are recolored in place; Grayscale sprites are converted to RGB. Locked, tilemap and reference
layers are skipped. The first time it touches the disk (a palette, a folder), Aseprite asks permission for the
`files.lua` script.

## Development (from WSL)

```bash
python3 install.py          # installs into the Windows Aseprite (restart Aseprite afterwards)
python3 build.py            # creates dist/EasyPaletteFixer.aseprite-extension
python3 tests/run.py        # tests inside Aseprite, in batch mode
python3 tests/parity.py <path/to/spritefusion-palette-snapper>   # pixel-for-pixel comparison with the Rust CLI
```

`ASEPRITE=/path/to/Aseprite.exe` changes the executable the tests use.
