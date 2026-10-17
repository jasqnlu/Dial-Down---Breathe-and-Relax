#!/usr/bin/env python3
"""Build Dial Down TikTok carousel "slide-show 1": eight 1080×1920 slides in the "7 weird habits" format.

The slides live in tiktok_slideshow_1/slides.html (photos in tiktok_slideshow_1/photos, CC0, sources in
credits.json). Each slide is rendered from slides.html#s1 … #s8 with a headless Chromium. TikTok Sans loads from
Google Fonts, so this needs network access.

Captions sit where TikTok's own text tool puts them (y ≈ 870–1050), clear of the caption bar and action column.

Later sets reuse this script: copy tiktok_slideshow_1/ to tiktok_slideshow_N/, edit it, and pass --page.
The slide count is the number of <section class="slide"> elements in the page.

Usage: python build_tiktok_slideshow_1.py --out "Branding/tiktok/slide-show 1" [--page <slides.html>] [--chrome <path>]
"""
import argparse
import os
import subprocess

from build_tiktok_sentences import find_chrome

HERE = os.path.dirname(os.path.abspath(__file__))
PAGE = os.path.join(HERE, "tiktok_slideshow_1", "slides.html")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--page", default=PAGE)
    ap.add_argument("--chrome", default=None)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    chrome = a.chrome or find_chrome()
    page = os.path.abspath(a.page)
    slides = open(page).read().count('<section class="slide"')
    for i in range(1, slides + 1):
        name = f"slide-{i}.png"
        subprocess.run([chrome, "--headless", "--hide-scrollbars", "--force-device-scale-factor=1",
                        "--allow-file-access-from-files", "--window-size=1080,1920",
                        "--virtual-time-budget=10000", f"--screenshot={os.path.abspath(os.path.join(a.out, name))}",
                        f"file://{page}#s{i}"], check=True, capture_output=True)
        print(name)


if __name__ == "__main__":
    main()
