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
import subprocess
import sys


def plan(draft):
    """Return (products, skipped) from a reviewed draft. Prices are in major units."""
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
        variants = it.get("variants") or []
        priced = [v for v in variants if v.get("price")]
        if not priced:
            skipped.append((name, "no price"))
            continue
        for v in priced:
            title = name if len(variants) == 1 else f"{name} ({v['label']})" if v.get("label") else name
            if v["price"] <= 0:
                skipped.append((title, "price not positive"))
                continue
            products.append({"title": title[:200], "price": float(v["price"]),
                             "description": (it.get("description") or "")[:500],
                             "section": it.get("section") or ""})
    titles = [p["title"] for p in products]
    dup = {t for t in titles if titles.count(t) > 1}
    if dup:
        raise SystemExit(f"refusing: duplicate product titles in the draft: {sorted(dup)}")
    return products, skipped


PHP = r"""
use FluentCart\App\Models\ProductDetail;
use FluentCart\App\Models\ProductVariation;
use FluentCart\App\Helpers\CurrenciesHelper;
$data = json_decode(base64_decode(getenv('MENU_B64')), true);
$store = get_option('fluent_cart_store_settings');
$cur = $store['currency'] ?? '';
if ($cur !== $data['currency']) { echo "REFUSED: store currency is $cur, menu is {$data['currency']}\n"; return; }
$mult = CurrenciesHelper::isZeroDecimal($cur) ? 1 : 100;
foreach ($data['products'] as $p) {
  $exists = get_posts(['post_type' => 'fluent-products', 'title' => $p['title'], 'post_status' => 'any', 'numberposts' => 1]);
  if ($exists) { echo "skip (exists): {$p['title']}\n"; continue; }
  $id = wp_insert_post(['post_title' => $p['title'], 'post_name' => sanitize_title($p['title']),
    'post_status' => 'draft', 'post_type' => 'fluent-products', 'post_excerpt' => $p['description']]);
  if (is_wp_error($id) || !$id) { echo "FAILED: {$p['title']}\n"; continue; }
  $cents = (int) round($p['price'] * $mult);
  $d = ProductDetail::query()->create(['post_id' => $id, 'fulfillment_type' => 'physical', 'variation_type' => 'simple',
    'min_price' => $cents, 'max_price' => $cents]);
  $v = ProductVariation::query()->create(['post_id' => $id, 'serial_index' => 1, 'variation_title' => $p['title'],
    'stock_status' => 'in-stock', 'payment_type' => 'onetime', 'fulfillment_type' => 'physical',
    'item_price' => $cents, 'item_status' => 'active',
    'other_info' => ['description' => '', 'payment_type' => 'onetime', 'tax_class' => 'standard', 'tax_exempt' => 'no',
      'times' => '', 'repeat_interval' => '', 'trial_days' => '', 'billing_summary' => '', 'manage_setup_fee' => 'no',
      'signup_fee_name' => '', 'signup_fee' => '', 'setup_fee_per_item' => 'no', 'is_bundle_product' => 'no']]);
  $d->default_variation_id = $v->id; $d->save();
  echo "created draft #$id: {$p['title']} = $cents (minor units)\n";
}
"""


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("draft")
    ap.add_argument("--csv", help="write the reviewed products to this CSV instead of importing")
    ap.add_argument("--apply", action="store_true", help="actually create the draft products")
    ap.add_argument("--ssh", help="ssh host alias of the hosting account")
    ap.add_argument("--path", help="WordPress path on that host")
    a = ap.parse_args(argv)
    draft = json.load(open(a.draft, encoding="utf-8"))
    products, skipped = plan(draft)
    for p in products:
        print(f"WILL CREATE  {p['title']:<40} {p['price']:>10,.2f} {draft['currency']}")
    for name, why in skipped:
        print(f"SKIPPED      {name}: {why}")
    print(f"{len(products)} to create, {len(skipped)} skipped")
    if a.csv:
        import csv
        with open(a.csv, "w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh)
            w.writerow(["Title", "Description", "Section", "Price", "Currency", "Status"])
            for p in products:
                w.writerow([p["title"], p["description"], p["section"], f"{p['price']:g}", draft["currency"], "draft"])
        print(f"wrote {len(products)} rows to {a.csv}")
        return 0
    if not a.apply:
        print("dry run: nothing written (use --apply)")
        return 0
    if not (a.ssh and a.path):
        raise SystemExit("--apply needs --ssh and --path")
    import base64
    payload = base64.b64encode(json.dumps({"currency": draft["currency"], "products": products}).encode()).decode()
    cmd = f"cd {a.path} && MENU_B64={payload} wp eval \"$(cat)\""
    r = subprocess.run(["ssh", a.ssh, cmd], input=PHP, capture_output=True, text=True)
    sys.stdout.write("\n".join(l for l in r.stdout.splitlines() if not l.startswith("Warning")) + "\n")
    if r.returncode != 0:
        sys.stderr.write(r.stderr[-500:])
    return r.returncode


if __name__ == "__main__":
    sys.exit(main())
