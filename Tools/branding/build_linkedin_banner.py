#!/usr/bin/env python3
"""Build the Dial Down LinkedIn cover (4200×700, company-page size) from the logo kit geometry.

Light version: pairs with the light app icon used as the profile photo.
Two versions: with the mark, and without it (for when the profile photo is\nalready the app icon, so the mark isn't shown twice). Safe zones: LinkedIn's profile photo covers the bottom-left on desktop and the
mobile app crops the sides, so content stays in the centre band.

Usage: python build_linkedin_banner.py --font Nunito.ttf --out Branding/logo-kit/social
"""
import argparse
import os

from shapely import affinity
from shapely.ops import unary_union

from build_logo_kit import (ACCENT, AMBER, EMBER, GLOW, INK, PAPER, Type, build_mark, d_of, fit,
                            gradient, mark_svg, svg)

W, H = 4200, 700          # output pixels (6:1)
DH = 396                  # layout is designed in a 396-unit-tall space…
S = H / DH                # …and scaled up by S to the output size
DW = W / S                # design-space width (2376 units at 6:1)
TAGLINE = "Tap where it’s tight. Breathe where it’s tense."
KICKER = "BREATHE AND RELAX  ·  iOS"


def banner(font_path, with_mark=True):
    word = Type(font_path, 750)
    tag = Type(font_path, 600)
    kick = Type(font_path, 700)

    defs = [
        '<radialGradient id="bg" cx=".62" cy=".45" r=".75">'
        f'<stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="{PAPER}"/></radialGradient>',
    ]
    body = [f'<rect width="{DW:.1f}" height="{DH}" fill="url(#bg)"/>']

    # Ghost mark: oversized, bleeding off the right edge, very faint.
    g_lobes, g_head = fit(build_mark(True), 560, DW - 84, 250)
    defs.append(gradient("ghost", g_lobes))
    body.append(f'<g opacity=".13">{mark_svg(g_lobes, g_head, "url(#ghost)", EMBER)}</g>')

    # Main mark + text block, centred as a group just right of centre (the page
    # logo / profile photo covers the bottom-left; mobile crops the sides).
    lobes, head = fit(build_mark(True), 176, 0, 0)
    mw = unary_union([lobes, head]).bounds
    mark_w = mw[2] - mw[0]
    word_size, tag_size, kick_size = 92, 30, 17
    text_w = max(word.width("Dial Down", word_size), tag.width(TAGLINE, tag_size))
    if not with_mark:
        mark_w = gap = 0  # profile photo is already the mark; don't repeat it
    else:
        gap = 40
    group_w = mark_w + gap + text_w
    x0 = DW / 2 + 48 - group_w / 2
    lobes, head = (affinity.translate(g, x0 - mw[0], DH / 2 - 6 - (mw[1] + mw[3]) / 2) for g in (lobes, head))
    if with_mark:
        defs.append(gradient("g", lobes))
        body.append(mark_svg(lobes, head, "url(#g)", EMBER))

    tx = x0 + mark_w + gap
    body.append(f'<path fill="{ACCENT}" d="{kick.path(KICKER, kick_size, tx + 2, 150, 0.22)}"/>')
    body.append(f'<path fill="{INK}" d="{word.path("Dial Down", word_size, tx - 3, 236)}"/>')
    body.append(f'<path fill="#3D4946" d="{tag.path(TAGLINE, tag_size, tx, 288)}"/>')

    # A thin amber rule echoing the gradient, under the text block.
    body.append(f'<defs><linearGradient id="rule" x1="0" x2="1"><stop offset="0" stop-color="{EMBER}"/>'
                f'<stop offset=".55" stop-color="{AMBER}"/><stop offset="1" stop-color="{GLOW}"/></linearGradient></defs>'
                f'<rect x="{tx:.1f}" y="316" width="64" height="4" rx="2" fill="url(#rule)"/>')

    # Clip to the canvas: the ghost mark deliberately bleeds past the edges.
    defs.append(f'<clipPath id="canvas"><rect width="{DW:.1f}" height="{DH}"/></clipPath>')
    return svg(W, H, f'<defs>{"".join(defs)}</defs><g transform="scale({S:.6f})"><g clip-path="url(#canvas)">'
               + "".join(body) + "</g></g>",
               title="Dial Down LinkedIn banner")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--font", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    with open(os.path.join(a.out, "linkedin-banner.svg"), "w") as f:
        f.write(banner(a.font))
    with open(os.path.join(a.out, "linkedin-banner-no-mark.svg"), "w") as f:
        f.write(banner(a.font, with_mark=False))


if __name__ == "__main__":
    main()
