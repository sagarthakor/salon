<?php

namespace App\Enums;

enum UserRole: string
{
    case SUPER_ADMIN = 'super_admin';
    case SALON_OWNER = 'salon_owner';
    case STAFF = 'staff';
    case CUSTOMER = 'customer';
}
