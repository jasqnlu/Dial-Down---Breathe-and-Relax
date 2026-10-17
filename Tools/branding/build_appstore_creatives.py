#!/usr/bin/env python3
"""Build the App Store "Header and Search Results" creatives (iOS 27+).

  header.png          3840×1646 (21:9)  product page header: mood, one idea, no UI
  search-results.png  3840×2560 (3:2)   search card: say what the app does, show the real UI

Both are flat RGB (App Store Connect rejects alpha). Apple crops each placement
differently per device, so everything important sits in the centre band.

Usage: python build_appstore_creatives.py --fonts <dir with Nunito-*.ttf> \
           --shots AppStoreScreenshots/6.9-inch --out Branding/appstore
"""
import argparse
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

INK = (14, 20, 19)
EMBER = (199, 95, 14)
AMBER = (245, 154, 58)
GLOW = (255, 201, 120)
PAPER = (255, 244, 230)
MUTED = (170, 180, 176)

HEADLINE = ["Breathe in.", "Dial down."]
KICKER = "BREATHE  ·  STRETCH  ·  RELAX"
SEARCH_HEAD = ["Tap where it’s tight.", "Breathe where it’s tense."]
# Screenshots by timestamp in their file names: left, centre (hero), right.
SEARCH_SHOTS = ["10.13.14", "10.12.09", "10.17.49"]  # breathing, body map, exercise player


def font(dirpath, weight, size):
    return ImageFont.truetype(os.path.join(dirpath, f"Nunito-{weight}.ttf"), size)


def base(w, h, glow_xy, glow_r, strength):
    """Ink canvas with a soft warm glow, like light through closed eyes."""
    img = Image.new("RGB", (w, h), INK)
    small = Image.new("L", (w // 8, h // 8), 0)
    d = ImageDraw.Draw(small)
    gx, gy, r = glow_xy[0] / 8, glow_xy[1] / 8, glow_r / 8
    for i in range(60, 0, -1):  # stacked discs → smooth radial falloff
        rr = r * i / 60
        d.ellipse([gx - rr, gy - rr, gx + rr, gy + rr], fill=int(strength * (1 - i / 60) ** 1.6))
    mask = small.resize((w, h), Image.BICUBIC).filter(ImageFilter.GaussianBlur(24))
    return Image.composite(Image.new("RGB", (w, h), EMBER), img, mask)


def rings(img, cx, cy, radii, width, alpha):
    """Concentric breathing rings, fading outward (echoes the Breathe screen)."""
    layer = Image.new("L", img.size, 0)
    d = ImageDraw.Draw(layer)
    for i, r in enumerate(radii):
        a = int(alpha * (1 - i / len(radii)) ** 1.3)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=a, width=width)
    layer = layer.filter(ImageFilter.GaussianBlur(2))
    img.paste(Image.new("RGB", img.size, AMBER), (0, 0), layer)


def gradient_fill(size, top, bottom):
    w, h = size
    g = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(h - 1, 1)
        g.putpixel((0, y), tuple(int(top[k] + (bottom[k] - top[k]) * t) for k in range(3)))
    return g.resize((w, h))


def text_centre(img, cx, y, text, fnt, fill, tracking=0):
    """Draw text centred on cx with its top at y; fill is a colour or (top, bottom) gradient."""
    d = ImageDraw.Draw(img)
    if tracking:
        widths = [d.textlength(ch, font=fnt) for ch in text]
        total = sum(widths) + tracking * (len(text) - 1)
        x = cx - total / 2
        for ch, cw in zip(text, widths):
            d.text((x, y), ch, font=fnt, fill=fill)
            x += cw + tracking
        return
    box = d.textbbox((0, 0), text, font=fnt)
    x = cx - (box[2] - box[0]) / 2 - box[0]
    if isinstance(fill[0], tuple):
        mask = Image.new("L", img.size, 0)
        ImageDraw.Draw(mask).text((x, y), text, font=fnt, fill=255)
        bb = mask.getbbox()
        grad = Image.new("RGB", img.size)
        grad.paste(gradient_fill((bb[2] - bb[0], bb[3] - bb[1]), *fill), bb[:2])
        img.paste(grad, (0, 0), mask)
    else:
        d.text((x, y), text, font=fnt, fill=fill)


def header(fonts):
    W, H = 3840, 1646
    cx, cy = W // 2, int(H * 0.47)
    img = base(W, H, (cx, cy), 1500, 70)
    rings(img, cx, cy, [430 + i * 150 for i in range(9)], 5, 120)

    head = font(fonts, "ExtraBold", 250)
    kick = font(fonts, "Bold", 64)
    line_h = 290
    top = cy - line_h - 40
    text_centre(img, cx, top - 150, KICKER, kick, GLOW, tracking=14)
    text_centre(img, cx, top, HEADLINE[0], head, PAPER)
    text_centre(img, cx, top + line_h, HEADLINE[1], head, (GLOW, EMBER))
    return img


def phone(shot_path, height):
    """A screenshot in a simple dark bezel with rounded corners, on an opaque tile + mask."""
    shot = Image.open(shot_path).convert("RGB")
    sw = round(shot.width * height / shot.height)
    shot = shot.resize((sw, height), Image.LANCZOS)
    bez = round(height * 0.012)
    W, H = sw + 2 * bez, height + 2 * bez
    tile = Image.new("RGB", (W, H), (40, 46, 44))
    inner = Image.new("L", (sw, height), 0)
    ImageDraw.Draw(inner).rounded_rectangle([0, 0, sw - 1, height - 1], radius=round(sw * 0.13), fill=255)
    tile.paste(shot, (bez, bez), inner)
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, W - 1, H - 1], radius=round(sw * 0.13) + bez, fill=255)
    return tile, mask


def place(img, tile, mask, x, y, shadow=True):
    if shadow:  # warm halo instead of a black drop shadow — reads on Ink
        halo = Image.new("L", img.size, 0)
        halo.paste(mask.point(lambda v: v * 0.32), (x, y + 30))
        halo = halo.filter(ImageFilter.GaussianBlur(70))
        img.paste(Image.new("RGB", img.size, EMBER), (0, 0), halo)
    img.paste(tile, (x, y), mask)


def search(fonts, shots):
    W, H = 3840, 2560
    cx = W // 2
    img = base(W, H, (cx, int(H * 0.82)), 1900, 85)

    head = font(fonts, "ExtraBold", 190)
    text_centre(img, cx, 150, SEARCH_HEAD[0], head, PAPER)
    text_centre(img, cx, 150 + 225, SEARCH_HEAD[1], head, (GLOW, EMBER))

    files = sorted(os.listdir(shots))
    path = lambda key: os.path.join(shots, next(f for f in files if key in f))
    side_h, hero_h = 1880, 2120
    left, lm = phone(path(SEARCH_SHOTS[0]), side_h)
    right, rm = phone(path(SEARCH_SHOTS[2]), side_h)
    hero, hm = phone(path(SEARCH_SHOTS[1]), hero_h)
    gap = 110
    place(img, left, lm, cx - hero.width // 2 - gap - left.width, 900)
    place(img, right, rm, cx + hero.width // 2 + gap, 900)
    place(img, hero, hm, cx - hero.width // 2, 720)  # bleeds off the bottom on purpose
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fonts", required=True)
    ap.add_argument("--shots", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for name, im in (("header.png", header(a.fonts)), ("search-results.png", search(a.fonts, a.shots))):
        assert im.mode == "RGB"
        im.save(os.path.join(a.out, name), optimize=True)
        print(name, im.size)


if __name__ == "__main__":
    main()
