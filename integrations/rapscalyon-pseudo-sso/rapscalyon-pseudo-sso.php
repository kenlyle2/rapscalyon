<?php
/**
 * Plugin Name: RapScalYon Pseudo SSO
 * Description: Mode B account handoff. A logged-in WordPress user (FluentAuth) with a verified email opens the app as a Supabase session. Requires RSY_SSO_SUPABASE_URL, RSY_SSO_SERVICE_ROLE_KEY and RSY_SSO_APP_URL in wp-config.php.
 * Version: 0.1.0
 * License: AGPL-3.0-or-later
 */
defined('ABSPATH') || exit;

// An email counts as verified when the mailbox was proven on this site: FluentAuth's signup code, or a completed password reset.
function rsy_sso_mark_verified($user_id) { $u = get_userdata($user_id); if ($u) update_user_meta($user_id, 'rsy_sso_verified_email', strtolower($u->user_email)); }
add_action('fluent_auth/before_creating_user', function ($form) { $GLOBALS['rsy_sso_signup_verified'] = (bool) apply_filters('fluent_auth/verify_signup_email', true, $form); });
add_action('user_register', function ($id) { if (!empty($GLOBALS['rsy_sso_signup_verified'])) rsy_sso_mark_verified($id); });
add_action('after_password_reset', function ($user) { rsy_sso_mark_verified($user->ID); });

add_action('template_redirect', function () {
    if (!isset($_GET['rapscalyon_app'])) return;
    if (!defined('RSY_SSO_SUPABASE_URL') || !defined('RSY_SSO_SERVICE_ROLE_KEY') || !defined('RSY_SSO_APP_URL')) wp_die('App launch is not configured.', 'Configuration error', ['response' => 500]);
    if (!is_user_logged_in()) { wp_safe_redirect(wp_login_url(home_url('/?rapscalyon_app=1'))); exit; }
    $user  = wp_get_current_user();
    $email = strtolower($user->user_email);
    if (get_user_meta($user->ID, 'rsy_sso_verified_email', true) !== $email) {
        wp_die('Please confirm your email first: use "Lost your password?" on the login page and set a new password. Then open the app again.', 'Email not confirmed', ['response' => 403]);
    }
    $res = wp_remote_post(rtrim(RSY_SSO_SUPABASE_URL, '/') . '/auth/v1/admin/generate_link', [
        'timeout' => 15,
        'headers' => ['Content-Type' => 'application/json', 'apikey' => RSY_SSO_SERVICE_ROLE_KEY, 'Authorization' => 'Bearer ' . RSY_SSO_SERVICE_ROLE_KEY],
        'body'    => wp_json_encode(['type' => 'magiclink', 'email' => $email]),
    ]);
    $body = is_wp_error($res) ? [] : (json_decode(wp_remote_retrieve_body($res), true) ?: []);
    $hash = $body['hashed_token'] ?? ($body['properties']['hashed_token'] ?? '');
    $type = $body['verification_type'] ?? ($body['properties']['verification_type'] ?? ''); // 'signup' for a first-time email, 'magiclink' after
    if (wp_remote_retrieve_response_code($res) !== 200 || !$hash || !in_array($type, ['signup', 'magiclink'], true)) wp_die('Could not open the app. Try again in a minute.', 'App launch failed', ['response' => 502]);
    $next = isset($_GET['next']) ? (string) wp_unslash($_GET['next']) : '/';
    $next = preg_match('#^/(?!/)#', $next) ? $next : '/';
    // Not wp_safe_redirect: the app is a different host by design; the target is the fixed constant, never request input.
    wp_redirect(rtrim(RSY_SSO_APP_URL, '/') . '/api/wp-fluentauth/confirm?' . http_build_query(['token_hash' => $hash, 'type' => $type, 'next' => $next]));
    exit;
});
