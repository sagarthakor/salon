<?php

namespace App\Services\Booking;

use App\Models\StaffBreak;
use App\Models\StaffLeave;
use App\Models\StaffWorkingHour;
use App\Support\TimeMath;
use Illuminate\Support\Collection;

/**
 * Pure, DB-free interval eligibility check. Callers are responsible for pre-loading
 * the staff's working hours/breaks/leave/existing items for the relevant day so this
 * class never issues a query itself — this is what keeps availability generation free
 * of N+1 queries when scanning many candidate slots and staff members.
 */
class StaffEligibilityChecker
{
    /**
     * @param  Collection<int, StaffWorkingHour>  $workingHours  the staff's working-hour row(s) for the target day of week
     * @param  Collection<int, StaffBreak>  $breaks  the staff's breaks for the target day of week
     * @param  Collection<int, StaffLeave>  $leaves  the staff's leave row(s) covering the target date
     * @param  Collection<int, object{start_time: string, end_time: string}>  $existingItems  the staff's non-cancelled booking items on the target date
     * @param  string  $start  the candidate's actual service start (not buffer-inflated)
     * @param  string  $end  the candidate's actual service end (not buffer-inflated)
     * @param  int  $bufferMinutes  cleanup buffer applied symmetrically around existing bookings only — working hours and breaks are exact boundaries and are not buffer-adjusted
     */
    public function isEligible(Collection $workingHours, Collection $breaks, Collection $leaves, Collection $existingItems, string $start, string $end, int $bufferMinutes = 0): bool
    {
        $workingHour = $workingHours->first();
        if ($workingHour === null || ! $workingHour->is_working) {
            return false;
        }
        $whStart = substr((string) $workingHour->start_time, 0, 5);
        $whEnd = substr((string) $workingHour->end_time, 0, 5);
        if ($start < $whStart || $end > $whEnd) {
            return false;
        }
        if ($leaves->isNotEmpty()) {
            return false;
        }
        foreach ($breaks as $break) {
            if ($this->overlaps($start, $end, substr((string) $break->start_time, 0, 5), substr((string) $break->end_time, 0, 5))) {
                return false;
            }
        }
        foreach ($existingItems as $item) {
            if ($this->overlapsWithBuffer($start, $end, substr((string) $item->start_time, 0, 5), substr((string) $item->end_time, 0, 5), $bufferMinutes)) {
                return false;
            }
        }

        return true;
    }

    private function overlaps(string $aStart, string $aEnd, string $bStart, string $bEnd): bool
    {
        return $aStart < $bEnd && $aEnd > $bStart;
    }

    /**
     * Both spans are extended by the buffer at their end before comparing, so a new
     * booking cannot start inside another booking's post-service cleanup window and
     * vice versa.
     */
    private function overlapsWithBuffer(string $aStart, string $aEnd, string $bStart, string $bEnd, int $bufferMinutes): bool
    {
        $aEndBuffered = TimeMath::fromMinutes(TimeMath::toMinutes($aEnd) + $bufferMinutes);
        $bEndBuffered = TimeMath::fromMinutes(TimeMath::toMinutes($bEnd) + $bufferMinutes);

        return $aStart < $bEndBuffered && $aEndBuffered > $bStart;
    }
}
