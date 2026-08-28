<?php

namespace App\Services\Billing\Gateways;

/**
 * The only contract `SubscriptionService`/`BillingService` and every
 * controller are allowed to depend on for payment-gateway behavior — never a
 * gateway SDK class directly. Bound in `AppServiceProvider` to
 * `RazorpayGateway` by default; tests bind `FakePaymentGateway` instead. See
 * SAAS_BILLING_ARCHITECTURE.md.
 */
interface PaymentGatewayInterface
{
    /** The gateway identifier stored on `payments.gateway`/`subscriptions.gateway` (e.g. 'razorpay'). */
    public function name(): string;

    /**
     * Creates a gateway order for a checkout. [$amount] is always the
     * server-resolved plan amount — callers must never accept it from the
     * client (see SAAS_BILLING_ARCHITECTURE.md, "Amount tampering").
     */
    public function createOrder(string $receipt, float $amount, string $currency, array $notes = []): GatewayOrder;

    /**
     * Verifies a client-reported payment against the gateway's own
     * signature scheme. Returns false — never throws — on any mismatch or
     * malformed input, so callers can uniformly treat "not verified" as one
     * outcome.
     */
    public function verifyPaymentSignature(string $orderId, string $paymentId, string $signature): bool;

    /** Verifies an inbound webhook's signature against the raw request body. */
    public function verifyWebhookSignature(string $payload, string $signature): bool;

    public function refundPayment(string $gatewayPaymentId, ?float $amount = null): GatewayRefund;
}
