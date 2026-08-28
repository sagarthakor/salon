<?php

namespace App\Services\Reports;

use App\Models\BranchHoliday;
use App\Models\StaffBreak;
use App\Models\StaffLeave;
use App\Models\StaffWorkingHour;
use App\Support\DateRange;
use App\Support\TimeMath;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;

/**
 * available_minutes / booked_minutes × 100. `available_minutes` is derived
 * purely from each staff member's own working-hour/break/leave rows for
 * every calendar day in the range — never estimated. Holidays are only
 * subtracted when the report is scoped to one branch (a staff member can
 * work across branches with different holiday calendars, so a tenant-wide
 * figure cannot correctly net out any one branch's holidays); this is a
 * documented simplification, not an omission. See "Staff utilization" in
 * REPORTING_ANALYTICS_ARCHITECTURE.md.
 */
class StaffUtilizationCalculator
{
    /**
     * @param  list<string>  $staffIds
     * @return array<string, int> staff_id => available minutes across the whole range
     */
    public function availableMinutesFor(array $staffIds, DateRange $range, ?string $branchId): array
    {
        if ($staffIds === []) {
            return [];
        }

        $workingHoursByStaff = StaffWorkingHour::query()->whereIn('staff_id', $staffIds)->get()->groupBy('staff_id');
        $breaksByStaff = StaffBreak::query()->whereIn('staff_id', $staffIds)->get()->groupBy('staff_id');
        $leavesByStaff = StaffLeave::query()->whereIn('staff_id', $staffIds)
            ->where('status', '!=', 'rejected')
            ->where('start_date', '<=', $range->endDate())
            ->where('end_date', '>=', $range->startDate())
            ->get()->groupBy('staff_id');

        $holidayDates = $branchId !== null
            ? BranchHoliday::query()->where('branch_id', $branchId)->where('is_closed', true)
                ->whereBetween('holiday_date', [$range->startDate(), $range->endDate()])
                ->get()->map(fn (BranchHoliday $h) => $h->holiday_date->toDateString())->all()
            : [];

        $dates = $range->dailyDates();
        $result = [];
        foreach ($staffIds as $staffId) {
            $result[$staffId] = $this->availableMinutesForStaff(
                $dates,
                $range->timezone,
                $workingHoursByStaff->get($staffId, collect()),
                $breaksByStaff->get($staffId, collect()),
                $leavesByStaff->get($staffId, collect()),
                $holidayDates,
            );
        }

        return $result;
    }

    /**
     * @param  list<string>  $dates
     * @param  Collection<int, StaffWorkingHour>  $workingHours
     * @param  Collection<int, StaffBreak>  $breaks
     * @param  Collection<int, StaffLeave>  $leaves
     * @param  list<string>  $holidayDates
     */
    private function availableMinutesForStaff(array $dates, string $timezone, Collection $workingHours, Collection $breaks, Collection $leaves, array $holidayDates): int
    {
        $workingHoursByDay = $workingHours->keyBy('day_of_week');
        $breaksByDay = $breaks->groupBy('day_of_week');

        $available = 0;
        foreach ($dates as $date) {
            if (in_array($date, $holidayDates, true)) {
                continue;
            }
            if ($leaves->contains(fn (StaffLeave $leave) => $date >= $leave->start_date->toDateString() && $date <= $leave->end_date->toDateString())) {
                continue;
            }

            $dayOfWeek = CarbonImmutable::createFromFormat('Y-m-d', $date, $timezone)->dayOfWeek;
            /** @var StaffWorkingHour|null $hour */
            $hour = $workingHoursByDay->get($dayOfWeek);
            if ($hour === null || ! $hour->is_working) {
                continue;
            }

            $minutes = TimeMath::toMinutes(substr((string) $hour->end_time, 0, 5)) - TimeMath::toMinutes(substr((string) $hour->start_time, 0, 5));
            foreach ($breaksByDay->get($dayOfWeek, collect()) as $break) {
                $minutes -= TimeMath::toMinutes(substr((string) $break->end_time, 0, 5)) - TimeMath::toMinutes(substr((string) $break->start_time, 0, 5));
            }

            $available += max(0, $minutes);
        }

        return $available;
    }
}
