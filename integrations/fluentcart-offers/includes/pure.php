<?php
/** Pure logic for the offers plugin: no WordPress calls, tested with plain PHP (tests/pure_test.php). */

/** Problems with an offer draft (schema 1, tools/offer_sync/contract.py); empty = valid. The receiver also takes image {b64, mime}. */
function rsy_offer_problems($o): array
{
    if (!is_array($o)) { return ['offer must be an object']; }
    $p = [];
    $allowed = ['schema', 'is_offer', 'source', 'title', 'description', 'variants', 'discount', 'currency', 'weekdays', 'time_window', 'valid_from', 'valid_until', 'image', 'confidence', 'flags'];
    foreach (array_keys($o) as $k) { if (!in_array($k, $allowed, true)) { $p[] = "unknown field: $k"; } }
    if (($o['schema'] ?? null) !== 1) { $p[] = 'schema must be 1'; }
    if (!is_bool($o['is_offer'] ?? null)) { $p[] = 'is_offer must be true or false'; }
    $src = $o['source'] ?? null;
    if (!is_array($src) || array_diff(['platform', 'page_url', 'post_id', 'post_url', 'posted_at'], array_keys($src))) {
        $p[] = 'source needs platform, page_url, post_id, post_url, posted_at';
    } else {
        if (($src['platform'] ?? '') !== 'facebook') { $p[] = 'source.platform must be facebook'; }
        foreach (['page_url', 'post_url'] as $k) { if (strpos((string) $src[$k], 'https://') !== 0) { $p[] = "source.$k must be https"; } }
        $id = (string) $src['post_id'];
        if ($id === '' || strlen($id) > 100) { $p[] = 'source.post_id is required (max 100)'; }
    }
    if (!preg_match('/^[A-Z]{3}$/', (string) ($o['currency'] ?? ''))) { $p[] = 'currency must be a 3-letter code'; }
    $c = $o['confidence'] ?? null;
    if (!is_numeric($c) || is_bool($c) || $c < 0 || $c > 1) { $p[] = 'confidence must be 0 to 1'; }
    if (!is_array($o['flags'] ?? null)) { $p[] = 'flags must be a list'; }
    if (($o['is_offer'] ?? false) !== true) { return $p; }
    $t = $o['title'] ?? null;
    if (!is_string($t) || $t === '' || mb_strlen($t) > 200) { $p[] = 'title is required (max 200)'; }
    if (mb_strlen((string) ($o['description'] ?? '')) > 500) { $p[] = 'description max 500'; }
    $vs = $o['variants'] ?? [];
    $d = $o['discount'] ?? null;
    if (!is_array($vs)) { $vs = []; $p[] = 'variants must be a list'; }
    if (!$vs && !$d) { $p[] = 'an offer needs variants with prices or a discount'; }
    if (count($vs) > 10) { $p[] = 'at most 10 variants'; }
    $labels = [];
    foreach ($vs as $v) {
        if (!is_array($v) || !isset($v['label'], $v['price']) || !is_string($v['label']) || !is_numeric($v['price']) || is_bool($v['price']) || $v['price'] <= 0 || mb_strlen($v['label']) > 100) {
            $p[] = 'each variant needs a label and a positive price'; break;
        }
        $labels[] = $v['label'];
    }
    if (count($vs) > 1 && (in_array('', $labels, true) || count(array_unique($labels)) !== count($labels))) { $p[] = 'several variants need a distinct label each'; }
    if ($d !== null && (!is_array($d) || !in_array($d['type'] ?? '', ['percent', 'amount'], true) || !is_numeric($d['amount'] ?? null) || $d['amount'] <= 0 || (($d['type'] ?? '') === 'percent' && $d['amount'] > 100))) {
        $p[] = 'discount needs type percent|amount and a positive amount (percent max 100)';
    }
    $wd = $o['weekdays'] ?? [];
    if (!is_array($wd) || count(array_unique($wd)) !== count($wd)) { $p[] = 'weekdays must be unique 0 to 6'; }
    else { foreach ($wd as $x) { if (!is_int($x) || $x < 0 || $x > 6) { $p[] = 'weekdays must be unique 0 to 6'; break; } } }
    $tw = $o['time_window'] ?? null;
    if ($tw !== null && (!is_array($tw) || !preg_match('/^([01]\d|2[0-3]):[0-5]\d$/', (string) ($tw['from'] ?? '')) || !preg_match('/^([01]\d|2[0-3]):[0-5]\d$/', (string) ($tw['to'] ?? '')))) { $p[] = 'time_window needs from and to as HH:MM'; }
    foreach (['valid_from', 'valid_until'] as $k) {
        if (($o[$k] ?? null) !== null && !preg_match('/^\d{4}-\d{2}-\d{2}$/', (string) $o[$k])) { $p[] = "$k must be YYYY-MM-DD"; }
    }
    if (!empty($o['valid_from']) && !empty($o['valid_until']) && $o['valid_until'] < $o['valid_from']) { $p[] = 'valid_until is before valid_from'; }
    $img = $o['image'] ?? null;
    if ($img !== null) {
        if (!is_array($img) || !isset($img['b64'], $img['mime']) || !in_array($img['mime'], ['image/jpeg', 'image/png', 'image/webp'], true)) { $p[] = 'image needs b64 and a jpeg, png or webp mime'; }
        elseif (strlen((string) $img['b64']) > 4 * 1024 * 1024) { $p[] = 'image too large (max about 3 MB)'; }
    }
    return $p;
}

/** Price in major units to FluentCart minor units for a currency with the given decimals factor (100, or 1 for zero-decimal). */
function rsy_offer_minor($price, int $factor): int { return (int) round(((float) $price) * $factor); }

/** The BulkProductInsertService payload for one offer: a draft in category Ofertas; sizes become variations. */
function rsy_offer_payload(array $o, int $factor, string $cid): array
{
    $vs = $o['variants'] ?? [];
    $many = count($vs) > 1;
    $variants = [];
    foreach ($vs as $v) {
        $variants[] = ['variation_title' => $many ? $v['label'] : $o['title'], 'item_price' => rsy_offer_minor($v['price'], $factor), 'other_info' => ['payment_type' => 'onetime']];
    }
    if (!$variants) {
        // a discount-only offer has no price of its own: the shop links it to an existing product after approval
        return [];
    }
    return [
        '_cid' => $cid, 'post_title' => $o['title'], 'post_excerpt' => (string) ($o['description'] ?? ''), 'post_status' => 'draft',
        'detail' => ['fulfillment_type' => 'physical', 'variation_type' => $many ? 'simple_variations' : 'simple'],
        'variants' => $variants, 'categories' => ['Ofertas'],
    ];
}

/** A review is needed unless the draft is clean: no flags, confidence at least 0.8. */
function rsy_offer_clean(array $o): bool { return empty($o['flags']) && (float) ($o['confidence'] ?? 0) >= 0.8; }

function rsy_b64url(string $s): string { return rtrim(strtr(base64_encode($s), '+/', '-_'), '='); }
function rsy_b64url_dec(string $s): string { return (string) base64_decode(strtr($s, '-_', '+/'), true); }

/** Signed approval token: id|action|expiry|nonce, HMAC-SHA256 over that text. The nonce makes it single use. */
function rsy_token_make(int $id, string $action, int $exp, string $nonce, string $secret): string
{
    $body = rsy_b64url("$id|$action|$exp|$nonce");
    return $body . '.' . rsy_b64url(hash_hmac('sha256', $body, $secret, true));
}

/** [id, action, nonce] or null for any problem (malformed, tampered, expired, wrong action). No detail leaks. */
function rsy_token_check(string $token, string $secret, int $now): ?array
{
    $parts = explode('.', $token);
    if (count($parts) !== 2 || $parts[0] === '' || strlen($token) > 300) { return null; }
    $want = rsy_b64url(hash_hmac('sha256', $parts[0], $secret, true));
    if (!hash_equals($want, $parts[1])) { return null; }
    $f = explode('|', rsy_b64url_dec($parts[0]));
    if (count($f) !== 4 || !ctype_digit($f[0]) || !in_array($f[1], ['approve', 'reject'], true) || !ctype_digit($f[2]) || (int) $f[2] < $now) { return null; }
    return [(int) $f[0], $f[1], $f[3]];
}
