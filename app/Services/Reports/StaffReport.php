<?php

namespace App\Services\Reports;

use App\Enums\BookingStatus;
use App\Enums\BusinessStatus;
use App\Models\Staff;
use App\Models\Tenant;
use App\Services\Reports\Concerns\QueriesBookingItems;
use App\Support\DateRange;
use Illuminate\Support\Arr;

/**
 * Staff performance — owner-only (never exposed to the Staff app; see the
 * controller/route). Revenue attribution mirrors `RevenueReport::byStaff()`:
 * gross = sum of that staff's own `booking_items.subtotal`, discount
 * proportionally allocated, so a multi-staff booking is never double-counted
 * or double-discounted.
 */
class StaffReport
{
    use QueriesBookingItems;

    /**
     * @param  array<string, mixed>  $filters
     */
    public function generate(Tenant $tenant, DateRange $range, array $filters): array
    {
        $staffQuery = Staff::query();
        if (! empty($filters['staff_id'])) {
            $staffQuery->where('id', $filters['staff_id']);
        }
        if (! empty($filters['branch_id'])) {
            $staffQuery->whereHas('branches', fn ($q) => $q->where('branches.id', $filters['branch_id']));
        }
        $staff = $staffQuery->get(['id', 'name', 'status']);
        $staffIds = $staff->pluck('id')->all();

        $discountExpr = $this->allocatedDiscountExpression();
        $bookingRows = $this->bookingItemsQuery($tenant, $range, $filters)
            ->selectRaw('bi.staff_id, COUNT(DISTINCT bi.booking_id) as assigned, '
                .'COUNT(DISTINCT CASE WHEN b.status = ? THEN bi.booking_id END) as completed, '
                .'COUNT(DISTINCT CASE WHEN b.status = ? THEN bi.booking_id END) as cancelled, '
                .'COUNT(DISTINCT CASE WHEN b.status = ? THEN bi.booking_id END) as no_show, '
                ."COALESCE(SUM(bi.subtotal), 0) as gross, COALESCE(SUM({$discountExpr}), 0) as discount",
                [BookingStatus::COMPLETED->value, BookingStatus::CANCELLED->value, BookingStatus::NO_SHOW->value])
            ->whereNotNull('bi.staff_id')
            ->groupBy('bi.staff_id')
            ->get()->keyBy('staff_id');

        $blockingStatuses = array_map(fn (BookingStatus $s) => $s->value, BookingStatus::blockingBooking());
        $minutesFilters = Arr::except($filters, ['status']);
        $bookedMinutes = $this->bookingItemsQuery($tenant, $range, $minutesFilters)
            ->whereIn('b.status', $blockingStatuses)
            ->whereNotNull('bi.staff_id')
            ->selectRaw('bi.staff_id, COALESCE(SUM(bi.service_duration_minutes * bi.quantity), 0) as minutes')
            ->groupBy('bi.staff_id')
            ->pluck('minutes', 'staff_id');

        $availableMinutes = (new StaffUtilizationCalculator)->availableMinutesFor($staffIds, $range, $filters['branch_id'] ?? null);

        $rows = $staff->map(function (Staff $s) use ($bookingRows, $bookedMinutes, $availableMinutes) {
            $row = $bookingRows->get($s->id);
            $assigned = (int) ($row->assigned ?? 0);
            $completed = (int) ($row->completed ?? 0);
            $cancelled = (int) ($row->cancelled ?? 0);
            $noShow = (int) ($row->no_show ?? 0);
            $gross = (float) ($row->gross ?? 0);
            $discount = (float) ($row->discount ?? 0);
            $net = $gross - $discount;
            $available = $availableMinutes[$s->id] ?? 0;
            $booked = (int) ($bookedMinutes[$s->id] ?? 0);

            return [
                'staff_id' => $s->id,
                'staff_name' => $s->name,
                'status' => $s->status->value,
                'assigned_bookings' => $assigned,
                'completed_bookings' => $completed,
                'cancelled_bookings' => $cancelled,
                'no_show_bookings' => $noShow,
                'gross_revenue' => number_format($gross, 2, '.', ''),
                'net_revenue' => number_format($net, 2, '.', ''),
                'average_booking_value' => $completed > 0 ? number_format($net / max($completed, 1), 2, '.', '') : number_format(0, 2, '.', ''),
                'completion_rate' => $assigned > 0 ? round($completed / $assigned, 4) : 0.0,
                'available_minutes' => $available,
                'booked_minutes' => $booked,
                'utilization_percent' => $available > 0 ? round(min($booked, $available) / $available * 100, 2) : null,
            ];
        });

        $sort = $filters['sort'] ?? 'staff_name';
        $direction = ($filters['direction'] ?? 'asc') === 'desc' ? 'desc' : 'asc';
        $sorted = $rows->sortBy(fn ($row) => $row[$sort] ?? $row['staff_name'], SORT_REGULAR, $direction === 'desc')->values();

        $perPage = min((int) ($filters['per_page'] ?? 20), 100);
        $page = max((int) ($filters['page'] ?? 1), 1);
        $paged = $sorted->slice(($page - 1) * $perPage, $perPage)->values();

        return [
            'summary' => [
                'total_staff' => $staff->count(),
                'active_staff' => $staff->where('status', BusinessStatus::ACTIVE)->count(),
            ],
            'data' => $paged->all(),
        ];
    }
}
