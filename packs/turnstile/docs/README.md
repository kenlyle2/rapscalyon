# turnstile

Server-side Turnstile verification is app code (POST the token to Cloudflare `siteverify` with `TURNSTILE_SECRET_KEY`).
This pack gives that code somewhere to record failures and ask "how many recent failures from this client?":
`ts_record_failure(action, ip_hash, reason, profile?)`, `ts_recent_failures(ip_hash, minutes)`, nightly `ts_purge_old`.
Hash the IP (HMAC with a server secret) before calling; raw IPs are never stored.
