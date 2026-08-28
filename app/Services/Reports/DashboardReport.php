<?php

namespace App\Services\Reports;

use App\Enums\BookingStatus;
use App\Enums\BusinessStatus;
use App\Models\Booking;
use App\Models\Customer;
use App\Models\Staff;
use App\Models\Tenant;
use App\Support\DateRange;
use Carbon\CarbonImmutable;

/**
 * The Reports section's "Overview" — a date-range-flexible superset of the
 * fixed-to-today `GET /dashboard/summary` (Phase 8, still used by the Home
 * tab; see DashboardController). Composes `BookingReport`/`RevenueReport`
 * rather than re-querying, so the two endpoints' numbers can never drift
 * apart for the same range/filters.
 */
class DashboardReport
{
    public function __construct(
        private readonly BookingReport $bookings,
        private readonly RevenueReport $revenue,
    ) {}

    /**
     * @param  array<string, mixed>  $filters
     */
    public function generate(Tenant $tenant, DateRange $range, array $filters): array
    {
        $bookingSummary = $this->bookings->generate($tenant, $range, $filters)['summary'];
        $revenueSummary = $this->revenue->generate($tenant, $range, $filters)['summary'];

        $today = CarbonImmutable::now($range->timezone)->toDateString();
        $nextAppointmentQuery = Booking::query()->with('customer')
            ->whereIn('status', array_map(fn (BookingStatus $s) => $s->value, [
                BookingStatus::PENDING, BookingStatus::CONFIRMED, BookingStatus::CHECKED_IN, BookingStatus::IN_SERVICE,
            ]))
            ->where('booking_date', '>=', $today);
        if (! empty($filters['branch_id'])) {
            $nextAppointmentQuery->where('branch_id', $filters['branch_id']);
        }
        $nextAppointment = $nextAppointmentQuery->orderBy('booking_date')->orderBy('start_time')->first();

        return [
            'summary' => [
                'range' => ['preset' => $range->preset, 'from' => $range->startDate(), 'to' => $range->endDate()],
                'bookings' => $bookingSummary,
                'revenue' => $revenueSummary,
                'active_staff' => Staff::query()->where('status', BusinessStatus::ACTIVE)->count(),
                'total_customers' => Customer::query()->count(),
                'next_appointment' => $nextAppointment ? [
                    'id' => $nextAppointment->id,
                    'booking_date' => $nextAppointment->booking_date->format('Y-m-d'),
                    'start_time' => substr((string) $nextAppointment->start_time, 0, 5),
                    'status' => $nextAppointment->status->value,
                    'customer_name' => $nextAppointment->customer?->name,
                ] : null,
            ],
        ];
    }
}
