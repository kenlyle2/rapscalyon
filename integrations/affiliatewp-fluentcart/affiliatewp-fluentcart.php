<?php
/**
 * Plugin Name: AffiliateWP for FluentCart
 * Description: Records AffiliateWP referrals for FluentCart orders: pending at checkout, unpaid once paid, rejected on a full refund.
 * Version: 0.1.0
 * License: AGPL-3.0-or-later
 * Requires Plugins: affiliate-wp, fluent-cart
 */

defined( 'ABSPATH' ) || exit;

add_filter( 'affwp_extended_integrations', function ( $integrations ) {
	$integrations['fluentcart'] = array(
		'name'  => 'FluentCart',
		'class' => 'RapScalYon_Affiliate_WP_FluentCart',
		'file'  => __DIR__ . '/class-integration.php',
	);

	return $integrations;
} );
