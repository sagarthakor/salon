<?php

namespace App\Services\Billing\Gateways;

use Illuminate\Http\Client\PendingRequest;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use RuntimeException;

/**
 * Talks to Razorpay's REST API directly over HTTP (no `razorpay/razorpay`
 * SDK dependency — the API surface used here is small, stable, and
 * documented, and avoiding the SDK keeps this phase from adding an
 * unverified third-party package). Selected because it's the standard
 * India-focused gateway: native INR, recurring-billing support, webhooks,
 * signature-verified payments, refunds, and a real sandbox/test mode — see
 * SAAS_BILLING_ARCHITECTURE.md.
 */
class RazorpayGateway implements PaymentGatewayInterface
{
    private const BASE_URL = 'https://api.razorpay.com/v1';

    public function __construct(
        private readonly ?string $key,
        private readonly ?string $secret,
        private readonly ?string $webhookSecret,
    ) {}

    public function name(): string
    {
        return 'razorpay';
    }

    public function createOrder(string $receipt, float $amount, string $currency, array $notes = []): GatewayOrder
    {
        $response = $this->client()->post(self::BASE_URL.'/orders', [
            // Razorpay amounts are always the smallest currency unit (paise for INR).
            'amount' => (int) round($amount * 100),
            'currency' => $currency,
            'receipt' => $receipt,
            'notes' => $notes,
            'payment_capture' => 1,
        ]);
        if ($response->failed()) {
            Log::error('razorpay.create_order_failed', ['status' => $response->status(), 'receipt' => $receipt]);
            throw new RuntimeException('Could not create a payment order with the gateway.');
        }
        $body = $response->json();

        return new GatewayOrder(id: (string) $body['id'], amount: $amount, currency: $currency, receipt: $receipt);
    }

    public function verifyPaymentSignature(string $orderId, string $paymentId, string $signature): bool
    {
        if ($this->secret === null || $this->secret === '') {
            return false;
        }
        $expected = hash_hmac('sha256', $orderId.'|'.$paymentId, $this->secret);

        return hash_equals($expected, $signature);
    }

    public function verifyWebhookSignature(string $payload, string $signature): bool
    {
        if ($this->webhookSecret === null || $this->webhookSecret === '') {
            return false;
        }
        $expected = hash_hmac('sha256', $payload, $this->webhookSecret);

        return hash_equals($expected, $signature);
    }

    public function refundPayment(string $gatewayPaymentId, ?float $amount = null): GatewayRefund
    {
        $payload = $amount !== null ? ['amount' => (int) round($amount * 100)] : [];
        $response = $this->client()->post(self::BASE_URL."/payments/{$gatewayPaymentId}/refund", $payload);
        if ($response->failed()) {
            Log::error('razorpay.refund_failed', ['status' => $response->status(), 'payment_id' => $gatewayPaymentId]);
            throw new RuntimeException('Could not process the refund with the gateway.');
        }
        $body = $response->json();

        return new GatewayRefund(id: (string) $body['id'], status: (string) ($body['status'] ?? 'processed'));
    }

    private function client(): PendingRequest
    {
        // Laravel's HTTP client already defaults to a 30s request timeout,
        // so this call was never truly unbounded — but every caller here is
        // a synchronous, user-facing checkout request, and 30s is longer
        // than any of them should ever legitimately wait. An explicit,
        // shorter timeout fails fast instead of holding a PHP-FPM worker
        // (and, for initiateCheckout(), a customer-facing HTTP response)
        // for half a minute on a slow/unresponsive gateway.
        return Http::withBasicAuth((string) $this->key, (string) $this->secret)->acceptJson()->timeout(10)->connectTimeout(5);
    }
}
