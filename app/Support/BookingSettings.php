<?php

namespace App\Support;

use App\Enums\SalonSettingKey;
use App\Models\Salon;

class BookingSettings
{
    public function __construct(private readonly Salon $salon) {}

    public function slotIntervalMinutes(): int
    {
        return $this->int(SalonSettingKey::SLOT_INTERVAL_MINUTES, 15);
    }

    public function minAdvanceMinutes(): int
    {
        return $this->int(SalonSettingKey::MIN_ADVANCE_BOOKING_MINUTES, 0);
    }

    public function maxAdvanceDays(): int
    {
        return $this->int(SalonSettingKey::MAX_ADVANCE_BOOKING_DAYS, 30);
    }

    public function bufferMinutes(): int
    {
        return $this->int(SalonSettingKey::BOOKING_BUFFER_MINUTES, 0);
    }

    public function cancellationWindowMinutes(): int
    {
        return $this->int(SalonSettingKey::CANCELLATION_WINDOW_MINUTES, 0);
    }

    private function int(SalonSettingKey $key, int $default): int
    {
        $setting = $this->salon->relationLoaded('settings')
            ? $this->salon->settings->firstWhere('key', $key->value)
            : $this->salon->settings()->where('key', $key->value)->first();

        return $setting?->value !== null ? (int) $setting->value : $default;
    }
}
