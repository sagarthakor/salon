<?php

namespace App\Events;

use App\Models\CustomerMembership;
use Illuminate\Foundation\Events\Dispatchable;

class MembershipActivated
{
    use Dispatchable;

    public function __construct(public readonly CustomerMembership $membership) {}
}
