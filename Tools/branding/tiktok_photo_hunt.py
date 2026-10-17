#!/usr/bin/env python3
"""Find CC0 portrait photos for a TikTok slideshow and tile them into labelled contact sheets to look at.

Searches Openverse (via the taste skill's assets.mjs) with CC0 only, portrait, ≥1000px wide, skipping Wikimedia
Commons (mostly scans and museum art). Downloads small thumbnails, writes sheet-N.jpg (24 per sheet, numbered)
and catalog.json (full metadata, indexed by those numbers) into --out.

Pick by number, then download the full file with the ref from catalog.json:
    node ~/.claude/skills/design-taste-frontend/scripts/assets.mjs --get <ref> --to <set>/photos --name <name>

Usage: python3 tiktok_photo_hunt.py --out <scratch dir> "query one" "query two" ...
"""
import argparse, concurrent.futures as cf, io, json, os, subprocess, urllib.request
from PIL import Image, ImageDraw, ImageFont

ASSETS = os.path.expanduser("~/.claude/skills/design-taste-frontend/scripts/assets.mjs")
SKIP_VIA = {"Wikimedia Commons"}


def search(q):
    r = subprocess.run(["node", ASSETS, q, "--source", "openverse", "--license", "cc0", "--orientation", "portrait",
                        "--min-width", "1000", "--limit", "12", "--no-check", "--json"], capture_output=True, text=True)
    try:
        d = json.loads(r.stdout)
    except ValueError:
        return []
    return [dict(it, q=q) for s in d["sources"] for it in s["items"] if it.get("via") not in SKIP_VIA]


def thumb(it):
    try:
        req = urllib.request.Request(it.get("smaller") or it["image"], headers={"User-Agent": "Mozilla/5.0"})
        im = Image.open(io.BytesIO(urllib.request.urlopen(req, timeout=30).read())).convert("RGB")
        im.thumbnail((300, 450))
        return it, im
    except Exception:
        return it, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("queries", nargs="+")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)

    items, seen = [], set()
    with cf.ThreadPoolExecutor(6) as ex:
        for res in ex.map(search, a.queries):
            for it in res:
                if it["ref"] not in seen:
                    seen.add(it["ref"])
                    items.append(it)
    with cf.ThreadPoolExecutor(12) as ex:
        got = [(it, im) for it, im in ex.map(thumb, items) if im]

    json.dump([it for it, _ in got], open(os.path.join(a.out, "catalog.json"), "w"), indent=1)
    cols, cw, ch, per = 6, 300, 480, 24
    font = ImageFont.load_default()
    for start in range(0, len(got), per):
        chunk = got[start:start + per]
        sheet = Image.new("RGB", (cols * cw, -(-len(chunk) // cols) * ch), "white")
        d = ImageDraw.Draw(sheet)
        for i, (it, im) in enumerate(chunk):
            x, y = (i % cols) * cw, (i // cols) * ch
            sheet.paste(im, (x + (cw - im.width) // 2, y))
            d.text((x + 4, y + 452), f"#{start + i} {it['q'][:22]}", fill="black", font=font)
        path = os.path.join(a.out, f"sheet-{start // per}.jpg")
        sheet.save(path, quality=80)
        print(path)
    print(len(got), "photos")


if __name__ == "__main__":
    main()
