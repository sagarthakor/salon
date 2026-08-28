<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\BookingStatus;
use App\Enums\BusinessStatus;
use App\Enums\LeaveStatus;
use App\Models\Booking;
use App\Models\Customer;
use App\Models\Staff;
use App\Models\StaffLeave;
use App\Support\ApiResponse;
use App\Support\ReportTimezoneResolver;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;

/**
 * Aggregate counters for the owner/staff dashboard home screen. Every value
 * is a real, server-computed query result — nothing here is fabricated or
 * hard-coded. See OWNER_APP_ARCHITECTURE.md for why this exists as one
 * endpoint rather than the client stitching several paginated list calls
 * together (would mean N+1-ish requests and, for "staff on leave today" and
 * "revenue today" specifically, data no list endpoint exposes at all).
 *
 * "Today" is resolved in the salon's own timezone (via
 * ReportTimezoneResolver, the same helper Phase 13's reports use), not the
 * server's — a booking at 00:30 local time must land on the correct local
 * business date. See "Timezone handling" in
 * REPORTING_ANALYTICS_ARCHITECTURE.md.
 */
class DashboardController extends TenantManagementController
{
    public function summary(): JsonResponse
    {
        $tenant = $this->viewableTenant();
        $timezone = ReportTimezoneResolver::resolve($tenant, null);
        $now = CarbonImmutable::now($timezone);
        $today = $now->toDateString();

        $todayBookings = Booking::query()->where('booking_date', $today)->get(['id', 'status', 'total']);
        $bookingCounts = ['total' => $todayBookings->count()];
        foreach (BookingStatus::cases() as $status) {
            $bookingCounts[$status->value] = $todayBookings->where('status', $status)->count();
        }
        $revenueToday = $todayBookings->where('status', BookingStatus::COMPLETED)->sum('total');

        $nextAppointment = Booking::query()
            ->with('customer')
            ->whereIn('status', [BookingStatus::PENDING, BookingStatus::CONFIRMED, BookingStatus::CHECKED_IN, BookingStatus::IN_SERVICE])
            ->where('booking_date', '>=', $today)
            ->orderBy('booking_date')->orderBy('start_time')
            ->first();

        $activeStaff = Staff::query()->where('status', BusinessStatus::ACTIVE)->count();
        $onLeaveToday = StaffLeave::query()
            ->where('status', '!=', LeaveStatus::REJECTED->value)
            ->where('start_date', '<=', $today)
            ->where('end_date', '>=', $today)
            ->distinct('staff_id')
            ->count('staff_id');

        $totalCustomers = Customer::query()->count();
        $newCustomersThisMonth = Customer::query()->where('created_at', '>=', $now->startOfMonth())->count();

        return ApiResponse::success([
            'date' => $today,
            'bookings' => $bookingCounts,
            'revenue_today' => number_format((float) $revenueToday, 2, '.', ''),
            'next_appointment' => $nextAppointment ? [
                'id' => $nextAppointment->id,
                'booking_date' => $nextAppointment->booking_date->format('Y-m-d'),
                'start_time' => substr((string) $nextAppointment->start_time, 0, 5),
                'status' => $nextAppointment->status->value,
                'customer_name' => $nextAppointment->customer?->name,
            ] : null,
            'staff' => ['active' => $activeStaff, 'on_leave_today' => $onLeaveToday],
            'customers' => ['total' => $totalCustomers, 'new_this_month' => $newCustomersThisMonth],
        ], 'Dashboard summary retrieved.');
    }
}
