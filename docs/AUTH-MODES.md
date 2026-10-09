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

## Hostinger: creating the WordPress site for Mode B
Verified read-only on 2026-10-09 through the Hostinger MCP. The OAuth grant covers whichever Hostinger account you sign in as: the first sign-in reached a different account (plan `cloud_economy_v2`, about 30 WordPress sites, several for other people), the second the RapScalYon account (one active order, plan `hostinger_business_v5`, two WordPress installations: `billing.rapscalyon.com` and `accounts.tatplat.shop`; the same order also holds `rapscalyon.surf` as a Node.js site). Check which account the MCP is on (`hosting_orders_list`) before any write, and name the domain in every call.

Steps. Each is an API operation (`search`, then `execute`) or a manual hPanel step:
1. **Domain.** Use a domain or subdomain the customer controls (a billing subdomain such as `billing.<customer-domain>`). If it is not registered at Hostinger, point its DNS where its nameservers are; `dns_records_*` only works for domains in the Hostinger portfolio (details in `CLIENT-SITES.md` in the private `rapscalyon-px-app` repo).
2. **Website.** `hosting_websites_create`, then poll `hosting_websites_list-setups` with the domain until `status: completed`. Calls made earlier answer 404 or 409.
3. **WordPress.** `wordpress_installations_list` filtered by `username` and `domain` first (an existing install makes the job fail unless `overwrite` is true; never set it on a site with content). Then `wordpress_installations_install` (needs `username`, `domain`, `site_title`, `credentials`). It returns "queued"; poll the list until the install appears. A new database counts against the plan's database limit (422 when full). The admin password goes in the call, so use a generated one, store it in the customer's password manager and never in a repo or a log.
4. **Plugins and constants.** Over SSH, from the WordPress root, run `integrations/rapscalyon-pseudo-sso/install-wordpress.sh --dry-run`, read it, then run it for real (section "Mode B: install and verify", step 3). AffiliateWP is installed by hand until a process for it is built; the licence is held (see [ARCHITECTURE.md](ARCHITECTURE.md)).
5. **Validate.** `wordpress_installations_check-if-are-valid` (needs the installation `id` from the list) reports missing files or broken plugins. Then run the Mode B checklist above.
6. **App.** Set `WP_LOGIN_URL` on the app host. For a Node.js app on Hostinger, `hosting_nodejs_replace-environment-variables` replaces the whole set and masks values on read, so a read-modify-write is impossible; use the hPanel for one variable, or supply the full set.

**Tried on 2026-10-09 on a scratch site** (`rsy-wptest-1009.hostingersite.com`, Business plan; a temporary `*.hostingersite.com` name works as the domain and is reachable at once):
- `hosting_websites_create` was accepted and the setup was `completed` within seconds. `wordpress_installations_install` needs `credentials.login`, `credentials.password` and `credentials.email` (not the names the schema text suggests); WordPress answered on `/wp-login.php` in about a minute.
- `wordpress_installations_list` did not show the new install until `wordpress_installations_detect` ran for the account. Run detect, then list.
- `wordpress_plugins_install` with `fluent-security` and `fluent-cart` returned `HTTP 500 Request failed`, yet both were installed and active (FluentAuth 3.0.5, FluentCart 1.7.1, the pinned versions). Never trust that 500; check `wordpress_plugins_list-installed`.
- Our own plugin: `hosting_files_generate-upload-url` (returns an upload URL and two auth keys, valid for hours; treat them as secrets), upload with the documented TUS `curl`, then `wordpress_plugins_deploy`. `plugin_path` is relative to `wp-content/plugins`, and deploy moves that folder to `plugins/<slug>`. Pointing it at the final folder renames the existing one to `<slug>-old-<hash>` and fails with a 500; upload to a staging folder (`wp-content/plugins/rsy-upload/`) and deploy that. The plugin then loaded and answered `/?rapscalyon_app=1` with its "App launch is not configured" 500, as designed.
- `install-wordpress.sh --dry-run` ran over SSH on that site and printed the expected `wp` commands. wp-config constants have no API operation: they are set by the script over SSH (or by hand).
- Not run: the constants with a real Supabase project, the Mode B checklist on this site, and the Hostinger AI Agent. Whether the install API works the same on every plan is unknown.

### Hostinger AI Agent (convenience only)
Decision 4: the Agent is never in the install path and nothing depends on it. Vendor claims, not tested here: it takes chat instructions for posts, WooCommerce, domains and DNS, and is included with WordPress Business and Cloud hosting plans (the plan mapping is unconfirmed; this account's plan is `cloud_economy_v2`). The Hostinger API exposes `wordpress_installations_jwt-token`, described as authenticating requests to an installation's own MCP endpoint, which suggests how the Agent acts on a site; that is an inference from the operation description, not tested. The plugin `hostinger-ai-assistant` seen on the billing site is a content-writing plugin, a different thing. An assistant answering a Hostinger question can answer from the wrong product context (hosting plan versus WordPress plugin versus Agent): check the product name in the answer.

## What was verified, and what was not
Verified on 2026-10-08, on a scratch WordPress (FluentAuth 3.0.5, FluentCart 1.7.1) against a local Supabase: the whole Mode B flow in the checklist above, new and existing emails, single-use links, `next` allow-listing, the unverified-user refusal, and an idempotent install script. FluentAuth, FluentCart and AffiliateWP behaviour was read from plugin source, not assumed.

Not verified: the FluentCart event payload shape against a real test subscription; FluentAuth's password-reset screens on a live site; the Playwright end-to-end suite with this pack; any hosted (non-local) Supabase project; the Hostinger "AI Agent" (a vendor claim, never in the install path); the Hostinger API calls that create a site and install WordPress (listed and described, not run).
