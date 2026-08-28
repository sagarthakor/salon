<?php

namespace App\Listeners\Loyalty;

use App\Enums\NotificationEventType;
use App\Events\BookingCompleted;
use App\Services\Loyalty\LoyaltyService;
use App\Services\Notifications\NotificationDispatcher;
use App\Support\TenantContext;
use Illuminate\Contracts\Events\ShouldBeDiscovered;
use Illuminate\Contracts\Queue\ShouldQueue;

/**
 * Awards loyalty points only on COMPLETED — never on mere creation (see
 * "Loyalty earning timing" in LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md).
 * `LoyaltyService::earnForBooking()` itself is idempotent (a unique
 * `(booking_id, type)` constraint on `loyalty_transactions`), so a
 * redelivered/duplicated event is always safe.
 *
 * See BookingNotificationSubscriber (Phase 11) for why ShouldBeDiscovered
 * must return false here too — otherwise Laravel's automatic event
 * discovery double-registers this alongside its class-based registration.
 */
class AwardLoyaltyPointsOnBookingCompleted implements ShouldBeDiscovered, ShouldQueue
{
    public static function shouldBeDiscovered(): bool
    {
        return false;
    }

    public bool $afterCommit = true;

    public function __construct(
        private readonly LoyaltyService $loyalty,
        private readonly NotificationDispatcher $dispatcher,
    ) {}

    public function handle(BookingCompleted $event): void
    {
        $booking = $event->booking;
        $context = app(TenantContext::class);
        $previous = $context->get();
        $context->set($booking->tenant);
        try {
            $booking->loadMissing(['branch.salon', 'customer.user']);
            $transaction = $this->loyalty->earnForBooking($booking);
            if ($transaction === null) {
                return;
            }

            $booking->update(['loyalty_points_earned' => $transaction->points]);

            $customerUser = $booking->customer?->user;
            if ($customerUser !== null) {
                $this->dispatcher->dispatch(
                    $booking->tenant,
                    $customerUser,
                    NotificationEventType::LOYALTY_POINTS_EARNED,
                    'customer',
                    ['points' => $transaction->points, 'balance' => $transaction->balance_after],
                    $booking,
                );
            }
        } finally {
            $previous !== null ? $context->set($previous) : $context->clear();
        }
    }
}
