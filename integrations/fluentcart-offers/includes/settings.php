<?php
if (!defined('ABSPATH')) { exit; }

function rsy_offers_settings(): array
{
    return wp_parse_args(get_option('rsy_offers_settings', []), ['auto_publish' => 0, 'notify_email' => '']);
}

add_action('admin_init', function () {
    register_setting('rsy_offers', 'rsy_offers_settings', ['sanitize_callback' => function ($v) {
        return ['auto_publish' => empty($v['auto_publish']) ? 0 : 1, 'notify_email' => sanitize_email($v['notify_email'] ?? '')];
    }]);
});

add_action('admin_menu', function () {
    add_options_page('Ofertas', 'RapScalYon Ofertas', 'manage_options', 'rsy-offers', function () {
        $s = rsy_offers_settings();
        echo '<div class="wrap"><h1>Ofertas</h1><form method="post" action="options.php">';
        settings_fields('rsy_offers');
        printf('<p><label><input type="checkbox" name="rsy_offers_settings[auto_publish]" value="1" %s> Publicar solas las ofertas limpias (sin avisos y con confianza alta). Desactivado: cada oferta espera su aprobación.</label></p>', checked($s['auto_publish'], 1, false));
        printf('<p><label>Correo para aprobar ofertas <input type="email" name="rsy_offers_settings[notify_email]" value="%s" class="regular-text"></label></p>', esc_attr($s['notify_email']));
        submit_button();
        echo '</form></div>';
    });
});
