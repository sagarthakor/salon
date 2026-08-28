<?php

namespace App\Enums;

enum NotificationChannel: string
{
    case IN_APP = 'in_app';
    case PUSH = 'push';
    case EMAIL = 'email';
    case WHATSAPP = 'whatsapp';
    case SMS = 'sms';

    /**
     * @return list<self>
     */
    public static function external(): array
    {
        return [self::PUSH, self::EMAIL, self::WHATSAPP, self::SMS];
    }
}
