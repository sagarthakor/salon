<?php

namespace App\Services\Reports;

use App\Enums\BookingStatus;
use App\Models\Branch;
use App\Models\Staff;
use App\Models\Tenant;
use App\Services\Reports\Concerns\FiltersBookings;
use App\Services\Reports\Concerns\QueriesBookingItems;
use App\Support\DateRange;
use App\Support\ReportSeriesBuilder;

/**
 * "Revenue" in this codebase means the booking-total value of COMPLETED
 * bookings — `bookings.total` (= subtotal − discount + tax; tax is always 0
 * today, no tax engine exists yet). There is no per-booking payment/POS
 * record anywhere in Phases 1–12 (Payment/Invoice belong exclusively to
 * SaaS subscription billing — see "SaaS billing report" below), so this
 * number is never called "cash collected" or "amount paid": it is the value
 * of service actually rendered, recognized at completion. See "Revenue
 * semantics" in REPORTING_ANALYTICS_ARCHITECTURE.md.
 */
class RevenueReport
{
    use FiltersBookings;
    use QueriesBookingItems;

    /**
     * @param  array<string, mixed>  $filters
     */
    public function generate(Tenant $tenant, DateRange $range, array $filters): array
    {
        $completedFilters = [...$filters, 'status' => BookingStatus::COMPLETED->value];

        $totals = $this->bookingsQuery($range, $completedFilters)->toBase()
            ->selectRaw('COUNT(*) as bookings, COALESCE(SUM(subtotal), 0) as gross, COALESCE(SUM(discount), 0) as discount, COALESCE(SUM(tax), 0) as tax, COALESCE(SUM(total), 0) as net')
            ->first();

        $groupBy = $filters['group_by'] ?? $range->defaultGroupBy();
        $dailyRows = $this->bookingsQuery($range, $completedFilters)->toBase()
            ->selectRaw('booking_date, COALESCE(SUM(total), 0) as net')
            ->groupBy('booking_date')
            ->get();
        $dailyValues = [];
        foreach ($dailyRows as $row) {
            $dailyValues[$row->booking_date] = ['revenue' => (float) $row->net];
        }
        $series = ReportSeriesBuilder::build($range, $groupBy, $dailyValues, ['revenue']);
        foreach ($series as &$point) {
            $point['revenue'] = $this->money($point['revenue']);
        }
        unset($point);

        return [
            'summary' => [
                'completed_bookings' => (int) $totals->bookings,
                'gross_booking_value' => $this->money($totals->gross),
                'discount' => $this->money($totals->discount),
                'tax' => $this->money($totals->tax),
                'net_revenue' => $this->money($totals->net),
                'average_booking_value' => $totals->bookings > 0 ? $this->money($totals->net / $totals->bookings) : $this->money(0),
            ],
            'series' => $series,
            'breakdown' => [
                'by_branch' => $this->byBranch($tenant, $range, $completedFilters),
                'by_staff' => $this->byStaff($tenant, $range, $completedFilters),
                'by_service' => $this->byService($tenant, $range, $completedFilters),
            ],
        ];
    }

    /**
     * @param  array<string, mixed>  $filters
     * @return list<array<string, mixed>>
     */
    private function byBranch(Tenant $tenant, DateRange $range, array $filters): array
    {
        $rows = $this->bookingsQuery($range, $filters)->toBase()
            ->selectRaw('branch_id, COUNT(*) as bookings, COALESCE(SUM(subtotal), 0) as gross, COALESCE(SUM(discount), 0) as discount, COALESCE(SUM(total), 0) as net')
            ->groupBy('branch_id')
            ->orderByDesc('net')
            ->get();

        $names = Branch::query()->whereIn('id', $rows->pluck('branch_id'))->pluck('name', 'id');

        return $rows->map(fn ($row) => [
            'branch_id' => $row->branch_id,
            'branch_name' => $names[$row->branch_id] ?? null,
            'bookings' => (int) $row->bookings,
            'gross_booking_value' => $this->money($row->gross),
            'discount' => $this->money($row->discount),
            'revenue' => $this->money($row->net),
            'average_booking_value' => $row->bookings > 0 ? $this->money($row->net / $row->bookings) : $this->money(0),
        ])->all();
    }

    /**
     * Attribution: each `booking_items` row is counted toward exactly the one
     * staff member assigned to it, so a multi-staff booking's revenue splits
     * across staff rather than being counted once per staff (no double
     * counting). Discount is proportionally allocated — see
     * `allocatedDiscountExpression()`.
     *
     * @param  array<string, mixed>  $filters
     * @return list<array<string, mixed>>
     */
    private function byStaff(Tenant $tenant, DateRange $range, array $filters): array
    {
        $discountExpr = $this->allocatedDiscountExpression();
        $rows = $this->bookingItemsQuery($tenant, $range, $filters)
            ->selectRaw("bi.staff_id, COUNT(DISTINCT bi.booking_id) as bookings, COALESCE(SUM(bi.subtotal), 0) as gross, COALESCE(SUM({$discountExpr}), 0) as discount")
            ->whereNotNull('bi.staff_id')
            ->groupBy('bi.staff_id')
            ->orderByDesc('gross')
            ->get();

        $names = Staff::query()->whereIn('id', $rows->pluck('staff_id'))->pluck('name', 'id');

        return $rows->map(function ($row) use ($names) {
            $net = (float) $row->gross - (float) $row->discount;

            return [
                'staff_id' => $row->staff_id,
                'staff_name' => $names[$row->staff_id] ?? null,
                'bookings' => (int) $row->bookings,
                'gross_revenue' => $this->money($row->gross),
                'discount_allocated' => $this->money($row->discount),
                'net_revenue' => $this->money($net),
                'average_booking_value' => $row->bookings > 0 ? $this->money($net / $row->bookings) : $this->money(0),
            ];
        })->all();
    }

    /**
     * Uses `booking_items.service_price`/`subtotal` — the historical price
     * snapshot captured at booking time — never the service's current
     * `price`, so a later price change never rewrites past reports.
     *
     * @param  array<string, mixed>  $filters
     * @return list<array<string, mixed>>
     */
    private function byService(Tenant $tenant, DateRange $range, array $filters): array
    {
        $discountExpr = $this->allocatedDiscountExpression();
        $rows = $this->bookingItemsQuery($tenant, $range, $filters)
            ->selectRaw("bi.service_id, bi.service_name, COUNT(DISTINCT bi.booking_id) as bookings, COALESCE(SUM(bi.quantity), 0) as quantity, COALESCE(SUM(bi.subtotal), 0) as gross, COALESCE(SUM({$discountExpr}), 0) as discount")
            ->groupBy('bi.service_id', 'bi.service_name')
            ->orderByDesc('gross')
            ->get();

        return $rows->map(function ($row) {
            $net = (float) $row->gross - (float) $row->discount;

            return [
                'service_id' => $row->service_id,
                'service_name' => $row->service_name,
                'bookings' => (int) $row->bookings,
                'quantity' => (int) $row->quantity,
                'gross_value' => $this->money($row->gross),
                'discount_allocated' => $this->money($row->discount),
                'net_value' => $this->money($net),
            ];
        })->all();
    }
}
