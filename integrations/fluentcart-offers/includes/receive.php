<?php
if (!defined('ABSPATH')) { exit; }

add_action('rest_api_init', function () {
    register_rest_route('rapscalyon/v1', '/offers', [
        'methods' => 'POST', 'callback' => 'rsy_offers_receive',
        'permission_callback' => function () { return current_user_can('rsy_manage_offers'); },
    ]);
});

function rsy_offers_store_currency(): string
{
    $s = get_option('fluent_cart_store_settings');
    return is_array($s) ? (string) ($s['currency'] ?? '') : '';
}

function rsy_offers_find(string $source_id): ?int
{
    $ids = get_posts(['post_type' => ['fluent-products', 'rsy_offer'], 'post_status' => 'any', 'numberposts' => 1, 'fields' => 'ids',
        'meta_key' => '_rsy_source_id', 'meta_value' => $source_id]);
    return $ids ? (int) $ids[0] : null;
}

function rsy_offers_sideload(array $img, string $title): ?array
{
    $bin = base64_decode((string) $img['b64'], true);
    if ($bin === false || strlen($bin) > 3 * 1024 * 1024) { return null; }
    $info = @getimagesizefromstring($bin);
    $ext = [IMAGETYPE_JPEG => 'jpg', IMAGETYPE_PNG => 'png', IMAGETYPE_WEBP => 'webp'][$info[2] ?? 0] ?? null;
    if (!$ext) { return null; }
    require_once ABSPATH . 'wp-admin/includes/file.php';
    require_once ABSPATH . 'wp-admin/includes/media.php';
    require_once ABSPATH . 'wp-admin/includes/image.php';
    $tmp = wp_tempnam('offer');
    file_put_contents($tmp, $bin);
    $id = media_handle_sideload(['name' => sanitize_file_name('oferta-' . wp_generate_password(8, false) . '.' . $ext), 'tmp_name' => $tmp], 0, $title);
    if (is_wp_error($id)) { @unlink($tmp); return null; }
    return ['id' => $id, 'url' => wp_get_attachment_url($id), 'title' => $title];
}

function rsy_offers_save_meta(int $id, array $o, string $source_id): void
{
    update_post_meta($id, '_rsy_source_id', $source_id);
    update_post_meta($id, '_rsy_source_url', esc_url_raw($o['source']['post_url']));
    update_post_meta($id, '_rsy_confidence', (float) $o['confidence']);
    update_post_meta($id, '_rsy_flags', array_map('sanitize_text_field', (array) $o['flags']));
    $o['weekdays'] ? update_post_meta($id, RSY_META_DAYS, array_map('intval', $o['weekdays'])) : delete_post_meta($id, RSY_META_DAYS);
    !empty($o['time_window']) ? update_post_meta($id, RSY_META_WINDOW, $o['time_window']) : delete_post_meta($id, RSY_META_WINDOW);
    !empty($o['valid_from']) ? update_post_meta($id, RSY_META_FROM, $o['valid_from']) : delete_post_meta($id, RSY_META_FROM);
    !empty($o['valid_until']) ? update_post_meta($id, RSY_META_UNTIL, $o['valid_until']) : delete_post_meta($id, RSY_META_UNTIL);
}

function rsy_offers_receive(WP_REST_Request $req)
{
    $o = $req->get_json_params();
    $problems = rsy_offer_problems($o);
    if ($problems) { return new WP_REST_Response(['status' => 'invalid', 'problems' => $problems], 400); }
    if ($o['is_offer'] === false) { return new WP_REST_Response(['status' => 'ignored']); }
    if ($o['currency'] !== rsy_offers_store_currency()) {
        return new WP_REST_Response(['status' => 'refused', 'message' => 'store currency is ' . rsy_offers_store_currency() . ', offer is ' . $o['currency']], 422);
    }
    $source_id = (string) $o['source']['post_id'];
    $existing = rsy_offers_find($source_id);
    if ($existing && get_post_meta($existing, '_rsy_decision', true) === 'rejected') {
        return new WP_REST_Response(['status' => 'rejected_earlier', 'id' => $existing]);
    }
    $factor = (class_exists('\FluentCart\App\Helpers\CurrenciesHelper') && \FluentCart\App\Helpers\CurrenciesHelper::isZeroDecimal($o['currency'])) ? 1 : 100;
    $payload = rsy_offer_payload($o, $factor, 'offer-' . $source_id);
    if (!$payload) { return rsy_offers_receive_discount($o, $existing, $source_id); }
    if ($existing) { return rsy_offers_update($existing, $o, $payload, $factor); }

    if (!class_exists('\FluentCart\App\Services\BulkProductInsertService')) { return new WP_REST_Response(['status' => 'error', 'message' => 'FluentCart is not available'], 500); }
    if (!empty($o['image'])) {
        $g = rsy_offers_sideload($o['image'], $o['title']);
        if ($g) { $payload['gallery'] = [$g]; }
    }
    $r = (new \FluentCart\App\Services\BulkProductInsertService())->insertChunk([$payload]);
    if (empty($r['created'][0]['id'])) { return new WP_REST_Response(['status' => 'error', 'message' => (string) ($r['errors'][0]['message'] ?? 'insert failed')], 500); }
    $id = (int) $r['created'][0]['id'];
    rsy_offers_save_meta($id, $o, $source_id);
    update_post_meta($id, '_rsy_decision', 'pending');
    rsy_schedule_refresh_state($id);
    $s = rsy_offers_settings();
    if ($s['auto_publish'] && rsy_offer_clean($o)) {
        wp_update_post(['ID' => $id, 'post_status' => 'publish']);
        update_post_meta($id, '_rsy_decision', 'approved');
        return new WP_REST_Response(['status' => 'published', 'id' => $id], 201);
    }
    rsy_offers_notify($id);
    return new WP_REST_Response(['status' => 'created_draft', 'id' => $id], 201);
}

function rsy_offers_update(int $id, array $o, array $payload, int $factor)
{
    $variations = class_exists('\FluentCart\App\Models\ProductVariation') ? \FluentCart\App\Models\ProductVariation::where('post_id', $id)->get() : [];
    $by_title = [];
    foreach ($variations as $v) { $by_title[$v->variation_title] = $v; }
    $want = [];
    foreach ($payload['variants'] as $v) { $want[$v['variation_title']] = $v['item_price']; }
    if (array_diff_key($want, $by_title) || array_diff_key($by_title, $want)) {
        return new WP_REST_Response(['status' => 'shape_changed', 'id' => $id, 'message' => 'sizes changed; reject the old offer and post again'], 409);
    }
    $price_changed = false;
    foreach ($want as $title => $price) {
        if ((int) $by_title[$title]->item_price !== $price) { $by_title[$title]->item_price = $price; $by_title[$title]->save(); $price_changed = true; }
    }
    wp_update_post(['ID' => $id, 'post_title' => $o['title'], 'post_excerpt' => (string) ($o['description'] ?? '')]);
    rsy_offers_save_meta($id, $o, (string) $o['source']['post_id']);
    rsy_schedule_refresh_state($id);
    if ($price_changed && get_post_status($id) === 'publish') {
        wp_update_post(['ID' => $id, 'post_status' => 'draft']);
        update_post_meta($id, '_rsy_decision', 'pending');
        rsy_offers_notify($id);
        return new WP_REST_Response(['status' => 'updated_back_to_draft', 'id' => $id]);
    }
    return new WP_REST_Response(['status' => 'updated', 'id' => $id]);
}

/** Store-local date and time to the GMT string FluentCart stores (the coupon controller does the same conversion). */
function rsy_offers_gmt(string $date, string $time): string { return get_gmt_from_date($date . ' ' . $time); }

/** A discount offer (no price of its own): a private record plus a disabled FluentCart coupon, enabled on approval. */
function rsy_offers_receive_discount(array $o, ?int $existing, string $source_id)
{
    if (!class_exists('\FluentCart\Api\Resource\CouponResource')) { return new WP_REST_Response(['status' => 'error', 'message' => 'FluentCart coupons are not available'], 500); }
    if ($existing) {
        wp_update_post(['ID' => $existing, 'post_title' => $o['title']]);
        rsy_offers_save_meta($existing, $o, $source_id);
        return new WP_REST_Response(['status' => 'updated', 'id' => $existing]);
    }
    $d = $o['discount'];
    $code = 'OFR' . strtoupper(wp_generate_password(6, false));
    $data = [
        'title' => $o['title'], 'code' => $code, 'type' => $d['type'] === 'percent' ? 'percentage' : 'fixed',
        'amount' => $d['type'] === 'percent' ? (float) $d['amount'] : (float) $d['amount'], 'status' => 'disabled',
        'stackable' => 'no', 'show_on_checkout' => 'no', 'conditions' => new stdClass(),
    ];
    if (!empty($o['valid_from'])) { $data['start_date'] = rsy_offers_gmt($o['valid_from'], '00:00:00'); }
    if (!empty($o['valid_until'])) { $data['end_date'] = rsy_offers_gmt($o['valid_until'], '23:59:59'); if (empty($data['start_date'])) { $data['start_date'] = rsy_offers_gmt(wp_date('Y-m-d'), '00:00:00'); } }
    $r = \FluentCart\Api\Resource\CouponResource::create($data);
    if (is_wp_error($r) || empty($r['data']['id'])) { return new WP_REST_Response(['status' => 'error', 'message' => is_wp_error($r) ? $r->get_error_message() : 'coupon create failed'], 500); }
    $id = wp_insert_post(['post_type' => 'rsy_offer', 'post_status' => 'draft', 'post_title' => $o['title'], 'post_excerpt' => (string) ($o['description'] ?? '')], true);
    if (is_wp_error($id)) { return new WP_REST_Response(['status' => 'error', 'message' => $id->get_error_message()], 500); }
    rsy_offers_save_meta($id, $o, $source_id);
    update_post_meta($id, '_rsy_coupon_id', (int) $r['data']['id']);
    update_post_meta($id, '_rsy_coupon_code', $code);
    update_post_meta($id, '_rsy_discount', $d);
    update_post_meta($id, '_rsy_decision', 'pending');
    rsy_schedule_refresh_state($id);
    $s = rsy_offers_settings();
    if ($s['auto_publish'] && rsy_offer_clean($o)) { rsy_offers_decide($id, 'approve'); return new WP_REST_Response(['status' => 'published', 'id' => $id, 'code' => $code], 201); }
    rsy_offers_notify($id);
    return new WP_REST_Response(['status' => 'created_draft', 'id' => $id, 'code' => $code], 201);
}

/** Approve or reject any offer record, whether it is a product or a coupon record. */
function rsy_offers_decide(int $id, string $action): void
{
    $coupon_id = (int) get_post_meta($id, '_rsy_coupon_id', true);
    if ($coupon_id && class_exists('\FluentCart\App\Models\Coupon')) {
        $c = \FluentCart\App\Models\Coupon::find($coupon_id);
        if ($c) { $c->status = $action === 'approve' ? 'active' : 'disabled'; $c->save(); }
    }
    if ($action === 'approve') { wp_update_post(['ID' => $id, 'post_status' => 'publish']); update_post_meta($id, '_rsy_decision', 'approved'); }
    else { update_post_meta($id, '_rsy_decision', 'rejected'); }
}
