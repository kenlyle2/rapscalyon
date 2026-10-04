<?php
/**
 * Plugin Name: RapScalYon FluentCart Offers
 * Description: Receives offers from the offer synchronizer, creates them as FluentCart draft products, asks the shopkeeper to approve with one tap, and serves the offers active now.
 * Version: 0.1.0
 * License: AGPL-3.0-or-later
 * Requires Plugins: fluent-cart
 *
 * Needs the RapScalYon FluentCart Schedule plugin (weekday and time checks). The synchronizer posts with a WordPress
 * application password belonging to a user with the role "Offer bot" (capability rsy_manage_offers, nothing else).
 */
if (!defined('ABSPATH')) { exit; }

require_once __DIR__ . '/includes/pure.php';

/** A private record for an offer that has no product of its own (a discount offer: it carries a coupon). */
add_action('init', function () {
    register_post_type('rsy_offer', ['public' => false, 'show_ui' => false, 'show_in_rest' => false, 'supports' => ['title', 'excerpt'], 'label' => 'Ofertas (registro)']);
});

register_activation_hook(__FILE__, function () {
    add_role('rsy_offer_bot', 'Offer bot', ['read' => true, 'rsy_manage_offers' => true]);
    $admin = get_role('administrator');
    if ($admin) { $admin->add_cap('rsy_manage_offers'); }
    if (!get_option('rsy_offers_secret')) { add_option('rsy_offers_secret', wp_generate_password(64, true, true), '', false); }
});

add_action('plugins_loaded', function () {
    if (!function_exists('rsy_is_active') && file_exists(WP_PLUGIN_DIR . '/fluentcart-schedule/fluentcart-schedule.php')) {
        require_once WP_PLUGIN_DIR . '/fluentcart-schedule/fluentcart-schedule.php';
    }
    if (!function_exists('rsy_product_is_active')) {
        add_action('admin_notices', function () { echo '<div class="notice notice-error"><p>RapScalYon FluentCart Offers needs the RapScalYon FluentCart Schedule plugin.</p></div>'; });
        return;
    }
    require_once __DIR__ . '/includes/receive.php';
    require_once __DIR__ . '/includes/approve.php';
    require_once __DIR__ . '/includes/feed.php';
    require_once __DIR__ . '/includes/settings.php';
});
