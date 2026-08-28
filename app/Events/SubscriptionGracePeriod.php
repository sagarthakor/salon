<?php

namespace App\Events;

use App\Models\Subscription;
use Illuminate\Foundation\Events\Dispatchable;

class SubscriptionGracePeriod
{
    use Dispatchable;

    public function __construct(public readonly Subscription $subscription) {}
}
