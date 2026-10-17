#!/usr/bin/env python3
"""Build the Dial Down laptop sticker: 3×4 in portrait, rounded corners, QR to the App Store.

  dialdown-sticker.png / .pdf   975×1275 px at 300 DPI = 3×4 in trim + 1/8 in bleed per side
  dialdown-sticker-preview.png  the same art with the cut line and safe area drawn on (not for print)

The QR code is regenerated sharp from the link (qr_matrix.swift, CoreImage), never upscaled from
a screenshot. It sits on a flat Paper panel with a 4-module quiet zone; the decoration stays outside it.

Usage: python build_sticker.py --fonts <dir with Nunito-*.ttf> --out Branding/sticker
"""
import argparse
import os
import subprocess

from PIL import Image, ImageDraw

from build_appstore_creatives import GLOW, INK, PAPER, base, font, rings, text_centre

HERE = os.path.dirname(os.path.abspath(__file__))
LOGO = os.path.join(HERE, "..", "..", "Branding", "logo-kit", "png", "dialdown-horizontal-on-dark.png")
LINK = "https://apps.apple.com/app/id6818409674?ct=laptop-sticker"  # ct= shows up in App Analytics
CAPTION = "SCAN TO BREATHE"

DPI = 300
BLEED = -(-DPI // 8)                   # 1/8 in (rounded up), trimmed off by the printer
W, H = 3 * DPI + 2 * BLEED, 4 * DPI + 2 * BLEED
SAFE = BLEED + DPI // 8                # keep content 1/8 in inside the cut line
CORNER = DPI // 4                      # 1/4 in corner radius to request from the printer
MODULE = 16                            # px per QR module: 33 modules → 528 px ≈ 1.76 in
QUIET = 4                              # modules of blank margin, per the QR spec


def qr_matrix(text):
    out = subprocess.run(["swift", os.path.join(HERE, "qr_matrix.swift"), text, "M"],
                         check=True, capture_output=True, text=True).stdout
    return [row for row in out.split() if row]


def sticker(fonts):
    cx = W // 2
    rows = qr_matrix(LINK)
    n = len(rows)
    panel = (n + 2 * QUIET) * MODULE                     # 656 px ≈ 2.19 in
    py = 395                                             # panel top
    pcy = py + panel // 2

    img = base(W, H, (cx, pcy), 1100, 80)
    rings(img, cx, pcy, [panel // 2 + 40 + i * 70 for i in range(9)], 4, 130)

    logo = Image.open(LOGO).convert("RGBA")
    lw = 640
    logo = logo.resize((lw, round(logo.height * lw / logo.width)), Image.LANCZOS)
    img.paste(logo, (cx - lw // 2, 140), logo)

    d = ImageDraw.Draw(img)
    px = cx - panel // 2
    d.rounded_rectangle([px, py, px + panel - 1, py + panel - 1], radius=44, fill=PAPER)
    ox, oy = px + QUIET * MODULE, py + QUIET * MODULE
    for y, row in enumerate(rows):
        for x, bit in enumerate(row):
            if bit == "1":
                d.rectangle([ox + x * MODULE, oy + y * MODULE,
                             ox + (x + 1) * MODULE - 1, oy + (y + 1) * MODULE - 1], fill=INK)

    text_centre(img, cx, py + panel + 45, CAPTION, font(fonts, "ExtraBold", 54), GLOW, tracking=12)
    return img


def preview(img):
    p = img.copy()
    d = ImageDraw.Draw(p)
    d.rounded_rectangle([BLEED, BLEED, W - BLEED - 1, H - BLEED - 1], radius=CORNER, outline=(255, 60, 60), width=3)
    d.rounded_rectangle([SAFE, SAFE, W - SAFE - 1, H - SAFE - 1], radius=CORNER - (SAFE - BLEED),
                        outline=(80, 200, 255), width=2)
    return p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fonts", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    img = sticker(a.fonts)
    assert img.mode == "RGB" and img.size == (W, H)
    img.save(os.path.join(a.out, "dialdown-sticker.png"), dpi=(DPI, DPI))
    img.save(os.path.join(a.out, "dialdown-sticker.pdf"), resolution=DPI)
    preview(img).save(os.path.join(a.out, "dialdown-sticker-preview.png"))
    print("sticker", img.size, f"{W / DPI:.3f}×{H / DPI:.3f} in")


if __name__ == "__main__":
    main()
