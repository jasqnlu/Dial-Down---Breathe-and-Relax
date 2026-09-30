#!/usr/bin/env python3
"""Build the Breath "Open Lungs · Airways" logo kit from one set of geometry.

Every SVG in Branding/logo-kit is generated here — edit the geometry/palette below
and re-run instead of hand-editing output files.

Requires: shapely, fonttools (pip install shapely fonttools) and the Nunito
variable font (OFL): https://github.com/google/fonts/raw/main/ofl/nunito/Nunito%5Bwght%5D.ttf

Usage: python build_logo_kit.py --font Nunito.ttf --out Branding/logo-kit
"""
import argparse
import os

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from shapely import affinity
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union

# ── Palette ────────────────────────────────────────────────────────────────
EMBER = "#C75F0E"   # gradient base, head on light
AMBER = "#F59A3A"   # gradient mid
GLOW = "#FFC978"    # gradient top, tagline on dark
CREAM = "#FFE2B0"   # head on dark
PAPER = "#FFF4E6"   # light tile, wordmark on dark
INK = "#0E1413"     # dark tile, wordmark on light (= luminaSurface dark)
ACCENT = "#B5540A"  # one-colour brand mono (= AccentColor light)

# ── Geometry (drawn on the original 256 concept grid) ─────────────────────
LOBE = [((120, 214), (74, 196), (50, 128), (56, 44)),
        ((56, 44), (96, 80), (122, 136), (120, 214))]
AIRWAY_MAIN = ((121, 182), (106, 156), (88, 124), (74, 88))
AIRWAY_BRANCHES = [((97, 136), (88, 134), (80, 132), (72, 126)),
                   ((108, 158), (99, 160), (90, 160), (81, 156)),
                   ((86, 114), (84, 106), (83, 100), (84, 92))]
MAIN_W, BRANCH_W = 6.0, 4.5
HEAD = (128, 66, 18)


def cubic(seg, n=96):
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = seg
    pts = []
    for i in range(n + 1):
        t = i / n
        a, b, c, d = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t ** 2, t ** 3
        pts.append((a * x0 + b * x1 + c * x2 + d * x3, a * y0 + b * y1 + c * y2 + d * y3))
    return pts


def build_mark(airways=True):
    """Returns (lobes, head) shapely geometries on the 256 concept grid."""
    ring = []
    for seg in LOBE:
        ring += cubic(seg)[:-1]
    left = Polygon(ring)
    if airways:
        cuts = [LineString(cubic(AIRWAY_MAIN)).buffer(MAIN_W / 2, quad_segs=16)]
        cuts += [LineString(cubic(b)).buffer(BRANCH_W / 2, quad_segs=16) for b in AIRWAY_BRANCHES]
        left = left.difference(unary_union(cuts))
    right = affinity.scale(left, xfact=-1, yfact=1, origin=(128, 0))
    head = Point(HEAD[0], HEAD[1]).buffer(HEAD[2], quad_segs=32)
    return unary_union([left, right]), head


def fit(geoms, box, cx, cy):
    """Scale geoms uniformly so their joint height == box, centred on (cx, cy)."""
    minx, miny, maxx, maxy = unary_union(geoms).bounds
    s = box / (maxy - miny)
    ox, oy = (minx + maxx) / 2, (miny + maxy) / 2
    return [affinity.translate(affinity.scale(g, s, s, origin=(ox, oy)), cx - ox, cy - oy) for g in geoms]


def d_of(geom):
    polys = getattr(geom, "geoms", [geom])
    out = []
    for p in polys:
        for ring in [p.exterior, *p.interiors]:
            c = list(ring.coords)[:-1]
            out.append("M" + " L".join(f"{x:.2f} {y:.2f}" for x, y in c) + "Z")
    return "".join(out)


def gradient(gid, lobes):
    _, miny, _, maxy = lobes.bounds
    return (f'<linearGradient id="{gid}" gradientUnits="userSpaceOnUse" x1="0" y1="{maxy:.1f}" x2="0" y2="{miny:.1f}">'
            f'<stop offset="0" stop-color="{EMBER}"/><stop offset=".55" stop-color="{AMBER}"/>'
            f'<stop offset="1" stop-color="{GLOW}"/></linearGradient>')


def mark_svg(lobes, head, lobe_fill, head_fill):
    return (f'<path fill-rule="evenodd" fill="{lobe_fill}" d="{d_of(lobes)}"/>'
            f'<path fill="{head_fill}" d="{d_of(head)}"/>')


def svg(w, h, body, title="Breath logo"):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w:.0f} {h:.0f}" role="img">'
            f'<title>{title}</title>{body}</svg>\n')


class Type:
    """Outlines text from the variable font at a fixed weight (no live <text>)."""

    def __init__(self, path, wght):
        font = TTFont(path)
        self.font = instantiateVariableFont(font, {"wght": wght})
        self.gs = self.font.getGlyphSet()
        self.cmap = self.font.getBestCmap()
        self.upm = self.font["head"].unitsPerEm

    def width(self, text, size, tracking=0.0):
        adv = sum(self.gs[self.cmap[ord(ch)]].width for ch in text)
        return (adv + tracking * self.upm * (len(text) - 1)) * size / self.upm

    def path(self, text, size, x, baseline, tracking=0.0):
        s = size / self.upm
        pen = SVGPathPen(self.gs)
        cursor = 0
        for ch in text:
            g = self.gs[self.cmap[ord(ch)]]
            g.draw(TransformPen(pen, (s, 0, 0, -s, x + cursor * s, baseline)))
            cursor += g.width + tracking * self.upm
        return pen.getCommands()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--font", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    out = a.out
    os.makedirs(out, exist_ok=True)

    def write(name, content):
        with open(os.path.join(out, name), "w") as f:
            f.write(content)

    # ── Symbol masters (256 canvas, mark 216 tall, optically lifted 2 px) ──
    for name, airways in (("breath-symbol", True), ("breath-symbol-small", False)):
        lobes, head = fit(build_mark(airways), 216, 128, 126)
        grad = f"<defs>{gradient('g', lobes)}</defs>"
        write(f"{name}.svg", svg(256, 256, grad + mark_svg(lobes, head, "url(#g)", EMBER)))
        write(f"{name}-on-dark.svg", svg(256, 256, grad + mark_svg(lobes, head, "url(#g)", CREAM)))
    lobes, head = fit(build_mark(True), 216, 128, 126)
    write("breath-symbol-black.svg", svg(256, 256, mark_svg(lobes, head, "#000000", "#000000")))
    write("breath-symbol-white.svg", svg(256, 256, mark_svg(lobes, head, "#FFFFFF", "#FFFFFF")))
    write("breath-symbol-accent.svg", svg(256, 256, mark_svg(lobes, head, ACCENT, ACCENT)))

    # ── Lockups ────────────────────────────────────────────────────────────
    word = Type(a.font, 750)
    tag = Type(a.font, 700)
    WORD_SIZE, TAG_SIZE, TAG_TRACK = 124, 27, 0.2
    ww = word.width("Breath", WORD_SIZE)
    tw = tag.width("RELAX & STRETCH", TAG_SIZE, TAG_TRACK)

    def horizontal(lobe_fill, head_fill, word_fill, tag_fill, defs_id):
        lb, hd = fit(build_mark(True), 216, 0, 128)
        minx = unary_union([lb, hd]).bounds[0]
        lb, hd = (affinity.translate(g, 20 - minx) for g in (lb, hd))
        x = unary_union([lb, hd]).bounds[2] + 34
        w = x + max(ww, tw) + 20
        body = (f"<defs>{gradient(defs_id, lb)}</defs>" if lobe_fill.startswith("url") else "")
        body += mark_svg(lb, hd, lobe_fill, head_fill)
        body += f'<path fill="{word_fill}" d="{word.path("Breath", WORD_SIZE, x - 4, 140)}"/>'
        body += f'<path fill="{tag_fill}" d="{tag.path("RELAX & STRETCH", TAG_SIZE, x, 190, TAG_TRACK)}"/>'
        return svg(w, 256, body)

    def stacked(lobe_fill, head_fill, word_fill, tag_fill, defs_id):
        w = max(ww, tw, 200) + 60
        lb, hd = fit(build_mark(True), 200, w / 2, 124)
        body = (f"<defs>{gradient(defs_id, lb)}</defs>" if lobe_fill.startswith("url") else "")
        body += mark_svg(lb, hd, lobe_fill, head_fill)
        body += f'<path fill="{word_fill}" d="{word.path("Breath", WORD_SIZE, (w - ww) / 2, 344)}"/>'
        body += f'<path fill="{tag_fill}" d="{tag.path("RELAX & STRETCH", TAG_SIZE, (w - tw) / 2, 394, TAG_TRACK)}"/>'
        return svg(w, 430, body)

    variants = {
        "": ("url(#g)", EMBER, INK, ACCENT),
        "-on-dark": ("url(#g)", CREAM, PAPER, GLOW),
        "-black": ("#000000", "#000000", "#000000", "#000000"),
        "-white": ("#FFFFFF", "#FFFFFF", "#FFFFFF", "#FFFFFF"),
    }
    for suffix, v in variants.items():
        write(f"breath-horizontal{suffix}.svg", horizontal(*v, "g"))
        write(f"breath-stacked{suffix}.svg", stacked(*v, "g"))
    wm = svg(ww + 16, 160, f'<path fill="{INK}" d="{word.path("Breath", WORD_SIZE, 8, 124)}"/>')
    write("breath-wordmark.svg", wm)

    # ── iOS app icons (1024, opaque, mark ~56 % of the tile, lifted 12 px) ──
    lb, hd = fit(build_mark(True), 574, 512, 500)
    grad = gradient("g", lb)
    glow = ('<radialGradient id="bg" cx=".5" cy=".44" r=".62"><stop offset="0" stop-color="#3A2410"/>'
            f'<stop offset="1" stop-color="{INK}"/></radialGradient>')
    paper = (f'<radialGradient id="bg" cx=".5" cy=".42" r=".7"><stop offset="0" stop-color="#FFFFFF"/>'
             f'<stop offset="1" stop-color="{PAPER}"/></radialGradient>')
    icons = {
        "icon-light": (paper, "url(#g)", EMBER),
        "icon-dark": (glow, "url(#g)", CREAM),
        "icon-tinted": ("", "#FFFFFF", "#FFFFFF"),
    }
    for name, (bg, lf, hf) in icons.items():
        bgfill = "url(#bg)" if bg else "#000000"
        body = f'<defs>{grad}{bg}</defs><rect width="1024" height="1024" fill="{bgfill}"/>'
        write(f"{name}.svg", svg(1024, 1024, body + mark_svg(lb, hd, lf, hf)))


if __name__ == "__main__":
    main()
