<?php

namespace App\Services\Reports;

use App\Enums\BookingStatus;
use App\Models\Booking;
use App\Models\Customer;
use App\Models\Tenant;
use App\Services\Reports\Concerns\FiltersBookings;
use App\Support\DateRange;
use App\Support\ReportSeriesBuilder;

/**
 * Definitions (see "Customer definitions" in REPORTING_ANALYTICS_ARCHITECTURE.md):
 *
 *   - New customer = `customer_profiles.created_at` falls inside the range.
 *   - Active customer = at least one non-cancelled booking in the range.
 *   - Returning customer = booked in the range AND has a COMPLETED booking
 *     dated before the range started (i.e. a real visit predates this period).
 *   - Repeat booking rate = customers with 2+ COMPLETED bookings in the
 *     range ÷ customers with 1+ COMPLETED booking in the range.
 *
 * "Total spend" on the top-customers list is that customer's COMPLETED
 * booking total within the selected range (their `bookings.total`, the same
 * net-of-discount figure RevenueReport uses) — never a re-derived or
 * all-time figure.
 */
class CustomerReport
{
    use FiltersBookings;

    /**
     * @param  array<string, mixed>  $filters
     */
    public function generate(Tenant $tenant, DateRange $range, array $filters): array
    {
        $totalCustomers = Customer::query()->count();
        $newCustomers = Customer::query()->whereBetween('created_at', [$range->start, $range->end])->count();

        $rangeBookings = $this->bookingsQuery($range, $filters)->toBase()->select('customer_id', 'status')->get();
        $byCustomer = $rangeBookings->groupBy('customer_id');
        $activeCustomers = $byCustomer->filter(fn ($rows) => $rows->contains(fn ($r) => $r->status !== BookingStatus::CANCELLED->value))->count();
        $completedCustomerIds = $byCustomer->filter(fn ($rows) => $rows->contains(fn ($r) => $r->status === BookingStatus::COMPLETED->value))->keys();
        $cancelledCustomerIds = $byCustomer->filter(fn ($rows) => $rows->contains(fn ($r) => $r->status === BookingStatus::CANCELLED->value))->keys();

        $returningCustomers = $byCustomer->isEmpty() ? 0 : Booking::query()
            ->whereIn('customer_id', $byCustomer->keys())
            ->where('status', BookingStatus::COMPLETED->value)
            ->where('booking_date', '<', $range->startDate())
            ->distinct('customer_id')->count('customer_id');

        $completedCountsPerCustomer = $this->bookingsQuery($range, [...$filters, 'status' => BookingStatus::COMPLETED->value])
            ->toBase()->pluck('customer_id')->countBy();
        $customersWithCompleted = $completedCountsPerCustomer->count();
        $customersWithRepeat = $completedCountsPerCustomer->filter(fn ($c) => $c >= 2)->count();
        $repeatBookingRate = $customersWithCompleted > 0 ? round($customersWithRepeat / $customersWithCompleted, 4) : null;

        $groupBy = $filters['group_by'] ?? $range->defaultGroupBy();
        $growthRows = Customer::query()->whereBetween('created_at', [$range->start, $range->end])
            ->toBase()->selectRaw('DATE(created_at) as d, COUNT(*) as cnt')->groupBy('d')->get();
        $dailyValues = [];
        foreach ($growthRows as $row) {
            $dailyValues[$row->d] = ['new_customers' => (int) $row->cnt];
        }
        $series = ReportSeriesBuilder::build($range, $groupBy, $dailyValues, ['new_customers']);

        return [
            'summary' => [
                'total_customers' => $totalCustomers,
                'new_customers' => $newCustomers,
                'active_customers' => $activeCustomers,
                'returning_customers' => $returningCustomers,
                'customers_with_completed_bookings' => $completedCustomerIds->count(),
                'customers_with_cancelled_bookings' => $cancelledCustomerIds->count(),
                'repeat_booking_rate' => $repeatBookingRate,
            ],
            'series' => $series,
            'data' => $this->topCustomers($range, $filters),
        ];
    }

    /**
     * @param  array<string, mixed>  $filters
     * @return list<array<string, mixed>>
     */
    private function topCustomers(DateRange $range, array $filters): array
    {
        $spendRows = $this->bookingsQuery($range, [...$filters, 'status' => BookingStatus::COMPLETED->value])
            ->toBase()
            ->selectRaw('customer_id, COUNT(*) as completed_bookings, COALESCE(SUM(total), 0) as spend')
            ->groupBy('customer_id')
            ->orderByDesc('spend')
            ->get();

        $perPage = min((int) ($filters['per_page'] ?? 20), 100);
        $page = max((int) ($filters['page'] ?? 1), 1);
        $paged = $spendRows->slice(($page - 1) * $perPage, $perPage)->values();
        $customerIds = $paged->pluck('customer_id')->all();

        $customers = Customer::query()->whereIn('id', $customerIds)->get(['id', 'name', 'phone'])->keyBy('id');
        $lastVisits = Booking::query()->whereIn('customer_id', $customerIds)->where('status', BookingStatus::COMPLETED->value)
            ->selectRaw('customer_id, MAX(booking_date) as last_visit')->groupBy('customer_id')->pluck('last_visit', 'customer_id');
        $upcoming = Booking::query()->whereIn('customer_id', $customerIds)
            ->whereIn('status', array_map(fn ($s) => $s->value, [BookingStatus::PENDING, BookingStatus::CONFIRMED, BookingStatus::CHECKED_IN, BookingStatus::IN_SERVICE]))
            ->where('booking_date', '>=', now()->toDateString())
            ->selectRaw('customer_id, MIN(booking_date) as next_visit')->groupBy('customer_id')->pluck('next_visit', 'customer_id');

        return $paged->map(function ($row) use ($customers, $lastVisits, $upcoming) {
            $customer = $customers->get($row->customer_id);

            return [
                'customer_id' => $row->customer_id,
                'customer_name' => $customer?->name,
                'completed_bookings' => (int) $row->completed_bookings,
                'total_spend' => number_format((float) $row->spend, 2, '.', ''),
                'last_visit' => $lastVisits[$row->customer_id] ?? null,
                'upcoming_booking' => $upcoming[$row->customer_id] ?? null,
            ];
        })->all();
    }
}
