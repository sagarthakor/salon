<?php

namespace App\Console\Commands;

use App\Services\Membership\MembershipService;
use Illuminate\Console\Command;

/**
 * `php artisan memberships:expire` — scheduled daily (see routes/console.php).
 * Idempotent: only ever moves ACTIVE memberships whose `expires_at` has
 * already passed to EXPIRED; running it twice in a row is a no-op the
 * second time. Pricing validation (MembershipService::activeMembershipFor())
 * independently re-checks `expires_at` on every booking too, so a
 * membership never grants a benefit past its expiry even if this command
 * hasn't run yet — see "Membership expiration".
 */
class ExpireCustomerMemberships extends Command
{
    protected $signature = 'memberships:expire';

    protected $description = 'Marks EXPIRED any customer membership whose expires_at has passed.';

    public function handle(MembershipService $memberships): int
    {
        $summary = $memberships->expireDueMemberships();
        $this->info(sprintf('expired: %d', $summary['expired']));

        return self::SUCCESS;
    }
}
