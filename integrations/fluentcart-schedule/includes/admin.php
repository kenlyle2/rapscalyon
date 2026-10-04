<?php
if (!defined('ABSPATH')) { exit; }

const RSY_NONCE = 'rsy_schedule_save';

add_action('add_meta_boxes', function () {
    add_meta_box('rsy-schedule', 'Disponibilidad (días y horas)', 'rsy_schedule_box', 'fluent-products', 'side');
});

function rsy_schedule_box(WP_Post $post): void
{
    $cfg = rsy_get_config($post->ID);
    $days = $cfg['days'] ?? [];
    $names = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
    wp_nonce_field(RSY_NONCE, 'rsy_nonce');
    echo '<p>Sin días marcados = todos los días. Hora de la tienda: ' . esc_html(wp_timezone_string()) . '.</p>';
    foreach ($names as $i => $n) {
        printf('<label style="display:block"><input type="checkbox" name="rsy_days[]" value="%d" %s> %s</label>', $i, checked(in_array($i, $days, true), true, false), esc_html($n));
    }
    printf('<p><label>Desde <input type="time" name="rsy_from" value="%s"></label> <label>hasta <input type="time" name="rsy_to" value="%s"></label></p>',
        esc_attr($cfg['window']['from'] ?? ''), esc_attr($cfg['window']['to'] ?? ''));
    printf('<p><label>Válida desde <input type="date" name="rsy_valid_from" value="%s"></label></p>', esc_attr($cfg['valid_from'] ?? ''));
    printf('<p><label>Válida hasta <input type="date" name="rsy_valid_until" value="%s"></label></p>', esc_attr($cfg['valid_until'] ?? ''));
}

add_action('save_post_fluent-products', function (int $post_id) {
    if (defined('DOING_AUTOSAVE') && DOING_AUTOSAVE) { return; }
    if (!isset($_POST['rsy_nonce']) || !wp_verify_nonce(sanitize_text_field(wp_unslash($_POST['rsy_nonce'])), RSY_NONCE)) { return; }
    if (!current_user_can('edit_post', $post_id)) { return; }
    $days = isset($_POST['rsy_days']) ? array_values(array_unique(array_filter(array_map('intval', (array) wp_unslash($_POST['rsy_days'])), function ($d) { return $d >= 0 && $d <= 6; }))) : [];
    $from = isset($_POST['rsy_from']) ? sanitize_text_field(wp_unslash($_POST['rsy_from'])) : '';
    $to = isset($_POST['rsy_to']) ? sanitize_text_field(wp_unslash($_POST['rsy_to'])) : '';
    $ok = function ($v) { return rsy_minutes($v) !== null; };
    $date = function ($k) { $v = isset($_POST[$k]) ? sanitize_text_field(wp_unslash($_POST[$k])) : ''; return preg_match('/^\d{4}-\d{2}-\d{2}$/', $v) ? $v : ''; };
    $days ? update_post_meta($post_id, RSY_META_DAYS, $days) : delete_post_meta($post_id, RSY_META_DAYS);
    ($ok($from) && $ok($to)) ? update_post_meta($post_id, RSY_META_WINDOW, ['from' => $from, 'to' => $to]) : delete_post_meta($post_id, RSY_META_WINDOW);
    foreach ([RSY_META_FROM => 'rsy_valid_from', RSY_META_UNTIL => 'rsy_valid_until'] as $meta => $key) {
        $v = $date($key);
        $v ? update_post_meta($post_id, $meta, $v) : delete_post_meta($post_id, $meta);
    }
    rsy_schedule_refresh_state($post_id);
});
