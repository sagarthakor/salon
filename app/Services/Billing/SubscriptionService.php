<?php

namespace App\Services\Billing;

use App\Enums\BillingInterval;
use App\Enums\SubscriptionStatus;
use App\Events\SubscriptionActivated;
use App\Events\SubscriptionCancelled;
use App\Events\SubscriptionCreated;
use App\Events\SubscriptionExpired;
use App\Events\SubscriptionGracePeriod;
use App\Events\SubscriptionPastDue;
use App\Models\Plan;
use App\Models\Subscription;
use App\Models\Tenant;
use App\Support\TenantContext;
use Carbon\CarbonImmutable;
use RuntimeException;

/**
 * The only class allowed to move a subscription between statuses — see
 * SAAS_BILLING_ARCHITECTURE.md for the full state machine and why no
 * controller ever accepts a client-supplied `status`.
 */
class SubscriptionService
{
    /**
     * Called from `Tenant::booted()` for every tenant, however it's created.
     * Silently does nothing if no active plan exists yet (defensive only —
     * the billing migration seeds one in every environment) rather than
     * blocking tenant creation itself on a billing concern.
     */
    public function startTrialFor(Tenant $tenant, ?Plan $plan = null): ?Subscription
    {
        $plan ??= Plan::query()->where('is_active', true)->oldest()->first();
        if ($plan === null) {
            return null;
        }

        $context = app(TenantContext::class);
        $previous = $context->get();
        $context->set($tenant);
        try {
            $now = CarbonImmutable::now();
            $subscription = Subscription::query()->create([
                'tenant_id' => $tenant->id,
                'plan_id' => $plan->id,
                'status' => SubscriptionStatus::TRIALING,
                'trial_starts_at' => $now,
                'trial_ends_at' => $now->addDays($plan->trial_days),
                'starts_at' => $now,
            ]);
            SubscriptionCreated::dispatch($subscription);

            return $subscription;
        } finally {
            $previous !== null ? $context->set($previous) : $context->clear();
        }
    }

    /**
     * First activation after checkout, or renewal — both are the same
     * operation: a verified payment always resets the current billing
     * period from *now*, regardless of what state the subscription was in.
     */
    public function activate(Subscription $subscription, Plan $plan, CarbonImmutable $now): Subscription
    {
        $subscription->update([
            'plan_id' => $plan->id,
            'status' => SubscriptionStatus::ACTIVE,
            'starts_at' => $subscription->starts_at ?? $now,
            'current_period_start' => $now,
            'current_period_end' => $this->addInterval($now, $plan),
            'cancel_at_period_end' => false,
            'cancelled_at' => null,
            'grace_ends_at' => null,
            'ended_at' => null,
        ]);
        SubscriptionActivated::dispatch($subscription);

        return $subscription->refresh();
    }

    /**
     * Owner-initiated cancellation — only ever sets the flag. The
     * subscription keeps normal access until `current_period_end`; the
     * lifecycle processor is what actually moves it to CANCELLED (see
     * `processLifecycle`). Immediate cancellation was not implemented in
     * this phase (optional per spec — "if supported, implement separately
     * and explicitly").
     */
    public function requestCancellation(Subscription $subscription): Subscription
    {
        if (! in_array($subscription->status, SubscriptionStatus::accessAllowed(), true)) {
            throw new RuntimeException('This subscription cannot be cancelled from its current status.');
        }
        $subscription->update(['cancel_at_period_end' => true, 'cancelled_at' => CarbonImmutable::now()]);

        return $subscription->refresh();
    }

    public function markPastDue(Subscription $subscription): Subscription
    {
        $subscription->update([
            'status' => SubscriptionStatus::PAST_DUE,
            'grace_ends_at' => CarbonImmutable::now()->addDays((int) config('billing.grace_period_days')),
        ]);
        SubscriptionPastDue::dispatch($subscription->refresh());

        return $subscription;
    }

    /**
     * Scheduler entry point (`subscriptions:process-lifecycle`) — the only
     * place subscriptions transition due to the passage of time rather than
     * a verified payment or an explicit owner action. Deliberately queries
     * `withoutGlobalScope('tenant')`: this runs platform-wide, across every
     * tenant, from a console context with no `TenantContext` set — the same
     * established pattern `CustomerBookingController` already uses for a
     * customer's cross-tenant booking list.
     *
     * @return array<string, int> counts per transition kind, for the command's output/logging
     */
    public function processLifecycle(?CarbonImmutable $now = null): array
    {
        $now ??= CarbonImmutable::now();
        $summary = ['trial_expired' => 0, 'period_ended_unpaid' => 0, 'cancelled' => 0, 'grace_started' => 0, 'expired' => 0];

        Subscription::query()->withoutGlobalScope('tenant')
            ->where('status', SubscriptionStatus::TRIALING)
            ->where('trial_ends_at', '<', $now)
            ->each(function (Subscription $subscription) use (&$summary): void {
                $this->markPastDue($subscription);
                $summary['trial_expired']++;
            });

        Subscription::query()->withoutGlobalScope('tenant')
            ->where('status', SubscriptionStatus::ACTIVE)
            ->where('current_period_end', '<', $now)
            ->each(function (Subscription $subscription) use (&$summary, $now): void {
                if ($subscription->cancel_at_period_end) {
                    $subscription->update(['status' => SubscriptionStatus::CANCELLED, 'ended_at' => $now]);
                    SubscriptionCancelled::dispatch($subscription->refresh());
                    $summary['cancelled']++;
                } else {
                    $this->markPastDue($subscription);
                    $summary['period_ended_unpaid']++;
                }
            });

        Subscription::query()->withoutGlobalScope('tenant')
            ->where('status', SubscriptionStatus::PAST_DUE)
            ->each(function (Subscription $subscription) use (&$summary): void {
                $subscription->update(['status' => SubscriptionStatus::GRACE_PERIOD]);
                SubscriptionGracePeriod::dispatch($subscription->refresh());
                $summary['grace_started']++;
            });

        Subscription::query()->withoutGlobalScope('tenant')
            ->where('status', SubscriptionStatus::GRACE_PERIOD)
            ->where('grace_ends_at', '<', $now)
            ->each(function (Subscription $subscription) use (&$summary, $now): void {
                $subscription->update(['status' => SubscriptionStatus::EXPIRED, 'ended_at' => $now]);
                SubscriptionExpired::dispatch($subscription->refresh());
                $summary['expired']++;
            });

        return $summary;
    }

    public function addInterval(CarbonImmutable $date, Plan $plan): CarbonImmutable
    {
        $count = $plan->billing_interval_count;

        return match ($plan->billing_interval) {
            BillingInterval::DAY => $date->addDays($count),
            BillingInterval::WEEK => $date->addWeeks($count),
            BillingInterval::MONTH => $date->addMonths($count),
            BillingInterval::YEAR => $date->addYears($count),
        };
    }
}
