# Account modes: who owns sign-up and login

A product has one of two account modes. Pick one per product; it is a pack choice, not a code fork.

| | Mode A: app accounts | Mode B: WordPress accounts (default for any business) |
|---|---|---|
| Who owns sign-up, login, recovery, second factor | The app, on Supabase Auth | WordPress, with FluentAuth |
| In the repo | Built-in password login in the app base code; recovery, magic link and MFA are **not built yet** (planned optional pack) | Pack `wp-fluentauth` plus the WordPress plugin `integrations/rapscalyon-pseudo-sso` |
| Subscriptions and affiliates | Optional FluentCart bridge | FluentCart and AffiliateWP (or FluentAffiliate), already in the commerce stacks ([COMMERCE-STACKS.md](COMMERCE-STACKS.md), [BILLING.md](BILLING.md)) |
| The customer maintains | Nothing extra | A WordPress site and its plugins |
| If WordPress is down | No effect | New app logins and "manage billing" fail; open app sessions continue until their refresh token expires |
| Right for | Internal tools, prototypes, anything with no money | Anything with sales, subscriptions or affiliates |

Mode A is semi-deprecated: it exists so a product with no storefront does not need WordPress.

## Choose
1. **Does the product take money, run subscriptions or pay affiliates?** Yes: Mode B. (Billing and affiliates already live in WordPress; one login for all of it.)
2. **Does the customer already run a WordPress site with FluentAuth?** Yes: Mode B.
3. **Otherwise** (internal tool, demo, prototype): Mode A.
4. **Will users need password recovery or a second factor in the app itself?** Mode B provides both through WordPress. In Mode A the recovery/MFA pack is not built yet, so choose Mode B or wait.

Switching later is supported and keeps the same Supabase user (the join key is the lowercased, verified email). Users moving A to B stop using their app password and sign in on WordPress.

## Mode A: install and verify
Nothing to install: the app base code ships the password login. `python3 tools/rapscalyon.py pack list` should show no pack that declares `[auth]`.
Verify: `/login` shows the form; a new account can sign in; the sign-up button is present.
Not available yet: password recovery, magic link, MFA enrolment in the app. Do not promise them.

## Mode B: install and verify
1. Core and the app are installed as usual. `python3 tools/rapscalyon.py pack add packs/wp-fluentauth --app app`, then `catalog`.
2. App environment: `WP_LOGIN_URL=https://<wordpress>/wp-login.php` (https only). The app's `/login` then redirects there and sign-up is refused.
3. WordPress, from its root with wp-cli: run `integrations/rapscalyon-pseudo-sso/install-wordpress.sh --dry-run` with `RSY_SSO_SUPABASE_URL`, `RSY_SSO_APP_URL` and `RSY_SSO_SERVICE_ROLE_KEY` set, read it, then run it without `--dry-run`. It installs FluentAuth and FluentCart at pinned versions and the plugin, and writes the three constants to `wp-config.php`. AffiliateWP is licensed: install it by hand.
4. Link users to the app with `https://<wordpress>/?rapscalyon_app=1` (a button or menu item); `&next=/path` picks the landing page.
5. Checklist:
   - a new user registers on WordPress and confirms the email;
   - `/?rapscalyon_app=1` lands in the app signed in;
   - `select * from wf_handoffs` shows one row for that user;
   - the same link opened twice fails the second time;
   - a user whose email WordPress has not confirmed is refused (403);
   - `/login` on the app redirects to WordPress.
6. Roll back: `pack remove wp-fluentauth` restores the built-in login; users keep their Supabase accounts.

### Security model (read before choosing Mode B)
- The Supabase service-role key lives in `wp-config.php` on the WordPress host. Anyone who controls that host or a WordPress administrator can open the app as any email. Require two-factor login for administrators (FluentAuth) and keep the host patched.
- The handoff session is `aal1`. Core's MFA gate passes only users with **no** verified Supabase factor, so never enrol Supabase MFA in this mode; second factors live in WordPress.
- The one-time link is redeemed by the app server, never passes through a third-party page, and a replay is rejected.
- Variant considered and not adopted: a ticket exchange through a Supabase Edge Function that keeps the service-role key out of WordPress. Worth revisiting only for many WordPress sites on one shared Supabase project.

## What was verified, and what was not
Verified on 2026-10-08, on a scratch WordPress (FluentAuth 3.0.5, FluentCart 1.7.1) against a local Supabase: the whole Mode B flow in the checklist above, new and existing emails, single-use links, `next` allow-listing, the unverified-user refusal, and an idempotent install script. FluentAuth, FluentCart and AffiliateWP behaviour was read from plugin source, not assumed.

Not verified: the FluentCart event payload shape against a real test subscription; FluentAuth's password-reset screens on a live site; the Playwright end-to-end suite with this pack; any hosted (non-local) Supabase project; the Hostinger "AI Agent" (a vendor claim, never in the install path).
