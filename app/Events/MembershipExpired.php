<?php

namespace App\Events;

use App\Models\CustomerMembership;
use Illuminate\Foundation\Events\Dispatchable;

class MembershipExpired
{
    use Dispatchable;

    public function __construct(public readonly CustomerMembership $membership) {}
}
