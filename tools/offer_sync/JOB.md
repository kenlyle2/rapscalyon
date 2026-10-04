# Offer sync job (runner-agnostic; OpenClaw schedules it, no GitHub Actions)

Command, every 30 minutes, from the repo root:

    python3 tools/offer_sync/sync.py shops.json --state offer-sync-state.json

Needs Python 3 stdlib only. `shops.json` has no secrets (copy `shops.example.json`). Secrets are set by the owner
in the runner's environment, never committed:

| Variable | Used for |
|---|---|
| `ANTHROPIC_API_KEY` | the no-tools extraction call |
| `RSY_<SHOP>_FB_TOKEN` | Graph API page token (source `graph`); `<SHOP>` is the shop name upper-cased, non-alphanumerics as `_` |
| `SCRAPECREATORS_API_KEY` | fallback source (`scrapecreators`) |
| `RSY_<SHOP>_WP_PASSWORD` | application password of the shop's `rsy_offer_bot` user |

Exit codes: 0 all shops ran; 1 a shop needs a person (expired Facebook token, bad credentials, wrong currency), see the
printed line; 2 bad config. Rate limits and server errors exit 0 and retry next run. `--dry-run` prints what would be sent and
writes nothing. Keep `offer-sync-state.json` between runs (handled post ids).
