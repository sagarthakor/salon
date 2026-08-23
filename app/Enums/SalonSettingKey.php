<?php

namespace App\Enums;

enum SalonSettingKey: string
{
    case BOOKING_ENABLED = 'booking_enabled';
    case CUSTOMER_BOOKING_ENABLED = 'customer_booking_enabled';
    case DEFAULT_TIMEZONE = 'default_timezone';
}
