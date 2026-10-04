<?php
if (!defined('ABSPATH')) { exit; }

add_action('rest_api_init', function () {
    register_rest_route('rapscalyon/v1', '/offers/active', [
        'methods' => 'GET', 'callback' => 'rsy_offers_feed', 'permission_callback' => '__return_true',
    ]);
});

/** Published offers that are active right now. Nothing else about a product is exposed. */
function rsy_offers_feed(WP_REST_Request $req)
{
    $limit = max(1, min(20, (int) $req->get_param('limit') ?: 6));
    $ids = get_posts(['post_type' => 'fluent-products', 'post_status' => 'publish', 'numberposts' => 100, 'fields' => 'ids',
        'meta_key' => '_rsy_source_id', 'meta_compare' => 'EXISTS']);
    $out = [];
    foreach ($ids as $id) {
        if (count($out) >= $limit) { break; }
        if (!rsy_product_is_active((int) $id)) { continue; }
        $detail = class_exists('\FluentCart\App\Models\ProductDetail') ? \FluentCart\App\Models\ProductDetail::where('post_id', $id)->first() : null;
        $gallery = get_post_meta($id, 'fluent-products-gallery-image', true);
        $img = is_array($gallery) && !empty($gallery[0]['url']) ? esc_url_raw($gallery[0]['url']) : null;
        $out[] = [
            'id' => (int) $id, 'title' => get_the_title($id), 'description' => wp_strip_all_tags(get_the_excerpt($id)),
            'price_min' => $detail ? (int) $detail->min_price : null, 'price_max' => $detail ? (int) $detail->max_price : null,
            'image' => $img, 'link' => get_permalink($id), 'days' => rsy_label(rsy_get_config((int) $id)),
        ];
    }
    $res = new WP_REST_Response(['currency' => rsy_offers_store_currency(), 'zero_decimal' => class_exists('\FluentCart\App\Helpers\CurrenciesHelper') ? \FluentCart\App\Helpers\CurrenciesHelper::isZeroDecimal(rsy_offers_store_currency()) : false, 'offers' => $out]);
    $res->header('Cache-Control', 'public, max-age=60');
    return $res;
}
