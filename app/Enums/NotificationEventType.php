<?php

namespace App\Enums;

/**
 * Every business event the notification system knows how to render and
 * route. Adding a new notification always starts here — see
 * NOTIFICATION_ARCHITECTURE.md.
 */
enum NotificationEventType: string
{
    case BOOKING_CREATED = 'booking.created';
    case BOOKING_CONFIRMED = 'booking.confirmed';
    case BOOKING_RESCHEDULED = 'booking.rescheduled';
    case BOOKING_CANCELLED = 'booking.cancelled';
    case BOOKING_CHECKED_IN = 'booking.checked_in';
    case BOOKING_STARTED = 'booking.started';
    case BOOKING_COMPLETED = 'booking.completed';
    case BOOKING_NO_SHOW = 'booking.no_show';
    case BOOKING_REMINDER = 'booking.reminder';
    case PAYMENT_SUCCEEDED = 'payment.succeeded';
    case PAYMENT_FAILED = 'payment.failed';
    case SUBSCRIPTION_ACTIVATED = 'subscription.activated';
    case SUBSCRIPTION_PAST_DUE = 'subscription.past_due';
    case SUBSCRIPTION_GRACE_PERIOD = 'subscription.grace_period';
    case SUBSCRIPTION_EXPIRED = 'subscription.expired';
    case SUBSCRIPTION_CANCELLED = 'subscription.cancelled';

    // Phase 12 — coupons/membership/loyalty. See
    // LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md, "Notifications".
    case MEMBERSHIP_ACTIVATED = 'membership.activated';
    case MEMBERSHIP_EXPIRED = 'membership.expired';
    case LOYALTY_POINTS_EARNED = 'loyalty.points_earned';
}
