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
- Sizes on one line ("Pequeña 5.000 Grande 9.000") become variants, imported as "Name (Size)".
- The import skips flagged items until the reviewer marks `"review_ok": true`, and refuses an unreviewed draft.
- WP-CLI route: refuses if the menu currency differs from the store currency, skips titles that already
  exist, creates drafts only. Store currency on the billing site was USD on 2026-10-04: set it to CRC first.

## Where Pickaxe fits (design, not built)
- The agent already sees an uploaded image, so it can transcribe a menu itself. This tool adds the part a
  model is bad at: deterministic price parsing, the checks above, and a file format FluentCart accepts.
- To call it from an agent, wrap `parse_text` (and `ocr_image`) in a small HTTPS endpoint that returns the draft
  JSON, and register it as a Pickaxe action. Not built: it needs somewhere to run (the machine with Tesseract)
  and an action key kept in Pickaxe's secret control.
- **The agent gets no WP-CLI or shell access.** Menu text and photos come from outside, and a prompt-injected
  agent with a shell on a live store could do anything the site user can. The agent produces the draft; a person
  reviews it; the client uploads the CSV, or the operator runs `--apply`.

## Not done
- FluentCart's own CSV screen was not tested with this CSV (column mapping is done in its UI).
- Sizes are separate products, not one product with variations; FluentCart's bulk-insert service supports
  `simple_variations` and would be the better target.
- Only tested on one synthetic image; real phone photos (curved, shadowed, handwritten) will need work.
- No PDF input yet.
