<?php

namespace App\Enums;

/**
 * See SAAS_BILLING_ARCHITECTURE.md for the full state machine. Only
 * `SubscriptionService` (never a controller taking a client-supplied
 * `status`) is allowed to transition a subscription between these.
 */
enum SubscriptionStatus: string
{
    case TRIALING = 'trialing';
    case ACTIVE = 'active';
    case PAST_DUE = 'past_due';
    case GRACE_PERIOD = 'grace_period';
    case CANCELLED = 'cancelled';
    case EXPIRED = 'expired';

    /**
     * Statuses under which normal business-feature access (bookings, staff,
     * customers, services, …) is allowed. Billing/subscription endpoints
     * themselves are always reachable regardless of status — see
     * `EnsureActiveSubscription`.
     */
    public static function accessAllowed(): array
    {
        return [self::TRIALING, self::ACTIVE, self::PAST_DUE, self::GRACE_PERIOD];
    }
}
