# Menu to FluentCart products

Photo or scan of a menu -> OCR -> reviewed draft -> FluentCart products (as drafts).

```
parse_menu.py menu.jpg -o draft.json      # OCR (Tesseract spa+eng) and parse; never imports
  (a person edits draft.json, sets "reviewed": true, and fixes or approves every flagged item)
import_menu.py draft.json --csv products.csv      # client route: upload in FluentCart, "Import a CSV"
import_menu.py draft.json --apply --ssh HOST --path WP_PATH   # operator route: WP-CLI, drafts only
```

Needs `tesseract` (with the `spa` language file) and Pillow for the photo clean-up. The parser tests
run without either: `python3 -m unittest discover -s tests`. `tests/make_sample.py` draws a made-up
Spanish menu for a full OCR run.

## What it refuses to guess
- A price it cannot read stays empty and is flagged. "12" in a colones menu is not read as 12 colones.
- "7 mil" is read as 7,000 but flagged.
- OCR often reads the colon sign as a "2" (7.000 becomes 27.000). A price far above the rest of the menu
  that starts with 2 is flagged with the likely value. This happened in the first test run.
- Sizes on one line become variants of one product.
- The import skips flagged items until the reviewer marks `"review_ok": true`, and refuses an unreviewed draft.
- WP-CLI route: refuses if the menu currency differs from the store currency, skips titles that already
  exist, creates drafts only. Store currency on the billing site was USD on 2026-10-04: set it to CRC first.

## Sizes, photos, categories
- **Sizes** ("Pequeña 5.000 Grande 9.000") become ONE product with `simple_variations`, one variant per size. Read from
  FluentCart 1.7.0 `BulkProductInsertService::insertSingleProduct`; `item_price` is in minor units (7000 CRC = 700000).
  The product's min/max price and default variant are derived by FluentCart itself.
- **Photos**: `menu_images.py menu.jpg draft.json` finds picture blocks (colour/texture outside the printed text), crops them,
  and attaches each to the nearest item (level with its text counts most). Ambiguous ones get `image_review`; the
  import drops an unchecked photo unless the reviewer sets `image_ok: true`. `images/contact.jpg` is the check sheet.
  FluentCart takes a `gallery` of `{id, url}`; the apply route uploads each crop to the media library first.
- **Categories**: the menu section ("Pizzas") becomes a FluentCart product category.
- `import_menu.py draft.json --json payload.json` writes the exact bulk-insert payload (the REST route, no SSH).

## Reuse check: existing AI features on the billing site (2026-10-04, plugin source read)
- **Hostinger AI Assistant 3.1.2**: "Create product with AI" (description from a short brief, length and tone, featured image) is a metabox on the WooCommerce `product` post type only; its content generator accepts only `post`, `product` and `page`. FluentCart products are `fluent-products`, so it never appears on them. Its MCP server has generic post-type list/search tools plus Woo-specific product tools; none create FluentCart variants. Hostinger's site Builder generated 0 products here.
- **FluentCart 1.7.0**: no AI description writer. Its MCP module (off by default, Settings, Features & addon) has product tools that are read-only (list, get, inventory).
- Result: nothing to reuse for importing or describing FluentCart products. The importer only uses printed text for descriptions; an optional "draft descriptions" step is a product decision for the owner, not built.
- A stylised social post (a promo image) is not a menu: OCR returned noise, the parser kept one flagged junk item and nothing would import. Reading art like that is the Pickaxe's job (vision), which is why the Importer Pickaxe exists.

## Where Pickaxe fits
- Recommended: a separate **Product Importer** Pickaxe. The agent reads the menu image
  and produces the draft; this tool's parser and checks do the deterministic part; a person reviews; the OPERATOR runs
  `--apply`. The agent holds no SSH key: menu text and photos are untrusted input, and a prompt-injected agent with a
  shell on a live store can do anything the site user can.
- Client-run alternative needing no key at all: the draft becomes `payload.json`, uploaded through FluentCart's own
  screen or posted to `POST /fluent-cart/v2/products/bulk-insert` with an application password the client creates.

## Not done
- Live run done 2026-10-04 on the billing site (store currency now CRC): one product with two variants, minor-unit prices, gallery photo and categories all verified, test products removed.
- FluentCart's own CSV screen was not tested with this CSV.
- Photo detection tested on one synthetic image; real photos with backgrounds and overlapping pictures need tuning.
- No PDF input yet.
