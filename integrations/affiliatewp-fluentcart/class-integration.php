<?php
/**
 * AffiliateWP integration for FluentCart. Loaded by AffiliateWP when the integration is enabled.
 *
 * Hooks (verified on FluentCart 1.7.0, see docs/BILLING.md):
 * - fluent_cart/checkout/prepare_other_data: runs in the shopper's request, where the referral cookie exists.
 * - fluent_cart/order_paid_done: runs later (Action Scheduler), after payment is confirmed.
 * - fluent_cart/order_fully_refunded, fluent_cart/order_status_changed_to_canceled.
 */

defined( 'ABSPATH' ) || exit;

use FluentCart\App\Helpers\CurrenciesHelper;

#[\AllowDynamicProperties]
class RapScalYon_Affiliate_WP_FluentCart extends Affiliate_WP_Base {

	public $context = 'fluentcart';

	public function init() {
		add_action( 'fluent_cart/checkout/prepare_other_data', array( $this, 'add_pending_referral' ), 20, 1 );
		add_action( 'fluent_cart/order_paid_done', array( $this, 'mark_referral_complete' ), 10, 1 );
		add_action( 'fluent_cart/order_fully_refunded', array( $this, 'revoke_referral' ), 10, 1 );
		add_action( 'fluent_cart/order_status_changed_to_canceled', array( $this, 'revoke_referral' ), 10, 1 );
	}

	public function plugin_is_active() {
		return defined( 'FLUENTCART_VERSION' ) || class_exists( '\FluentCart\App\App' );
	}

	/**
	 * @param array $data Hook payload with the checkout `order` and `cart`.
	 */
	public function add_pending_referral( $data ) {
		$order = $data['order'] ?? null;

		if ( empty( $order->id ) || ! $this->was_referred() ) {
			return;
		}

		$this->email = $order->customer->email ?? '';

		if ( $this->is_affiliate_email( $this->email ) ) {
			$this->log( 'Referral not created: the buyer is the affiliate.' );
			return;
		}

		$base   = $this->minor_to_major( (int) $order->total_amount - (int) $order->tax_total - (int) $order->shipping_total, $order->currency );
		$amount = $this->calculate_referral_amount( $base, $order->id );

		$this->insert_pending_referral(
			$amount,
			$order->id,
			sprintf( 'FluentCart order #%s', $order->id ),
			array(),
			array( 'order_total' => $this->minor_to_major( (int) $order->total_amount, $order->currency ) )
		);
	}

	/**
	 * @param array $data Hook payload with `order`.
	 */
	public function mark_referral_complete( $data ) {
		$order = $data['order'] ?? null;

		if ( ! empty( $order->id ) ) {
			$this->complete_referral( $order->id );
		}
	}

	/**
	 * @param array $data Hook payload with `order`.
	 */
	public function revoke_referral( $data ) {
		$order = $data['order'] ?? null;

		if ( ! empty( $order->id ) ) {
			$this->reject_referral( $order->id, true );
		}
	}

	public function get_order_total( $order = 0 ) {
		$order = is_object( $order ) ? $order : \FluentCart\App\Models\Order::find( $order );

		return $order ? $this->minor_to_major( (int) $order->total_amount, $order->currency ) : 0;
	}

	public function get_customer( $order_id = 0 ) {
		$order    = \FluentCart\App\Models\Order::with( 'customer' )->find( $order_id );
		$customer = $order->customer ?? null;

		return $customer ? array(
			'email'      => $customer->email,
			'first_name' => $customer->first_name,
			'last_name'  => $customer->last_name,
			'user_id'    => $customer->user_id,
			'ip'         => $order->ip_address,
		) : array();
	}

	/** FluentCart stores money as integer minor units; most currencies have two decimals. */
	private function minor_to_major( $amount, $currency ) {
		return CurrenciesHelper::isZeroDecimal( $currency ) ? $amount : $amount / 100;
	}
}
