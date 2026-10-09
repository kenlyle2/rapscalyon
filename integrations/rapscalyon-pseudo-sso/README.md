# rapscalyon-pseudo-sso (WordPress plugin, account mode B)

Hands a logged-in WordPress user with a confirmed email to the app as a Supabase session: `https://<wordpress>/?rapscalyon_app=1[&next=/path]`. Pairs with the `wp-fluentauth` pack (`/api/wp-fluentauth/confirm`). Full steps and checklist: `packs/wp-fluentauth/docs/README.md`.

- Needs `RSY_SSO_SUPABASE_URL`, `RSY_SSO_SERVICE_ROLE_KEY`, `RSY_SSO_APP_URL` as constants in `wp-config.php`. `install-wordpress.sh --dry-run` sets them from the environment.
- An email counts as confirmed when FluentAuth's signup verification or a WordPress password reset proved the mailbox (usermeta `rsy_sso_verified_email`). Users created some other way must reset their password once.
- Tested: Supabase side against a local stack (new email creates user and profile, `signup` vs `magiclink` token type, `aal1`, single use) and the app route against `next dev`. Not yet run inside a live WordPress.
