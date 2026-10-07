<?php
/**
 * Plugin Name: RapScalYon WPSubscription Bridge
 * Description: Sends WPSubscription (WooCommerce) subscription lifecycle events, signed, to the RapScalYon core billing webhook. Replaces Bit Integrations for this job.
 * Version: 0.1.0
 * License: AGPL-3.0-or-later
 *
 * Configure in wp-config.php (same constants as the FluentCart bridge):
 *   define('RAPSCALYON_WEBHOOK_URL', 'https://<your-app>/api/billing-webhook');
 *   define('RAPSCALYON_WEBHOOK_SECRET', '<same value as BILLING_WEBHOOK_SECRET in the app>');
 *
 * Hook names and arguments were read in the WPSubscription 2.3.0 source (wordpress.org slug `subscription`):
 *   subscrpt_subscription_{activated|cancelled|expired|on_hold|pending_cancellation|payment_failed}($subscription_id)
 *   subscrpt_subscription_resumed($subscription_id, $old_status)
 *   subscrpt_subscription_payment_completed($subscription_id, $payment_id)
 * A subscription is a post of type `subscrpt_order`; its owner is the post author. Not yet run against a live store.
 */
if (!defined('ABSPATH') && !defined('RAPSCALYON_WPS_TEST')) { exit; }

/**
 * Map one WPSubscription event to the flat JSON the core webhook documents. Pure: no WordPress calls.
 * $ctx: subscription_id, email, customer_id?, product_name?, plan_key?, discriminator?
 * The event id carries the time of the event, so a cancel, resume and second cancel are three events; a retry reuses the payload.
 */
function rapscalyon_wps_payload(string $status, array $ctx, int $now) {
    $sub_id = $ctx['subscription_id'] ?? null;
    $email = $ctx['email'] ?? null;
    if (!$sub_id || !$email) { return null; } // nothing the core could match; the caller logs it
    $disc = (string) ($ctx['discriminator'] ?? '');
    return array_filter([
        'source' => 'wpsubscription',
        'subscription_id' => (string) $sub_id,
        'customer_id' => isset($ctx['customer_id']) ? (string) $ctx['customer_id'] : null,
        'status' => $status,
        'email' => strtolower(trim((string) $email)),
        'product_name' => $ctx['product_name'] ?? null,
        'plan_key' => isset($ctx['plan_key']) ? (string) $ctx['plan_key'] : null,
        'event_id' => 'wps:' . $sub_id . ':' . $status . ($disc !== '' ? ':' . $disc : '') . ':' . $now,
        'occurred_at' => gmdate('c', $now),
    ], function ($v) { return $v !== null && $v !== ''; });
}

function rapscalyon_wps_sign(string $body, string $secret): string { return hash_hmac('sha256', $body, $secret); }

/** Look up what the payload needs from WordPress and WooCommerce. Returns the $ctx array above. */
function rapscalyon_wps_context(int $subscription_id): array {
    $user_id = (int) get_post_field('post_author', $subscription_id);
    $email = $user_id ? (string) get_the_author_meta('email', $user_id) : '';
    $order_id = (int) get_post_meta($subscription_id, '_subscrpt_order_id', true);
    if ($email === '' && $order_id && function_exists('wc_get_order')) {
        $order = wc_get_order($order_id);
        $email = $order ? (string) $order->get_billing_email() : '';
    }
    $product_id = (int) get_post_meta($subscription_id, '_subscrpt_product_id', true);
    return [
        'subscription_id' => $subscription_id,
        'email' => $email,
        'customer_id' => $user_id ?: null,
        'product_name' => $product_id ? get_the_title($product_id) : null,
        'plan_key' => $product_id ?: null,
        'order_id' => $order_id,
    ];
}

function rapscalyon_wps_send(array $payload, int $attempt = 1) {
    if (!defined('RAPSCALYON_WEBHOOK_URL') || !defined('RAPSCALYON_WEBHOOK_SECRET')) { error_log('rapscalyon-wps: not configured'); return; }
    $body = wp_json_encode($payload);
    $res = wp_remote_post(RAPSCALYON_WEBHOOK_URL, [
        'timeout' => 10,
        'headers' => ['Content-Type' => 'application/json', 'x-webhook-signature' => rapscalyon_wps_sign($body, RAPSCALYON_WEBHOOK_SECRET)],
        'body' => $body,
    ]);
    $code = is_wp_error($res) ? 0 : (int) wp_remote_retrieve_response_code($res);
    // 404 means "profile not found": the buyer has not signed up in the app yet. Retrying later can succeed, so it retries too.
    if ($code >= 200 && $code < 300) { return; }
    error_log("rapscalyon-wps: {$payload['status']} for {$payload['subscription_id']} failed (HTTP {$code}, attempt {$attempt})");
    if ($attempt < 4) { wp_schedule_single_event(time() + 300 * $attempt * $attempt, 'rapscalyon_wps_retry', [$payload, $attempt + 1]); }
}

function rapscalyon_wps_emit(string $status, int $subscription_id, array $extra = []) {
    $ctx = array_merge(rapscalyon_wps_context($subscription_id), $extra);
    $p = rapscalyon_wps_payload($status, $ctx, time());
    if ($p === null) { error_log("rapscalyon-wps: {$status} event for subscription {$subscription_id} without an email, skipped"); return; }
    rapscalyon_wps_send($p);
}

if (function_exists('add_action')) {
    add_action('rapscalyon_wps_retry', 'rapscalyon_wps_send', 10, 2);

    // hook => status the core understands (core maps: active/renewed, on-hold/past_due -> payment_failed, pending-cancel -> canceled, expired, refunded)
    $map = [
        'subscrpt_subscription_activated'            => 'active',
        'subscrpt_subscription_resumed'              => 'active',
        'subscrpt_subscription_cancelled'            => 'canceled',
        'subscrpt_subscription_pending_cancellation' => 'pending-cancel',
        'subscrpt_subscription_expired'              => 'expired',
        'subscrpt_subscription_on_hold'              => 'on-hold',
        'subscrpt_subscription_payment_failed'       => 'past_due',
    ];
    foreach ($map as $hook => $status) {
        add_action($hook, function ($subscription_id) use ($status) { rapscalyon_wps_emit($status, (int) $subscription_id); }, 10, 1);
    }

    // A completed payment is a renewal unless it is the parent order, which the activated hook already reported.
    add_action('subscrpt_subscription_payment_completed', function ($subscription_id, $payment_id = 0) {
        $subscription_id = (int) $subscription_id; $payment_id = (int) $payment_id;
        if ($payment_id && $payment_id === (int) get_post_meta($subscription_id, '_subscrpt_order_id', true)) { return; }
        rapscalyon_wps_emit('renewed', $subscription_id, ['discriminator' => (string) $payment_id]);
    }, 10, 2);

    // A fully refunded WooCommerce order refunds the subscriptions that were bought in it (WPSubscription has no refund hook).
    add_action('woocommerce_order_fully_refunded', function ($order_id) {
        if (!class_exists('\SpringDevs\Subscription\Illuminate\Helper')) { return; }
        foreach ((array) \SpringDevs\Subscription\Illuminate\Helper::get_subscriptions_from_order((int) $order_id) as $row) {
            if (!empty($row->subscription_id)) { rapscalyon_wps_emit('refunded', (int) $row->subscription_id, ['discriminator' => 'o' . (int) $order_id]); }
        }
    }, 10, 1);
}
