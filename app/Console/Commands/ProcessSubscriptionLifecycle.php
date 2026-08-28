<?php

namespace App\Console\Commands;

use App\Services\Billing\SubscriptionService;
use Illuminate\Console\Command;

/**
 * `php artisan subscriptions:process-lifecycle` — scheduled daily (see
 * routes/console.php). Only ever transitions subscriptions based on the
 * passage of time (trial/period/grace expiry); never initiates a charge —
 * payment collection always goes through the gateway-driven checkout flow,
 * never blindly from this command. See SAAS_BILLING_ARCHITECTURE.md,
 * "Scheduler".
 */
class ProcessSubscriptionLifecycle extends Command
{
    protected $signature = 'subscriptions:process-lifecycle';

    protected $description = 'Transitions subscriptions whose trial, billing period, or grace window has elapsed.';

    public function handle(SubscriptionService $subscriptions): int
    {
        $summary = $subscriptions->processLifecycle();

        foreach ($summary as $kind => $count) {
            $this->info(sprintf('%s: %d', $kind, $count));
        }

        return self::SUCCESS;
    }
}
