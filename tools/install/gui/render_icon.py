#!/usr/bin/env python3
"""Renders an SVG of assets/icon to PNG at the sizes asked for, the way
assets/icon/README.md documents it: with resvg (or rsvg-convert), whichever of
these is there:

    the `resvg` program          brew install resvg / cargo install resvg
    the `rsvg-convert` program   librsvg
    the resvg_py module          pip install resvg-py   (in the Python that runs this)

    render_icon.py <icon.svg> <out-256.png> 256 [<out-64.png> 64 ...]
    render_icon.py --check       status 0 when one of the three is there

Qt's own SVG reader is not one of them: it ignores the clip path and the shadow,
so the tile comes out square. Nothing rendered is kept in the repository.
"""
import shutil
import subprocess
import sys


def renderer():
    if shutil.which("resvg"):
        return "resvg"
    if shutil.which("rsvg-convert"):
        return "rsvg-convert"
    try:
        import resvg_py  # noqa: F401
        return "resvg_py"
    except ImportError:
        return None


def render(how, svg, out, px):
    if how == "resvg":
        subprocess.run(["resvg", "-w", str(px), "-h", str(px), svg, out], check=True)
    elif how == "rsvg-convert":
        subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), svg, "-o", out], check=True)
    else:
        import resvg_py
        with open(out, "wb") as f:
            f.write(bytes(resvg_py.svg_to_bytes(svg_path=svg, width=px, height=px)))


def main(argv):
    how = renderer()
    if len(argv) == 2 and argv[1] == "--check":
        print(how or "none")
        return 0 if how else 1
    if len(argv) < 4 or len(argv) % 2:
        sys.stderr.write(__doc__)
        return 2
    if not how:
        sys.stderr.write("render_icon.py: no SVG renderer (resvg, rsvg-convert or the resvg_py module)\n")
        return 1
    for i in range(2, len(argv), 2):
        render(how, argv[1], argv[i], int(argv[i + 1]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
