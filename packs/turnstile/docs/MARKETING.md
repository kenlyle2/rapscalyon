# Bot protection with Turnstile
> Verify Cloudflare Turnstile tokens on the server, log abuse safely, and slow repeat offenders.

## Who it's for
Any public form: signup, contact, lead capture, comment, waitlist.

## What you get
- A ready `/api/turnstile/verify` route.
- Failure log keyed by an HMAC of the visitor's IP (never the raw address), readable by admins only.
- Automatic throttling after repeated failures and a nightly purge.

## Works well with
every public entry point; especially signup and real-estate-listings enquiries.

## Under the hood
Verification happens server-side only. Raw IPs are never stored, and retention defaults to 30 days.
