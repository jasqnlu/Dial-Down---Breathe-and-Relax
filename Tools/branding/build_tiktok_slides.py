#!/usr/bin/env python3
"""Build the Dial Down TikTok photo carousel: 1080×1920 slides ending on a scannable QR code.

TikTok overlays its own UI on photo posts: the caption and music bar cover roughly the bottom 25%,
and the like/comment/share column covers the right edge. All text stays inside SAFE_* below; only
the bottom of the phone mockups is allowed to sit under that UI.

A viewer watching on their phone can't point its camera at its own screen, so the last slide says
how to scan from a screenshot and gives "search Dial Down" as a fallback.

Usage: python build_tiktok_slides.py --fonts <dir with Nunito-*.ttf> \
           --shots AppStoreScreenshots/6.9-inch --out Branding/tiktok
"""
import argparse
import os

from PIL import Image, ImageDraw

from build_appstore_creatives import (AMBER, EMBER, GLOW, INK, MUTED, PAPER, base, font, phone, place,
                                      rings, text_centre)
from build_sticker import LOGO, QUIET, qr_matrix

W, H = 1080, 1920
SAFE_TOP, SAFE_BOTTOM = 170, 1440      # text band clear of TikTok's top tabs and bottom caption
SAFE_X = 90                            # side margin (right side also clears the action column)
LINK = "https://apps.apple.com/app/id6818409674?ct=tiktok"
WARM = (GLOW, EMBER)                   # vertical gradient for the emphasised line

# (headline lines, emphasised line, screenshot timestamp or None)
SLIDES = [
    ("hook", None, None),
    (["Tap exactly", "where it’s tight."], "Shoulder? Neck? Lower back?", "10.12.09"),
    (["Get a stretch", "for that spot."], "Step by step, with a timer.", "10.17.49"),
    (["Then breathe", "it out."], "Box, 4-7-8 or belly breathing.", "10.13.14"),
    (["Every stretch,", "sorted by body part."], "Find one in seconds.", "10.13.10"),
    (["Ready-made", "routines."], "Desk breaks, sleep, warm-ups and more.", "10.14.05"),
    ("cta", None, None),
]


def wrap(draw, text, fnt, max_w):
    lines, cur = [], ""
    for word in text.split():
        trial = f"{cur} {word}".strip()
        if draw.textlength(trial, font=fnt) <= max_w or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = word
    return lines + [cur]


def canvas(glow_y=0.75):
    img = base(W, H, (W // 2, int(H * glow_y)), 1100, 75)
    return img, ImageDraw.Draw(img)


def hook(fonts):
    img, d = canvas(0.5)
    rings(img, W // 2, H // 2 - 60, [260 + i * 95 for i in range(8)], 3, 110)
    big = font(fonts, "ExtraBold", 104)
    lines = ["POV: your", "shoulders have", "been up by your", "ears since 9am"]
    y = 560
    for i, line in enumerate(lines):
        text_centre(img, W // 2, y, line, big, WARM if i == len(lines) - 1 else PAPER)
        y += 128
    text_centre(img, W // 2, y + 90, "swipe for the fix  ›››", font(fonts, "Bold", 50), MUTED)
    return img


def feature(fonts, shots, head, sub, key):
    img, d = canvas()
    head_f, sub_f = font(fonts, "ExtraBold", 92), font(fonts, "Bold", 46)
    y = SAFE_TOP + 60
    for i, line in enumerate(head):
        text_centre(img, W // 2, y, line, head_f, WARM if i == len(head) - 1 else PAPER)
        y += 110
    for line in wrap(d, sub, sub_f, W - 2 * SAFE_X):
        text_centre(img, W // 2, y + 24, line, sub_f, MUTED)
        y += 60
    shot = next(os.path.join(shots, f) for f in sorted(os.listdir(shots)) if key in f)
    tile, mask = phone(shot, 1240)
    place(img, tile, mask, W // 2 - tile.width // 2, y + 90)  # bottom runs under TikTok's caption
    return img


def cta(fonts):
    img, d = canvas(0.45)
    logo = Image.open(LOGO).convert("RGBA")
    lw = 520
    logo = logo.resize((lw, round(logo.height * lw / logo.width)), Image.LANCZOS)
    img.paste(logo, (W // 2 - lw // 2, SAFE_TOP + 20), logo)

    text_centre(img, W // 2, SAFE_TOP + 230, "Screenshot this.", font(fonts, "ExtraBold", 96), WARM)

    rows = qr_matrix(LINK)
    module = 15
    panel = (len(rows) + 2 * QUIET) * module              # 615 px
    px, py = W // 2 - panel // 2, SAFE_TOP + 400
    rings(img, W // 2, py + panel // 2, [panel // 2 + 40 + i * 70 for i in range(6)], 3, 110)
    d.rounded_rectangle([px, py, px + panel - 1, py + panel - 1], radius=40, fill=PAPER)
    ox, oy = px + QUIET * module, py + QUIET * module
    for y, row in enumerate(rows):
        for x, bit in enumerate(row):
            if bit == "1":
                d.rectangle([ox + x * module, oy + y * module,
                             ox + (x + 1) * module - 1, oy + (y + 1) * module - 1], fill=INK)

    step_f = font(fonts, "Bold", 42)
    y = py + panel + 60
    for line in ["Open it in Photos, then touch and hold", "the code to open the App Store."]:
        text_centre(img, W // 2, y, line, step_f, PAPER)
        y += 56
    text_centre(img, W // 2, y + 30, "or search “Dial Down” on the App Store", step_f, AMBER)
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fonts", required=True)
    ap.add_argument("--shots", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for i, (head, sub, key) in enumerate(SLIDES, 1):
        if head == "hook":
            img = hook(a.fonts)
        elif head == "cta":
            img = cta(a.fonts)
        else:
            img = feature(a.fonts, a.shots, head, sub, key)
        assert img.mode == "RGB" and img.size == (W, H)
        name = f"slide-{i}.png"
        img.save(os.path.join(a.out, name))
        print(name)


if __name__ == "__main__":
    main()
