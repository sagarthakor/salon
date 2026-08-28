<?php

namespace App\Console\Commands;

use App\Services\Loyalty\LoyaltyService;
use Illuminate\Console\Command;

/**
 * `php artisan loyalty:expire-points` — scheduled daily (see
 * routes/console.php). Only tenants with `LOYALTY_POINTS_EXPIRY_DAYS` set
 * (> 0) are affected; see LoyaltyService::expireDuePoints() for the
 * idempotent, per-account expiry sweep and why every expiry produces an
 * EXPIRE ledger transaction rather than silently zeroing the balance.
 */
class ExpireLoyaltyPoints extends Command
{
    protected $signature = 'loyalty:expire-points';

    protected $description = 'Expires loyalty point balances that have been inactive past the tenant\'s configured expiry window.';

    public function handle(LoyaltyService $loyalty): int
    {
        $summary = $loyalty->expireDuePoints();
        $this->info(sprintf('accounts_processed: %d', $summary['accounts_processed']));
        $this->info(sprintf('points_expired: %d', $summary['points_expired']));

        return self::SUCCESS;
    }
}
