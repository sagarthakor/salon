<?php

namespace App\Enums;

/**
 * `points` on a LoyaltyTransaction is always the signed delta actually
 * applied to the account balance — EARN/ADJUSTMENT(+) are positive,
 * REDEEM/EXPIRE/ADJUSTMENT(-) are negative. See LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md.
 */
enum LoyaltyTransactionType: string
{
    case EARN = 'earn';
    case REDEEM = 'redeem';
    case ADJUSTMENT = 'adjustment';
    case EXPIRE = 'expire';
    case REVERSAL = 'reversal';
}
