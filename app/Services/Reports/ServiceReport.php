<?php

namespace App\Services\Reports;

use App\Enums\BookingStatus;
use App\Models\Tenant;
use App\Services\Reports\Concerns\QueriesBookingItems;
use App\Support\DateRange;

/**
 * Most-booked services and the service-category breakdown, both from
 * `booking_items` historical snapshots (`service_name`/`service_price`) —
 * never the service's current, possibly-changed `price`. See "Service
 * report" in REPORTING_ANALYTICS_ARCHITECTURE.md.
 */
class ServiceReport
{
    use QueriesBookingItems;

    /**
     * @param  array<string, mixed>  $filters
     */
    public function generate(Tenant $tenant, DateRange $range, array $filters): array
    {
        $discountExpr = $this->allocatedDiscountExpression();
        $rows = $this->bookingItemsQuery($tenant, $range, $filters)
            ->selectRaw('bi.service_id, bi.service_name, COUNT(DISTINCT bi.booking_id) as bookings, '
                .'COUNT(DISTINCT CASE WHEN b.status = ? THEN bi.booking_id END) as completed, '
                .'COALESCE(SUM(bi.quantity), 0) as quantity, COALESCE(SUM(bi.subtotal), 0) as gross, '
                ."COALESCE(SUM({$discountExpr}), 0) as discount, COALESCE(AVG(bi.service_price), 0) as average_price",
                [BookingStatus::COMPLETED->value])
            ->groupBy('bi.service_id', 'bi.service_name')
            ->get();

        $sortKey = in_array($filters['sort'] ?? null, ['bookings', 'gross', 'completed', 'quantity'], true) ? $filters['sort'] : 'bookings';
        $direction = ($filters['direction'] ?? 'desc') === 'asc' ? 'asc' : 'desc';
        $sorted = $rows->sortBy(fn ($r) => (float) $r->{$sortKey}, SORT_REGULAR, $direction === 'desc')->values();

        $perPage = min((int) ($filters['per_page'] ?? 20), 100);
        $page = max((int) ($filters['page'] ?? 1), 1);
        $paged = $sorted->slice(($page - 1) * $perPage, $perPage)->values()->map(fn ($r) => [
            'service_id' => $r->service_id,
            'service_name' => $r->service_name,
            'bookings' => (int) $r->bookings,
            'completed_bookings' => (int) $r->completed,
            'quantity' => (int) $r->quantity,
            'gross_value' => number_format((float) $r->gross, 2, '.', ''),
            'discount_allocated' => number_format((float) $r->discount, 2, '.', ''),
            'net_value' => number_format((float) $r->gross - (float) $r->discount, 2, '.', ''),
            'average_price' => number_format((float) $r->average_price, 2, '.', ''),
        ]);

        $categoryRows = $this->bookingItemsQuery($tenant, $range, $filters)
            ->join('services as sv', 'sv.id', '=', 'bi.service_id')
            ->join('service_categories as sc', 'sc.id', '=', 'sv.category_id')
            ->selectRaw('sc.id as category_id, sc.name as category_name, COUNT(DISTINCT bi.booking_id) as bookings, COALESCE(SUM(bi.subtotal), 0) as gross')
            ->groupBy('sc.id', 'sc.name')
            ->orderByDesc('gross')
            ->get();
        $totalCategoryBookings = (int) $categoryRows->sum('bookings');

        return [
            'summary' => [
                'total_services_booked' => $rows->count(),
                'total_bookings' => (int) $rows->sum('bookings'),
            ],
            'data' => $paged->all(),
            'breakdown' => [
                'by_category' => $categoryRows->map(fn ($r) => [
                    'category_id' => $r->category_id,
                    'category_name' => $r->category_name,
                    'bookings' => (int) $r->bookings,
                    'revenue' => number_format((float) $r->gross, 2, '.', ''),
                    'percent_of_service_bookings' => $totalCategoryBookings > 0 ? round($r->bookings / $totalCategoryBookings, 4) : 0.0,
                ])->all(),
            ],
        ];
    }
}
