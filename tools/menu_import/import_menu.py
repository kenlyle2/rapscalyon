#!/usr/bin/env python3
"""Create FluentCart products (as DRAFTS) from a menu draft that a person has reviewed.

Input: the JSON written by parse_menu.py after a human edited it and set "reviewed": true.
Default is a dry run that prints the plan. With --apply it runs a generated PHP script on the
billing site through WP-CLI over SSH. It only ever creates draft products; nothing goes live
until the owner publishes them in WordPress.

Safety rules (each one refuses rather than guesses):
- "reviewed" must be true.
- An item with needs_review is skipped unless the reviewer set "review_ok": true on it.
- An item with no price is skipped.
- The menu currency must equal the store's currency (checked on the site before any write).
- A product whose title already exists is skipped, so a re-run does not duplicate.
- This script is run by the operator. The AI agent never receives shell or WP-CLI access.

Usage:
  import_menu.py draft.json                              # dry run
  import_menu.py draft.json --apply --ssh rapscalyon --path domains/billing.example.com/public_html
  import_menu.py draft.json --csv products.csv           # for FluentCart's own "Import a CSV" screen

The CSV route needs no shell access at all, so the client can upload it themselves in
FluentCart (Products, Import a CSV) and map the columns there. Prices in the CSV are in
major units (7000 means 7,000 CRC); check the store currency first.
"""
import argparse
import json
import os
import subprocess
import sys


def plan(draft):
    """Return (products, skipped) from a reviewed draft. Prices are in major units.

    One product per menu item. An item with several sizes becomes ONE product with
    `simple_variations`: one variant per size, titled by the size label."""
    if draft.get("schema") != 1:
        raise SystemExit("unsupported draft schema")
    if draft.get("reviewed") is not True:
        raise SystemExit('refusing: the draft is not marked "reviewed": true (a person must check it first)')
    products, skipped = [], []
    for it in draft.get("items", []):
        name = (it.get("name") or "").strip()
        if not name:
            skipped.append(("(no name)", "empty name"))
            continue
        if it.get("needs_review") and it.get("review_ok") is not True:
            skipped.append((name, "needs_review: " + "; ".join(it["needs_review"])))
            continue
        if it.get("image_review") and it.get("image_ok") is not True:
            it = dict(it, image=None)  # an unchecked photo is dropped, the product is still created
        priced = [v for v in (it.get("variants") or []) if v.get("price")]
        if not priced:
            skipped.append((name, "no price"))
            continue
        if any(v["price"] <= 0 for v in priced):
            skipped.append((name, "price not positive"))
            continue
        labels = [(v.get("label") or "").strip() for v in priced]
        if len(priced) > 1 and (not all(labels) or len(set(labels)) != len(labels)):
            skipped.append((name, "several prices need a distinct size label each"))
            continue
        products.append({
            "title": name[:200],
            "description": (it.get("description") or "")[:500],
            "section": it.get("section") or "",
            "variants": [{"label": l if len(priced) > 1 else name[:200], "price": float(v["price"])}
                         for l, v in zip(labels, priced)],
            "image": it.get("image") or None,
        })
    titles = [p["title"] for p in products]
    dup = {t for t in titles if titles.count(t) > 1}
    if dup:
        raise SystemExit(f"refusing: duplicate product titles in the draft: {sorted(dup)}")
    return products, skipped


def bulk_payload(products, minor_factor, image_ids=None):
    """The exact structure FluentCart's BulkProductInsertService::insertChunk takes.
    `image_ids` maps a product title to {id, url} of an uploaded media item."""
    image_ids = image_ids or {}
    out = []
    for n, p in enumerate(products):
        many = len(p["variants"]) > 1
        item = {
            "_cid": f"menu-{n}",
            "post_title": p["title"],
            "post_excerpt": p["description"],
            "post_status": "draft",
            "detail": {"fulfillment_type": "physical", "variation_type": "simple_variations" if many else "simple"},
            "variants": [{"variation_title": v["label"], "item_price": int(round(v["price"] * minor_factor)),
                          "other_info": {"payment_type": "onetime"}} for v in p["variants"]],
        }
        if p["section"]:
            item["categories"] = [p["section"]]
        if p["title"] in image_ids:
            item["gallery"] = [dict(image_ids[p["title"]], title=p["title"])]
        out.append(item)
    return out


PHP = r"""
use FluentCart\App\Services\BulkProductInsertService;
use FluentCart\App\Helpers\CurrenciesHelper;
$data = json_decode(base64_decode(getenv('MENU_B64')), true);
$store = get_option('fluent_cart_store_settings');
$cur = $store['currency'] ?? '';
if ($cur !== $data['currency']) { echo "REFUSED: store currency is $cur, menu is {$data['currency']}\n"; return; }
$mult = CurrenciesHelper::isZeroDecimal($cur) ? 1 : 100;
$admins = get_users(['role' => 'administrator', 'number' => 1, 'fields' => 'ID']);
wp_set_current_user((int) $admins[0]);
require_once ABSPATH . 'wp-admin/includes/file.php';
require_once ABSPATH . 'wp-admin/includes/media.php';
require_once ABSPATH . 'wp-admin/includes/image.php';
$todo = [];
foreach ($data['products'] as $p) {
  if (get_posts(['post_type' => 'fluent-products', 'title' => $p['post_title'], 'post_status' => 'any', 'numberposts' => 1])) {
    echo "skip (exists): {$p['post_title']}\n"; continue;
  }
  if (!empty($p['_image_file']) && file_exists($p['_image_file'])) {
    $tmp = ['name' => basename($p['_image_file']), 'tmp_name' => $p['_image_file']];
    $aid = media_handle_sideload($tmp, 0, $p['post_title']);
    if (!is_wp_error($aid)) { $p['gallery'] = [['id' => $aid, 'url' => wp_get_attachment_url($aid), 'title' => $p['post_title']]]; }
    else { echo "image failed for {$p['post_title']}: " . $aid->get_error_message() . "\n"; }
  }
  unset($p['_image_file']);
  foreach ($p['variants'] as &$v) { $v['item_price'] = (int) round($v['item_price'] / 100 * $mult); }
  unset($v);
  $todo[] = $p;
}
$svc = new BulkProductInsertService();
foreach (array_chunk($todo, 10) as $chunk) {
  $r = $svc->insertChunk($chunk);
  foreach ($r['created'] as $c) { echo "created draft #{$c['id']} ({$c['_cid']})\n"; }
  foreach ($r['errors'] as $e) { echo "ERROR {$e['title']}: {$e['message']}\n"; }
}
"""


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("draft")
    ap.add_argument("--json", help="write the FluentCart bulk-insert payload (REST or Pickaxe route) to this file")
    ap.add_argument("--csv", help="write a plain CSV of the reviewed products instead of importing")
    ap.add_argument("--apply", action="store_true", help="actually create the draft products")
    ap.add_argument("--ssh", help="ssh host alias of the hosting account")
    ap.add_argument("--path", help="WordPress path on that host")
    a = ap.parse_args(argv)
    draft = json.load(open(a.draft, encoding="utf-8"))
    base = os.path.dirname(os.path.abspath(a.draft))
    products, skipped = plan(draft)
    for p in products:
        sizes = ", ".join(f"{v['label']} {v['price']:,.0f}" for v in p["variants"]) if len(p["variants"]) > 1 \
            else f"{p['variants'][0]['price']:,.0f}"
        print(f"WILL CREATE  {p['title']:<28} {sizes} {draft['currency']}{'  +photo' if p['image'] else ''}")
    for name, why in skipped:
        print(f"SKIPPED      {name}: {why}")
    print(f"{len(products)} to create, {len(skipped)} skipped")
    if a.json:
        json.dump({"products": bulk_payload(products, 100)}, open(a.json, "w"), ensure_ascii=False, indent=2)
        print(f"wrote bulk-insert payload to {a.json}")
        return 0
    if a.csv:
        import csv
        with open(a.csv, "w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh)
            w.writerow(["Title", "Variation", "Description", "Section", "Price", "Currency", "Status"])
            for p in products:
                for v in p["variants"]:
                    w.writerow([p["title"], v["label"] if len(p["variants"]) > 1 else "", p["description"],
                                p["section"], f"{v['price']:g}", draft["currency"], "draft"])
        print(f"wrote {a.csv}")
        return 0
    if not a.apply:
        print("dry run: nothing written (use --apply)")
        return 0
    if not (a.ssh and a.path):
        raise SystemExit("--apply needs --ssh and --path")
    import base64
    remote = f"/tmp/menu-import-{os.getpid()}"
    payload_products = bulk_payload(products, 100)
    imgs = [(pl, p["image"]) for pl, p in zip(payload_products, products) if p["image"]]
    if imgs:
        subprocess.run(["ssh", a.ssh, f"mkdir -p {remote}"], check=True)
        for n, (pl, img) in enumerate(imgs):
            src = img if os.path.isabs(img) else os.path.join(base, img)
            dst = f"{remote}/{n}-{os.path.basename(src)}"
            subprocess.run(["scp", "-q", src, f"{a.ssh}:{dst}"], check=True)
            pl["_image_file"] = dst
    payload = base64.b64encode(json.dumps({"currency": draft["currency"], "products": payload_products}).encode()).decode()
    cmd = f"cd {a.path} && MENU_B64={payload} wp eval \"$(cat)\""
    r = subprocess.run(["ssh", a.ssh, cmd], input=PHP, capture_output=True, text=True)
    sys.stdout.write("\n".join(l for l in r.stdout.splitlines() if not l.startswith("Warning")) + "\n")
    if imgs:
        subprocess.run(["ssh", a.ssh, f"rm -rf {remote}"])
    if r.returncode != 0:
        sys.stderr.write(r.stderr[-500:])
    return r.returncode


if __name__ == "__main__":
    sys.exit(main())
