<?php
if (!defined('ABSPATH')) { exit; }

function rsy_inactive_error(int $post_id): WP_Error
{
    $label = rsy_label(rsy_get_config($post_id));
    return new WP_Error('rsy_not_available', $label ?: 'Esta oferta no está disponible ahora.');
}

/**
 * Every purchase path: ProductVariation::canPurchase() runs this filter (named for bundles, but it receives every variation),
 * including the instant-checkout URL, which does not pass through fluent_cart/cart/can_purchase.
 */
add_filter('fluent_cart/variation/can_purchase_bundle', function ($check, $args = []) {
    if (is_wp_error($check)) { return $check; }
    $variation = is_array($args) ? ($args['variation'] ?? null) : null;
    $post_id = $variation && isset($variation->post_id) ? (int) $variation->post_id : 0;
    if ($post_id && !rsy_product_is_active($post_id)) { return rsy_inactive_error($post_id); }
    return $check;
}, 10, 2);

/** Adding to the cart (fluent_cart/cart/can_purchase, app/Models/Cart.php). */
add_filter('fluent_cart/cart/can_purchase', function ($can, $args = []) {
    if (is_wp_error($can)) { return $can; }
    $variation = is_array($args) ? ($args['variation'] ?? null) : null;
    $post_id = $variation && isset($variation->post_id) ? (int) $variation->post_id : 0;
    if ($post_id && !rsy_product_is_active($post_id)) { return rsy_inactive_error($post_id); }
    return $can;
}, 10, 2);

/** A cart filled earlier is checked again before checkout (api/Checkout/CheckoutApi.php). */
add_filter('fluent_cart/checkout/validate_before_process', function ($valid) {
    if (is_wp_error($valid)) { return $valid; }
    if (!class_exists('\FluentCart\App\Helpers\CartHelper')) { return $valid; }
    $cart = \FluentCart\App\Helpers\CartHelper::getCart();
    $items = $cart && is_array($cart->cart_data ?? null) ? $cart->cart_data : [];
    foreach ($items as $item) {
        $post_id = (int) ($item['post_id'] ?? 0);
        if ($post_id && !rsy_product_is_active($post_id)) { return rsy_inactive_error($post_id); }
    }
    return $valid;
});

/** The button says when the product is available instead of a plain "Not Available". */
add_filter('fluent_cart/product/out_of_stock_text', function ($text) {
    $post = get_post();
    if ($post && $post->post_type === 'fluent-products') {
        $label = rsy_label(rsy_get_config($post->ID));
        if ($label && !rsy_product_is_active($post->ID)) { return $label; }
    }
    return $text;
});

/**
 * A coupon belongs to a scheduled record when a post carries its id in _rsy_coupon_id (the offers plugin does this for
 * discount offers). FluentCart coupons have only start and end dates, so weekday and hour limits are enforced here.
 */
add_filter('fluent_cart/coupon/can_use_coupon', function ($can, $args = []) {
    if (is_wp_error($can) || !$can) { return $can; }
    $coupon = is_array($args) ? ($args['coupon'] ?? null) : null;
    if (!$coupon || empty($coupon->id)) { return $can; }
    $ids = get_posts(['post_type' => array_values(get_post_types()), 'post_status' => 'any', 'numberposts' => 1, 'fields' => 'ids', 'meta_key' => '_rsy_coupon_id', 'meta_value' => (int) $coupon->id]);
    if ($ids && !rsy_product_is_active((int) $ids[0])) { return rsy_inactive_error((int) $ids[0]); }
    return $can;
}, 10, 2);
