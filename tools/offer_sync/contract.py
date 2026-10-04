"""Offer draft, schema 1: the shape every part of the offer synchronizer agrees on.

`validate(offer)` returns a list of problems (empty means valid). It is the same contract as
offer.schema.json, written without a dependency so the runner stays a plain stdlib script.
Weekdays are 0 Monday to 6 Sunday; an empty list means every day. Prices are major units.
"""
import re

_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
_TIME = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")
_KEYS = {"schema", "is_offer", "source", "title", "description", "variants", "discount", "currency",
         "weekdays", "time_window", "valid_from", "valid_until", "image", "confidence", "flags"}
_SRC = {"platform", "page_url", "post_id", "post_url", "posted_at"}


def validate(o):
    if not isinstance(o, dict):
        return ["offer must be an object"]
    p = [f"unknown field: {k}" for k in o if k not in _KEYS]
    if o.get("schema") != 1:
        p.append("schema must be 1")
    if not isinstance(o.get("is_offer"), bool):
        p.append("is_offer must be true or false")
    src = o.get("source")
    if not isinstance(src, dict) or set(src) != _SRC:
        p.append("source needs exactly " + ", ".join(sorted(_SRC)))
    else:
        if src["platform"] != "facebook":
            p.append("source.platform must be facebook")
        for k in ("page_url", "post_url"):
            if not str(src[k]).startswith("https://"):
                p.append(f"source.{k} must be https")
        if not src["post_id"] or len(str(src["post_id"])) > 100:
            p.append("source.post_id is required (max 100)")
    if not re.fullmatch(r"[A-Z]{3}", str(o.get("currency", ""))):
        p.append("currency must be a 3-letter code")
    c = o.get("confidence")
    if isinstance(c, bool) or not isinstance(c, (int, float)) or not 0 <= c <= 1:
        p.append("confidence must be 0 to 1")
    if not isinstance(o.get("flags"), list) or not all(isinstance(f, str) and len(f) <= 200 for f in o["flags"]):
        p.append("flags must be a list of short strings")
    if o.get("is_offer") is True:
        t = o.get("title")
        if not isinstance(t, str) or not 1 <= len(t) <= 200:
            p.append("title is required (max 200)")
        if len(o.get("description") or "") > 500:
            p.append("description max 500")
        vs = o.get("variants") or []
        d = o.get("discount")
        if not vs and not d:
            p.append("an offer needs variants with prices or a discount")
        if len(vs) > 10:
            p.append("at most 10 variants")
        for v in vs:
            if not isinstance(v, dict) or set(v) != {"label", "price"} or isinstance(v["price"], bool) \
                    or not isinstance(v["price"], (int, float)) or v["price"] <= 0:
                p.append("each variant needs a label and a positive price")
                break
        if len(vs) > 1 and (not all(v.get("label") for v in vs) or len({v["label"] for v in vs}) != len(vs)):
            p.append("several variants need a distinct label each")
        if d is not None and (not isinstance(d, dict) or d.get("type") not in ("percent", "amount")
                              or not isinstance(d.get("amount"), (int, float)) or d["amount"] <= 0
                              or (d["type"] == "percent" and d["amount"] > 100)):
            p.append("discount needs type percent|amount and a positive amount (percent max 100)")
        wd = o.get("weekdays", [])
        if not isinstance(wd, list) or len(set(wd)) != len(wd) or not all(isinstance(x, int) and not isinstance(x, bool) and 0 <= x <= 6 for x in wd):
            p.append("weekdays must be unique integers 0 (Monday) to 6 (Sunday)")
        tw = o.get("time_window")
        if tw is not None and (not isinstance(tw, dict) or set(tw) != {"from", "to"}
                               or not _TIME.match(str(tw["from"])) or not _TIME.match(str(tw["to"]))):
            p.append("time_window needs from and to as HH:MM")
        vf, vu = o.get("valid_from"), o.get("valid_until")
        for k, v in (("valid_from", vf), ("valid_until", vu)):
            if v is not None and not _DATE.match(str(v)):
                p.append(f"{k} must be YYYY-MM-DD")
        if vf and vu and _DATE.match(str(vf)) and _DATE.match(str(vu)) and vu < vf:
            p.append("valid_until is before valid_from")
    return p
