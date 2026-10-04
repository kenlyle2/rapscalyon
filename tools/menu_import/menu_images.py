#!/usr/bin/env python3
"""Cut dish photos out of a menu image and attach each one to the item it sits next to.

Good enough for a business to be live today, not perfect: a person looks at the contact sheet
(images/contact.jpg) and fixes or deletes wrong ones before import. Nothing here is guessed
silently: an ambiguous photo gets `image_review` set on the item.

How it works
1. Tesseract TSV gives a box for every printed line.
2. A photo is a block of colourful or high-contrast pixels that is NOT text. The image is cut
   into cells; cells with texture or colour, outside the text boxes, are joined into blocks.
3. Each item gets a box (its name line plus the description lines below it, up to the next item).
4. Each photo goes to the nearest item box (edge distance, text above/below/beside all count).
   An item keeps its single nearest photo. If a second item is almost as near, the item is flagged.

Usage: menu_images.py menu.jpg draft.json [--out images]   (edits draft.json in place)
"""
import argparse
import difflib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile


def ocr_lines(path, lang="spa+eng", psm=6):
    """Printed lines with boxes, in reading order: [{text, x0, y0, x1, y1}] in original pixels."""
    from PIL import Image, ImageOps

    exe = shutil.which("tesseract")
    if not exe:
        raise RuntimeError("tesseract is not installed")
    env = dict(os.environ)
    local = os.path.expanduser("~/.local/share/tessdata")
    if os.path.isdir(local) and "TESSDATA_PREFIX" not in env:
        env["TESSDATA_PREFIX"] = local
    have = subprocess.run([exe, "--list-langs"], capture_output=True, text=True, env=env).stdout.split()
    wanted = [l for l in lang.split("+") if l in have] or ["eng"]
    im = ImageOps.exif_transpose(Image.open(path)).convert("L")
    scale = 1.0
    if im.width < 1600:
        scale = 1600 / im.width
        im = im.resize((int(im.width * scale), int(im.height * scale)))
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "in.png")
        im.save(src)
        out = subprocess.run([exe, src, "stdout", "-l", "+".join(wanted), "--psm", str(psm), "-c", "tessedit_create_tsv=1"],
                             capture_output=True, text=True, env=env)
    lines = {}
    for row in out.stdout.splitlines()[1:]:
        c = row.split("\t")
        if len(c) < 12 or not c[11].strip() or float(c[10]) < 45:  # low confidence = picture noise, not text
            continue
        key = tuple(c[1:5])  # page, block, paragraph, line
        x, y, w, h = (int(v) / scale for v in c[6:10])
        L = lines.setdefault(key, {"words": [], "x0": x, "y0": y, "x1": x + w, "y1": y + h})
        L["words"].append(c[11])
        L["x0"], L["y0"] = min(L["x0"], x), min(L["y0"], y)
        L["x1"], L["y1"] = max(L["x1"], x + w), max(L["y1"], y + h)
    res = [{"text": " ".join(v["words"]), "x0": v["x0"], "y0": v["y0"], "x1": v["x1"], "y1": v["y1"]}
           for v in lines.values()]
    return sorted(res, key=lambda l: (round(l["y0"] / 8), l["x0"]))


def _norm(s):
    return re.sub(r"[^a-z0-9ñáéíóú ]", "", s.lower()).strip()


def item_boxes(items, lines):
    """Walk the items and the OCR lines in step. An item's box is its name line plus the lines up to
    the next item's name line. Returns {item index: (x0, y0, x1, y1)} for the items that were found."""
    anchors, ptr = {}, 0
    for i, it in enumerate(items):
        want = _norm(it["name"])
        best, best_j = 0.0, None
        for j in range(ptr, min(len(lines), ptr + 12)):
            t = _norm(lines[j]["text"])
            r = 1.0 if want and want in t else difflib.SequenceMatcher(None, want, t[: len(want) + 6]).ratio()
            if r > best:
                best, best_j = r, j
        if best_j is not None and best >= 0.6:
            anchors[i] = best_j
            ptr = best_j + 1
    order = sorted(anchors.items(), key=lambda kv: kv[1])
    boxes = {}
    for k, (i, j) in enumerate(order):
        end = order[k + 1][1] if k + 1 < len(order) else min(len(lines), j + 4)
        end = min(end, j + 4)  # an item's description is a few lines at most
        grp = [lines[j]]
        for l in lines[j + 1:end]:
            if l["text"].isupper():  # a section heading ends the item
                break
            grp.append(l)
        boxes[i] = (min(l["x0"] for l in grp), min(l["y0"] for l in grp),
                    max(l["x1"] for l in grp), max(l["y1"] for l in grp))
    return boxes


def find_photos(path, lines, cell=12):
    """Rectangles (x0, y0, x1, y1) of picture-like blocks outside the text. Needs numpy + Pillow."""
    import numpy as np
    from PIL import Image, ImageOps

    im = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
    W, H = im.size
    a = np.asarray(im, dtype=np.float32)
    gh, gw = H // cell, W // cell
    if gh < 4 or gw < 4:
        return []
    a = a[: gh * cell, : gw * cell]
    cells = a.reshape(gh, cell, gw, cell, 3).transpose(0, 2, 1, 3, 4).reshape(gh, gw, -1, 3)
    lum = cells.mean(axis=3)
    sat = cells.max(axis=3) - cells.min(axis=3)
    busy = (lum.std(axis=2) > 28) | (sat.mean(axis=2) > 45)  # texture or colour
    # a flat background colour (cream paper, a coloured banner) is neither; text edges are removed below
    for l in lines:
        pad = cell
        x0, x1 = int((l["x0"] - pad) // cell), int((l["x1"] + pad) // cell) + 1
        y0, y1 = int((l["y0"] - pad) // cell), int((l["y1"] + pad) // cell) + 1
        busy[max(y0, 0): max(y1, 0), max(x0, 0): max(x1, 0)] = False
    seen = np.zeros_like(busy)
    rects = []
    for sy in range(gh):
        for sx in range(gw):
            if not busy[sy, sx] or seen[sy, sx]:
                continue
            stack, comp = [(sy, sx)], []
            seen[sy, sx] = True
            while stack:
                y, x = stack.pop()
                comp.append((y, x))
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = y + dy, x + dx
                        if 0 <= ny < gh and 0 <= nx < gw and busy[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            stack.append((ny, nx))
            ys, xs = [c[0] for c in comp], [c[1] for c in comp]
            x0, y0, x1, y1 = min(xs) * cell, min(ys) * cell, (max(xs) + 1) * cell, (max(ys) + 1) * cell
            w, h = x1 - x0, y1 - y0
            fill = len(comp) / ((w // cell) * (h // cell))
            # big enough to be a dish, not a line or rule, and mostly filled (text blobs are stringy)
            if w >= W * 0.07 and h >= W * 0.07 and fill >= 0.5 and 0.3 <= w / h <= 3.5:
                rects.append((x0, y0, x1, y1))
    return rects


def _gap(a, b):
    """Distance from a photo to an item box. A photo is usually beside or under its text, so being
    level with the item (centre to centre, vertically) counts most and sideways distance counts little."""
    dx = max(a[0] - b[2], b[0] - a[2], 0)
    dy = abs((a[1] + a[3]) / 2 - (b[1] + b[3]) / 2)
    return dy + 0.25 * dx


def assign(photos, boxes):
    """Each photo to its nearest item box; each item keeps its nearest photo.
    Returns {item index: (photo rect, ambiguous)}."""
    best = {}
    for p in photos:
        ranked = sorted(((_gap(p, b), i) for i, b in boxes.items()))
        if not ranked:
            continue
        d, i = ranked[0]
        amb = len(ranked) > 1 and ranked[1][0] <= max(d * 1.3, d + 20)
        if i not in best or d < best[i][0]:
            best[i] = (d, p, amb)
    return {i: (p, amb) for i, (d, p, amb) in best.items()}


def slug(s):
    s = re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")
    return s or "item"


def snip(path, draft, out="images", lang="spa+eng"):
    """Crop photos from `path`, attach to draft items. Returns a short report."""
    from PIL import Image, ImageDraw, ImageOps

    os.makedirs(out, exist_ok=True)
    lines = ocr_lines(path, lang)
    photos = find_photos(path, lines)
    boxes = item_boxes(draft["items"], lines)
    got = assign(photos, boxes)
    im = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
    used = []
    for i, (rect, amb) in got.items():
        it = draft["items"][i]
        f = f"{slug(it['name'])}.jpg"
        im.crop(rect).save(os.path.join(out, f), quality=88)
        it["image"] = os.path.join(out, f)
        it.pop("image_review", None)
        if amb:
            it["image_review"] = "photo sits between two items; check it belongs to this one"
        used.append(rect)
    # contact sheet for the human check: the menu with each photo outlined and numbered
    sheet = im.copy()
    d = ImageDraw.Draw(sheet)
    for i, b in boxes.items():
        d.rectangle(b, outline=(0, 120, 255), width=2)
    for i, (rect, amb) in got.items():
        d.rectangle(rect, outline=(255, 140, 0) if amb else (0, 170, 0), width=4)
        d.text((rect[0] + 6, rect[1] + 6), draft["items"][i]["name"], fill=(255, 0, 0))
    sheet.thumbnail((1600, 1600))
    sheet.save(os.path.join(out, "contact.jpg"), quality=80)
    return {"photos_found": len(photos), "items_matched": len(boxes), "attached": len(got),
            "ambiguous": sum(1 for _, a in got.values() if a)}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("image")
    ap.add_argument("draft")
    ap.add_argument("--out", default="images")
    ap.add_argument("--lang", default="spa+eng")
    a = ap.parse_args(argv)
    draft = json.load(open(a.draft, encoding="utf-8"))
    rep = snip(a.image, draft, a.out, a.lang)
    json.dump(draft, open(a.draft, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print(json.dumps(rep))
    print(f"contact sheet: {os.path.join(a.out, 'contact.jpg')} (green = attached, orange = check, blue = item text)")


if __name__ == "__main__":
    sys.exit(main())
