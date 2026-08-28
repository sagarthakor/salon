<?php

namespace App\Services\Pricing;

final class LoyaltyRedemptionResult
{
    public function __construct(
        public readonly int $pointsRedeemed,
        public readonly float $discount,
        public readonly ?string $message = null,
    ) {}

    public static function none(): self
    {
        return new self(0, 0.0);
    }
}
