<?php
// Plain PHP tests for includes/pure.php. Run: php tests/pure_test.php
require __DIR__ . '/../includes/pure.php';

$fail = 0;
function check($name, $got, $want) { global $fail; if ($got !== $want) { $fail++; echo "FAIL $name: got " . var_export($got, true) . "\n"; } }
$fx = function ($n) { return json_decode(file_get_contents(__DIR__ . '/../../../tools/offer_sync/tests/data/' . $n . '.json'), true); };

foreach (['offer_example_monday', 'offer_percent_weekend', 'not_offer', 'offer_ambiguous'] as $n) {
    check("fixture $n valid", rsy_offer_problems($fx($n)), []);
}
$o = $fx('offer_example_monday');
$bad = function ($k, $v) use ($o) { $x = $o; $x[$k] = $v; return count(rsy_offer_problems($x)) > 0; };
check('weekday 7', $bad('weekdays', [7]), true);
check('duplicate weekday', $bad('weekdays', [0, 0]), true);
check('zero price', $bad('variants', [['label' => '', 'price' => 0]]), true);
check('lowercase currency', $bad('currency', 'crc'), true);
check('confidence 2', $bad('confidence', 2), true);
check('unknown field', $bad('extra', 1), true);
check('non-https post url', rsy_offer_problems(array_replace_recursive($o, ['source' => ['post_url' => 'javascript:alert(1)']])) !== [], true);
check('percent over 100', $bad('discount', ['type' => 'percent', 'amount' => 150]), true);
check('bad image mime', $bad('image', ['b64' => 'AAAA', 'mime' => 'text/html']), true);
check('good image', $bad('image', ['b64' => 'AAAA', 'mime' => 'image/png']), false);
check('11 variants', $bad('variants', array_map(function ($i) { return ['label' => "v$i", 'price' => 1]; }, range(1, 11))), true);

check('minor 12000 CRC', rsy_offer_minor(12000, 100), 1200000);
check('minor zero-decimal', rsy_offer_minor(12000, 1), 12000);
check('minor float rounding', rsy_offer_minor(19.99, 100), 1999);
$pl = rsy_offer_payload($o, 100, 'c1');
check('payload draft', $pl['post_status'], 'draft');
check('payload price minor', $pl['variants'][0]['item_price'], 1200000);
check('payload category', $pl['categories'], ['Ofertas']);
check('payload single is simple', $pl['detail']['variation_type'], 'simple');
$o2 = $o; $o2['variants'] = [['label' => 'Pequeña', 'price' => 5000], ['label' => 'Grande', 'price' => 9000]];
check('payload sizes variations', rsy_offer_payload($o2, 100, 'c2')['detail']['variation_type'], 'simple_variations');
check('discount-only has no payload', rsy_offer_payload($fx('offer_percent_weekend'), 100, 'c3'), []);
check('clean offer', rsy_offer_clean($o), true);
check('flagged offer not clean', rsy_offer_clean($fx('offer_ambiguous')), false);

$sec = 'test-secret';
$t = rsy_token_make(42, 'approve', 2000, 'n0nce', $sec);
check('token ok', rsy_token_check($t, $sec, 1000), [42, 'approve', 'n0nce']);
check('token expired', rsy_token_check($t, $sec, 2001), null);
check('token wrong secret', rsy_token_check($t, 'other', 1000), null);
[$b, $s] = explode('.', $t);
check('tampered body', rsy_token_check(rsy_b64url('43|approve|2000|n0nce') . '.' . $s, $sec, 1000), null);
check('tampered sig', rsy_token_check($b . '.' . substr($s, 0, -2) . 'AA', $sec, 1000), null);
check('garbage', rsy_token_check('abc', $sec, 1000), null);
check('empty', rsy_token_check('', $sec, 1000), null);
check('unknown action not accepted', rsy_token_check(rsy_token_make(1, 'delete', 2000, 'n', $sec), $sec, 1000), null);

echo $fail ? "$fail failed\n" : "all passed\n";
exit($fail ? 1 : 0);
