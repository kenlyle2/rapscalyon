# consents

A ledger of who agreed to what. One row per event: a grant or a withdrawal, for one purpose, for one person, with the source, the wording version they saw and the evidence. The current answer is the latest row for that person and purpose.

- `person_id` optionally names the person row (from the `people` pack, same subject enforced). `person_key` stays because an inbound STOP only knows a phone number. Erasing the person keeps the ledger row and clears `person_id`.
- `purpose` is a lowercase token you choose (`sms_messages`, `whatsapp_messages`, `email_marketing`, `session_recording`, `health_data`). The pack fixes none of them.
- `person_key` identifies the person by what you contact them on: an E.164 phone number or a lowercased email address. It must already be trimmed and lowercased, so one person is one key.
- `cn_has_consent(subject, purpose, key)` answers true only when the latest row is a grant. A sender calls it before every message; no row means no consent.
- `cn_withdraw(...)` is for the service role: an inbound STOP reply records a withdrawal even when no user is signed in. It is idempotent and records nothing for someone who never consented.
- Users record grants and withdrawals as new rows. Nothing is edited or deleted; the ledger is the evidence.

A message-sending pack should refuse to send unless `cn_has_consent` is true, and should call `cn_withdraw` from its inbound webhook. This pack does not send anything and does not know any provider.
