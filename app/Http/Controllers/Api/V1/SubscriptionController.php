<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\PaymentStatus;
use App\Http\Requests\Billing\CheckoutRequest;
use App\Http\Requests\Billing\RenewRequest;
use App\Http\Requests\Billing\VerifyPaymentRequest;
use App\Http\Resources\InvoiceResource;
use App\Http\Resources\PaymentResource;
use App\Http\Resources\SubscriptionResource;
use App\Models\Invoice;
use App\Models\Payment;
use App\Models\Plan;
use App\Models\Subscription;
use App\Models\Tenant;
use App\Services\Billing\BillingService;
use App\Services\Billing\Gateways\PaymentGatewayInterface;
use App\Services\Billing\SubscriptionService;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * `show`/`payments`/`invoices` use `viewableTenant()` — any tenant member
 * (owner or staff) may view billing status, matching Phase 9's staff-app
 * precedent of read access without write access. `checkout`/`renew`/`cancel`
 * use `managedTenant()` — owner/super-admin only (Phase 10 instructions
 * #44: "Staff cannot manage tenant subscription"). Never accessible to a
 * `customer` at all — customers hold no tenant membership, so `tenant.context`
 * already rejects them before any of these methods run.
 */
class SubscriptionController extends TenantManagementController
{
    public function __construct(
        private readonly BillingService $billing,
        private readonly SubscriptionService $subscriptions,
        private readonly PaymentGatewayInterface $gateway,
    ) {}

    public function show(): JsonResponse
    {
        $tenant = $this->viewableTenant();
        $subscription = Subscription::query()->with('plan')->first();
        if ($subscription === null) {
            $subscription = $this->subscriptions->startTrialFor($tenant);
        }

        return ApiResponse::success(new SubscriptionResource($subscription), 'Subscription retrieved.');
    }

    public function checkout(CheckoutRequest $request): JsonResponse
    {
        $tenant = $this->managedTenant();
        $plan = Plan::query()->findOrFail($request->validated('plan_id'));
        $subscription = $this->currentSubscription($tenant);
        $payment = $this->billing->initiateCheckout($tenant, $subscription, $plan, $request->header('Idempotency-Key'));

        return ApiResponse::success($this->checkoutPayload($payment, $plan), 'Checkout order created.', 201);
    }

    public function renew(RenewRequest $request): JsonResponse
    {
        $tenant = $this->managedTenant();
        $subscription = $this->currentSubscription($tenant);
        $planId = $request->validated('plan_id') ?? $subscription->plan_id;
        $plan = Plan::query()->findOrFail($planId);
        $payment = $this->billing->initiateCheckout($tenant, $subscription, $plan, $request->header('Idempotency-Key'));

        return ApiResponse::success($this->checkoutPayload($payment, $plan), 'Renewal order created.', 201);
    }

    /**
     * The client-driven half of verification (the webhook, handled by
     * `PaymentWebhookController`, is the server-driven half — whichever
     * arrives first wins, both converge through `BillingService::verifyAndFinalize`).
     * Never trusts the client's claim of success on its own — the gateway
     * signature is independently re-verified here before anything activates.
     */
    public function verify(VerifyPaymentRequest $request): JsonResponse
    {
        $this->managedTenant();
        $payment = Payment::query()->findOrFail($request->validated('payment_id'));
        $payment = $this->billing->verifyAndFinalize($payment, $request->validated('gateway_payment_id'), $request->validated('gateway_signature'));
        if ($payment->status !== PaymentStatus::PAID) {
            return ApiResponse::error('Payment could not be verified.', [], 402);
        }

        return ApiResponse::success(new SubscriptionResource($payment->subscription->fresh('plan')), 'Payment verified. Subscription is now active.');
    }

    public function cancel(): JsonResponse
    {
        $tenant = $this->managedTenant();
        $subscription = $this->currentSubscription($tenant);
        $subscription = $this->subscriptions->requestCancellation($subscription);

        return ApiResponse::success(new SubscriptionResource($subscription->fresh('plan')), 'Subscription will be cancelled at the end of the current billing period.');
    }

    public function payments(Request $request): JsonResponse
    {
        $this->viewableTenant();
        $payments = Payment::query()->latest()->paginate(min($request->integer('per_page', 20), 100));

        return ApiResponse::success(PaymentResource::collection($payments), 'Payments retrieved.');
    }

    public function invoices(Request $request): JsonResponse
    {
        $this->viewableTenant();
        $invoices = Invoice::query()->with('items')->latest()->paginate(min($request->integer('per_page', 20), 100));

        return ApiResponse::success(InvoiceResource::collection($invoices), 'Invoices retrieved.');
    }

    private function currentSubscription(Tenant $tenant): Subscription
    {
        return Subscription::query()->first() ?? $this->subscriptions->startTrialFor($tenant);
    }

    private function checkoutPayload(Payment $payment, Plan $plan): array
    {
        return [
            'payment_id' => $payment->id,
            // Echoed back so the client can safely retry this exact checkout
            // attempt (e.g. after a network timeout) by sending it again as
            // the `Idempotency-Key` header — see SAAS_BILLING_ARCHITECTURE.md.
            'idempotency_key' => $payment->idempotency_key,
            'gateway' => $this->gateway->name(),
            // Public/publishable key only — never the secret. Safe for the
            // Flutter client to receive and hand to the gateway's checkout SDK.
            'gateway_key' => config('services.razorpay.key'),
            'gateway_order_id' => $payment->gateway_order_id,
            'amount' => $plan->amount,
            'currency' => $plan->currency,
            'plan' => ['id' => $plan->id, 'name' => $plan->name, 'code' => $plan->code],
        ];
    }
}
