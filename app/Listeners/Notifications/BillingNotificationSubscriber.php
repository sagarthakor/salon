<?php

namespace App\Listeners\Notifications;

use App\Enums\NotificationEventType;
use App\Events\PaymentFailed;
use App\Events\PaymentSucceeded;
use App\Events\SubscriptionActivated;
use App\Events\SubscriptionCancelled;
use App\Events\SubscriptionExpired;
use App\Events\SubscriptionGracePeriod;
use App\Events\SubscriptionPastDue;
use App\Models\Tenant;
use App\Services\Notifications\NotificationDispatcher;
use Illuminate\Contracts\Events\ShouldBeDiscovered;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Events\Dispatcher;

/**
 * Notifies the tenant's owner(s) of billing/subscription lifecycle events.
 * Payment/Subscription rows carry `tenant_id` directly and `Tenant` itself
 * is never tenant-scoped, so — unlike BookingNotificationSubscriber — no
 * TenantContext juggling is needed here to resolve the tenant or its owners.
 *
 * See BookingNotificationSubscriber for why ShouldBeDiscovered::false is
 * required alongside the explicit Event::subscribe() registration.
 */
class BillingNotificationSubscriber implements ShouldBeDiscovered, ShouldQueue
{
    public static function shouldBeDiscovered(): bool
    {
        return false;
    }

    public bool $afterCommit = true;

    public function __construct(private readonly NotificationDispatcher $dispatcher) {}

    public function subscribe(Dispatcher $events): array
    {
        return [
            PaymentSucceeded::class => 'handlePaymentSucceeded',
            PaymentFailed::class => 'handlePaymentFailed',
            SubscriptionActivated::class => 'handleSubscriptionActivated',
            SubscriptionPastDue::class => 'handleSubscriptionPastDue',
            SubscriptionGracePeriod::class => 'handleSubscriptionGracePeriod',
            SubscriptionExpired::class => 'handleSubscriptionExpired',
            SubscriptionCancelled::class => 'handleSubscriptionCancelled',
        ];
    }

    public function handlePaymentSucceeded(PaymentSucceeded $event): void
    {
        $this->notifyOwners($event->payment->tenant_id, NotificationEventType::PAYMENT_SUCCEEDED, [
            'amount' => $event->payment->amount,
            'currency' => $event->payment->currency,
        ]);
    }

    public function handlePaymentFailed(PaymentFailed $event): void
    {
        $this->notifyOwners($event->payment->tenant_id, NotificationEventType::PAYMENT_FAILED, [
            'amount' => $event->payment->amount,
            'currency' => $event->payment->currency,
        ]);
    }

    public function handleSubscriptionActivated(SubscriptionActivated $event): void
    {
        $this->notifyOwners($event->subscription->tenant_id, NotificationEventType::SUBSCRIPTION_ACTIVATED, [
            'plan_name' => $event->subscription->plan?->name ?? 'your plan',
        ]);
    }

    public function handleSubscriptionPastDue(SubscriptionPastDue $event): void
    {
        $this->notifyOwners($event->subscription->tenant_id, NotificationEventType::SUBSCRIPTION_PAST_DUE, []);
    }

    public function handleSubscriptionGracePeriod(SubscriptionGracePeriod $event): void
    {
        $this->notifyOwners($event->subscription->tenant_id, NotificationEventType::SUBSCRIPTION_GRACE_PERIOD, [
            'grace_ends_at' => $event->subscription->grace_ends_at?->toDateString(),
        ]);
    }

    public function handleSubscriptionExpired(SubscriptionExpired $event): void
    {
        $this->notifyOwners($event->subscription->tenant_id, NotificationEventType::SUBSCRIPTION_EXPIRED, []);
    }

    public function handleSubscriptionCancelled(SubscriptionCancelled $event): void
    {
        $this->notifyOwners($event->subscription->tenant_id, NotificationEventType::SUBSCRIPTION_CANCELLED, []);
    }

    /**
     * @param  array<string, mixed>  $context
     */
    private function notifyOwners(string $tenantId, NotificationEventType $event, array $context): void
    {
        $tenant = Tenant::query()->find($tenantId);
        if ($tenant === null) {
            return;
        }
        foreach ($tenant->users()->wherePivot('role', 'salon_owner')->get() as $owner) {
            $this->dispatcher->dispatch($tenant, $owner, $event, 'owner', $context);
        }
    }
}
