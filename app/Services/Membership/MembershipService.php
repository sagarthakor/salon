<?php

namespace App\Services\Membership;

use App\Enums\CouponDiscountType;
use App\Enums\CustomerMembershipStatus;
use App\Enums\PaymentStatus;
use App\Events\MembershipActivated;
use App\Events\MembershipExpired;
use App\Models\Customer;
use App\Models\CustomerMembership;
use App\Models\MembershipPayment;
use App\Models\MembershipPlan;
use App\Models\Service;
use App\Models\Tenant;
use App\Models\User;
use App\Services\Billing\Gateways\PaymentGatewayInterface;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use RuntimeException;

/**
 * Customer memberships are a completely separate domain from Phase 10's
 * SaaS subscription (owner → platform) — see "Subscription vs Membership"
 * in LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md. This service depends on the
 * exact same `PaymentGatewayInterface` Phase 10 uses (never a second
 * gateway), but owns its own `membership_payments`/`customer_memberships`
 * tables and never touches `SubscriptionService`/`BillingService`.
 */
class MembershipService
{
    public function __construct(private readonly PaymentGatewayInterface $gateway) {}

    public function activeMembershipFor(Tenant $tenant, Customer $customer): ?CustomerMembership
    {
        return CustomerMembership::query()
            ->where('tenant_id', $tenant->id)->where('customer_id', $customer->id)
            ->where('status', CustomerMembershipStatus::ACTIVE)
            ->where('expires_at', '>', CarbonImmutable::now())
            ->latest('starts_at')
            ->first();
    }

    /**
     * @param  Collection<int, Service>  $services
     */
    public function benefitFor(?CustomerMembership $membership, Collection $services): MembershipBenefitResult
    {
        if ($membership === null || ! $membership->isCurrentlyActive()) {
            return MembershipBenefitResult::none();
        }
        $plan = $membership->membershipPlan;
        $qualifying = $this->qualifyingSubtotal($plan, $services);
        if ($qualifying <= 0) {
            return MembershipBenefitResult::none();
        }

        $raw = $plan->discount_type === CouponDiscountType::PERCENTAGE
            ? $qualifying * ((float) $plan->discount_value / 100)
            : (float) $plan->discount_value;
        $capped = min($raw, $qualifying);
        if ($plan->maximum_discount_amount !== null) {
            $capped = min($capped, (float) $plan->maximum_discount_amount);
        }

        return new MembershipBenefitResult($membership, round(max(0.0, $capped), 2));
    }

    /**
     * Starts a membership checkout — the amount charged is always
     * `$plan->price`, never anything the client sends (same rule as Phase
     * 10's checkout; see "Money rule").
     */
    public function initiateCheckout(Tenant $tenant, Customer $customer, MembershipPlan $plan, ?string $idempotencyKey): MembershipPayment
    {
        $payment = null;
        if ($idempotencyKey !== null) {
            $existing = MembershipPayment::query()
                ->where('idempotency_key', $idempotencyKey)
                ->whereIn('status', [PaymentStatus::PENDING, PaymentStatus::PAID])
                ->first();
            if ($existing !== null && ($existing->status === PaymentStatus::PAID || $existing->gateway_order_id !== null)) {
                return $existing;
            }
            // A PENDING payment with no gateway_order_id yet is a prior
            // attempt whose gateway call never completed — reuse it rather
            // than creating a second payment row for the same idempotency key.
            $payment = $existing;
        }

        $payment ??= MembershipPayment::query()->create([
            'tenant_id' => $tenant->id,
            'customer_id' => $customer->id,
            'membership_plan_id' => $plan->id,
            'amount' => $plan->price,
            'currency' => $plan->currency,
            'status' => PaymentStatus::PENDING,
            'gateway' => $this->gateway->name(),
            'idempotency_key' => $idempotencyKey ?? (string) Str::ulid(),
        ]);

        // Deliberately outside any DB transaction/lock — see the identical
        // reasoning in BillingService::initiateCheckout() and
        // PERFORMANCE_HARDENING.md.
        $order = $this->gateway->createOrder(receipt: $payment->id, amount: (float) $plan->price, currency: $plan->currency, notes: [
            'tenant_id' => $tenant->id,
            'membership_plan_code' => $plan->code,
        ]);
        $payment->update(['gateway_order_id' => $order->id]);

        return $payment->refresh();
    }

    /**
     * The client-driven half of verification — re-verifies the gateway
     * signature server-side, so a membership is never activated solely
     * because the client claims success. The webhook handler
     * (`PaymentWebhookController`) is the server-driven half, converging on
     * the same `recordSuccess()` below; whichever arrives first wins,
     * matching Phase 10's `BillingService::verifyAndFinalize()` pattern
     * exactly.
     */
    public function verifyAndFinalize(MembershipPayment $payment, string $gatewayPaymentId, string $gatewaySignature): MembershipPayment
    {
        if ($payment->status === PaymentStatus::PAID) {
            return $payment;
        }
        if ($payment->gateway_order_id === null) {
            return $this->recordFailure($payment, 'Payment has no associated gateway order.');
        }
        $verified = $this->gateway->verifyPaymentSignature($payment->gateway_order_id, $gatewayPaymentId, $gatewaySignature);
        if (! $verified) {
            return $this->recordFailure($payment, 'Gateway signature verification failed.');
        }

        return $this->recordSuccess($payment, $gatewayPaymentId, $gatewaySignature);
    }

    /**
     * The single path both `verifyAndFinalize()` and the webhook handler
     * call once a payment is known-good (signature already verified by
     * whichever caller). Idempotent: an already-PAID payment is returned
     * unchanged.
     */
    public function recordSuccess(MembershipPayment $payment, string $gatewayPaymentId, ?string $gatewaySignature = null): MembershipPayment
    {
        if ($payment->status === PaymentStatus::PAID) {
            return $payment;
        }

        return DB::transaction(function () use ($payment, $gatewayPaymentId, $gatewaySignature): MembershipPayment {
            $now = CarbonImmutable::now();
            $payment->update([
                'status' => PaymentStatus::PAID,
                'gateway_payment_id' => $gatewayPaymentId,
                'gateway_signature' => $gatewaySignature,
                'paid_at' => $now,
            ]);

            $membership = $this->activate($payment->tenant, $payment->customer, $payment->membershipPlan, (float) $payment->amount, $payment->currency, 'purchase', $now);
            $payment->update(['customer_membership_id' => $membership->id]);

            return $payment->refresh();
        });
    }

    public function recordFailure(MembershipPayment $payment, string $reason): MembershipPayment
    {
        if ($payment->status === PaymentStatus::PAID) {
            return $payment;
        }
        $payment->update(['status' => PaymentStatus::FAILED, 'failed_at' => CarbonImmutable::now(), 'failure_reason' => $reason]);

        return $payment->refresh();
    }

    /**
     * Owner-granted membership — no payment, fully auditable
     * (`source = 'owner_grant'`, `purchased_amount = 0`). Never fakes a
     * payment record. See "Membership purchase without payment".
     */
    public function grant(Tenant $tenant, Customer $customer, MembershipPlan $plan, ?User $actor): CustomerMembership
    {
        return DB::transaction(fn () => $this->activate($tenant, $customer, $plan, 0.0, $plan->currency, 'owner_grant', CarbonImmutable::now()));
    }

    /**
     * Cancels any other currently-active membership for this customer (at
     * most one active membership at a time — see "Membership renewal": a
     * renewal is simply purchasing/granting again) and creates the new one.
     */
    private function activate(Tenant $tenant, Customer $customer, MembershipPlan $plan, float $amount, string $currency, string $source, CarbonImmutable $now): CustomerMembership
    {
        CustomerMembership::query()
            ->where('tenant_id', $tenant->id)->where('customer_id', $customer->id)
            ->where('status', CustomerMembershipStatus::ACTIVE)
            ->update(['status' => CustomerMembershipStatus::CANCELLED]);

        $membership = CustomerMembership::query()->create([
            'tenant_id' => $tenant->id,
            'customer_id' => $customer->id,
            'membership_plan_id' => $plan->id,
            'status' => CustomerMembershipStatus::ACTIVE,
            'starts_at' => $now,
            'expires_at' => $now->addDays($plan->duration_days),
            'purchased_amount' => $amount,
            'currency' => $currency,
            'source' => $source,
        ]);
        MembershipActivated::dispatch($membership);

        return $membership;
    }

    /**
     * @return array{expired: int}
     */
    public function expireDueMemberships(?CarbonImmutable $now = null): array
    {
        $now = $now ?? CarbonImmutable::now();
        $summary = ['expired' => 0];

        CustomerMembership::query()->withoutGlobalScope('tenant')
            ->where('status', CustomerMembershipStatus::ACTIVE)
            ->where('expires_at', '<', $now)
            ->each(function (CustomerMembership $membership) use (&$summary): void {
                $membership->update(['status' => CustomerMembershipStatus::EXPIRED]);
                MembershipExpired::dispatch($membership->refresh());
                $summary['expired']++;
            });

        return $summary;
    }

    public function cancel(CustomerMembership $membership): CustomerMembership
    {
        if ($membership->status !== CustomerMembershipStatus::ACTIVE) {
            throw new RuntimeException('Only an active membership can be cancelled.');
        }
        $membership->update(['status' => CustomerMembershipStatus::CANCELLED]);

        return $membership->refresh();
    }

    /**
     * @param  Collection<int, Service>  $services
     */
    private function qualifyingSubtotal(MembershipPlan $plan, Collection $services): float
    {
        if ($plan->appliesToAllServices()) {
            return (float) $services->sum('price');
        }

        $allowedServiceIds = $plan->services()->pluck('services.id')->all();
        $allowedCategoryIds = $plan->categories()->pluck('service_categories.id')->all();

        return (float) $services
            ->filter(fn ($service) => in_array($service->id, $allowedServiceIds, true) || in_array($service->category_id, $allowedCategoryIds, true))
            ->sum('price');
    }
}
