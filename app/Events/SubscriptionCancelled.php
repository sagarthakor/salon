<?php

namespace App\Events;

use App\Models\Subscription;
use Illuminate\Foundation\Events\Dispatchable;

/**
 * Fired when a subscription actually ends at cancel_at_period_end (not when
 * the owner merely requests cancellation — see SubscriptionService::cancel()
 * vs. the lifecycle processor).
 */
class SubscriptionCancelled
{
    use Dispatchable;

    public function __construct(public readonly Subscription $subscription) {}
}
