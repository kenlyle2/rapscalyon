<?php
// php test.php — payload, signature and hook-wiring checks with WordPress stubbed; needs no WordPress.
define('RAPSCALYON_WPS_TEST', 1);
require __DIR__ . '/rapscalyon-wpsubscription-bridge.php';
$fail = 0; $ok = function ($c, $m) use (&$fail) { echo ($c ? 'ok   ' : 'FAIL ') . $m . "\n"; if (!$c) { $fail++; } };
$t = 1730000000;
$p = rapscalyon_wps_payload('active', ['subscription_id' => 7, 'email' => ' A@B.co ', 'customer_id' => 3, 'product_name' => 'Pro', 'plan_key' => 12], $t);
$ok($p['status'] === 'active' && $p['subscription_id'] === '7' && $p['email'] === 'a@b.co' && $p['product_name'] === 'Pro' && $p['plan_key'] === '12' && $p['customer_id'] === '3', 'maps an active event, email lowercased');
$ok($p['source'] === 'wpsubscription' && $p['event_id'] === 'wps:7:active:' . $t && $p['occurred_at'] === gmdate('c', $t), 'source, event id with time, ISO date');
$ok(rapscalyon_wps_payload('canceled', ['subscription_id' => 7, 'email' => 'a@b.co'], $t + 5)['event_id'] !== rapscalyon_wps_payload('canceled', ['subscription_id' => 7, 'email' => 'a@b.co'], $t)['event_id'], 'a second cancel is a different event');
$ok(rapscalyon_wps_payload('renewed', ['subscription_id' => 7, 'email' => 'a@b.co', 'discriminator' => '55'], $t)['event_id'] === 'wps:7:renewed:55:' . $t, 'discriminator in event id');
$ok(rapscalyon_wps_payload('active', ['subscription_id' => 7], $t) === null, 'no email -> skipped');
$ok(rapscalyon_wps_payload('active', ['email' => 'a@b.co'], $t) === null, 'no subscription id -> skipped');
$ok(!array_key_exists('plan_key', rapscalyon_wps_payload('active', ['subscription_id' => 7, 'email' => 'a@b.co'], $t)), 'absent optional fields are left out');
$ok(rapscalyon_wps_sign('{"a":1}', 's') === hash_hmac('sha256', '{"a":1}', 's'), 'signature is hex HMAC-SHA256');
// the statuses must be ones the core route understands (app/api/billing-webhook/route.ts KIND map)
$route = file_get_contents(__DIR__ . '/../../app/app/api/billing-webhook/route.ts');
foreach (['active', 'renewed', 'canceled', 'pending-cancel', 'expired', 'on-hold', 'past_due', 'refunded'] as $s) { $ok(strpos($route, $s) !== false, "core route knows status '$s'"); }
exit($fail ? 1 : 0);
