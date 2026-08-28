<?php

namespace App\Services\Reports;

use App\Enums\BookingStatus;
use App\Models\Booking;
use App\Models\Coupon;
use App\Models\CouponUsage;
use App\Models\Tenant;
use App\Support\DateRange;

/**
 * Every figure comes from `coupon_usages` — an immutable, one-row-per-
 * application ledger (see CouponUsage) — never recomputed from the coupon's
 * *current* discount configuration, so a coupon edited or deactivated after
 * the fact never rewrites its own history.
 */
class CouponReport
{
    /**
     * @param  array<string, mixed>  $filters
     */
    public function generate(Tenant $tenant, DateRange $range, array $filters): array
    {
        $usage = CouponUsage::query()->whereBetween('used_at', [$range->start, $range->end]);
        if (! empty($filters['coupon_id'])) {
            $usage->where('coupon_id', $filters['coupon_id']);
        }
        if (! empty($filters['customer_id'])) {
            $usage->where('customer_id', $filters['customer_id']);
        }

        $rows = $usage->toBase()
            ->selectRaw('coupon_id, COUNT(*) as times_used, COUNT(DISTINCT customer_id) as customers, COALESCE(SUM(discount_amount), 0) as discount_given')
            ->groupBy('coupon_id')
            ->get();

        $couponIds = $rows->pluck('coupon_id');
        $coupons = Coupon::query()->whereIn('id', $couponIds)->get()->keyBy('id');

        $revenueByCoupon = Booking::query()->whereIn('coupon_id', $couponIds)
            ->where('status', BookingStatus::COMPLETED->value)
            ->whereBetween('booking_date', [$range->startDate(), $range->endDate()])
            ->toBase()->selectRaw('coupon_id, COALESCE(SUM(total), 0) as revenue')->groupBy('coupon_id')->pluck('revenue', 'coupon_id');

        $data = $rows->map(function ($row) use ($coupons, $revenueByCoupon) {
            $coupon = $coupons->get($row->coupon_id);
            $usageRate = $coupon?->usage_limit ? round($row->times_used / $coupon->usage_limit, 4) : null;

            return [
                'coupon_id' => $row->coupon_id,
                'code' => $coupon?->code,
                'times_used' => (int) $row->times_used,
                'unique_customers' => (int) $row->customers,
                'discount_given' => number_format((float) $row->discount_given, 2, '.', ''),
                'revenue_after_discount' => number_format((float) ($revenueByCoupon[$row->coupon_id] ?? 0), 2, '.', ''),
                'usage_limit' => $coupon?->usage_limit,
                'usage_rate' => $usageRate,
            ];
        })->sortByDesc('times_used')->values();

        $perPage = min((int) ($filters['per_page'] ?? 20), 100);
        $page = max((int) ($filters['page'] ?? 1), 1);
        $paged = $data->slice(($page - 1) * $perPage, $perPage)->values();

        return [
            'summary' => [
                'coupons_used' => $rows->count(),
                'total_times_used' => (int) $rows->sum('times_used'),
                'total_discount_given' => number_format((float) $rows->sum('discount_given'), 2, '.', ''),
            ],
            'data' => $paged->all(),
        ];
    }
}
