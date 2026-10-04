#!/usr/bin/env python3
"""Offer sync runner: Facebook posts -> offer drafts -> the shop's FluentCart (fluentcart-offers receiver).

    sync.py shops.json [--state state.json] [--dry-run] [--shop NAME]

shops.json holds no secrets: a list of {name, page_url, page_id, source: "graph"|"scrapecreators", site, currency, user}.
Secrets come from the environment only: RSY_<NAME>_FB_TOKEN (graph), SCRAPECREATORS_API_KEY, RSY_<NAME>_WP_PASSWORD
(application password of the rsy_offer_bot user), ANTHROPIC_API_KEY. Nothing is written except the state file (post ids
already handled). A failing shop never stops the others. Exit 0 = all shops ran, 1 = some shop needs a person, 2 = bad config.
"""
import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import extractor  # noqa: E402
import sources  # noqa: E402

SHOP_KEYS = {"name", "page_url", "page_id", "source", "site", "currency", "user"}


def env_name(shop, suffix):
    return "RSY_" + "".join(c if c.isalnum() else "_" for c in shop["name"].upper()) + "_" + suffix


def load_shops(path):
    shops = json.load(open(path, encoding="utf-8"))
    for s in shops:
        if not SHOP_KEYS <= set(s) or s["source"] not in ("graph", "scrapecreators") or not s["site"].startswith("https://"):
            raise SystemExit(f"bad shop entry: {s.get('name', '?')}")
    return shops


def post_offer(site, user, password, offer, fetch=None):
    """-> (http_status, reply dict). The image, when present, rides inside the offer as {b64, mime}."""
    body = json.dumps(offer).encode()
    auth = base64.b64encode(f"{user}:{password}".encode()).decode()
    req = urllib.request.Request(site.rstrip("/") + "/wp-json/rapscalyon/v1/offers", body,
                                 {"content-type": "application/json", "authorization": "Basic " + auth})
    try:
        with (fetch or urllib.request.urlopen)(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except ValueError:
            return e.code, {}
    except (urllib.error.URLError, TimeoutError):
        return 0, {"status": "network"}


def run_shop(shop, state, env, llm, make_source, poster, downloader, dry=False):
    """-> (report lines, needs_person bool). `state[name]` is the list of handled post ids, updated in place."""
    name, lines, needs = shop["name"], [], False
    seen = set(state.get(name, []))
    try:
        src = make_source(shop, env)
        posts = src.recent(seen=seen)
    except sources.SourceError as e:
        return [f"{name}: {e.kind}: {e}"], e.kind == "reconnect"
    except KeyError as e:
        return [f"{name}: missing secret {e}"], True
    password = env.get(env_name(shop, "WP_PASSWORD"), "")
    for p in reversed(posts):  # oldest first
        offer, why = extractor.extract(p, shop["page_url"], shop["currency"], llm)
        if offer is None:
            lines.append(f"{name} {p['post_id']}: skipped ({why})")
            state.setdefault(name, []).append(p["post_id"])
            continue
        for url in p["image_urls"][:1]:
            img = downloader(url)
            if img:
                offer["image"] = {"b64": base64.b64encode(img[0]).decode(), "mime": {"jpg": "image/jpeg", "png": "image/png", "webp": "image/webp"}[img[1]]}
        if dry:
            lines.append(f"{name} {p['post_id']}: WOULD SEND {offer['title']!r} flags={offer['flags']}")
            continue
        status, reply = poster(shop["site"], shop["user"], password, offer)
        lines.append(f"{name} {p['post_id']}: {status} {reply.get('status', '')}")
        if status in (200, 201, 409) or reply.get("status") in ("ignored", "rejected_earlier"):
            state.setdefault(name, []).append(p["post_id"])
        if status in (401, 403, 422):
            needs = True
            break
        if status == 0 or status >= 500:
            break  # try again next run
    state[name] = state.get(name, [])[-500:]
    return lines, needs


def make_source(shop, env):
    if shop["source"] == "graph":
        return sources.GraphApiSource(shop["page_id"], env[env_name(shop, "FB_TOKEN")])
    return sources.ScrapeCreatorsSource(shop["page_url"], env["SCRAPECREATORS_API_KEY"])


def main(argv=None, env=None):
    env = os.environ if env is None else env
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("shops")
    ap.add_argument("--state", default="offer-sync-state.json")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--shop")
    a = ap.parse_args(argv)
    shops = [s for s in load_shops(a.shops) if not a.shop or s["name"] == a.shop]
    if not env.get("ANTHROPIC_API_KEY"):
        print("missing ANTHROPIC_API_KEY", file=sys.stderr)
        return 2
    try:
        state = json.load(open(a.state))
    except (OSError, ValueError):
        state = {}
    llm = extractor.anthropic_llm(env["ANTHROPIC_API_KEY"])
    bad = False
    for shop in shops:
        lines, needs = run_shop(shop, state, env, llm, make_source, post_offer, sources.download_image, a.dry_run)
        print("\n".join(lines) or f"{shop['name']}: nothing new")
        bad |= needs
    if not a.dry_run:
        tmp = a.state + ".tmp"
        json.dump(state, open(tmp, "w"))
        os.replace(tmp, a.state)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
