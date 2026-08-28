<?php

namespace App\Services\Reports;

use App\Enums\BookingStatus;
use App\Models\Branch;
use App\Models\Tenant;
use App\Services\Reports\Concerns\FiltersBookings;
use App\Support\DateRange;

/**
 * Every branch belonging to the tenant appears — including one with zero
 * bookings in the selected range — so "Branch comparison" in the Owner App
 * never silently drops a branch that simply had no activity.
 */
class BranchReport
{
    use FiltersBookings;

    /**
     * @param  array<string, mixed>  $filters
     */
    public function generate(Tenant $tenant, DateRange $range, array $filters): array
    {
        $branches = Branch::query()
            ->when(! empty($filters['branch_id']), fn ($q) => $q->where('id', $filters['branch_id']))
            ->get(['id', 'name', 'status']);

        $rows = $this->bookingsQuery($range, $filters)->toBase()
            ->selectRaw('branch_id, COUNT(*) as total, '
                .'SUM(CASE WHEN status = ? THEN 1 ELSE 0 END) as completed, '
                .'SUM(CASE WHEN status = ? THEN 1 ELSE 0 END) as cancelled, '
                .'SUM(CASE WHEN status = ? THEN 1 ELSE 0 END) as no_show, '
                .'COALESCE(SUM(CASE WHEN status = ? THEN total ELSE 0 END), 0) as revenue',
                [BookingStatus::COMPLETED->value, BookingStatus::CANCELLED->value, BookingStatus::NO_SHOW->value, BookingStatus::COMPLETED->value])
            ->groupBy('branch_id')
            ->get()->keyBy('branch_id');

        $data = $branches->map(function (Branch $branch) use ($rows) {
            $row = $rows->get($branch->id);
            $total = (int) ($row->total ?? 0);
            $completed = (int) ($row->completed ?? 0);
            $cancelled = (int) ($row->cancelled ?? 0);
            $noShow = (int) ($row->no_show ?? 0);
            $revenue = (float) ($row->revenue ?? 0);

            return [
                'branch_id' => $branch->id,
                'branch_name' => $branch->name,
                'status' => $branch->status->value,
                'bookings' => $total,
                'completed' => $completed,
                'cancelled' => $cancelled,
                'no_show' => $noShow,
                'revenue' => number_format($revenue, 2, '.', ''),
                'average_booking_value' => $completed > 0 ? number_format($revenue / $completed, 2, '.', '') : number_format(0, 2, '.', ''),
                'completion_rate' => $total > 0 ? round($completed / $total, 4) : 0.0,
                'cancellation_rate' => $total > 0 ? round($cancelled / $total, 4) : 0.0,
                'no_show_rate' => $total > 0 ? round($noShow / $total, 4) : 0.0,
            ];
        })->sortByDesc('revenue')->values();

        return [
            'summary' => [
                'total_branches' => $branches->count(),
                'total_bookings' => (int) $rows->sum('total'),
                'total_revenue' => number_format((float) $rows->sum('revenue'), 2, '.', ''),
            ],
            'data' => $data->all(),
        ];
    }
}
