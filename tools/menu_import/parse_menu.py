#!/usr/bin/env python3
"""Turn a photographed or scanned menu into a DRAFT list of products.

OCR (Tesseract, Spanish + English) -> line parser -> JSON draft. The draft is
never imported by this script. A person reads it, fixes it, sets "reviewed": true,
and only then does import_menu.py create FluentCart products (as drafts).

Nothing is guessed: a price that cannot be read with confidence is left null and
flagged in `needs_review`; lines that are not understood go to `unparsed`.

Usage:
  parse_menu.py menu.jpg [--currency CRC] [--lang spa+eng] [-o draft.json]
  parse_menu.py --text menu.txt        # skip OCR, parse already-extracted text
Also importable: parse_text(text, currency) and ocr_image(path, lang).
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

SCHEMA = 1
CURRENCY_SYMBOLS = {"₡": "CRC", "¢": "CRC", "$": "USD", "€": "EUR"}

# A number as printed on a menu: 7.000  7,000  7 000  7000  12.50  12,50
NUM = r"\d{1,3}(?:[.,\s]\d{3})+|\d+(?:[.,]\d{1,2})?"
PRICE_RE = re.compile(
    rf"(?P<sym>[₡¢$€]|CRC|USD|colones)?\s*(?P<num>{NUM})\s*(?P<mil>mil\b)?\s*(?P<sym2>colones|CRC|USD)?",
    re.IGNORECASE,
)
LEADER_RE = re.compile(r"[.…·_\-–—]{2,}|\s{3,}")


def ocr_image(path, lang="spa+eng", psm=6):
    """Run Tesseract on an image and return its text. Raises if tesseract is missing."""
    exe = shutil.which("tesseract")
    if not exe:
        raise RuntimeError("tesseract is not installed (brew/apt install tesseract-ocr)")
    env = dict(os.environ)
    local = os.path.expanduser("~/.local/share/tessdata")
    if os.path.isdir(local) and "TESSDATA_PREFIX" not in env:
        env["TESSDATA_PREFIX"] = local
    have = subprocess.run([exe, "--list-langs"], capture_output=True, text=True, env=env).stdout.split()
    wanted = [l for l in lang.split("+") if l in have] or ["eng"]
    with tempfile.TemporaryDirectory() as tmp:
        src = path
        try:  # upscale small photos: Tesseract reads small text badly
            from PIL import Image, ImageOps

            im = Image.open(path)
            im = ImageOps.exif_transpose(im).convert("L")
            if im.width < 1600:
                f = 1600 / im.width
                im = im.resize((int(im.width * f), int(im.height * f)))
            src = os.path.join(tmp, "in.png")
            im.save(src)
        except ImportError:
            pass
        out = subprocess.run(
            [exe, src, "stdout", "-l", "+".join(wanted), "--psm", str(psm)],
            capture_output=True, text=True, env=env,
        )
        if out.returncode != 0:
            raise RuntimeError(f"tesseract failed: {out.stderr.strip()[:300]}")
        return out.stdout


def _to_number(raw, mil, currency):
    """Return (value, assumption) for a printed number, or (None, reason)."""
    s = raw.strip()
    if mil:
        base = s.replace(",", ".").replace(" ", "")
        try:
            return float(base) * 1000, "read 'mil' as thousands"
        except ValueError:
            return None, f"cannot read '{raw} mil'"
    groups = re.fullmatch(r"\d{1,3}(?:[.,\s]\d{3})+", s)
    if groups:  # 7.000 / 7,000 / 7 000 are thousands separators
        return float(re.sub(r"[.,\s]", "", s)), None
    if re.fullmatch(r"\d+", s):
        v = float(s)
        if currency == "CRC" and v < 100:
            return None, f"'{s}' is too small for colones; maybe 'mil' was dropped"
        return v, None
    m = re.fullmatch(r"(\d+)[.,](\d{1,2})", s)
    if m:
        return float(f"{m.group(1)}.{m.group(2)}"), None
    return None, f"cannot read '{raw}'"


def find_prices(line, currency):
    """All prices on a line: list of dicts with span, value, assumption, currency."""
    found = []
    for m in PRICE_RE.finditer(line):
        num = m.group("num")
        if not num:
            continue
        sym = (m.group("sym") or m.group("sym2") or "").strip()
        cur = CURRENCY_SYMBOLS.get(sym, sym.upper() if sym.upper() in ("CRC", "USD") else None)
        if sym.lower() == "colones":
            cur = "CRC"
        # a bare number with no symbol is a price only if it ends the line/segment
        # or follows a size label; plain numbers inside a description are not.
        has_marker = bool(sym or m.group("mil"))
        value, note = _to_number(num, bool(m.group("mil")), cur or currency)
        found.append({
            "span": m.span(), "raw": m.group(0).strip(), "value": value, "note": note,
            "currency": cur, "marked": has_marker,
        })
    return found


def _clean(s):
    s = LEADER_RE.sub(" ", s)
    s = re.sub(r"\s+", " ", s).strip(" -–—:.,·_|")
    return s


def _is_heading(line):
    t = line.strip()
    if not t or len(t) > 40 or any(ch.isdigit() for ch in t):
        return False
    letters = [c for c in t if c.isalpha()]
    return bool(letters) and (t.isupper() or t.endswith(":"))


def parse_text(text, currency="CRC"):
    items, unparsed, warnings = [], [], []
    section = None
    lines = [l.rstrip() for l in text.splitlines()]
    last = None
    for n, line in enumerate(lines, 1):
        if not line.strip():  # OCR puts blank lines between real lines; keep `last`
            continue
        if _is_heading(line):
            section = _clean(line).title()
            last = None
            continue
        prices = find_prices(line, currency)
        # keep trailing-number prices and marked prices; drop stray numbers mid-text
        end = len(line.rstrip()) - 1
        if prices and prices[-1]["span"][1] >= end:
            # a trailing price makes this a price line; earlier unmarked numbers count only
            # when a label (a size word) sits in front of them: "Pequeña 5.000 Grande 9.000"
            keep, prev_end = [], 0
            for p in prices:
                if p["marked"] or p is prices[-1] or re.search(r"[^\W\d_]", line[prev_end:p["span"][0]]):
                    keep.append(p)
                prev_end = p["span"][1]
            prices = keep
        else:
            prices = [p for p in prices if p["marked"]]
        if not prices:
            if last is not None and len(line.strip()) > 2:  # description of the previous item
                d = _clean(line)
                last["description"] = (last["description"] + " " + d).strip()
                last["line_refs"].append(n)
            else:
                unparsed.append({"line": n, "text": line.strip()})
            continue
        head = _clean(line[: prices[0]["span"][0]])
        if not head and last is not None:  # price on its own line: belongs to the previous item
            for p in prices:
                _attach(last, p, "", currency)
            last["line_refs"].append(n)
            continue
        if not head:
            unparsed.append({"line": n, "text": line.strip()})
            continue
        item = {"name": head, "description": "", "section": section, "price": None,
                "variants": [], "currency": currency, "needs_review": [], "line_refs": [n]}
        if len(prices) == 1:
            _attach(item, prices[0], "", currency)
        else:  # "Pepperoni Pequeña 5.000 Grande 9.000": a size label precedes each price
            words = head.split()
            labels, prev_end = [], prices[0]["span"][1]
            if len(words) >= 2:
                item["name"], first = " ".join(words[:-1]), words[-1]
            else:
                first = ""
            labels.append(first)
            for p in prices[1:]:
                labels.append(_clean(line[prev_end: p["span"][0]]))
                prev_end = p["span"][1]
            for lab, p in zip(labels, prices):
                _attach(item, p, lab, currency)
            if any(not v["label"] for v in item["variants"]):
                item["needs_review"].append("several prices on one line but a size label is missing")
        if not item["variants"] and item["price"] is None:
            item["needs_review"].append("no usable price")
        items.append(item)
        last = item
    for it in items:
        for v in it["variants"]:
            if v["price"] is None and v["note"]:
                it["needs_review"].append(v["note"])
    _flag_symbol_misreads(items, currency)
    if not items:
        warnings.append("no items found: check the photo (flat, lit, whole menu) or paste the text")
    return {"schema": SCHEMA, "currency": currency, "reviewed": False, "items": items,
            "unparsed": unparsed, "warnings": warnings}


def _flag_symbol_misreads(items, currency):
    """OCR often reads the colon sign (₡) as a '2', turning 7.000 into 27.000. A price that
    starts with 2 and is far above the rest of the menu is flagged, with the likely value."""
    vals = sorted(v["price"] for i in items for v in i["variants"] if v["price"])
    if len(vals) < 3:
        return
    median = vals[len(vals) // 2]
    for it in items:
        for v in it["variants"]:
            x = v["price"]
            if x and x > 2.5 * median and str(int(x))[0] == "2" and len(str(int(x))) >= 4:
                alt = int(str(int(x))[1:])
                it["needs_review"].append(
                    f"{int(x)} is far above the rest of the menu; the currency sign may have been read as a '2' (maybe {alt})")


def _attach(item, p, label, currency):
    if p["currency"] and p["currency"] != currency:
        item["needs_review"].append(f"price '{p['raw']}' is in {p['currency']}, expected {currency}")
        p = dict(p, value=None, note="currency mismatch")
    item["variants"].append({"label": label, "price": p["value"], "raw": p["raw"], "note": p["note"]})
    if len(item["variants"]) == 1:
        item["price"] = p["value"]
    else:
        item["price"] = None  # several sizes: no single price
    if p["note"] and p["value"] is not None:
        item["needs_review"].append(p["note"])


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("image", nargs="?")
    ap.add_argument("--text", help="parse this text file instead of running OCR")
    ap.add_argument("--currency", default="CRC")
    ap.add_argument("--lang", default="spa+eng")
    ap.add_argument("-o", "--out")
    a = ap.parse_args(argv)
    if a.text:
        raw = open(a.text, encoding="utf-8").read()
        source = a.text
    elif a.image:
        raw = ocr_image(a.image, a.lang)
        source = a.image
    else:
        ap.error("give an image or --text")
    draft = parse_text(raw, a.currency)
    draft["source"] = os.path.basename(source)
    draft["ocr_text"] = raw
    out = json.dumps(draft, ensure_ascii=False, indent=2)
    if a.out:
        open(a.out, "w", encoding="utf-8").write(out + "\n")
        flagged = sum(1 for i in draft["items"] if i["needs_review"])
        print(f"{len(draft['items'])} items, {flagged} flagged, {len(draft['unparsed'])} unparsed lines -> {a.out}")
    else:
        print(out)


if __name__ == "__main__":
    sys.exit(main())
