<?php

namespace App\Services\Reports\Concerns;

use App\Models\Tenant;
use App\Support\DateRange;
use Illuminate\Database\Query\Builder;
use Illuminate\Support\Facades\DB;

/**
 * `staff_id`/`service_id`/per-item pricing live on `booking_items`, and
 * status/branch/customer/coupon live on the parent `bookings` row — reports
 * that need both together (staff/service revenue attribution) join the two
 * tables directly with the query builder rather than hydrating Eloquent
 * models, since these are pure aggregate reads over what can be a large
 * number of rows (see instruction on avoiding collection-based aggregation).
 *
 * `DB::table()` bypasses Eloquent's `BelongsToTenant` global scope entirely,
 * so every query built here MUST filter `b.tenant_id` explicitly — that
 * `where` is added unconditionally below and is not optional.
 */
trait QueriesBookingItems
{
    /**
     * @param  array<string, mixed>  $filters
     */
    protected function bookingItemsQuery(Tenant $tenant, DateRange $range, array $filters): Builder
    {
        $query = DB::table('booking_items as bi')
            ->join('bookings as b', 'b.id', '=', 'bi.booking_id')
            ->where('b.tenant_id', $tenant->getKey())
            ->whereBetween('b.booking_date', [$range->startDate(), $range->endDate()]);

        if (! empty($filters['branch_id'])) {
            $query->where('b.branch_id', $filters['branch_id']);
        }
        if (! empty($filters['customer_id'])) {
            $query->where('b.customer_id', $filters['customer_id']);
        }
        if (! empty($filters['status'])) {
            $query->where('b.status', $filters['status']);
        }
        if (! empty($filters['coupon_id'])) {
            $query->where('b.coupon_id', $filters['coupon_id']);
        }
        if (! empty($filters['staff_id'])) {
            $query->where('bi.staff_id', $filters['staff_id']);
        }
        if (! empty($filters['service_id'])) {
            $query->where('bi.service_id', $filters['service_id']);
        }
        if (! empty($filters['category_id'])) {
            $query->join('services as s', 's.id', '=', 'bi.service_id')->where('s.category_id', $filters['category_id']);
        }

        return $query;
    }

    /**
     * A booking's `discount` column isn't itemized per service/staff — it is
     * allocated across that booking's items proportionally by each item's
     * share of the booking subtotal. This is a standard, documented
     * allocation (never a fabricated number): the sum of every item's
     * allocated discount for a booking always equals that booking's real
     * `discount`, so per-service/per-staff totals never double-count or
     * invent money. See "Revenue by staff" / "Revenue by service" in
     * REPORTING_ANALYTICS_ARCHITECTURE.md.
     */
    protected function allocatedDiscountExpression(): string
    {
        // `CAST(... AS REAL)` matters: SQLite's `/` performs *integer*
        // division when both operands happen to be whole numbers (e.g.
        // 300/800 => 0), which silently zeroes out every allocation. MySQL/
        // Postgres already return a decimal here regardless, so the cast is
        // a no-op there.
        return 'CASE WHEN b.subtotal > 0 THEN (CAST(bi.subtotal AS REAL) / b.subtotal) * b.discount ELSE 0 END';
    }
}
