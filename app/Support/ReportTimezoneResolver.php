<?php

namespace App\Support;

use App\Models\Branch;
use App\Models\Tenant;

/**
 * The single place a report decides which timezone "today"/"this month"
 * etc. are resolved against. See "Timezone handling" in
 * REPORTING_ANALYTICS_ARCHITECTURE.md:
 *
 *   - A report filtered to one branch uses that branch's own timezone —
 *     exactly the timezone `booking_date` was captured in for that branch's
 *     bookings (see BookingController), so date-range boundaries line up
 *     perfectly with the stored business date.
 *   - A tenant-wide report (no branch filter) anchors to the salon's
 *     timezone. If the tenant operates branches across differing
 *     timezones, a tenant-wide "today" is necessarily an approximation for
 *     branches other than the one the salon's timezone was set for — this
 *     is a documented limitation, not a silent bug.
 */
class ReportTimezoneResolver
{
    public static function resolve(Tenant $tenant, ?string $branchId): string
    {
        if ($branchId !== null) {
            $branch = Branch::query()->find($branchId);
            if ($branch?->timezone) {
                return $branch->timezone;
            }
        }

        return $tenant->salon?->timezone ?: 'UTC';
    }
}
