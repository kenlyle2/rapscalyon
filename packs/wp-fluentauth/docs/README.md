# wp-fluentauth (account mode B)

WordPress owns sign-up, login, recovery and MFA (FluentAuth). The app owns nothing of that: `/login` redirects to the WordPress login page (`WP_LOGIN_URL`), the sign-up button is hidden and the sign-up action refuses.

## How a user gets in
1. Signs up or logs in on WordPress (FluentAuth).
2. Opens `https://<wordpress>/?rapscalyon_app=1` (a button or menu link). The WordPress plugin `integrations/rapscalyon-pseudo-sso` checks the email is confirmed, asks Supabase for a single-use link for that email, and sends the browser to `/api/wp-fluentauth/confirm`.
3. The confirm route redeems the token (`verifyOtp`), sets the Supabase session cookies, records the handoff in `wf_handoffs`, and redirects to a local `next` path.

A first-time email gets its Supabase user and profile created by Supabase at step 2 (tested on local Supabase, 2026-10-08).

## Install
1. `python3 tools/rapscalyon.py pack add packs/wp-fluentauth` (then `catalog`).
2. App environment: `WP_LOGIN_URL=https://<wordpress>/wp-login.php` (https only).
3. WordPress: from the WordPress root with wp-cli, `RSY_SSO_SUPABASE_URL=... RSY_SSO_APP_URL=... RSY_SSO_SERVICE_ROLE_KEY=... integrations/rapscalyon-pseudo-sso/install-wordpress.sh --dry-run`, read it, then run without `--dry-run`. AffiliateWP is licensed: install it by hand.
4. Checklist: (a) a new test user registers on WordPress and confirms the email; (b) `/?rapscalyon_app=1` lands in the app signed in; (c) `select * from wf_handoffs` shows one row; (d) the same link opened twice fails the second time; (e) an unconfirmed user is refused; (f) `/login` on the app redirects to WordPress.

## Rules
- Do not enrol Supabase MFA factors in this mode. The handoff session is `aal1`; core's gate passes only users with no verified factor. Second factors live in WordPress (FluentAuth).
- Not for use with the Mode A pack: two login declarations are rejected by the installer.

## Remove
`pack remove wp-fluentauth` restores the built-in login. Users keep their Supabase accounts and can use the Mode A recovery pack's password reset.
