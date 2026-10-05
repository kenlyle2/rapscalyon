# Offer sync job (runner-agnostic; OpenClaw schedules it, no GitHub Actions)

Command, every 30 minutes, from the repo root:

    python3 tools/offer_sync/sync.py shops.json --state offer-sync-state.json

Add `--env-file .env.offer-sync` to read secrets from a local file instead of the runner environment (gitignored, template in the repo root). Needs Python 3 stdlib only. `shops.json` has no secrets (copy `shops.example.json`). Secrets are set by the owner
in the runner's environment, never committed:

| Variable | Used for |
|---|---|
| `ANTHROPIC_API_KEY` | the no-tools extraction call (default) |
| `RSY_LLM=deepseek` + `DEEPSEEK_API_KEY` | use DeepSeek instead (model `deepseek-flash`, reads images; override with `DEEPSEEK_MODEL`, `DEEPSEEK_VISION_MODEL`) |
| `SCRAPECREATORS_API_KEY` | default source (`scrapecreators`): reads public posts from the page URL |
| `RSY_<SHOP>_FB_TOKEN` | optional Graph API page token (source `graph`); `<SHOP>` is the shop name upper-cased, non-alphanumerics as `_` |
| `RSY_<SHOP>_WP_PASSWORD` | application password of the shop's `rsy_offer_bot` user |

Exit codes: 0 all shops ran; 1 a shop needs a person (expired Facebook token, bad credentials, wrong currency), see the
printed line; 2 bad config. Rate limits and server errors exit 0 and retry next run. `--dry-run` prints what would be sent and
writes nothing. Keep `offer-sync-state.json` between runs (handled post ids).
