<?php

namespace App\Enums;

enum CustomerMembershipStatus: string
{
    case ACTIVE = 'active';
    case EXPIRED = 'expired';
    case CANCELLED = 'cancelled';
}
