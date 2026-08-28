<?php

namespace App\Services\Pricing;

/**
 * The complete, server-computed result of pricing a set of services —
 * returned by both the read-only preview endpoint and (via
 * `BookingPricingService::reserve()`) actual booking creation. Every field
 * here is a plain scalar so it serializes identically for the preview
 * response and the booking snapshot. See
 * LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md, "Pricing breakdown".
 */
final class PricingBreakdown
{
    /**
     * @param  list<string>  $messages  human-readable, non-fatal notes (e.g. "Coupon WELCOME10 applied", "Only 200 of the requested 500 points could be redeemed")
     */
    public function __construct(
        public readonly float $subtotal,
        public readonly ?string $couponId,
        public readonly ?string $couponCode,
        public readonly float $couponDiscount,
        public readonly ?string $customerMembershipId,
        public readonly float $membershipDiscount,
        public readonly int $loyaltyPointsRedeemed,
        public readonly float $loyaltyDiscount,
        public readonly float $tax,
        public readonly float $total,
        public readonly array $messages = [],
    ) {}

    public function toArray(): array
    {
        return [
            'subtotal' => round($this->subtotal, 2),
            'coupon_code' => $this->couponCode,
            'coupon_discount' => round($this->couponDiscount, 2),
            'membership_discount' => round($this->membershipDiscount, 2),
            'loyalty_points_redeemed' => $this->loyaltyPointsRedeemed,
            'loyalty_discount' => round($this->loyaltyDiscount, 2),
            'discount' => round($this->couponDiscount + $this->membershipDiscount + $this->loyaltyDiscount, 2),
            'tax' => round($this->tax, 2),
            'total' => round($this->total, 2),
            'messages' => $this->messages,
        ];
    }
}
