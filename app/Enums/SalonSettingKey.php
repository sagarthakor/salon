<?php

namespace App\Enums;

enum SalonSettingKey: string
{
    case BOOKING_ENABLED = 'booking_enabled';
    case CUSTOMER_BOOKING_ENABLED = 'customer_booking_enabled';
    case DEFAULT_TIMEZONE = 'default_timezone';
    case SLOT_INTERVAL_MINUTES = 'slot_interval_minutes';
    case MIN_ADVANCE_BOOKING_MINUTES = 'min_advance_booking_minutes';
    case MAX_ADVANCE_BOOKING_DAYS = 'max_advance_booking_days';
    case BOOKING_BUFFER_MINUTES = 'booking_buffer_minutes';
    case CANCELLATION_WINDOW_MINUTES = 'cancellation_window_minutes';

    // Phase 12 — loyalty program settings, per tenant. See
    // LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md, "Loyalty settings".
    case LOYALTY_ENABLED = 'loyalty_enabled';
    /** Currency amount spent per 1 point earned, e.g. 100 => ₹100 spent = 1 point. */
    case LOYALTY_EARN_RATE_AMOUNT = 'loyalty_earn_rate_amount';
    /** A completed booking's subtotal must be at least this much to earn any points. */
    case LOYALTY_MIN_BOOKING_AMOUNT_FOR_EARNING = 'loyalty_min_booking_amount_for_earning';
    /** 0 = points never expire. */
    case LOYALTY_POINTS_EXPIRY_DAYS = 'loyalty_points_expiry_days';
    /** Currency value of 1 point when redeemed, e.g. 1 => 1 point = ₹1. */
    case LOYALTY_REDEMPTION_VALUE = 'loyalty_redemption_value';
    /** Maximum percentage (0–100) of a booking's subtotal payable via loyalty points. */
    case LOYALTY_MAX_REDEMPTION_PERCENT = 'loyalty_max_redemption_percent';
}
