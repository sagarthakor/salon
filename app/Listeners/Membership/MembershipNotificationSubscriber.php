<?php

namespace App\Listeners\Membership;

use App\Enums\NotificationEventType;
use App\Events\MembershipActivated;
use App\Events\MembershipExpired;
use App\Models\CustomerMembership;
use App\Services\Notifications\NotificationDispatcher;
use App\Support\TenantContext;
use Illuminate\Contracts\Events\ShouldBeDiscovered;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Events\Dispatcher;

/**
 * Notifies the customer of their own membership lifecycle — reuses Phase
 * 11's NotificationDispatcher outright, no new channel/provider code. See
 * BookingNotificationSubscriber for why ShouldBeDiscovered::false is
 * required alongside the explicit Event::subscribe() registration.
 */
class MembershipNotificationSubscriber implements ShouldBeDiscovered, ShouldQueue
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
            MembershipActivated::class => 'handleActivated',
            MembershipExpired::class => 'handleExpired',
        ];
    }

    public function handleActivated(MembershipActivated $event): void
    {
        $this->notifyCustomer($event->membership, NotificationEventType::MEMBERSHIP_ACTIVATED);
    }

    public function handleExpired(MembershipExpired $event): void
    {
        $this->notifyCustomer($event->membership, NotificationEventType::MEMBERSHIP_EXPIRED);
    }

    private function notifyCustomer(CustomerMembership $membership, NotificationEventType $event): void
    {
        $context = app(TenantContext::class);
        $previous = $context->get();
        $context->set($membership->tenant);
        try {
            $membership->loadMissing(['customer.user', 'membershipPlan']);
            $customerUser = $membership->customer?->user;
            if ($customerUser === null) {
                return;
            }
            $this->dispatcher->dispatch($membership->tenant, $customerUser, $event, 'customer', [
                'plan_name' => $membership->membershipPlan->name,
                'expires_at' => $membership->expires_at->toDateString(),
            ], $membership);
        } finally {
            $previous !== null ? $context->set($previous) : $context->clear();
        }
    }
}
