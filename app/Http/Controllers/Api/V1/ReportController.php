<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Requests\Reports\BookingReportRequest;
use App\Http\Requests\Reports\BranchReportRequest;
use App\Http\Requests\Reports\CouponReportRequest;
use App\Http\Requests\Reports\CustomerReportRequest;
use App\Http\Requests\Reports\DashboardReportRequest;
use App\Http\Requests\Reports\LoyaltyReportRequest;
use App\Http\Requests\Reports\MembershipReportRequest;
use App\Http\Requests\Reports\RevenueReportRequest;
use App\Http\Requests\Reports\ServiceReportRequest;
use App\Http\Requests\Reports\StaffReportRequest;
use App\Services\Reports\BookingReport;
use App\Services\Reports\BranchReport;
use App\Services\Reports\CouponReport;
use App\Services\Reports\CustomerReport;
use App\Services\Reports\DashboardReport;
use App\Services\Reports\LoyaltyReport;
use App\Services\Reports\MembershipReport;
use App\Services\Reports\RevenueReport;
use App\Services\Reports\ServiceReport;
use App\Services\Reports\StaffReport;
use App\Support\ApiResponse;
use App\Support\DateRange;
use App\Support\ReportTimezoneResolver;
use App\Support\TenantContext;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Http\JsonResponse;
use InvalidArgumentException;

/**
 * Every action is owner-only (`managedTenant()`) — reports are never exposed
 * to Staff or Customer sessions (see "Owner authorization" in
 * REPORTING_ANALYTICS_ARCHITECTURE.md). This deliberately differs from
 * `DashboardController::summary()`, which staff can also read.
 *
 * All ten reports share the same request shape: resolve the tenant, resolve
 * a `DateRange` in the correct timezone (branch-specific when a `branch_id`
 * filter is given, otherwise the salon's), gather the validated filters, and
 * hand both to the report class. No SQL or aggregation lives here.
 */
class ReportController extends TenantManagementController
{
    public function dashboard(DashboardReportRequest $request, DashboardReport $report): JsonResponse
    {
        $tenant = $this->managedTenant();

        return ApiResponse::success($report->generate($tenant, $this->range($request), $request->validated()), 'Dashboard report retrieved.');
    }

    public function revenue(RevenueReportRequest $request, RevenueReport $report): JsonResponse
    {
        $tenant = $this->managedTenant();

        return ApiResponse::success($report->generate($tenant, $this->range($request), $request->validated()), 'Revenue report retrieved.');
    }

    public function bookings(BookingReportRequest $request, BookingReport $report): JsonResponse
    {
        $tenant = $this->managedTenant();

        return ApiResponse::success($report->generate($tenant, $this->range($request), $request->validated()), 'Booking report retrieved.');
    }

    public function customers(CustomerReportRequest $request, CustomerReport $report): JsonResponse
    {
        $tenant = $this->managedTenant();

        return ApiResponse::success($report->generate($tenant, $this->range($request), $request->validated()), 'Customer report retrieved.');
    }

    public function services(ServiceReportRequest $request, ServiceReport $report): JsonResponse
    {
        $tenant = $this->managedTenant();

        return ApiResponse::success($report->generate($tenant, $this->range($request), $request->validated()), 'Service report retrieved.');
    }

    public function staff(StaffReportRequest $request, StaffReport $report): JsonResponse
    {
        $tenant = $this->managedTenant();

        return ApiResponse::success($report->generate($tenant, $this->range($request), $request->validated()), 'Staff performance report retrieved.');
    }

    public function branches(BranchReportRequest $request, BranchReport $report): JsonResponse
    {
        $tenant = $this->managedTenant();

        return ApiResponse::success($report->generate($tenant, $this->range($request), $request->validated()), 'Branch report retrieved.');
    }

    public function coupons(CouponReportRequest $request, CouponReport $report): JsonResponse
    {
        $tenant = $this->managedTenant();

        return ApiResponse::success($report->generate($tenant, $this->range($request), $request->validated()), 'Coupon report retrieved.');
    }

    public function memberships(MembershipReportRequest $request, MembershipReport $report): JsonResponse
    {
        $tenant = $this->managedTenant();

        return ApiResponse::success($report->generate($tenant, $this->range($request), $request->validated()), 'Membership report retrieved.');
    }

    public function loyalty(LoyaltyReportRequest $request, LoyaltyReport $report): JsonResponse
    {
        $tenant = $this->managedTenant();

        return ApiResponse::success($report->generate($tenant, $this->range($request), $request->validated()), 'Loyalty report retrieved.');
    }

    private function range(FormRequest $request): DateRange
    {
        $tenant = app(TenantContext::class)->require();
        $timezone = ReportTimezoneResolver::resolve($tenant, $request->validated('branch_id'));
        try {
            return DateRange::resolve(
                $request->validated('range') ?? 'this_month',
                $request->validated('from'),
                $request->validated('to'),
                $timezone,
            );
        } catch (InvalidArgumentException $e) {
            throw new HttpResponseException(ApiResponse::error($e->getMessage(), ['range' => [$e->getMessage()]], 422));
        }
    }
}
