<?php

namespace App\Services\Booking;

use App\Enums\BookingStatus;
use App\Enums\BusinessStatus;
use App\Enums\LeaveStatus;
use App\Events\BookingCancelled;
use App\Events\BookingCheckedIn;
use App\Events\BookingCompleted;
use App\Events\BookingConfirmed;
use App\Events\BookingCreated;
use App\Events\BookingNoShow;
use App\Events\BookingRescheduled;
use App\Events\BookingStarted;
use App\Models\Booking;
use App\Models\BookingItem;
use App\Models\BookingStatusHistory;
use App\Models\Branch;
use App\Models\BranchWorkingHour;
use App\Models\Customer;
use App\Models\Service;
use App\Models\Staff;
use App\Models\StaffBreak;
use App\Models\StaffLeave;
use App\Models\StaffWorkingHour;
use App\Models\Tenant;
use App\Models\User;
use App\Services\Booking\Exceptions\BookingUnavailableException;
use App\Services\Pricing\BookingPricingService;
use App\Support\BookingSettings;
use App\Support\TimeMath;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Orchestrates booking creation, cancellation, rescheduling, and status transitions.
 * Every mutating operation runs inside a locking transaction that revalidates all
 * business rules against fresh database state — see BOOKING_ENGINE.md for the
 * double-booking prevention strategy this implements.
 */
class BookingService
{
    private const LOCK_RETRY_ATTEMPTS = 3;

    public function __construct(
        private readonly AvailabilityService $availability,
        private readonly StaffEligibilityChecker $checker,
        private readonly BookingPricingService $pricing,
    ) {}

    /**
     * @param  array<int, array{service_id: string, staff_id: ?string}>  $items
     */
    public function create(Tenant $tenant, Branch $branch, Customer $customer, array $items, CarbonImmutable $date, string $startTime, ?string $notes, ?User $actor, ?string $couponCode = null, ?int $loyaltyPointsToRedeem = null): Booking
    {
        return DB::transaction(function () use ($tenant, $branch, $customer, $items, $date, $startTime, $notes, $actor, $couponCode, $loyaltyPointsToRedeem): Booking {
            if ((string) $branch->tenant_id !== (string) $tenant->id || $branch->status !== BusinessStatus::ACTIVE) {
                throw new BookingUnavailableException('The selected branch is not available.');
            }
            if ((string) $customer->tenant_id !== (string) $tenant->id || $customer->status !== BusinessStatus::ACTIVE) {
                throw new BookingUnavailableException('The selected customer is not available.');
            }

            $serviceIds = array_column($items, 'service_id');
            $services = Service::query()->whereIn('id', $serviceIds)->where('branch_id', $branch->id)->where('status', BusinessStatus::ACTIVE)->get()->keyBy('id');
            if ($services->count() !== count(array_unique($serviceIds))) {
                throw new BookingUnavailableException('One or more services are invalid for this branch.');
            }

            $settings = $this->settingsFor($branch);
            $branchTz = $branch->timezone ?: 'UTC';
            $nowLocal = CarbonImmutable::now($branchTz);
            $this->assertWithinBookingWindow($date, $startTime, $branchTz, $nowLocal, $settings);
            $workingHour = $this->assertBranchOpen($branch, $date);
            $branchOpenMinutes = TimeMath::toMinutes(substr((string) $workingHour->opening_time, 0, 5));
            $branchCloseMinutes = TimeMath::toMinutes(substr((string) $workingHour->closing_time, 0, 5));

            $mode = $this->resolveStaffMode($items);
            $itemTimes = $this->computeItemTimes($items, $services, $startTime, $mode);
            $occupiedEndMinutes = max(array_column($itemTimes, 'end_minutes')) + $settings->bufferMinutes();
            if (TimeMath::toMinutes($startTime) < $branchOpenMinutes || $occupiedEndMinutes > $branchCloseMinutes) {
                throw new BookingUnavailableException('The requested services do not fit within branch working hours.');
            }

            $resolvedStaffByIndex = $this->resolveAndLockStaff($branch, $services, $items, $itemTimes, $mode, $date, $settings->bufferMinutes());

            $subtotal = 0.0;
            $bookingItems = [];
            foreach ($items as $index => $item) {
                $service = $services->get($item['service_id']);
                $staff = $resolvedStaffByIndex[$index];
                $lineSubtotal = (float) $service->price;
                $subtotal += $lineSubtotal;
                $bookingItems[] = [
                    'service_id' => $service->id,
                    'staff_id' => $staff->id,
                    'service_name' => $service->name,
                    'service_price' => $service->price,
                    'service_duration_minutes' => $service->duration_minutes,
                    'quantity' => 1,
                    'start_time' => TimeMath::fromMinutes($itemTimes[$index]['start_minutes']),
                    'end_time' => TimeMath::fromMinutes($itemTimes[$index]['end_minutes']),
                    'subtotal' => $lineSubtotal,
                ];
            }

            $booking = Booking::query()->create([
                'branch_id' => $branch->id,
                'customer_id' => $customer->id,
                'booking_date' => $date->toDateString(),
                'start_time' => $startTime,
                'end_time' => TimeMath::fromMinutes(max(array_column($itemTimes, 'end_minutes'))),
                'status' => BookingStatus::PENDING,
                'subtotal' => $subtotal,
                'discount' => 0,
                'tax' => 0,
                'total' => $subtotal,
                'notes' => $notes,
                'created_by' => $actor?->id,
            ]);

            foreach ($bookingItems as $itemData) {
                $booking->items()->create($itemData);
            }

            // Pricing (coupon/membership/loyalty) is reserved only now that
            // the booking row exists — CouponUsage/LoyaltyTransaction rows
            // reference `booking_id`, and a foreign key to a row that
            // doesn't exist yet would fail under real FK enforcement (unlike
            // SQLite's default, MySQL checks per-statement, not deferred to
            // commit). The booking is then updated with the final,
            // server-computed numbers — never anything the client sent. See
            // BookingPricingService and "Transaction safety" in
            // LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md: if reserving a
            // coupon/loyalty redemption fails (race lost, expired between
            // preview and now), the exception rolls back this entire
            // transaction — the booking, its items, and the failed
            // reservation attempt all vanish together.
            $lineServices = collect($bookingItems)->map(fn (array $item) => (object) [
                'id' => $item['service_id'],
                'price' => $item['service_price'],
                'category_id' => $services->get($item['service_id'])?->category_id,
            ]);
            $pricing = $this->pricing->reserve($tenant, $branch->salon, $customer, $lineServices, $couponCode, $loyaltyPointsToRedeem, $booking);
            $booking->update([
                'discount' => $pricing->couponDiscount + $pricing->membershipDiscount + $pricing->loyaltyDiscount,
                'tax' => $pricing->tax,
                'total' => $pricing->total,
                'coupon_id' => $pricing->couponId,
                'coupon_code' => $pricing->couponCode,
                'coupon_discount' => $pricing->couponDiscount,
                'customer_membership_id' => $pricing->customerMembershipId,
                'membership_discount' => $pricing->membershipDiscount,
                'loyalty_points_redeemed' => $pricing->loyaltyPointsRedeemed,
                'loyalty_discount' => $pricing->loyaltyDiscount,
            ]);

            BookingStatusHistory::query()->create(['booking_id' => $booking->id, 'from_status' => null, 'to_status' => BookingStatus::PENDING, 'changed_by' => $actor?->id]);

            event(new BookingCreated($booking));

            return $booking->fresh(['items.staff', 'items.service', 'customer', 'branch']);
        }, self::LOCK_RETRY_ATTEMPTS);
    }

    public function cancel(Booking $booking, ?string $reason, ?User $actor, bool $override): Booking
    {
        return DB::transaction(function () use ($booking, $reason, $actor, $override): Booking {
            $locked = Booking::query()->whereKey($booking->id)->lockForUpdate()->firstOrFail();
            if (! $locked->status->canTransitionTo(BookingStatus::CANCELLED)) {
                throw new BookingUnavailableException("A booking with status {$locked->status->value} can no longer be cancelled.");
            }
            if (! $override) {
                $branch = $locked->branch;
                $settings = $this->settingsFor($branch);
                $branchTz = $branch->timezone ?: 'UTC';
                $windowMinutes = $settings->cancellationWindowMinutes();
                if ($windowMinutes > 0) {
                    $startInstant = CarbonImmutable::parse($locked->booking_date->toDateString().' '.substr((string) $locked->start_time, 0, 5), $branchTz);
                    if (CarbonImmutable::now($branchTz)->addMinutes($windowMinutes)->gt($startInstant)) {
                        throw new BookingUnavailableException('This booking is within the cancellation window and can no longer be self-cancelled.');
                    }
                }
            }

            $from = $locked->status;
            $locked->update(['status' => BookingStatus::CANCELLED, 'cancellation_reason' => $reason, 'cancelled_at' => now(), 'cancelled_by' => $actor?->id]);
            BookingStatusHistory::query()->create(['booking_id' => $locked->id, 'from_status' => $from, 'to_status' => BookingStatus::CANCELLED, 'changed_by' => $actor?->id, 'reason' => $reason]);

            event(new BookingCancelled($locked));

            return $locked->fresh(['items.staff', 'items.service', 'customer', 'branch']);
        }, self::LOCK_RETRY_ATTEMPTS);
    }

    public function reschedule(Booking $booking, CarbonImmutable $date, string $startTime, ?User $actor): Booking
    {
        return DB::transaction(function () use ($booking, $date, $startTime, $actor): Booking {
            $locked = Booking::query()->whereKey($booking->id)->lockForUpdate()->firstOrFail();
            if (! in_array($locked->status, [BookingStatus::PENDING, BookingStatus::CONFIRMED], true)) {
                throw new BookingUnavailableException('Only pending or confirmed bookings can be rescheduled.');
            }

            $branch = $locked->branch;
            $settings = $this->settingsFor($branch);
            $branchTz = $branch->timezone ?: 'UTC';
            $nowLocal = CarbonImmutable::now($branchTz);
            $this->assertWithinBookingWindow($date, $startTime, $branchTz, $nowLocal, $settings);
            $workingHour = $this->assertBranchOpen($branch, $date);
            $branchOpenMinutes = TimeMath::toMinutes(substr((string) $workingHour->opening_time, 0, 5));
            $branchCloseMinutes = TimeMath::toMinutes(substr((string) $workingHour->closing_time, 0, 5));

            $items = $locked->items()->orderBy('id')->get();
            $distinctStaffIds = $items->pluck('staff_id')->unique()->values();
            $sequential = $distinctStaffIds->count() === 1;

            $cursor = TimeMath::toMinutes($startTime);
            $newTimes = [];
            $maxEnd = 0;
            foreach ($items as $item) {
                $start = $sequential ? $cursor : TimeMath::toMinutes($startTime);
                $end = $start + $item->service_duration_minutes;
                $newTimes[$item->id] = ['start' => $start, 'end' => $end];
                $maxEnd = max($maxEnd, $end);
                if ($sequential) {
                    $cursor = $end;
                }
            }
            $occupiedEndMinutes = $maxEnd + $settings->bufferMinutes();
            if (TimeMath::toMinutes($startTime) < $branchOpenMinutes || $occupiedEndMinutes > $branchCloseMinutes) {
                throw new BookingUnavailableException('The requested time does not fit within branch working hours.');
            }

            $lockedStaff = Staff::query()->whereIn('id', $distinctStaffIds)->orderBy('id')->lockForUpdate()->get()->keyBy('id');
            if ($sequential) {
                $staff = $lockedStaff->get($items->first()->staff_id);
                if ($staff === null || $staff->status !== BusinessStatus::ACTIVE) {
                    throw new BookingUnavailableException('An assigned staff member is no longer available.');
                }
                $firstStart = $newTimes[$items->first()->id]['start'];
                $eligible = $this->staffEligibleForSpan($staff, $branch, $date, TimeMath::fromMinutes($firstStart), TimeMath::fromMinutes($maxEnd), $settings->bufferMinutes(), $locked->id);
                if (! $eligible) {
                    throw new BookingUnavailableException('The assigned staff member is not available for the rescheduled time.');
                }
            } else {
                foreach ($items as $item) {
                    $staff = $lockedStaff->get($item->staff_id);
                    if ($staff === null || $staff->status !== BusinessStatus::ACTIVE) {
                        throw new BookingUnavailableException('An assigned staff member is no longer available.');
                    }
                    $span = $newTimes[$item->id];
                    $eligible = $this->staffEligibleForSpan($staff, $branch, $date, TimeMath::fromMinutes($span['start']), TimeMath::fromMinutes($span['end']), $settings->bufferMinutes(), $locked->id);
                    if (! $eligible) {
                        throw new BookingUnavailableException('The assigned staff member is not available for the rescheduled time.');
                    }
                }
            }

            $oldDate = $locked->booking_date->toDateString();
            $oldStart = substr((string) $locked->start_time, 0, 5);

            $locked->update(['booking_date' => $date->toDateString(), 'start_time' => $startTime, 'end_time' => TimeMath::fromMinutes($maxEnd)]);
            foreach ($items as $item) {
                $span = $newTimes[$item->id];
                $item->update(['start_time' => TimeMath::fromMinutes($span['start']), 'end_time' => TimeMath::fromMinutes($span['end'])]);
            }

            BookingStatusHistory::query()->create([
                'booking_id' => $locked->id,
                'from_status' => $locked->status,
                'to_status' => $locked->status,
                'changed_by' => $actor?->id,
                'reason' => "Rescheduled from {$oldDate} {$oldStart} to {$date->toDateString()} {$startTime}",
            ]);

            event(new BookingRescheduled($locked, $oldDate, $oldStart));

            return $locked->fresh(['items.staff', 'items.service', 'customer', 'branch']);
        }, self::LOCK_RETRY_ATTEMPTS);
    }

    public function transition(Booking $booking, BookingStatus $target, ?User $actor, ?string $reason = null): Booking
    {
        return DB::transaction(function () use ($booking, $target, $actor, $reason): Booking {
            $locked = Booking::query()->whereKey($booking->id)->lockForUpdate()->firstOrFail();
            if (! $locked->status->canTransitionTo($target)) {
                throw new BookingUnavailableException("A booking cannot move from {$locked->status->value} to {$target->value}.");
            }
            $from = $locked->status;
            $locked->update(['status' => $target]);
            BookingStatusHistory::query()->create(['booking_id' => $locked->id, 'from_status' => $from, 'to_status' => $target, 'changed_by' => $actor?->id, 'reason' => $reason]);

            match ($target) {
                BookingStatus::CONFIRMED => event(new BookingConfirmed($locked)),
                BookingStatus::CHECKED_IN => event(new BookingCheckedIn($locked)),
                BookingStatus::IN_SERVICE => event(new BookingStarted($locked)),
                BookingStatus::COMPLETED => event(new BookingCompleted($locked)),
                BookingStatus::NO_SHOW => event(new BookingNoShow($locked)),
                default => null,
            };

            return $locked->fresh(['items.staff', 'items.service', 'customer', 'branch']);
        }, self::LOCK_RETRY_ATTEMPTS);
    }

    private function settingsFor(Branch $branch): BookingSettings
    {
        $branch->loadMissing('salon.settings');

        return new BookingSettings($branch->salon);
    }

    private function assertWithinBookingWindow(CarbonImmutable $date, string $startTime, string $branchTz, CarbonImmutable $nowLocal, BookingSettings $settings): void
    {
        if ($date->startOfDay()->lt($nowLocal->startOfDay())) {
            throw new BookingUnavailableException('Bookings cannot be made in the past.');
        }
        if ($date->startOfDay()->gt($nowLocal->startOfDay()->addDays($settings->maxAdvanceDays()))) {
            throw new BookingUnavailableException('The selected date is beyond the maximum advance booking period.');
        }
        $startInstant = CarbonImmutable::parse($date->toDateString().' '.$startTime, $branchTz);
        if ($startInstant->lt($nowLocal->addMinutes($settings->minAdvanceMinutes()))) {
            throw new BookingUnavailableException('The selected time does not satisfy the minimum advance booking window.');
        }
    }

    private function assertBranchOpen(Branch $branch, CarbonImmutable $date): BranchWorkingHour
    {
        $isHoliday = $branch->holidays()->where('holiday_date', $date->toDateString())->where('is_closed', true)->exists();
        if ($isHoliday) {
            throw new BookingUnavailableException('The branch is closed on the selected date.');
        }
        $workingHour = $branch->workingHours()->where('day_of_week', $date->dayOfWeek)->first();
        if ($workingHour === null || ! $workingHour->is_open) {
            throw new BookingUnavailableException('The branch is not open on the selected date.');
        }

        return $workingHour;
    }

    /**
     * @param  array<int, array{service_id: string, staff_id: ?string}>  $items
     */
    private function resolveStaffMode(array $items): string
    {
        $staffIds = array_column($items, 'staff_id');
        $nullCount = count(array_filter($staffIds, fn ($id) => $id === null));
        if ($nullCount === count($items)) {
            return 'auto';
        }
        if ($nullCount > 0) {
            throw new BookingUnavailableException('Specify a staff member for every service, or leave all unspecified for automatic assignment.');
        }
        $distinct = array_unique($staffIds);

        return count($distinct) === 1 ? 'sequential' : 'parallel';
    }

    /**
     * @param  array<int, array{service_id: string, staff_id: ?string}>  $items
     * @param  Collection<string, Service>  $services
     * @return array<int, array{start_minutes: int, end_minutes: int}>
     */
    private function computeItemTimes(array $items, $services, string $startTime, string $mode): array
    {
        $times = [];
        if ($mode === 'parallel') {
            $start = TimeMath::toMinutes($startTime);
            foreach ($items as $index => $item) {
                $duration = $services->get($item['service_id'])->duration_minutes;
                $times[$index] = ['start_minutes' => $start, 'end_minutes' => $start + $duration];
            }

            return $times;
        }

        $cursor = TimeMath::toMinutes($startTime);
        foreach ($items as $index => $item) {
            $duration = $services->get($item['service_id'])->duration_minutes;
            $times[$index] = ['start_minutes' => $cursor, 'end_minutes' => $cursor + $duration];
            $cursor += $duration;
        }

        return $times;
    }

    /**
     * @param  array<int, array{service_id: string, staff_id: ?string}>  $items
     * @param  Collection<string, Service>  $services
     * @param  array<int, array{start_minutes: int, end_minutes: int}>  $itemTimes
     * @return array<int, Staff>
     */
    private function resolveAndLockStaff(Branch $branch, $services, array $items, array $itemTimes, string $mode, CarbonImmutable $date, int $bufferMinutes): array
    {
        if ($mode === 'auto') {
            $pool = $this->availability->eligibleStaffQuery($branch, $services)->orderBy('id')->lockForUpdate()->get();
            $startTime = TimeMath::fromMinutes($itemTimes[0]['start_minutes']);
            $endTime = TimeMath::fromMinutes(max(array_column($itemTimes, 'end_minutes')));
            foreach ($pool as $staff) {
                if ($this->staffEligibleForSpan($staff, $branch, $date, $startTime, $endTime, $bufferMinutes)) {
                    return array_fill(0, count($items), $staff);
                }
            }
            throw new BookingUnavailableException('No staff member is available for the selected slot.');
        }

        if ($mode === 'sequential') {
            $staffId = $items[0]['staff_id'];
            $staff = Staff::query()->whereKey($staffId)->lockForUpdate()->first();
            if ($staff === null || $staff->status !== BusinessStatus::ACTIVE) {
                throw new BookingUnavailableException('The selected staff member is not available.');
            }
            foreach ($services as $service) {
                if (! $staff->services()->where('services.id', $service->id)->exists()) {
                    throw new BookingUnavailableException('The selected staff member cannot perform one or more of the requested services.');
                }
            }
            $startTime = TimeMath::fromMinutes($itemTimes[0]['start_minutes']);
            $endTime = TimeMath::fromMinutes(max(array_column($itemTimes, 'end_minutes')));
            if (! $this->staffEligibleForSpan($staff, $branch, $date, $startTime, $endTime, $bufferMinutes)) {
                throw new BookingUnavailableException('The selected staff member is not available for the selected slot.');
            }

            return array_fill(0, count($items), $staff);
        }

        // parallel: distinct explicit staff per item
        $staffIds = array_values(array_unique(array_column($items, 'staff_id')));
        sort($staffIds);
        $locked = Staff::query()->whereIn('id', $staffIds)->lockForUpdate()->get()->keyBy('id');
        $resolved = [];
        foreach ($items as $index => $item) {
            $staff = $locked->get($item['staff_id']);
            if ($staff === null || $staff->status !== BusinessStatus::ACTIVE) {
                throw new BookingUnavailableException('One of the selected staff members is not available.');
            }
            $service = $services->get($item['service_id']);
            if (! $staff->services()->where('services.id', $service->id)->exists()) {
                throw new BookingUnavailableException('A selected staff member cannot perform their assigned service.');
            }
            $start = TimeMath::fromMinutes($itemTimes[$index]['start_minutes']);
            $end = TimeMath::fromMinutes($itemTimes[$index]['end_minutes']);
            if (! $this->staffEligibleForSpan($staff, $branch, $date, $start, $end, $bufferMinutes)) {
                throw new BookingUnavailableException('A selected staff member is not available for the selected slot.');
            }
            $resolved[$index] = $staff;
        }

        return $resolved;
    }

    private function staffEligibleForSpan(Staff $staff, Branch $branch, CarbonImmutable $date, string $start, string $end, int $bufferMinutes = 0, ?string $excludeBookingId = null): bool
    {
        if (! $staff->branches()->where('branches.id', $branch->id)->exists()) {
            return false;
        }
        $dayOfWeek = $date->dayOfWeek;
        $workingHours = StaffWorkingHour::query()->where('staff_id', $staff->id)->where('day_of_week', $dayOfWeek)->get();
        $breaks = StaffBreak::query()->where('staff_id', $staff->id)->where('day_of_week', $dayOfWeek)->get();
        $leaves = StaffLeave::query()->where('staff_id', $staff->id)
            ->where('status', '!=', LeaveStatus::REJECTED->value)
            ->where('start_date', '<=', $date->toDateString())
            ->where('end_date', '>=', $date->toDateString())
            ->get();
        $blockingStatuses = array_map(fn (BookingStatus $s) => $s->value, BookingStatus::blockingBooking());
        // `lockForUpdate()` matters here, not just correctness-in-spirit: this
        // method always runs after the caller has already taken a row lock
        // on `$staff` (see resolveAndLockStaff()/reschedule()), inside a
        // transaction whose default MySQL isolation is REPEATABLE READ. A
        // plain SELECT here would keep reading the transaction's original
        // snapshot even after waiting out that lock, so a conflicting
        // booking committed by another transaction *while this one was
        // blocked on the staff lock* could be invisible to this check — a
        // real double-booking window a locking read closes, since InnoDB
        // always gives a locking read the latest committed data regardless
        // of snapshot. See "Booking concurrency" in SECURITY_HARDENING.md.
        $items = BookingItem::query()->where('staff_id', $staff->id)
            ->whereHas('booking', function ($q) use ($branch, $date, $blockingStatuses, $excludeBookingId): void {
                $q->where('branch_id', $branch->id)->where('booking_date', $date->toDateString())->whereIn('status', $blockingStatuses);
                if ($excludeBookingId !== null) {
                    $q->whereKeyNot($excludeBookingId);
                }
            })->lockForUpdate()->get();

        return $this->checker->isEligible($workingHours, $breaks, $leaves, $items, $start, $end, $bufferMinutes);
    }
}
