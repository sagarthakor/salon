<?php

namespace App\Services\Reports;

use App\Enums\LoyaltyTransactionType;
use App\Http\Resources\LoyaltyTransactionResource;
use App\Models\LoyaltyAccount;
use App\Models\LoyaltyTransaction;
use App\Models\Tenant;
use App\Support\DateRange;

/**
 * Every figure is read from the `loyalty_transactions` ledger — never
 * inferred from the current `loyalty_accounts.balance` alone, since a
 * balance is a snapshot, not a history. `points` is a signed delta (see
 * LoyaltyTransaction); EARN is always positive, REDEEM/EXPIRE always
 * negative, ADJUSTMENT/REVERSAL either — earned/redeemed/expired are
 * reported as positive magnitudes, adjustment keeps its sign.
 */
class LoyaltyReport
{
    /**
     * @param  array<string, mixed>  $filters
     */
    public function generate(Tenant $tenant, DateRange $range, array $filters): array
    {
        $base = LoyaltyTransaction::query()->whereBetween('created_at', [$range->start, $range->end]);
        if (! empty($filters['customer_id'])) {
            $base->where('customer_id', $filters['customer_id']);
        }

        $sums = (clone $base)->toBase()->selectRaw('type, COALESCE(SUM(points), 0) as total')->groupBy('type')->pluck('total', 'type');

        $earned = (float) ($sums[LoyaltyTransactionType::EARN->value] ?? 0);
        $redeemed = abs((float) ($sums[LoyaltyTransactionType::REDEEM->value] ?? 0));
        $expired = abs((float) ($sums[LoyaltyTransactionType::EXPIRE->value] ?? 0));
        $adjusted = (float) ($sums[LoyaltyTransactionType::ADJUSTMENT->value] ?? 0) + (float) ($sums[LoyaltyTransactionType::REVERSAL->value] ?? 0);

        $outstanding = empty($filters['customer_id'])
            ? (int) LoyaltyAccount::query()->sum('balance')
            : (int) (LoyaltyAccount::query()->where('customer_id', $filters['customer_id'])->value('balance') ?? 0);

        $perPage = min((int) ($filters['per_page'] ?? 20), 100);
        $page = max((int) ($filters['page'] ?? 1), 1);
        $transactions = (clone $base)->latest()->paginate($perPage, ['*'], 'page', $page);

        return [
            'summary' => [
                'points_earned' => (int) $earned,
                'points_redeemed' => (int) $redeemed,
                'points_expired' => (int) $expired,
                'points_adjusted' => (int) $adjusted,
                'outstanding_points' => $outstanding,
            ],
            'data' => LoyaltyTransactionResource::collection($transactions)->resolve(),
        ];
    }
}
