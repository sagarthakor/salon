<?php

namespace App\Services\Booking;

use App\Enums\BookingStatus;
use App\Enums\BusinessStatus;
use App\Enums\LeaveStatus;
use App\Models\BookingItem;
use App\Models\Branch;
use App\Models\Service;
use App\Models\Staff;
use App\Models\StaffBreak;
use App\Models\StaffLeave;
use App\Models\StaffWorkingHour;
use App\Support\BookingSettings;
use App\Support\TimeMath;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Collection;

/**
 * Reusable slot-generation and staff-eligibility scanning for a branch, a set of
 * requested services, and an optional specific staff member. Used by the public
 * availability endpoint and, for final revalidation, by BookingService.
 */
class AvailabilityService
{
    public function __construct(private readonly StaffEligibilityChecker $checker) {}

    /**
     * @param  Collection<int, Service>  $services
     * @return array{date:string, duration_minutes:int, buffer_minutes:int, slots: list<array{start_time:string,end_time:string,staff_ids:list<string>}>}
     */
    public function forBranch(Branch $branch, CarbonImmutable $date, Collection $services, ?Staff $requestedStaff): array
    {
        $branch->loadMissing('salon.settings');
        $settings = new BookingSettings($branch->salon);
        $totalDuration = (int) $services->sum('duration_minutes');
        $bufferMinutes = $settings->bufferMinutes();
        $occupiedMinutes = $totalDuration + $bufferMinutes;

        $empty = ['date' => $date->toDateString(), 'duration_minutes' => $totalDuration, 'buffer_minutes' => $bufferMinutes, 'slots' => []];
        if ($totalDuration <= 0) {
            return $empty;
        }

        $branchTz = $branch->timezone ?: 'UTC';
        $nowLocal = CarbonImmutable::now($branchTz);
        $today = $nowLocal->startOfDay();
        $maxDate = $today->addDays($settings->maxAdvanceDays());
        if ($date->startOfDay()->lt($today) || $date->startOfDay()->gt($maxDate)) {
            return $empty;
        }

        $isHoliday = $branch->holidays()->where('holiday_date', $date->toDateString())->where('is_closed', true)->exists();
        if ($isHoliday) {
            return $empty;
        }

        $dayOfWeek = $date->dayOfWeek;
        $workingHour = $branch->workingHours()->where('day_of_week', $dayOfWeek)->first();
        if ($workingHour === null || ! $workingHour->is_open) {
            return $empty;
        }
        $branchOpen = substr((string) $workingHour->opening_time, 0, 5);
        $branchClose = substr((string) $workingHour->closing_time, 0, 5);

        $candidateStaff = $this->eligibleStaffQuery($branch, $services)
            ->when($requestedStaff, fn (Builder $q, Staff $staff) => $q->whereKey($staff->id))
            ->get();
        if ($candidateStaff->isEmpty()) {
            return $empty;
        }
        $staffIds = $candidateStaff->pluck('id')->all();

        $workingHoursByStaff = StaffWorkingHour::query()->whereIn('staff_id', $staffIds)->where('day_of_week', $dayOfWeek)->get()->groupBy('staff_id');
        $breaksByStaff = StaffBreak::query()->whereIn('staff_id', $staffIds)->where('day_of_week', $dayOfWeek)->get()->groupBy('staff_id');
        $leavesByStaff = StaffLeave::query()->whereIn('staff_id', $staffIds)
            ->where('status', '!=', LeaveStatus::REJECTED->value)
            ->where('start_date', '<=', $date->toDateString())
            ->where('end_date', '>=', $date->toDateString())
            ->get()->groupBy('staff_id');
        $blockingStatuses = array_map(fn (BookingStatus $s) => $s->value, BookingStatus::blockingBooking());
        $itemsByStaff = BookingItem::query()->whereIn('staff_id', $staffIds)
            ->whereHas('booking', fn ($q) => $q->where('branch_id', $branch->id)->where('booking_date', $date->toDateString())->whereIn('status', $blockingStatuses))
            ->get()->groupBy('staff_id');

        $slotInterval = $settings->slotIntervalMinutes();
        $minAllowedInstant = $nowLocal->addMinutes($settings->minAdvanceMinutes());

        $slots = [];
        $cursor = TimeMath::toMinutes($branchOpen);
        $closeMinutes = TimeMath::toMinutes($branchClose);
        $emptyCollection = collect();

        while ($cursor + $occupiedMinutes <= $closeMinutes) {
            $slotStart = TimeMath::fromMinutes($cursor);
            $slotServiceEnd = TimeMath::fromMinutes($cursor + $totalDuration);

            $candidateInstant = CarbonImmutable::parse($date->toDateString().' '.$slotStart, $branchTz);
            if ($candidateInstant->lt($minAllowedInstant)) {
                $cursor += $slotInterval;

                continue;
            }

            $eligibleIds = $candidateStaff->filter(fn (Staff $staff) => $this->checker->isEligible(
                $workingHoursByStaff->get($staff->id, $emptyCollection),
                $breaksByStaff->get($staff->id, $emptyCollection),
                $leavesByStaff->get($staff->id, $emptyCollection),
                $itemsByStaff->get($staff->id, $emptyCollection),
                $slotStart,
                $slotServiceEnd,
                $bufferMinutes,
            ))->pluck('id')->values()->all();

            if ($eligibleIds !== []) {
                $slots[] = ['start_time' => $slotStart, 'end_time' => $slotServiceEnd, 'staff_ids' => $eligibleIds];
            }

            $cursor += $slotInterval;
        }

        return ['date' => $date->toDateString(), 'duration_minutes' => $totalDuration, 'buffer_minutes' => $bufferMinutes, 'slots' => $slots];
    }

    /**
     * @param  Collection<int, Service>  $services
     */
    public function eligibleStaffQuery(Branch $branch, Collection $services): Builder
    {
        $query = Staff::query()->where('status', BusinessStatus::ACTIVE)->whereHas('branches', fn ($q) => $q->where('branches.id', $branch->id));
        foreach ($services as $service) {
            $query->whereHas('services', fn ($q) => $q->where('services.id', $service->id));
        }

        return $query;
    }
}
