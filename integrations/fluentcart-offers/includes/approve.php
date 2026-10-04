<?php
if (!defined('ABSPATH')) { exit; }

const RSY_TOKEN_TTL = 7 * DAY_IN_SECONDS;

/** Email the shopkeeper two links (approve, reject). The links open a page with a button: opening a link changes nothing. */
function rsy_offers_notify(int $id): void
{
    $s = rsy_offers_settings();
    $to = $s['notify_email'] ?: get_option('admin_email');
    $nonce = wp_generate_password(20, false);
    update_post_meta($id, '_rsy_token_nonce', $nonce);
    $secret = (string) get_option('rsy_offers_secret');
    $link = function ($a) use ($id, $nonce, $secret) {
        return add_query_arg('rsy_offer', rsy_token_make($id, $a, time() + RSY_TOKEN_TTL, $nonce, $secret), home_url('/'));
    };
    $title = get_the_title($id);
    $flags = (array) get_post_meta($id, '_rsy_flags', true);
    $body = "Encontramos esta oferta en su página de Facebook:\n\n" . wp_strip_all_tags($title) . "\n"
        . ($flags ? "\nRevise esto antes de publicar:\n- " . implode("\n- ", $flags) . "\n" : '')
        . "\nPara publicarla en su tienda: " . $link('approve')
        . "\nPara descartarla: " . $link('reject')
        . "\n\nNo se publica nada hasta que usted lo apruebe. Los enlaces valen 7 días.";
    wp_mail($to, 'Nueva oferta para aprobar: ' . wp_strip_all_tags($title), $body);
}

function rsy_offers_page(string $msg, string $form = ''): void
{
    nocache_headers();
    header('X-Robots-Tag: noindex, nofollow');
    header('Referrer-Policy: no-referrer');
    echo '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>Oferta</title>'
        . '<body style="font:18px/1.5 system-ui;max-width:32rem;margin:3rem auto;padding:0 1rem"><p>' . esc_html($msg) . '</p>' . $form . '</body>';
    exit;
}

add_action('template_redirect', function () {
    if (!isset($_GET['rsy_offer'])) { return; }
    $secret = (string) get_option('rsy_offers_secret');
    $token = sanitize_text_field(wp_unslash($_GET['rsy_offer']));
    $invalid = 'Este enlace ya no es válido.';
    $c = $secret ? rsy_token_check($token, $secret, time()) : null;
    if (!$c) { status_header(400); rsy_offers_page($invalid); }
    [$id, $action, $nonce] = $c;
    $stored = (string) get_post_meta($id, '_rsy_token_nonce', true);
    if ($stored === '' || !hash_equals($stored, $nonce) || !in_array(get_post_type($id), ['fluent-products', 'rsy_offer'], true)) { status_header(400); rsy_offers_page($invalid); }
    $title = get_the_title($id);
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        $label = $action === 'approve' ? 'Publicar la oferta' : 'Descartar la oferta';
        rsy_offers_page($title, '<form method="post"><button style="font-size:1.1rem;padding:.7rem 1.2rem">' . esc_html($label) . '</button></form>');
    }
    delete_post_meta($id, '_rsy_token_nonce'); // single use
    rsy_offers_decide($id, $action);
    rsy_offers_page($action === 'approve' ? 'Listo: la oferta está publicada.' : 'Listo: la oferta se descartó y no se volverá a crear.');
});
