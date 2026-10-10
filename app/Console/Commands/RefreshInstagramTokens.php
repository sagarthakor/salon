<?php

namespace App\Console\Commands;

use App\Models\InstagramConnection;
use App\Services\Instagram\InstagramConnectionService;
use Illuminate\Console\Command;

/**
 * `php artisan instagram:refresh-tokens` — scheduled daily. Long-lived
 * Instagram tokens last 60 days and can only be refreshed while still valid,
 * so connections expiring within 20 days are refreshed ahead of time. A
 * connection Meta rejects is flagged `expired` (the owner sees "reconnect").
 */
class RefreshInstagramTokens extends Command
{
    protected $signature = 'instagram:refresh-tokens';

    protected $description = 'Refreshes Instagram access tokens that are close to expiring.';

    public function handle(InstagramConnectionService $service): int
    {
        $refreshed = $failed = 0;
        InstagramConnection::withoutGlobalScope('tenant')
            ->where('status', InstagramConnection::STATUS_ACTIVE)
            ->where('token_expires_at', '<=', now()->addDays(20))
            ->where('token_expires_at', '>', now())
            ->each(function (InstagramConnection $connection) use ($service, &$refreshed, &$failed): void {
                $service->refresh($connection) ? $refreshed++ : $failed++;
            });
        // Already past expiry: cannot be refreshed any more.
        InstagramConnection::withoutGlobalScope('tenant')
            ->where('status', InstagramConnection::STATUS_ACTIVE)
            ->where('token_expires_at', '<=', now())
            ->each(fn (InstagramConnection $c) => $service->markExpired($c, 'The Instagram token expired. Please reconnect your account.'));

        $this->info("refreshed: {$refreshed}");
        $this->info("not_refreshed: {$failed}");

        return self::SUCCESS;
    }
}
