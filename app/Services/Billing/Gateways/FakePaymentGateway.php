<?php

namespace App\Services\Billing\Gateways;

use Illuminate\Support\Str;

/**
 * Test-only stand-in for `RazorpayGateway`, bound in `tests/TestCase`/
 * individual tests via `$this->app->bind(PaymentGatewayInterface::class, ...)`.
 * Never bound in a real environment — no HTTP calls, no gateway SDK, no
 * network access. Signature verification is driven by [$validSignatures] so
 * a test can exercise both the "verified" and "tampered/invalid" paths
 * deterministically. See SAAS_BILLING_ARCHITECTURE.md, "Payment gateway
 * testing", for what this fake stands in for and why.
 */
class FakePaymentGateway implements PaymentGatewayInterface
{
    /** @var array<string, bool> signature => whether it verifies */
    public array $validSignatures = [];

    /** @var list<array{receipt: string, amount: float, currency: string}> */
    public array $createdOrders = [];

    /**
     * Set to make the next createOrder() call throw, simulating a gateway
     * outage/timeout — used to test that a checkout retry after a failed
     * order-creation call reuses the same pending Payment row rather than
     * creating a duplicate invoice (see BillingService::initiateCheckout()
     * and "Checkout no longer holds a DB transaction across the gateway
     * call" in PERFORMANCE_HARDENING.md). Resets itself after firing once.
     */
    public bool $failNextCreateOrder = false;

    public function name(): string
    {
        return 'fake';
    }

    public function createOrder(string $receipt, float $amount, string $currency, array $notes = []): GatewayOrder
    {
        if ($this->failNextCreateOrder) {
            $this->failNextCreateOrder = false;
            throw new \RuntimeException('Simulated gateway outage.');
        }

        $this->createdOrders[] = ['receipt' => $receipt, 'amount' => $amount, 'currency' => $currency];

        return new GatewayOrder(id: 'order_fake_'.Str::random(12), amount: $amount, currency: $currency, receipt: $receipt);
    }

    public function verifyPaymentSignature(string $orderId, string $paymentId, string $signature): bool
    {
        return $this->validSignatures[$signature] ?? false;
    }

    public function verifyWebhookSignature(string $payload, string $signature): bool
    {
        return $this->validSignatures[$signature] ?? false;
    }

    public function refundPayment(string $gatewayPaymentId, ?float $amount = null): GatewayRefund
    {
        return new GatewayRefund(id: 'rfnd_fake_'.Str::random(12), status: 'processed');
    }
}
