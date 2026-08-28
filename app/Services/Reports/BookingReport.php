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
 * Booking volume/status counts, the booking-status trend, and — folded into
 * the same report rather than separate endpoints (see instruction #45's
 * route list, which has no dedicated cancellation/no-show routes) — the
 * cancellation and no-show reports.
 *
 * cancellation_rate = cancelled_bookings / total_bookings.
 * no_show_rate = no_show_bookings / total_bookings.
 * Both denominators are every booking in the filtered range (not just
 * terminal ones) — see "Metric definitions" in
 * REPORTING_ANALYTICS_ARCHITECTURE.md.
 */
class BookingReport
{
    use FiltersBookings;
    use QueriesBookingItems;

    /**
     * @param  array<string, mixed>  $filters
     */
    public function generate(Tenant $tenant, DateRange $range, array $filters): array
    {
        $statusCounts = $this->bookingsQuery($range, $filters)->toBase()
            ->selectRaw('status, COUNT(*) as cnt')
            ->groupBy('status')
            ->pluck('cnt', 'status');

        $counts = [];
        $total = 0;
        foreach (BookingStatus::cases() as $status) {
            $count = (int) ($statusCounts[$status->value] ?? 0);
            $counts[$status->value] = $count;
            $total += $count;
        }
        $cancelled = $counts[BookingStatus::CANCELLED->value];
        $noShow = $counts[BookingStatus::NO_SHOW->value];

        $groupBy = $filters['group_by'] ?? $range->defaultGroupBy();
        $trendRows = $this->bookingsQuery($range, $filters)->toBase()
            ->selectRaw('booking_date, status, COUNT(*) as cnt')
            ->groupBy('booking_date', 'status')
            ->get();
        $dailyValues = [];
        foreach ($trendRows as $row) {
            $dailyValues[$row->booking_date]['total'] = ($dailyValues[$row->booking_date]['total'] ?? 0) + (int) $row->cnt;
            if (in_array($row->status, [BookingStatus::COMPLETED->value, BookingStatus::CANCELLED->value, BookingStatus::NO_SHOW->value], true)) {
                $dailyValues[$row->booking_date][$row->status] = ($dailyValues[$row->booking_date][$row->status] ?? 0) + (int) $row->cnt;
            }
        }
        $series = ReportSeriesBuilder::build($range, $groupBy, $dailyValues, [
            'total', BookingStatus::COMPLETED->value, BookingStatus::CANCELLED->value, BookingStatus::NO_SHOW->value,
        ]);

        $reasonRows = $this->bookingsQuery($range, [...$filters, 'status' => BookingStatus::CANCELLED->value])->toBase()
            ->selectRaw('COALESCE(NULLIF(cancellation_reason, \'\'), \'Not specified\') as reason, COUNT(*) as cnt')
            ->groupBy('reason')
            ->orderByDesc('cnt')
            ->get();

        return [
            'summary' => [
                'total' => $total,
                ...$counts,
                'cancellation_rate' => $total > 0 ? round($cancelled / $total, 4) : 0.0,
                'no_show_rate' => $total > 0 ? round($noShow / $total, 4) : 0.0,
            ],
            'series' => $series,
            'breakdown' => [
                'by_branch' => $this->byBranch($range, $filters),
                'by_staff' => $this->byStaff($tenant, $range, $filters),
                'cancellation_reasons' => $reasonRows->map(fn ($r) => ['reason' => $r->reason, 'count' => (int) $r->cnt])->all(),
            ],
        ];
    }

    /**
     * @param  array<string, mixed>  $filters
     * @return list<array<string, mixed>>
     */
    private function byBranch(DateRange $range, array $filters): array
    {
        $rows = $this->bookingsQuery($range, $filters)->toBase()
            ->selectRaw('branch_id, COUNT(*) as total, '
                .'SUM(CASE WHEN status = ? THEN 1 ELSE 0 END) as completed, '
                .'SUM(CASE WHEN status = ? THEN 1 ELSE 0 END) as cancelled, '
                .'SUM(CASE WHEN status = ? THEN 1 ELSE 0 END) as no_show',
                [BookingStatus::COMPLETED->value, BookingStatus::CANCELLED->value, BookingStatus::NO_SHOW->value])
            ->groupBy('branch_id')
            ->get();

        $names = Branch::query()->whereIn('id', $rows->pluck('branch_id'))->pluck('name', 'id');

        return $rows->map(fn ($row) => [
            'branch_id' => $row->branch_id,
            'branch_name' => $names[$row->branch_id] ?? null,
            'total' => (int) $row->total,
            'completed' => (int) $row->completed,
            'cancelled' => (int) $row->cancelled,
            'no_show' => (int) $row->no_show,
            'cancellation_rate' => $row->total > 0 ? round($row->cancelled / $row->total, 4) : 0.0,
            'no_show_rate' => $row->total > 0 ? round($row->no_show / $row->total, 4) : 0.0,
        ])->all();
    }

    /**
     * @param  array<string, mixed>  $filters
     * @return list<array<string, mixed>>
     */
    private function byStaff(Tenant $tenant, DateRange $range, array $filters): array
    {
        $rows = $this->bookingItemsQuery($tenant, $range, $filters)
            ->selectRaw('bi.staff_id, COUNT(DISTINCT bi.booking_id) as total, '
                .'COUNT(DISTINCT CASE WHEN b.status = ? THEN bi.booking_id END) as completed, '
                .'COUNT(DISTINCT CASE WHEN b.status = ? THEN bi.booking_id END) as cancelled, '
                .'COUNT(DISTINCT CASE WHEN b.status = ? THEN bi.booking_id END) as no_show',
                [BookingStatus::COMPLETED->value, BookingStatus::CANCELLED->value, BookingStatus::NO_SHOW->value])
            ->whereNotNull('bi.staff_id')
            ->groupBy('bi.staff_id')
            ->get();

        $names = Staff::query()->whereIn('id', $rows->pluck('staff_id'))->pluck('name', 'id');

        return $rows->map(fn ($row) => [
            'staff_id' => $row->staff_id,
            'staff_name' => $names[$row->staff_id] ?? null,
            'total' => (int) $row->total,
            'completed' => (int) $row->completed,
            'cancelled' => (int) $row->cancelled,
            'no_show' => (int) $row->no_show,
        ])->all();
    }
}
