<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\MembershipPayment;
use App\Models\Payment;
use App\Models\WebhookEvent;
use App\Services\Billing\BillingService;
use App\Services\Billing\Gateways\PaymentGatewayInterface;
use App\Services\Membership\MembershipService;
use App\Support\ApiResponse;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * No `auth:sanctum` — the gateway, not an authenticated user, calls this.
 * Authenticity comes entirely from the signature check below, never from
 * anything else in the request. See SAAS_BILLING_ARCHITECTURE.md, "Webhooks".
 *
 * Idempotency: every event is recorded in `webhook_events` (unique on
 * gateway + event id), looked up with a row lock, so a duplicated/retried
 * delivery of the same event is a safe no-op rather than a second
 * payment/invoice/period extension. Critically, "already handled" means
 * `processed_at` is actually set, not merely that the row exists — a
 * webhook whose row was created but whose `process()` call then threw
 * (e.g. a transient DB error) reuses that same row and is genuinely
 * retried on the next delivery, rather than being permanently swallowed as
 * a duplicate even though it never actually completed. See "Webhook
 * idempotency" in SECURITY_HARDENING.md.
 */
class PaymentWebhookController extends Controller
{
    public function __construct(
        private readonly PaymentGatewayInterface $gateway,
        private readonly BillingService $billing,
        private readonly MembershipService $memberships,
    ) {}

    public function handle(Request $request): JsonResponse
    {
        $rawPayload = $request->getContent();
        $signature = (string) $request->header('X-Razorpay-Signature', '');

        if (! $this->gateway->verifyWebhookSignature($rawPayload, $signature)) {
            Log::warning('billing.webhook_signature_invalid', ['gateway' => $this->gateway->name()]);

            return response()->json(['success' => false, 'message' => 'Invalid webhook signature.', 'errors' => (object) []], 400);
        }

        $payload = json_decode($rawPayload, true) ?? [];
        $eventType = (string) ($payload['event'] ?? 'unknown');
        // Razorpay sends `X-Razorpay-Event-Id`; if a gateway/version doesn't,
        // fall back to a content hash so the same delivery still dedupes.
        $eventId = (string) $request->header('X-Razorpay-Event-Id', hash('sha256', $rawPayload));

        $event = DB::transaction(function () use ($eventType, $eventId, $payload): ?WebhookEvent {
            $existing = WebhookEvent::query()
                ->where('gateway', $this->gateway->name())
                ->where('gateway_event_id', $eventId)
                ->lockForUpdate()
                ->first();
            if ($existing !== null && $existing->processed_at !== null) {
                return null;
            }

            return $existing ?? WebhookEvent::query()->create([
                'gateway' => $this->gateway->name(),
                'gateway_event_id' => $eventId,
                'event_type' => $eventType,
                'payload' => $payload,
            ]);
        });

        if ($event === null) {
            Log::info('billing.webhook_duplicate', ['gateway' => $this->gateway->name(), 'event_id' => $eventId]);

            return ApiResponse::success(null, 'Event already processed.');
        }

        $this->process($eventType, $payload);
        $event->update(['processed_at' => now()]);

        return ApiResponse::success(null, 'Webhook processed.');
    }

    private function process(string $eventType, array $payload): void
    {
        $entity = $payload['payload']['payment']['entity'] ?? null;
        $orderId = $entity['order_id'] ?? null;
        $gatewayPaymentId = $entity['id'] ?? null;
        if ($entity === null || $orderId === null || $gatewayPaymentId === null) {
            return;
        }

        // No authenticated tenant session on a webhook — an intentional,
        // narrow cross-tenant lookup by gateway order id, the same
        // `withoutGlobalScope('tenant')` pattern already used for the
        // customer app's cross-tenant own-bookings list.
        $payment = Payment::query()->withoutGlobalScope('tenant')->where('gateway_order_id', $orderId)->first();
        if ($payment !== null) {
            $this->processSubscriptionPayment($payment, $eventType, $gatewayPaymentId, $entity);

            return;
        }

        // Phase 12 — the same webhook endpoint also converges membership
        // purchases (a completely separate `membership_payments` domain, see
        // "Subscription vs Membership" in
        // LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md) rather than adding a
        // second webhook route for what is, from the gateway's perspective,
        // the same kind of event.
        $membershipPayment = MembershipPayment::query()->withoutGlobalScope('tenant')->where('gateway_order_id', $orderId)->first();
        if ($membershipPayment !== null) {
            $this->processMembershipPayment($membershipPayment, $eventType, $gatewayPaymentId, $entity);

            return;
        }

        Log::warning('billing.webhook_unknown_order', ['order_id' => $orderId]);
    }

    private function processSubscriptionPayment(Payment $payment, string $eventType, string $gatewayPaymentId, array $entity): void
    {
        $context = app(TenantContext::class);
        $context->set($payment->tenant);
        try {
            match ($eventType) {
                'payment.captured' => $this->billing->recordPaymentSuccess($payment, $gatewayPaymentId),
                'payment.failed' => $this->billing->recordPaymentFailure($payment, (string) ($entity['error_description'] ?? 'Payment failed at the gateway.')),
                default => null,
            };
        } finally {
            $context->clear();
        }
    }

    private function processMembershipPayment(MembershipPayment $payment, string $eventType, string $gatewayPaymentId, array $entity): void
    {
        $context = app(TenantContext::class);
        $context->set($payment->tenant);
        try {
            match ($eventType) {
                'payment.captured' => $this->memberships->recordSuccess($payment, $gatewayPaymentId),
                'payment.failed' => $this->memberships->recordFailure($payment, (string) ($entity['error_description'] ?? 'Payment failed at the gateway.')),
                default => null,
            };
        } finally {
            $context->clear();
        }
    }
}
