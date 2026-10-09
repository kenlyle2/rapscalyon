#!/usr/bin/env bash
# Mode B WordPress install: FluentAuth, FluentCart, the pseudo-SSO plugin, FluentAuth hardening, wp-config constants.
# Run where wp-cli runs, in the WordPress root. Idempotent. Dry run first:  ./install-wordpress.sh --dry-run
# Secrets come from the environment and are written only to wp-config.php on that server. Never commit them.
# RSY_SSO_ALLOW_HTTP=1 permits http URLs for a scratch install on this machine only. Never set it on a real site.
# Needs: RSY_SSO_SUPABASE_URL (https), RSY_SSO_SERVICE_ROLE_KEY, RSY_SSO_APP_URL (https). AffiliateWP is licensed: install it by hand.
set -euo pipefail
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUENT_AUTH_VERSION=3.0.5   # source read 2026-10-08; billing runs 3.0.4
FLUENT_CART_VERSION=1.7.1   # source read 2026-10-08; billing runs 1.7.0

for v in RSY_SSO_SUPABASE_URL RSY_SSO_SERVICE_ROLE_KEY RSY_SSO_APP_URL; do
  [ -n "${!v:-}" ] || { echo "refusing: $v is not set" >&2; exit 1; }
done
for v in RSY_SSO_SUPABASE_URL RSY_SSO_APP_URL; do
  [[ "${!v}" == https://* || "${RSY_SSO_ALLOW_HTTP:-}" = 1 ]] || { echo "refusing: $v must start with https://" >&2; exit 1; }
done

run() { if [ "$DRY" = 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }
wp core is-installed >/dev/null 2>&1 || { echo "refusing: no WordPress here (run from the WordPress root)" >&2; exit 1; }

install_plugin() { # slug version
  if wp plugin is-installed "$1" 2>/dev/null; then run wp plugin activate "$1"; else run wp plugin install "$1" --version="$2" --activate; fi
}
install_plugin fluent-security "$FLUENT_AUTH_VERSION"
install_plugin fluent-cart "$FLUENT_CART_VERSION"

PLUGIN_DIR="$(wp plugin path 2>/dev/null || echo wp-content/plugins)/rapscalyon-pseudo-sso"
run mkdir -p "$PLUGIN_DIR"
run cp "$HERE/rapscalyon-pseudo-sso.php" "$PLUGIN_DIR/rapscalyon-pseudo-sso.php"
run wp plugin activate rapscalyon-pseudo-sso

# wp config set overwrites an existing constant with the same value, so re-running changes nothing.
run wp config set RSY_SSO_SUPABASE_URL "$RSY_SSO_SUPABASE_URL" --type=constant --quiet
run wp config set RSY_SSO_APP_URL "$RSY_SSO_APP_URL" --type=constant --quiet
if [ "$DRY" = 1 ]; then echo "[dry-run] wp config set RSY_SSO_SERVICE_ROLE_KEY <hidden> --type=constant"; else wp config set RSY_SSO_SERVICE_ROLE_KEY "$RSY_SSO_SERVICE_ROLE_KEY" --type=constant --quiet; fi

# FluentAuth baseline (admins need a second factor; see apply-settings.php.txt for the settings).
if [ "$DRY" = 1 ]; then echo "[dry-run] wp eval \"\$(cat $HERE/../fluentauth/apply-settings.php.txt)\""; else wp eval "$(cat "$HERE/../fluentauth/apply-settings.php.txt")"; fi
echo "done. Next: set WP_LOGIN_URL in the app, then follow docs/README.md of the wp-fluentauth pack (verification checklist)."
