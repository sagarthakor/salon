<?php

namespace App\Services\Reports\Concerns;

use App\Models\Booking;
use App\Support\DateRange;
use Illuminate\Database\Eloquent\Builder;

/**
 * The one place a `bookings` query is scoped to a date range + the shared
 * filter set (branch/staff/service/status/customer) — every report that
 * touches bookings builds from this so the definition of "bookings in this
 * report" never drifts between reports. Tenant isolation itself needs no
 * explicit `where` here: `Booking` already carries the `BelongsToTenant`
 * global scope keyed to the authenticated tenant context.
 *
 * `staff_id`/`service_id` live on `booking_items`, not `bookings` — a
 * booking can contain several staff/services — so those two filters apply
 * via `whereHas('items', ...)`, which correctly matches a booking that has
 * *any* matching item without double-counting the booking itself.
 */
trait FiltersBookings
{
    /**
     * @param  array<string, mixed>  $filters
     */
    protected function bookingsQuery(DateRange $range, array $filters): Builder
    {
        $query = Booking::query()->whereBetween('booking_date', [$range->startDate(), $range->endDate()]);

        if (! empty($filters['branch_id'])) {
            $query->where('branch_id', $filters['branch_id']);
        }
        if (! empty($filters['customer_id'])) {
            $query->where('customer_id', $filters['customer_id']);
        }
        if (! empty($filters['status'])) {
            $query->where('status', $filters['status']);
        }
        if (! empty($filters['coupon_id'])) {
            $query->where('coupon_id', $filters['coupon_id']);
        }
        if (! empty($filters['staff_id']) || ! empty($filters['service_id']) || ! empty($filters['category_id'])) {
            $query->whereHas('items', function (Builder $q) use ($filters): void {
                if (! empty($filters['staff_id'])) {
                    $q->where('staff_id', $filters['staff_id']);
                }
                if (! empty($filters['service_id'])) {
                    $q->where('service_id', $filters['service_id']);
                }
                if (! empty($filters['category_id'])) {
                    $q->whereHas('service', fn (Builder $sq) => $sq->where('category_id', $filters['category_id']));
                }
            });
        }

        return $query;
    }

    protected function money(int|float|string $value): string
    {
        return number_format((float) $value, 2, '.', '');
    }
}
