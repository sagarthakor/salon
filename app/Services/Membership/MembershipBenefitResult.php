<?php

namespace App\Services\Membership;

use App\Models\CustomerMembership;

final class MembershipBenefitResult
{
    public function __construct(
        public readonly ?CustomerMembership $membership,
        public readonly float $discount = 0.0,
    ) {}

    public static function none(): self
    {
        return new self(null, 0.0);
    }
}
