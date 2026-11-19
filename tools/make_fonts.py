#!/usr/bin/env python3
"""rebuild app/fonts from the woff2 files pikabu.ru serves.

uikit cannot load woff2, so each file is unpacked to a plain ttf. needs
fonttools and brotli (pip install fonttools brotli); the app never runs this.
the urls are the ones in the site's own stylesheet, cs.pikabu.ru/apps/ub/.../style/.
"""

import pathlib
import sys
import urllib.request

from fontTools.ttLib import TTFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "app" / "fonts"
BASE = "https://cs.pikabu.ru/apps/ub/"
FONTS = {
    "Roboto-Regular.ttf": "5.0.827/mobile/style/roboto-regular.woff2",
    "Roboto-Medium.ttf": "5.0.827/mobile/style/roboto-500.woff2",
    "Roboto-Bold.ttf": "5.4.81/mobile/style/roboto-bold.woff2",
}
# the postscript names uikit looks the fonts up by
POSTSCRIPT = {
    "Roboto-Regular.ttf": "Roboto-Regular",
    "Roboto-Medium.ttf": "Roboto-Medium",
    "Roboto-Bold.ttf": "Roboto-Bold",
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, path in FONTS.items():
        request = urllib.request.Request(BASE + path, headers={"User-Agent": "Mozilla/5.0"})
        packed = OUT / (name + ".woff2.tmp")
        packed.write_bytes(urllib.request.urlopen(request, timeout=60).read())
        # head.modified would change on every save, so a rebuild is byte for byte the same
        font = TTFont(str(packed), recalcTimestamp=False)
        font.flavor = None
        if font["name"].getDebugName(6) != POSTSCRIPT[name]:
            raise SystemExit("%s has postscript name %s" % (name, font["name"].getDebugName(6)))
        font.save(str(OUT / name))
        packed.unlink()
        print("%s  %d bytes" % (name, (OUT / name).stat().st_size))


if __name__ == "__main__":
    sys.exit(main())
