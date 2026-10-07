<?php
/**
 * Plugin Name: RapScalYon FluentCart Bridge
 * Description: Sends FluentCart subscription lifecycle events, signed, to the RapScalYon core billing webhook.
 * Version: 0.1.0
 * License: AGPL-3.0-or-later
 *
 * Configure in wp-config.php:
 *   define('RAPSCALYON_WEBHOOK_URL', 'https://<your-app>/api/billing-webhook');
 *   define('RAPSCALYON_WEBHOOK_SECRET', '<same value as BILLING_WEBHOOK_SECRET in the app>');
 *
 * FluentCart documents WordPress action hooks (dev.fluentcart.com/hooks/actions/subscriptions.html) and no outgoing
 * webhooks, so this plugin is the sender. Hook names and the `$data` keys come from that page; the property names read
 * from the subscription/customer/order objects are NOT verified against a live store (see rapscalyon_fc_get).
 */
if (!defined('ABSPATH') && !defined('RAPSCALYON_FC_TEST')) { exit; }

/** Read the first present key from an object or array; the field names FluentCart uses are tried in order. */
function rapscalyon_fc_get($src, array $keys) {
    foreach ($keys as $k) {
        if (is_array($src) && isset($src[$k]) && $src[$k] !== '') { return $src[$k]; }
        if (is_object($src) && isset($src->$k) && $src->$k !== '') { return $src->$k; }
    }
    return null;
}

/** Map one FluentCart hook to the flat JSON the core webhook documents. Pure: no WordPress calls. */
/** The event id carries the time of the event, so cancel, resume and a second cancel are different events; a retry reuses the payload. */
function rapscalyon_fc_payload(string $status, array $data, string $discriminator = '', ?int $now = null) {
    $now = $now ?? time();
    $sub = $data['subscription'] ?? null;
    $cust = $data['customer'] ?? null;
    $order = $data['order'] ?? null;
    $sub_id = rapscalyon_fc_get($sub, ['id', 'vendor_subscription_id']);
    $email = rapscalyon_fc_get($cust, ['email', 'user_email']) ?? rapscalyon_fc_get($order, ['customer_email', 'email']);
    if ($sub_id === null || $email === null) { return null; } // nothing the core could match; the caller logs it
    return array_filter([
        'source' => 'fluentcart',
        'subscription_id' => (string) $sub_id,
        'customer_id' => rapscalyon_fc_get($cust, ['id']),
        'status' => $status,
        'email' => (string) $email,
        'product_name' => rapscalyon_fc_get($sub, ['item_name', 'product_name', 'title', 'plan_name']),
        'plan_key' => rapscalyon_fc_get($sub, ['variation_id', 'object_id', 'item_id']),
        'event_id' => 'fc:' . $sub_id . ':' . $status . ($discriminator !== '' ? ':' . $discriminator : '') . ':' . $now,
        'occurred_at' => gmdate('c', $now),
    ], function ($v) { return $v !== null; });
}

function rapscalyon_fc_sign(string $body, string $secret): string { return hash_hmac('sha256', $body, $secret); }

function rapscalyon_fc_send(array $payload, int $attempt = 1) {
    if (!defined('RAPSCALYON_WEBHOOK_URL') || !defined('RAPSCALYON_WEBHOOK_SECRET')) { error_log('rapscalyon-fc: not configured'); return; }
    $body = wp_json_encode($payload);
    $res = wp_remote_post(RAPSCALYON_WEBHOOK_URL, [
        'timeout' => 10,
        'headers' => ['Content-Type' => 'application/json', 'x-webhook-signature' => rapscalyon_fc_sign($body, RAPSCALYON_WEBHOOK_SECRET)],
        'body' => $body,
    ]);
    $code = is_wp_error($res) ? 0 : (int) wp_remote_retrieve_response_code($res);
    // 404 means "profile not found": the user has not signed up in the app yet. Retrying later can succeed, so it retries too.
    if ($code >= 200 && $code < 300) { return; }
    error_log("rapscalyon-fc: {$payload['status']} for {$payload['subscription_id']} failed (HTTP {$code}, attempt {$attempt})");
    if ($attempt < 4) { wp_schedule_single_event(time() + 300 * $attempt * $attempt, 'rapscalyon_fc_retry', [$payload, $attempt + 1]); }
}
if (function_exists('add_action')) {
    add_action('rapscalyon_fc_retry', 'rapscalyon_fc_send', 10, 2);

    // hook => [status the core understands, discriminator source]
    $map = [
        'fluent_cart/payments/subscription_active'   => ['active', null],
        'fluent_cart/payments/subscription_trialing' => ['trialing', null],
        'fluent_cart/payments/subscription_canceled' => ['canceled', null],
        'fluent_cart/payments/subscription_expired'  => ['expired', null],
        'fluent_cart/payments/subscription_failing'  => ['past_due', null],
        'fluent_cart/subscription_past_due'          => ['past_due', null],
        'fluent_cart/subscriptions/system_charge_failed'    => ['past_due', 'attempt'],
        'fluent_cart/subscriptions/system_charge_succeeded' => ['renewed', 'attempt'],
    ];
    foreach ($map as $hook => [$status, $disc]) {
        add_action($hook, function ($data) use ($status, $disc) {
            $data = is_array($data) ? $data : (array) $data;
            $d = $disc ? (string) ($data[$disc] ?? '') . ':' . (string) rapscalyon_fc_get($data['order'] ?? null, ['id']) : '';
            $p = rapscalyon_fc_payload($status, $data, $d);
            if ($p === null) { error_log("rapscalyon-fc: {$status} event without subscription id or email, skipped"); return; }
            rapscalyon_fc_send($p);
        }, 10, 1);
    }
}
