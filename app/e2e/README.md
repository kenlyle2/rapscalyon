# UI end-to-end test

Drives the shell and every pack page in a headless browser against a hosted or local Supabase project that has all packs installed.
1. Create a confirmed user `e2e@example.test` / `E2e-pass-12345` (admin API) and set `profiles.is_admin = true` for it.
2. `cd app && npx next dev -p 3057` with `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` set.
3. `npm i playwright` somewhere and run `node e2e/ui.e2e.mjs`.

## Interview API check
`node e2e/interview.e2e.mjs` against `next dev` (port 3058, `INTERVIEW_API_KEY=test-key INTERVIEW_SIGNING_KEY=<any>`): auth mode, store, affiliates, unmatched needs, and the confirm ticket. No database or browser needed.
