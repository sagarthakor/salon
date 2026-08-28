<?php

namespace App\Services\Notifications;

use App\Enums\BookingStatus;
use App\Enums\NotificationEventType;
use App\Models\Booking;
use App\Support\TenantContext;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;

/**
 * Scans upcoming bookings for due reminders and dispatches at most one
 * notification per (booking, reminder_type) — see
 * NOTIFICATION_ARCHITECTURE.md, "Reminder idempotency". Runs platform-wide
 * from the scheduler with no TenantContext set, the same
 * withoutGlobalScope('tenant') pattern SubscriptionService::processLifecycle
 * uses.
 */
class BookingReminderService
{
    public function __construct(
        private readonly NotificationDispatcher $dispatcher,
        private readonly BookingRecipientResolver $recipients,
    ) {}

    /**
     * @return array{scanned: int, sent: int, skipped_duplicate: int}
     */
    public function processDueReminders(?CarbonImmutable $now = null): array
    {
        $now = $now ?? CarbonImmutable::now();
        $offsets = config('notifications.reminders.offsets', []);
        $windowMinutes = (int) config('notifications.reminders.window_minutes', 15);
        $summary = ['scanned' => 0, 'sent' => 0, 'skipped_duplicate' => 0];

        // Bound the candidate set to the next 2 days server-side (cheap
        // index hit on booking_date); the precise per-branch-timezone
        // instant check happens in PHP below since bookings only store a
        // local date/time plus the branch's timezone, not a stored UTC
        // instant. Deliberately does NOT eager-load branch/customer/staff
        // here — those are tenant-scoped models (BelongsToTenant) and this
        // query spans every tenant with no TenantContext set, so an eager
        // load here would silently come back empty; each is loaded inside
        // the per-booking tenant context below instead.
        $candidates = Booking::query()->withoutGlobalScope('tenant')
            ->whereIn('status', [BookingStatus::PENDING->value, BookingStatus::CONFIRMED->value])
            ->whereBetween('booking_date', [$now->toDateString(), $now->addDays(2)->toDateString()])
            ->with('tenant') // Tenant itself is never scoped, so this one is safe to eager-load here
            ->get();

        $context = app(TenantContext::class);
        $previousContext = $context->get();
        try {
            foreach ($candidates as $booking) {
                $summary['scanned']++;
                $context->set($booking->tenant);
                $booking->loadMissing(['branch.salon', 'customer', 'items.service', 'items.staff.user']);

                $branchTz = $booking->branch->timezone ?: 'UTC';
                $startInstant = CarbonImmutable::parse($booking->booking_date->toDateString().' '.substr((string) $booking->start_time, 0, 5), $branchTz);
                $minutesUntilStart = $now->diffInMinutes($startInstant, false);

                foreach ($offsets as $reminderType => $offsetMinutes) {
                    if (abs($minutesUntilStart - $offsetMinutes) > $windowMinutes) {
                        continue;
                    }

                    $inserted = DB::table('booking_reminders')->insertOrIgnore([
                        'tenant_id' => $booking->tenant_id,
                        'booking_id' => $booking->id,
                        'reminder_type' => $reminderType,
                        'scheduled_at' => $startInstant->subMinutes($offsetMinutes),
                        'sent_at' => $now,
                        'created_at' => $now,
                        'updated_at' => $now,
                    ]);

                    if ($inserted === 0) {
                        $summary['skipped_duplicate']++;

                        continue;
                    }

                    $this->sendReminder($booking);
                    $summary['sent']++;
                }
            }
        } finally {
            $previousContext !== null ? $context->set($previousContext) : $context->clear();
        }

        return $summary;
    }

    private function sendReminder(Booking $booking): void
    {
        $payload = [
            'booking_id' => $booking->id,
            'booking_reference' => strtoupper(substr($booking->id, -8)),
            'salon_name' => $booking->branch->salon->name ?? '',
            'service_names' => $booking->items->pluck('service_name')->unique()->implode(', '),
            'date' => $booking->booking_date->format('Y-m-d'),
            'time' => substr((string) $booking->start_time, 0, 5),
        ];

        $customer = $this->recipients->customerUser($booking);
        if ($customer !== null) {
            $this->dispatcher->dispatch($booking->tenant, $customer, NotificationEventType::BOOKING_REMINDER, 'customer', $payload, $booking, $this->recipients->customerPhone($booking));
        }
    }
}
