<?php

namespace App\Http\Requests\Reports\Concerns;

use App\Enums\BookingStatus;
use App\Support\DateRange;
use App\Support\TenantContext;
use Illuminate\Validation\Rule;

/**
 * Building blocks every report FormRequest composes from — never a
 * one-size-fits-all base class, since instruction #5 requires each report to
 * expose only the filters that make business sense for it. Every ID filter
 * is scoped to the authenticated tenant via `Rule::exists(...)->where(...)`,
 * the same pattern used throughout Phases 1–12 (see BookingRequest,
 * CustomerRequest) — an ID belonging to another tenant simply fails
 * validation (422), it is never silently ignored.
 */
trait HasReportFilterRules
{
    protected function tenantId(): ?string
    {
        return app(TenantContext::class)->id();
    }

    /** @return array<string, array<int, mixed>> */
    protected function dateRangeRules(): array
    {
        return [
            'range' => ['nullable', Rule::in(DateRange::PRESETS)],
            'from' => ['nullable', 'date_format:Y-m-d', 'required_if:range,custom'],
            'to' => ['nullable', 'date_format:Y-m-d', 'required_if:range,custom', 'after_or_equal:from'],
        ];
    }

    /** @return array<string, array<int, mixed>> */
    protected function branchFilterRule(): array
    {
        return ['branch_id' => ['nullable', Rule::exists('branches', 'id')->where('tenant_id', $this->tenantId())]];
    }

    /** @return array<string, array<int, mixed>> */
    protected function staffFilterRule(): array
    {
        return ['staff_id' => ['nullable', Rule::exists('staff_profiles', 'id')->where('tenant_id', $this->tenantId())]];
    }

    /** @return array<string, array<int, mixed>> */
    protected function serviceFilterRule(): array
    {
        return ['service_id' => ['nullable', Rule::exists('services', 'id')->where('tenant_id', $this->tenantId())]];
    }

    /** @return array<string, array<int, mixed>> */
    protected function categoryFilterRule(): array
    {
        return ['category_id' => ['nullable', Rule::exists('service_categories', 'id')->where('tenant_id', $this->tenantId())]];
    }

    /** @return array<string, array<int, mixed>> */
    protected function statusFilterRule(): array
    {
        return ['status' => ['nullable', Rule::enum(BookingStatus::class)]];
    }

    /** @return array<string, array<int, mixed>> */
    protected function customerFilterRule(): array
    {
        return ['customer_id' => ['nullable', Rule::exists('customer_profiles', 'id')->where('tenant_id', $this->tenantId())]];
    }

    /** @return array<string, array<int, mixed>> */
    protected function couponFilterRule(): array
    {
        return ['coupon_id' => ['nullable', Rule::exists('coupons', 'id')->where('tenant_id', $this->tenantId())]];
    }

    /** @return array<string, array<int, mixed>> */
    protected function membershipPlanFilterRule(): array
    {
        return ['membership_plan_id' => ['nullable', Rule::exists('membership_plans', 'id')->where('tenant_id', $this->tenantId())]];
    }

    /** @return array<string, array<int, mixed>> */
    protected function groupByRule(): array
    {
        return ['group_by' => ['nullable', Rule::in(['day', 'week', 'month'])]];
    }

    /** @return array<string, array<int, mixed>> */
    protected function paginationRules(): array
    {
        return [
            'page' => ['nullable', 'integer', 'min:1'],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:100'],
        ];
    }

    /**
     * @param  list<string>  $allowed  whitelisted sortable columns/aliases — never a raw client-supplied column name.
     * @return array<string, array<int, mixed>>
     */
    protected function sortRules(array $allowed): array
    {
        return [
            'sort' => ['nullable', Rule::in($allowed)],
            'direction' => ['nullable', Rule::in(['asc', 'desc'])],
        ];
    }

    /**
     * Resolve the validated `range`/`from`/`to` into a concrete DateRange,
     * anchored to the given timezone (the salon's, or a filtered branch's —
     * see ReportTimezoneResolver).
     */
    protected function resolveDateRange(string $timezone): DateRange
    {
        return DateRange::resolve(
            $this->validated('range') ?? 'this_month',
            $this->validated('from'),
            $this->validated('to'),
            $timezone,
        );
    }
}
