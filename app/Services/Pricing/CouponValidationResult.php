<?php

namespace App\Services\Pricing;

use App\Models\Coupon;

final class CouponValidationResult
{
    public function __construct(
        public readonly bool $valid,
        public readonly float $discount = 0.0,
        public readonly ?string $message = null,
        public readonly ?Coupon $coupon = null,
    ) {}

    public static function invalid(string $message): self
    {
        return new self(valid: false, message: $message);
    }

    public static function valid(Coupon $coupon, float $discount): self
    {
        return new self(valid: true, discount: $discount, coupon: $coupon);
    }
}
