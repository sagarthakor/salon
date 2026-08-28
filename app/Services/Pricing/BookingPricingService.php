<?php

namespace App\Services\Pricing;

use App\Models\Booking;
use App\Models\Customer;
use App\Models\Salon;
use App\Models\Service;
use App\Models\Tenant;
use App\Services\Booking\Exceptions\BookingUnavailableException;
use App\Services\Loyalty\LoyaltyService;
use App\Services\Membership\MembershipBenefitResult;
use App\Services\Membership\MembershipService;
use Illuminate\Support\Collection;

/**
 * The single place discount stacking is decided — never duplicated in a
 * controller. See "Discount stacking" in
 * LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md for the exact rule:
 *
 *   - At most ONE primary discount applies: an explicitly-supplied, valid
 *     coupon always wins; otherwise the customer's active membership
 *     benefit (if any) applies automatically. Never both.
 *   - Loyalty point redemption may additionally apply on top of whichever
 *     primary discount (if any) was granted.
 *
 * `preview()` is pure and never throws — used by the read-only
 * price-preview endpoint and internally to compute the numbers `reserve()`
 * then commits. `reserve()` additionally locks/re-validates/records usage
 * and must run inside the caller's own DB transaction (see
 * BookingService::create()) so a lost race rolls back the whole booking,
 * never leaving an orphaned discount record.
 */
class BookingPricingService
{
    public function __construct(
        private readonly CouponService $coupons,
        private readonly MembershipService $memberships,
        private readonly LoyaltyService $loyalty,
    ) {}

    /**
     * @param  Collection<int, Service>  $services
     */
    public function preview(Tenant $tenant, Salon $salon, Customer $customer, Collection $services, ?string $couponCode, ?int $loyaltyPointsToRedeem): PricingBreakdown
    {
        $subtotal = (float) $services->sum('price');
        $messages = [];

        $couponResult = null;
        if ($couponCode !== null) {
            $coupon = $this->coupons->findByCode($tenant, $couponCode);
            $couponResult = $coupon !== null
                ? $this->coupons->validate($coupon, $customer, $services, $subtotal)
                : CouponValidationResult::invalid('This coupon code was not found.');
            if (! $couponResult->valid) {
                $messages[] = $couponResult->message;
            }
        }

        $useCoupon = $couponResult !== null && $couponResult->valid;
        $membershipBenefit = $useCoupon
            ? MembershipBenefitResult::none()
            : $this->memberships->benefitFor($this->memberships->activeMembershipFor($tenant, $customer), $services);

        if ($useCoupon) {
            $messages[] = "Coupon {$couponResult->coupon->code} applied.";
        } elseif ($membershipBenefit->discount > 0) {
            $messages[] = 'Membership benefit applied.';
        }

        $afterPrimaryDiscount = $subtotal - ($useCoupon ? $couponResult->discount : $membershipBenefit->discount);

        $loyaltyResult = ($loyaltyPointsToRedeem ?? 0) > 0
            ? $this->loyalty->previewRedemption($salon, $tenant, $customer, $loyaltyPointsToRedeem, max(0.0, $afterPrimaryDiscount))
            : LoyaltyRedemptionResult::none();
        if ($loyaltyResult->message !== null) {
            $messages[] = $loyaltyResult->message;
        }

        $total = max(0.0, $afterPrimaryDiscount - $loyaltyResult->discount);

        return new PricingBreakdown(
            subtotal: $subtotal,
            couponId: $useCoupon ? $couponResult->coupon->id : null,
            couponCode: $useCoupon ? $couponResult->coupon->code : null,
            couponDiscount: $useCoupon ? $couponResult->discount : 0.0,
            customerMembershipId: $membershipBenefit->membership?->id,
            membershipDiscount: $membershipBenefit->discount,
            loyaltyPointsRedeemed: $loyaltyResult->pointsRedeemed,
            loyaltyDiscount: $loyaltyResult->discount,
            tax: 0.0,
            total: $total,
            messages: array_values(array_filter($messages)),
        );
    }

    /**
     * @param  Collection<int, Service>  $services
     *
     * @throws BookingUnavailableException if an explicitly-supplied coupon code is no longer valid at creation time
     */
    public function reserve(Tenant $tenant, Salon $salon, Customer $customer, Collection $services, ?string $couponCode, ?int $loyaltyPointsToRedeem, Booking $booking): PricingBreakdown
    {
        $subtotal = (float) $services->sum('price');

        $couponResult = null;
        if ($couponCode !== null) {
            $coupon = $this->coupons->findByCode($tenant, $couponCode);
            if ($coupon === null) {
                throw new BookingUnavailableException('This coupon code was not found.');
            }
            $couponResult = $this->coupons->reserve($tenant, $coupon->id, $customer, $services, $subtotal, $booking);
            if (! $couponResult->valid) {
                throw new BookingUnavailableException($couponResult->message ?? 'This coupon can no longer be applied.');
            }
        }

        $useCoupon = $couponResult !== null && $couponResult->valid;
        $membershipBenefit = $useCoupon
            ? MembershipBenefitResult::none()
            : $this->memberships->benefitFor($this->memberships->activeMembershipFor($tenant, $customer), $services);

        $afterPrimaryDiscount = $subtotal - ($useCoupon ? $couponResult->discount : $membershipBenefit->discount);

        $loyaltyResult = ($loyaltyPointsToRedeem ?? 0) > 0
            ? $this->loyalty->redeem($salon, $tenant, $customer, $loyaltyPointsToRedeem, max(0.0, $afterPrimaryDiscount), $booking)
            : LoyaltyRedemptionResult::none();

        $total = max(0.0, $afterPrimaryDiscount - $loyaltyResult->discount);

        return new PricingBreakdown(
            subtotal: $subtotal,
            couponId: $useCoupon ? $couponResult->coupon->id : null,
            couponCode: $useCoupon ? $couponResult->coupon->code : null,
            couponDiscount: $useCoupon ? $couponResult->discount : 0.0,
            customerMembershipId: $membershipBenefit->membership?->id,
            membershipDiscount: $membershipBenefit->discount,
            loyaltyPointsRedeemed: $loyaltyResult->pointsRedeemed,
            loyaltyDiscount: $loyaltyResult->discount,
            tax: 0.0,
            total: $total,
        );
    }
}
