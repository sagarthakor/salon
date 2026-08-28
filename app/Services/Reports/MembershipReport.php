<?php

namespace App\Services\Reports;

use App\Enums\CustomerMembershipStatus;
use App\Enums\PaymentStatus;
use App\Models\CustomerMembership;
use App\Models\MembershipPayment;
use App\Models\MembershipPlan;
use App\Models\Tenant;
use App\Support\DateRange;

/**
 * Status counts group `customer_memberships` whose `starts_at` (purchase/
 * grant date) falls inside the selected range, by their *current* status —
 * this keeps the date filter meaningful for a report about a period, while
 * still reflecting today's real status (a membership doesn't freeze its
 * status at the moment it was granted).
 *
 * Membership revenue is `membership_payments` (Phase 12) — deliberately
 * never mixed with SaaS `payments`/`invoices` (Phase 10), which bill the
 * tenant for platform access, not the tenant's own customers for a
 * membership. See "SaaS billing report" in
 * REPORTING_ANALYTICS_ARCHITECTURE.md.
 */
class MembershipReport
{
    /**
     * @param  array<string, mixed>  $filters
     */
    public function generate(Tenant $tenant, DateRange $range, array $filters): array
    {
        $plansQuery = MembershipPlan::query();
        if (! empty($filters['membership_plan_id'])) {
            $plansQuery->where('id', $filters['membership_plan_id']);
        }
        $totalPlans = $plansQuery->count();

        $membershipsQuery = CustomerMembership::query()->whereBetween('starts_at', [$range->start, $range->end]);
        if (! empty($filters['membership_plan_id'])) {
            $membershipsQuery->where('membership_plan_id', $filters['membership_plan_id']);
        }
        if (! empty($filters['customer_id'])) {
            $membershipsQuery->where('customer_id', $filters['customer_id']);
        }

        $statusCounts = (clone $membershipsQuery)->toBase()->selectRaw('status, COUNT(*) as cnt')->groupBy('status')->pluck('cnt', 'status');

        $revenue = MembershipPayment::query()
            ->where('status', PaymentStatus::PAID->value)
            ->whereBetween('paid_at', [$range->start, $range->end])
            ->when(! empty($filters['membership_plan_id']), fn ($q) => $q->where('membership_plan_id', $filters['membership_plan_id']))
            ->when(! empty($filters['customer_id']), fn ($q) => $q->where('customer_id', $filters['customer_id']))
            ->sum('amount');

        $popularPlans = (clone $membershipsQuery)->toBase()
            ->selectRaw('membership_plan_id, COUNT(*) as memberships')
            ->groupBy('membership_plan_id')
            ->orderByDesc('memberships')
            ->get();
        $planNames = MembershipPlan::query()->whereIn('id', $popularPlans->pluck('membership_plan_id'))->pluck('name', 'id');

        return [
            'summary' => [
                'total_plans' => $totalPlans,
                'memberships_started' => (int) $statusCounts->sum(),
                'active_memberships' => (int) ($statusCounts[CustomerMembershipStatus::ACTIVE->value] ?? 0),
                'expired_memberships' => (int) ($statusCounts[CustomerMembershipStatus::EXPIRED->value] ?? 0),
                'cancelled_memberships' => (int) ($statusCounts[CustomerMembershipStatus::CANCELLED->value] ?? 0),
                'membership_revenue' => number_format((float) $revenue, 2, '.', ''),
            ],
            'breakdown' => [
                'by_plan' => $popularPlans->map(fn ($row) => [
                    'membership_plan_id' => $row->membership_plan_id,
                    'plan_name' => $planNames[$row->membership_plan_id] ?? null,
                    'memberships' => (int) $row->memberships,
                ])->all(),
            ],
        ];
    }
}
