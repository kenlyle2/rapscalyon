# Security: interior-designs

- Clients can only read jobs of their own subjects. All writes go through `idg_request_design` (checks login, subject access and MFA) or service-role functions, which no API role can execute.
- Charge happens in the same transaction as job creation; refund is derived from the charge key and runs once.
- The reference and result keys are storage keys (character allow-list, no `..`), never URLs or data URLs. The BuilderKit original stored the reference image inside the row.
- `idg_record_design` and the executor functions are service-role only; the ingest API that calls them must authenticate the end user itself (a model-filled action input is not identity).
- No webhook secret or model key is stored. The executor checks the webhook signature (the original did not).
- Known gaps: storage bucket policies, per-subject rate limits beyond core's daily and monthly limits, executor not written.


## Ingest API (0.2.0)

- Shared-secret authentication, constant time; no secret, no processing. Rate limiting is not built: the secret is the only gate.
- The email is trusted only because it arrives from Pickaxe's runtime through the action holding the secret. Anyone holding the secret can claim any confirmed email, so the secret must stay in Pickaxe's secret control and rotate if exposed.
- Only confirmed emails resolve (`idg_resolve_user`); no account is ever created or linked by this route. Guests are refused.
- Source downloads defend against server-side request forgery: https only, an allowlist of hosts (exact or subdomain), no credentials or ports, no redirects, a 12 MB cap and a 20 second timeout. File type comes from the bytes, never the header.
- Object keys are built from the subject id and a hash of the response id, so a caller cannot choose a key (the database also refuses `..` and odd characters).
- `idg_resolve_user` and `idg_ensure_subject` are service-role only (execute revoked from public, anon and authenticated), tested.
- Errors never echo the secret, the email or storage keys. Open: per-user rate limits, an audit trail of ingest calls.
