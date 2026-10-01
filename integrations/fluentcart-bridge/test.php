<?php
// php test.php — pure payload/signature checks; needs no WordPress.
define('RAPSCALYON_FC_TEST', 1);
require __DIR__ . '/rapscalyon-fluentcart-bridge.php';
$fail = 0; $ok = function ($c, $m) use (&$fail) { echo ($c ? 'ok   ' : 'FAIL ') . $m . "\n"; if (!$c) { $fail++; } };
$p = rapscalyon_fc_payload('active', ['subscription' => (object) ['id' => 7, 'item_name' => 'Pro'], 'customer' => (object) ['id' => 3, 'email' => 'a@b.co']]);
$ok($p['status'] === 'active' && $p['subscription_id'] === '7' && $p['email'] === 'a@b.co' && $p['product_name'] === 'Pro', 'maps an active event');
$ok($p['event_id'] === 'fc:7:active' && $p['source'] === 'fluentcart', 'stable idempotency key and source');
$ok(rapscalyon_fc_payload('active', ['subscription' => (object) ['id' => 7]]) === null, 'no email -> skipped');
$ok(rapscalyon_fc_payload('canceled', ['subscription' => ['id' => 9], 'order' => ['customer_email' => 'x@y.zz']])['email'] === 'x@y.zz', 'falls back to order email');
$ok(rapscalyon_fc_sign('{"a":1}', 's') === hash_hmac('sha256', '{"a":1}', 's'), 'signature is hex HMAC-SHA256');
exit($fail ? 1 : 0);
