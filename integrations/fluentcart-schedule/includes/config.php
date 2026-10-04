<?php
if (!defined('ABSPATH')) { exit; }

/** Meta keys, shared with the offers plugin. */
const RSY_META_DAYS = '_rsy_days';
const RSY_META_WINDOW = '_rsy_window';
const RSY_META_FROM = '_rsy_valid_from';
const RSY_META_UNTIL = '_rsy_valid_until';
const RSY_META_STATE = '_rsy_state';

/** The schedule stored on a product, in the shape rsy_is_active() takes. Empty array = no schedule. */
function rsy_get_config(int $post_id): array
{
    $days = get_post_meta($post_id, RSY_META_DAYS, true);
    $win = get_post_meta($post_id, RSY_META_WINDOW, true);
    $cfg = [
        'days'        => is_array($days) ? array_map('intval', $days) : [],
        'window'      => (is_array($win) && !empty($win['from']) && !empty($win['to'])) ? ['from' => (string) $win['from'], 'to' => (string) $win['to']] : null,
        'valid_from'  => (string) get_post_meta($post_id, RSY_META_FROM, true) ?: null,
        'valid_until' => (string) get_post_meta($post_id, RSY_META_UNTIL, true) ?: null,
    ];
    return ($cfg['days'] || $cfg['window'] || $cfg['valid_from'] || $cfg['valid_until']) ? $cfg : [];
}

function rsy_product_is_active(int $post_id, ?int $now = null): bool
{
    $cfg = rsy_get_config($post_id);
    return !$cfg || rsy_is_active($cfg, $now ?? time(), wp_timezone_string());
}
