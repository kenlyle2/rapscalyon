<?php
if (!defined('ABSPATH')) { exit; }

const RSY_TICK_HOOK = 'rsy_schedule_tick';

/** Store the state and purge the page cache when it changes. Truth is still checked at purchase time. */
function rsy_schedule_refresh_state(int $post_id): void
{
    $now = rsy_product_is_active($post_id) ? 'active' : 'inactive';
    if (get_post_meta($post_id, RSY_META_STATE, true) !== $now) {
        update_post_meta($post_id, RSY_META_STATE, $now);
        do_action('litespeed_purge_post', $post_id);
        clean_post_cache($post_id);
    }
}

add_action(RSY_TICK_HOOK, function () {
    $ids = get_posts([
        'post_type' => 'fluent-products', 'post_status' => 'any', 'numberposts' => -1, 'fields' => 'ids',
        'meta_query' => ['relation' => 'OR',
            ['key' => RSY_META_DAYS, 'compare' => 'EXISTS'], ['key' => RSY_META_WINDOW, 'compare' => 'EXISTS'],
            ['key' => RSY_META_FROM, 'compare' => 'EXISTS'], ['key' => RSY_META_UNTIL, 'compare' => 'EXISTS']],
    ]);
    foreach ($ids as $id) { rsy_schedule_refresh_state((int) $id); }
});

add_action('init', function () {
    if (function_exists('as_has_scheduled_action') && !as_has_scheduled_action(RSY_TICK_HOOK)) {
        as_schedule_recurring_action(time() + 60, 15 * MINUTE_IN_SECONDS, RSY_TICK_HOOK, [], 'rapscalyon');
    }
}, 20);

function rsy_schedule_unschedule(): void
{
    if (function_exists('as_unschedule_all_actions')) { as_unschedule_all_actions(RSY_TICK_HOOK); }
}
