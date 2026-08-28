<?php

namespace App\Services\Loyalty;

use App\Enums\LoyaltyTransactionType;
use App\Models\Booking;
use App\Models\Customer;
use App\Models\LoyaltyAccount;
use App\Models\LoyaltyTransaction;
use App\Models\Salon;
use App\Models\Tenant;
use App\Models\User;
use App\Services\Pricing\LoyaltyRedemptionResult;
use App\Support\LoyaltySettings;
use Carbon\CarbonImmutable;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Every balance-changing operation goes through here and creates exactly
 * one `LoyaltyTransaction` row alongside the `LoyaltyAccount.balance`
 * update — never mutated independently. See "Loyalty ledger" in
 * LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md.
 */
class LoyaltyService
{
    public function accountFor(Tenant $tenant, Customer $customer): LoyaltyAccount
    {
        return LoyaltyAccount::query()->firstOrCreate(
            ['tenant_id' => $tenant->id, 'customer_id' => $customer->id],
            ['balance' => 0, 'lifetime_earned' => 0, 'lifetime_redeemed' => 0],
        );
    }

    /**
     * Pure read — safe for the price-preview endpoint. `reserve()`-style
     * re-validation happens in `redeem()` under a row lock.
     */
    public function previewRedemption(Salon $salon, Tenant $tenant, Customer $customer, int $requestedPoints, float $subtotal): LoyaltyRedemptionResult
    {
        $settings = new LoyaltySettings($salon);
        if (! $settings->isEnabled() || $requestedPoints <= 0) {
            return LoyaltyRedemptionResult::none();
        }

        $account = $this->accountFor($tenant, $customer);
        [$allowed, $discount] = $this->allowedRedemption($settings, $account->balance, $requestedPoints, $subtotal);
        if ($allowed <= 0) {
            return LoyaltyRedemptionResult::none();
        }

        $message = $allowed < $requestedPoints
            ? "Only {$allowed} of the requested {$requestedPoints} points could be redeemed."
            : null;

        return new LoyaltyRedemptionResult($allowed, $discount, $message);
    }

    /**
     * Re-validates under a row lock and, only if any redemption is still
     * possible, deducts the balance and records a REDEEM transaction
     * against [$booking]. Must run inside the caller's own transaction —
     * see BookingPricingService::reserve().
     */
    public function redeem(Salon $salon, Tenant $tenant, Customer $customer, int $requestedPoints, float $subtotal, Booking $booking): LoyaltyRedemptionResult
    {
        $settings = new LoyaltySettings($salon);
        if (! $settings->isEnabled() || $requestedPoints <= 0) {
            return LoyaltyRedemptionResult::none();
        }

        $account = LoyaltyAccount::query()
            ->where('tenant_id', $tenant->id)->where('customer_id', $customer->id)
            ->lockForUpdate()->first() ?? $this->accountFor($tenant, $customer);

        [$allowed, $discount] = $this->allowedRedemption($settings, $account->balance, $requestedPoints, $subtotal);
        if ($allowed <= 0) {
            return LoyaltyRedemptionResult::none();
        }

        $newBalance = $account->balance - $allowed;
        $account->update(['balance' => $newBalance, 'lifetime_redeemed' => $account->lifetime_redeemed + $allowed]);
        LoyaltyTransaction::query()->create([
            'tenant_id' => $tenant->id,
            'customer_id' => $customer->id,
            'loyalty_account_id' => $account->id,
            'booking_id' => $booking->id,
            'type' => LoyaltyTransactionType::REDEEM,
            'points' => -$allowed,
            'balance_after' => $newBalance,
            'description' => "Redeemed against booking {$booking->id}",
        ]);

        return new LoyaltyRedemptionResult($allowed, $discount);
    }

    /**
     * Called only when a booking reaches COMPLETED (never on mere
     * creation — see "Loyalty earning timing"). Idempotent: the
     * `unique(booking_id, type)` constraint on `loyalty_transactions`
     * guarantees a booking can never earn twice, even under a duplicated
     * event/retry — this method treats that constraint violation as "already
     * earned," not an error.
     */
    public function earnForBooking(Booking $booking): ?LoyaltyTransaction
    {
        $salon = $booking->branch->salon;
        $settings = new LoyaltySettings($salon);
        if (! $settings->isEnabled()) {
            return null;
        }

        $total = (float) $booking->total;
        if ($total < $settings->minBookingAmountForEarning()) {
            return null;
        }
        $earnRate = $settings->earnRateAmount();
        if ($earnRate <= 0) {
            return null;
        }
        $points = (int) floor($total / $earnRate);
        if ($points <= 0) {
            return null;
        }

        if (LoyaltyTransaction::query()->where('booking_id', $booking->id)->where('type', LoyaltyTransactionType::EARN->value)->exists()) {
            return null;
        }

        try {
            return DB::transaction(function () use ($booking, $points): LoyaltyTransaction {
                $customer = $booking->customer;
                $account = LoyaltyAccount::query()
                    ->where('tenant_id', $booking->tenant_id)->where('customer_id', $customer->id)
                    ->lockForUpdate()->first() ?? $this->accountFor($booking->tenant, $customer);

                $newBalance = $account->balance + $points;
                $account->update(['balance' => $newBalance, 'lifetime_earned' => $account->lifetime_earned + $points]);

                return LoyaltyTransaction::query()->create([
                    'tenant_id' => $booking->tenant_id,
                    'customer_id' => $customer->id,
                    'loyalty_account_id' => $account->id,
                    'booking_id' => $booking->id,
                    'type' => LoyaltyTransactionType::EARN,
                    'points' => $points,
                    'balance_after' => $newBalance,
                    'description' => "Earned from booking {$booking->id}",
                ]);
            });
        } catch (QueryException $e) {
            // A concurrent process won the race and already inserted the EARN
            // row for this booking_id — the unique constraint is the final
            // authority, this is not a real error.
            if ($this->isUniqueConstraintViolation($e)) {
                return null;
            }
            throw $e;
        }
    }

    /**
     * Owner-authorized manual correction — always requires a reason, always
     * produces an ADJUSTMENT row. Never lets the balance go negative.
     */
    public function adjust(Tenant $tenant, Customer $customer, int $delta, string $reason, ?User $actor): LoyaltyTransaction
    {
        if ($delta === 0) {
            throw new RuntimeException('An adjustment must be non-zero.');
        }

        return DB::transaction(function () use ($tenant, $customer, $delta, $reason, $actor): LoyaltyTransaction {
            $account = LoyaltyAccount::query()
                ->where('tenant_id', $tenant->id)->where('customer_id', $customer->id)
                ->lockForUpdate()->first() ?? $this->accountFor($tenant, $customer);

            $newBalance = $account->balance + $delta;
            if ($newBalance < 0) {
                throw new RuntimeException('This adjustment would take the balance below zero.');
            }

            $account->update([
                'balance' => $newBalance,
                'lifetime_earned' => $delta > 0 ? $account->lifetime_earned + $delta : $account->lifetime_earned,
                'lifetime_redeemed' => $delta < 0 ? $account->lifetime_redeemed + abs($delta) : $account->lifetime_redeemed,
            ]);

            return LoyaltyTransaction::query()->create([
                'tenant_id' => $tenant->id,
                'customer_id' => $customer->id,
                'loyalty_account_id' => $account->id,
                'type' => LoyaltyTransactionType::ADJUSTMENT,
                'points' => $delta,
                'balance_after' => $newBalance,
                'description' => $reason,
                'reference_type' => $actor !== null ? 'user' : null,
                'reference_id' => $actor?->id,
            ]);
        });
    }

    /**
     * Scheduler entry point (see ExpireLoyaltyPoints command). Zeroes out
     * every account whose points were last touched before the tenant's
     * configured expiry window — simple full-balance expiry per account
     * rather than FIFO-per-earning-batch, which this phase's ledger schema
     * does not attempt to model. Every expiry produces an EXPIRE
     * transaction; points are never silently deleted. Idempotent by
     * construction: an account with a zero balance is skipped, so running
     * this twice in a row is a no-op the second time.
     *
     * @return array{accounts_processed: int, points_expired: int}
     */
    public function expireDuePoints(?CarbonImmutable $now = null): array
    {
        $now = $now ?? CarbonImmutable::now();
        $summary = ['accounts_processed' => 0, 'points_expired' => 0];

        LoyaltyAccount::query()->withoutGlobalScope('tenant')
            ->where('balance', '>', 0)
            ->chunkById(100, function ($accounts) use ($now, &$summary): void {
                foreach ($accounts as $account) {
                    $salon = Salon::query()->withoutGlobalScope('tenant')->where('tenant_id', $account->tenant_id)->first();
                    if ($salon === null) {
                        continue;
                    }
                    $settings = new LoyaltySettings($salon);
                    $expiryDays = $settings->pointsExpiryDays();
                    if ($expiryDays <= 0) {
                        continue;
                    }

                    $lastActivity = LoyaltyTransaction::query()->where('loyalty_account_id', $account->id)->max('created_at');
                    $cutoff = $lastActivity !== null ? CarbonImmutable::parse($lastActivity)->addDays($expiryDays) : null;
                    if ($cutoff === null || $now->lt($cutoff)) {
                        continue;
                    }

                    DB::transaction(function () use ($account, &$summary): void {
                        $locked = LoyaltyAccount::query()->withoutGlobalScope('tenant')->whereKey($account->id)->lockForUpdate()->first();
                        if ($locked === null || $locked->balance <= 0) {
                            return;
                        }
                        $expired = $locked->balance;
                        $locked->update(['balance' => 0]);
                        LoyaltyTransaction::query()->create([
                            'tenant_id' => $locked->tenant_id,
                            'customer_id' => $locked->customer_id,
                            'loyalty_account_id' => $locked->id,
                            'type' => LoyaltyTransactionType::EXPIRE,
                            'points' => -$expired,
                            'balance_after' => 0,
                            'description' => 'Points expired due to inactivity',
                        ]);
                        $summary['accounts_processed']++;
                        $summary['points_expired'] += $expired;
                    });
                }
            });

        return $summary;
    }

    /**
     * @return array{0: int, 1: float} [allowedPoints, discountAmount]
     */
    private function allowedRedemption(LoyaltySettings $settings, int $availableBalance, int $requestedPoints, float $subtotal): array
    {
        $redemptionValue = $settings->redemptionValue();
        if ($redemptionValue <= 0) {
            return [0, 0.0];
        }
        $maxAmount = $subtotal * ($settings->maxRedemptionPercent() / 100);
        $maxPointsByAmount = (int) floor($maxAmount / $redemptionValue);

        $allowed = max(0, min($requestedPoints, $availableBalance, $maxPointsByAmount));

        return [$allowed, round($allowed * $redemptionValue, 2)];
    }

    private function isUniqueConstraintViolation(QueryException $e): bool
    {
        return str_contains(strtolower($e->getMessage()), 'unique');
    }
}
