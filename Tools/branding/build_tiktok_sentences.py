#!/usr/bin/env python3
"""Build the second Dial Down TikTok carousel ("the sentence is the layout"): seven 1080×1920 slides.

The slides are laid out in tiktok_sentences/slides.html, where each sentence carries a crop of the real app in
place of one word. This script writes the App Store QR code next to it, then renders each slide (slides.html#s1 …
#s7) with a headless Chromium. Nunito loads from Google Fonts, so it needs network access.

Same TikTok safe zones as build_tiktok_slides.py: text stays between y 170 and 1440 and clear of the right-hand
action column; only the full-bleed app crops run under the caption.

Usage: python build_tiktok_sentences.py --out Branding/tiktok/sentences [--chrome <path to chrome or headless shell>]
"""
import argparse
import glob
import os
import subprocess

from build_sticker import QUIET, qr_matrix

HERE = os.path.dirname(os.path.abspath(__file__))
PAGE = os.path.join(HERE, "tiktok_sentences", "slides.html")
LINK = "https://apps.apple.com/app/id6818409674?ct=tiktok-sentences"   # ct= shows up in App Analytics
SLIDES = 7
INK = "#0E1413"


def write_qr(path):
    rows = qr_matrix(LINK)
    n = len(rows) + 2 * QUIET
    cells = "".join(f'<rect x="{x + QUIET}" y="{y + QUIET}" width="1" height="1"/>'
                    for y, row in enumerate(rows) for x, bit in enumerate(row) if bit == "1")
    with open(path, "w") as f:
        f.write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {n} {n}" shape-rendering="crispEdges">'
                f'<g fill="{INK}">{cells}</g></svg>\n')


def find_chrome():
    candidates = ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                  "/Applications/Chromium.app/Contents/MacOS/Chromium"]
    candidates += sorted(glob.glob(os.path.expanduser(
        "~/Library/Caches/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-*/chrome-headless-shell")))
    for c in candidates:
        if os.path.exists(c):
            return c
    raise SystemExit("No Chrome found; pass --chrome")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--chrome", default=None)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    chrome = a.chrome or find_chrome()
    write_qr(os.path.join(HERE, "tiktok_sentences", "qr.svg"))

    for i in range(1, SLIDES + 1):
        name = f"slide-{i}.png"
        subprocess.run([chrome, "--headless", "--hide-scrollbars", "--force-device-scale-factor=1",
                        "--allow-file-access-from-files", "--window-size=1080,1920",
                        "--virtual-time-budget=10000", f"--screenshot={os.path.abspath(os.path.join(a.out, name))}",
                        f"file://{PAGE}#s{i}"], check=True, capture_output=True)
        print(name)


if __name__ == "__main__":
    main()
