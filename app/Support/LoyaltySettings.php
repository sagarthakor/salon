<?php

namespace App\Support;

use App\Enums\SalonSettingKey;
use App\Models\Salon;

/**
 * Reads the tenant's loyalty configuration from the same `salon_settings`
 * key-value store `BookingSettings` already reads booking configuration
 * from — no separate loyalty_settings table. Every value has a safe
 * default so a tenant that has never touched loyalty settings simply has
 * the program disabled (see `isEnabled()`), never a crash or a fabricated
 * rate. See LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md, "Loyalty settings".
 */
class LoyaltySettings
{
    public function __construct(private readonly Salon $salon) {}

    public function isEnabled(): bool
    {
        return (bool) $this->raw(SalonSettingKey::LOYALTY_ENABLED, false);
    }

    /** Currency amount spent per 1 point earned. */
    public function earnRateAmount(): float
    {
        return (float) $this->raw(SalonSettingKey::LOYALTY_EARN_RATE_AMOUNT, 100.0);
    }

    public function minBookingAmountForEarning(): float
    {
        return (float) $this->raw(SalonSettingKey::LOYALTY_MIN_BOOKING_AMOUNT_FOR_EARNING, 0.0);
    }

    /** 0 = points never expire. */
    public function pointsExpiryDays(): int
    {
        return (int) $this->raw(SalonSettingKey::LOYALTY_POINTS_EXPIRY_DAYS, 0);
    }

    /** Currency value of 1 point when redeemed. */
    public function redemptionValue(): float
    {
        return (float) $this->raw(SalonSettingKey::LOYALTY_REDEMPTION_VALUE, 1.0);
    }

    public function maxRedemptionPercent(): int
    {
        return max(0, min(100, (int) $this->raw(SalonSettingKey::LOYALTY_MAX_REDEMPTION_PERCENT, 50)));
    }

    private function raw(SalonSettingKey $key, mixed $default): mixed
    {
        $setting = $this->salon->relationLoaded('settings')
            ? $this->salon->settings->firstWhere('key', $key->value)
            : $this->salon->settings()->where('key', $key->value)->first();

        return $setting?->value ?? $default;
    }
}
