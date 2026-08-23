<?php

namespace App\Enums;

enum TenantMembershipRole: string
{
    case SALON_OWNER = 'salon_owner';
    case STAFF = 'staff';
}
