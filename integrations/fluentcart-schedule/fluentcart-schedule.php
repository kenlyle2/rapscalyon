<?php
/**
 * Plugin Name: RapScalYon FluentCart Schedule
 * Description: Make a FluentCart product available only on chosen weekdays, hours and dates, in the store's timezone.
 * Version: 0.1.0
 * License: AGPL-3.0-or-later
 *
 * A product with no schedule is untouched. The check is made at the moment of purchase, so it is correct even when
 * WordPress cron is late; the scheduled tick only keeps a stored state and the page cache tidy.
 */
if (!defined('ABSPATH')) { exit; }

define('RSY_SCHEDULE_DIR', __DIR__);
require_once __DIR__ . '/includes/active.php';
require_once __DIR__ . '/includes/config.php';
require_once __DIR__ . '/includes/admin.php';
require_once __DIR__ . '/includes/enforce.php';
require_once __DIR__ . '/includes/tick.php';

register_deactivation_hook(__FILE__, 'rsy_schedule_unschedule');
