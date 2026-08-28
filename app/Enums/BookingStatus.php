<?php

namespace App\Enums;

enum BookingStatus: string
{
    case PENDING = 'pending';
    case CONFIRMED = 'confirmed';
    case CHECKED_IN = 'checked_in';
    case IN_SERVICE = 'in_service';
    case COMPLETED = 'completed';
    case CANCELLED = 'cancelled';
    case NO_SHOW = 'no_show';

    public function canTransitionTo(self $target): bool
    {
        return match ($this) {
            self::PENDING => in_array($target, [self::CONFIRMED, self::CANCELLED], true),
            self::CONFIRMED => in_array($target, [self::CHECKED_IN, self::CANCELLED, self::NO_SHOW], true),
            self::CHECKED_IN => in_array($target, [self::IN_SERVICE, self::CANCELLED], true),
            self::IN_SERVICE => in_array($target, [self::COMPLETED, self::CANCELLED], true),
            self::COMPLETED, self::CANCELLED, self::NO_SHOW => false,
        };
    }

    public function isTerminal(): bool
    {
        return in_array($this, [self::COMPLETED, self::CANCELLED, self::NO_SHOW], true);
    }

    /**
     * @return list<self>
     */
    public static function blockingBooking(): array
    {
        return [self::PENDING, self::CONFIRMED, self::CHECKED_IN, self::IN_SERVICE, self::COMPLETED];
    }
}
