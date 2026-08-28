<?php

namespace App\Services\Pricing;

use App\Enums\BookingStatus;
use App\Enums\CouponDiscountType;
use App\Models\Booking;
use App\Models\Coupon;
use App\Models\CouponUsage;
use App\Models\Customer;
use App\Models\Service;
use App\Models\Tenant;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;

/**
 * All coupon validation and (atomic, race-safe) usage recording. Every
 * check here runs server-side — a coupon's validity is never decided by
 * anything Flutter sends beyond the code itself. See "Coupon validation" in
 * LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md.
 */
class CouponService
{
    public function findByCode(Tenant $tenant, string $code): ?Coupon
    {
        return Coupon::query()->where('tenant_id', $tenant->id)->where('code', Coupon::normalizeCode($code))->first();
    }

    /**
     * Pure read — safe to call from the price-preview endpoint. Does not
     * lock or mutate anything; `reserve()` re-validates under a lock right
     * before actually consuming a usage slot, so a coupon that stops being
     * valid between preview and booking creation is still caught.
     *
     * `$forUpdate` must be true only when called from `reserve()`, which
     * already holds a row lock on `$coupon` inside the caller's
     * transaction: it upgrades the per-customer-usage-count and
     * first-booking-only checks below from plain reads to locking reads.
     * Without this, two simultaneous bookings from the *same* customer
     * against a `usage_limit_per_customer`-1 coupon would serialize on the
     * coupon-row lock (so the second waits for the first to commit) but —
     * under MySQL's default REPEATABLE READ isolation — could still read
     * each other's `CouponUsage`/prior-booking state from the transaction's
     * original snapshot rather than the just-committed data, letting both
     * requests pass the check. A locking read always sees the latest
     * committed data regardless of snapshot, closing that window. See
     * "Coupon concurrency" in SECURITY_HARDENING.md.
     *
     * @param  Collection<int, Service>  $services  the services on this booking, keyed by id
     */
    public function validate(Coupon $coupon, Customer $customer, Collection $services, float $subtotal, ?string $excludeBookingId = null, bool $forUpdate = false): CouponValidationResult
    {
        if (! $coupon->is_active) {
            return CouponValidationResult::invalid('This coupon is not active.');
        }
        $now = CarbonImmutable::now();
        if ($coupon->starts_at !== null && $now->lt($coupon->starts_at)) {
            return CouponValidationResult::invalid('This coupon is not valid yet.');
        }
        if ($coupon->expires_at !== null && $now->gt($coupon->expires_at)) {
            return CouponValidationResult::invalid('This coupon has expired.');
        }
        if ($coupon->usage_limit !== null && $coupon->usage_count >= $coupon->usage_limit) {
            return CouponValidationResult::invalid('This coupon has reached its usage limit.');
        }
        if ($coupon->usage_limit_per_customer !== null) {
            $customerUsageQuery = CouponUsage::query()->where('coupon_id', $coupon->id)->where('customer_id', $customer->id);
            $customerUsageCount = $forUpdate ? $customerUsageQuery->lockForUpdate()->count() : $customerUsageQuery->count();
            if ($customerUsageCount >= $coupon->usage_limit_per_customer) {
                return CouponValidationResult::invalid('You have already used this coupon the maximum number of times.');
            }
        }
        if ($coupon->first_booking_only && $this->hasPriorBookings($customer, $excludeBookingId, $forUpdate)) {
            return CouponValidationResult::invalid('This coupon is only valid for a first booking.');
        }

        $qualifyingSubtotal = $this->qualifyingSubtotal($coupon, $services);
        if ($qualifyingSubtotal <= 0) {
            return CouponValidationResult::invalid('This coupon does not apply to the selected services.');
        }
        if ($coupon->minimum_booking_amount !== null && $subtotal < (float) $coupon->minimum_booking_amount) {
            return CouponValidationResult::invalid('This booking does not meet the coupon\'s minimum amount.');
        }

        $discount = $this->computeDiscount($coupon, $qualifyingSubtotal);
        if ($discount <= 0) {
            return CouponValidationResult::invalid('This coupon does not provide a discount for this booking.');
        }

        return CouponValidationResult::valid($coupon, $discount);
    }

    /**
     * Re-validates under a row lock and, only if still valid, atomically
     * increments `usage_count` and records a `CouponUsage` row — the two
     * writes a real race (two simultaneous bookings against a
     * usage_limit-1 coupon) must never both succeed for. Must be called
     * from inside the caller's own DB transaction (see
     * BookingPricingService::reserve(), which already holds one).
     */
    public function reserve(Tenant $tenant, string $couponId, Customer $customer, Collection $services, float $subtotal, Booking $booking): CouponValidationResult
    {
        $locked = Coupon::query()->where('tenant_id', $tenant->id)->whereKey($couponId)->lockForUpdate()->first();
        if ($locked === null) {
            return CouponValidationResult::invalid('This coupon no longer exists.');
        }

        // Excludes the booking currently being created from the
        // "first booking only" check — by this point in BookingService::create()
        // the booking row already exists (see "Transaction safety" in
        // LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md for why creation order
        // is booking-first, reserve-second), so without this exclusion every
        // booking would count as its own prior booking.
        $result = $this->validate($locked, $customer, $services, $subtotal, $booking->id, forUpdate: true);
        if (! $result->valid) {
            return $result;
        }

        $locked->increment('usage_count');
        CouponUsage::query()->create([
            'tenant_id' => $tenant->id,
            'coupon_id' => $locked->id,
            'customer_id' => $customer->id,
            'booking_id' => $booking->id,
            'discount_amount' => $result->discount,
            'used_at' => CarbonImmutable::now(),
        ]);

        return $result;
    }

    /**
     * @param  Collection<int, Service>  $services
     */
    private function qualifyingSubtotal(Coupon $coupon, Collection $services): float
    {
        if ($coupon->appliesToAllServices()) {
            return (float) $services->sum('price');
        }

        $allowedServiceIds = $coupon->services()->pluck('services.id')->all();
        $allowedCategoryIds = $coupon->categories()->pluck('service_categories.id')->all();

        return (float) $services
            ->filter(fn ($service) => in_array($service->id, $allowedServiceIds, true) || in_array($service->category_id, $allowedCategoryIds, true))
            ->sum('price');
    }

    private function computeDiscount(Coupon $coupon, float $qualifyingSubtotal): float
    {
        $raw = $coupon->discount_type === CouponDiscountType::PERCENTAGE
            ? $qualifyingSubtotal * ((float) $coupon->discount_value / 100)
            : (float) $coupon->discount_value;

        $capped = min($raw, $qualifyingSubtotal);
        if ($coupon->maximum_discount_amount !== null) {
            $capped = min($capped, (float) $coupon->maximum_discount_amount);
        }

        return round(max(0.0, $capped), 2);
    }

    private function hasPriorBookings(Customer $customer, ?string $excludeBookingId, bool $forUpdate = false): bool
    {
        $blocking = array_map(fn (BookingStatus $s) => $s->value, BookingStatus::blockingBooking());
        $query = Booking::query()->where('customer_id', $customer->id)->whereIn('status', $blocking);
        if ($excludeBookingId !== null) {
            $query->whereKeyNot($excludeBookingId);
        }

        // `exists()` cannot be combined with `lockForUpdate()` reliably
        // across drivers (the EXISTS(...) wrapping isn't guaranteed to place
        // the locking clause inside the subquery), so the locked path counts
        // instead — equivalent for a boolean check, and unambiguously locks
        // the matched rows.
        return $forUpdate ? $query->lockForUpdate()->count() > 0 : $query->exists();
    }
}
