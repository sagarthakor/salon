<?php

namespace App\Listeners\Notifications;

use App\Enums\NotificationEventType;
use App\Events\BookingCancelled;
use App\Events\BookingCheckedIn;
use App\Events\BookingCompleted;
use App\Events\BookingConfirmed;
use App\Events\BookingCreated;
use App\Events\BookingNoShow;
use App\Events\BookingRescheduled;
use App\Events\BookingStarted;
use App\Models\Booking;
use App\Services\Notifications\BookingRecipientResolver;
use App\Services\Notifications\NotificationDispatcher;
use App\Support\TenantContext;
use Illuminate\Contracts\Events\ShouldBeDiscovered;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Events\Dispatcher;

/**
 * The "Notification Dispatcher" side of every booking lifecycle event —
 * resolves who should be notified (customer/staff/owner) and hands each one
 * to NotificationDispatcher. Booking/BookingService itself never calls a
 * channel or provider; it only fires the plain domain event (see
 * NOTIFICATION_ARCHITECTURE.md).
 *
 * `$afterCommit = true` (from ShouldQueue's queued-listener contract) is
 * what guarantees this never runs before the originating booking
 * transaction commits — see BookingService, which fires these events as the
 * last statement inside `DB::transaction()`.
 *
 * Implements ShouldBeDiscovered (returning false) to opt OUT of Laravel's
 * automatic event discovery: `Application::configure()` enables listener
 * auto-discovery by default, which would otherwise register every `handle*`
 * method here a second time on top of the explicit `Event::subscribe()` call
 * in AppServiceProvider, double-firing every notification.
 */
class BookingNotificationSubscriber implements ShouldBeDiscovered, ShouldQueue
{
    public static function shouldBeDiscovered(): bool
    {
        return false;
    }

    public bool $afterCommit = true;

    public function __construct(
        private readonly NotificationDispatcher $dispatcher,
        private readonly BookingRecipientResolver $recipients,
    ) {}

    public function subscribe(Dispatcher $events): array
    {
        return [
            BookingCreated::class => 'handleCreated',
            BookingConfirmed::class => 'handleConfirmed',
            BookingRescheduled::class => 'handleRescheduled',
            BookingCancelled::class => 'handleCancelled',
            BookingCheckedIn::class => 'handleCheckedIn',
            BookingStarted::class => 'handleStarted',
            BookingCompleted::class => 'handleCompleted',
            BookingNoShow::class => 'handleNoShow',
        ];
    }

    public function handleCreated(BookingCreated $event): void
    {
        $this->withBooking($event->booking, function (Booking $booking): void {
            $context = $this->context($booking);
            if (($customer = $this->recipients->customerUser($booking)) !== null) {
                $this->dispatcher->dispatch($booking->tenant, $customer, NotificationEventType::BOOKING_CREATED, 'customer', $context, $booking, $this->recipients->customerPhone($booking));
            }
            foreach ($this->recipients->staffUsers($booking) as $staff) {
                $this->dispatcher->dispatch($booking->tenant, $staff, NotificationEventType::BOOKING_CREATED, 'staff', $context, $booking);
            }
            foreach ($this->recipients->ownerUsers($booking->tenant) as $owner) {
                $this->dispatcher->dispatch($booking->tenant, $owner, NotificationEventType::BOOKING_CREATED, 'owner', $context, $booking);
            }
        });
    }

    public function handleConfirmed(BookingConfirmed $event): void
    {
        $this->withBooking($event->booking, function (Booking $booking): void {
            $context = $this->context($booking);
            if (($customer = $this->recipients->customerUser($booking)) !== null) {
                $this->dispatcher->dispatch($booking->tenant, $customer, NotificationEventType::BOOKING_CONFIRMED, 'customer', $context, $booking, $this->recipients->customerPhone($booking));
            }
            foreach ($this->recipients->staffUsers($booking) as $staff) {
                $this->dispatcher->dispatch($booking->tenant, $staff, NotificationEventType::BOOKING_CONFIRMED, 'staff', $context, $booking);
            }
        });
    }

    public function handleRescheduled(BookingRescheduled $event): void
    {
        $this->withBooking($event->booking, function (Booking $booking) use ($event): void {
            $context = $this->context($booking) + ['old_date' => $event->previousDate, 'old_time' => $event->previousStartTime];
            if (($customer = $this->recipients->customerUser($booking)) !== null) {
                $this->dispatcher->dispatch($booking->tenant, $customer, NotificationEventType::BOOKING_RESCHEDULED, 'customer', $context, $booking, $this->recipients->customerPhone($booking));
            }
            foreach ($this->recipients->staffUsers($booking) as $staff) {
                $this->dispatcher->dispatch($booking->tenant, $staff, NotificationEventType::BOOKING_RESCHEDULED, 'staff', $context, $booking);
            }
        });
    }

    public function handleCancelled(BookingCancelled $event): void
    {
        $this->withBooking($event->booking, function (Booking $booking): void {
            $context = $this->context($booking) + ['reason' => $booking->cancellation_reason];
            if (($customer = $this->recipients->customerUser($booking)) !== null) {
                $this->dispatcher->dispatch($booking->tenant, $customer, NotificationEventType::BOOKING_CANCELLED, 'customer', $context, $booking, $this->recipients->customerPhone($booking));
            }
            foreach ($this->recipients->staffUsers($booking) as $staff) {
                $this->dispatcher->dispatch($booking->tenant, $staff, NotificationEventType::BOOKING_CANCELLED, 'staff', $context, $booking);
            }
            foreach ($this->recipients->ownerUsers($booking->tenant) as $owner) {
                $this->dispatcher->dispatch($booking->tenant, $owner, NotificationEventType::BOOKING_CANCELLED, 'owner', $context, $booking);
            }
        });
    }

    /**
     * Low-noise operational transitions — owner-facing only (an audit trail
     * of "the day's bookings moved forward"), never pushed/emailed/texted to
     * the customer or the staff member who is the one making the change.
     * See NOTIFICATION_ARCHITECTURE.md, "Booking status changes".
     */
    public function handleCheckedIn(BookingCheckedIn $event): void
    {
        $this->notifyOwnersOnly($event->booking, NotificationEventType::BOOKING_CHECKED_IN);
    }

    public function handleStarted(BookingStarted $event): void
    {
        $this->notifyOwnersOnly($event->booking, NotificationEventType::BOOKING_STARTED);
    }

    public function handleCompleted(BookingCompleted $event): void
    {
        $this->withBooking($event->booking, function (Booking $booking): void {
            $context = $this->context($booking);
            if (($customer = $this->recipients->customerUser($booking)) !== null) {
                $this->dispatcher->dispatch($booking->tenant, $customer, NotificationEventType::BOOKING_COMPLETED, 'customer', $context, $booking, $this->recipients->customerPhone($booking));
            }
            foreach ($this->recipients->staffUsers($booking) as $staff) {
                $this->dispatcher->dispatch($booking->tenant, $staff, NotificationEventType::BOOKING_COMPLETED, 'staff', $context, $booking);
            }
        });
    }

    public function handleNoShow(BookingNoShow $event): void
    {
        $this->withBooking($event->booking, function (Booking $booking): void {
            $context = $this->context($booking);
            foreach ($this->recipients->ownerUsers($booking->tenant) as $owner) {
                $this->dispatcher->dispatch($booking->tenant, $owner, NotificationEventType::BOOKING_NO_SHOW, 'owner', $context, $booking);
            }
            foreach ($this->recipients->staffUsers($booking) as $staff) {
                $this->dispatcher->dispatch($booking->tenant, $staff, NotificationEventType::BOOKING_NO_SHOW, 'staff', $context, $booking);
            }
        });
    }

    private function notifyOwnersOnly(Booking $booking, NotificationEventType $event): void
    {
        $this->withBooking($booking, function (Booking $booking) use ($event): void {
            $context = $this->context($booking);
            foreach ($this->recipients->ownerUsers($booking->tenant) as $owner) {
                $this->dispatcher->dispatch($booking->tenant, $owner, $event, 'owner', $context, $booking);
            }
        });
    }

    /**
     * Runs entirely inside the originating request's call stack (afterCommit
     * listeners execute synchronously under the `sync` queue driver, right
     * as BookingService's transaction commits — before control even returns
     * to the calling controller). Restoring the *previous* context rather
     * than unconditionally clearing it is deliberate: an unconditional clear
     * would wipe out the outer controller's own tenant context mid-request.
     * Same pattern as SubscriptionService::startTrialFor.
     */
    private function withBooking(Booking $booking, callable $callback): void
    {
        $context = app(TenantContext::class);
        $previous = $context->get();
        $context->set($booking->tenant);
        try {
            $booking->loadMissing(['branch.salon', 'customer', 'items.service', 'items.staff.user']);
            $callback($booking);
        } finally {
            $previous !== null ? $context->set($previous) : $context->clear();
        }
    }

    /**
     * @return array<string, mixed>
     */
    private function context(Booking $booking): array
    {
        return [
            'booking_id' => $booking->id,
            'booking_reference' => strtoupper(substr($booking->id, -8)),
            'salon_name' => $booking->branch->salon->name ?? '',
            'branch_name' => $booking->branch->name ?? '',
            'service_names' => $booking->items->pluck('service_name')->unique()->implode(', '),
            'customer_name' => $booking->customer->name ?? 'the customer',
            'date' => $booking->booking_date->format('Y-m-d'),
            'time' => substr((string) $booking->start_time, 0, 5),
        ];
    }
}
