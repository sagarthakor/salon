<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class SalonSettingsResource extends JsonResource
{
    /**
     * A brand-new salon has zero `salon_settings` rows until the owner
     * explicitly saves this screen once — `updateOrCreate()` in
     * `SalonController::updateSettings()` is the only place a row is ever
     * created. Without these defaults, `toArray()` returned an EMPTY PHP
     * array for that salon, which `json_encode` serializes as a JSON array
     * (`[]`), not an object (`{}`) — the Flutter client's
     * `_client.get<Map<String, dynamic>>('/salon/settings')` then throws a
     * raw `TypeError` casting that array to a Map (never an `ApiException`),
     * which is exactly the real-device "Could not load settings" report.
     * Booking is opt-out, not opt-in, for a freshly onboarded salon — see
     * BOOKING_ENGINE.md, "Booking settings defaults".
     */
    private const DEFAULTS = [
        'booking_enabled' => true,
        'customer_booking_enabled' => true,
        'slot_interval_minutes' => 15,
        'min_advance_booking_minutes' => 0,
        'max_advance_booking_days' => 30,
        'booking_buffer_minutes' => 0,
        'cancellation_window_minutes' => 0,
    ];

    public function toArray(Request $request): array
    {
        $stored = $this->resource->mapWithKeys(fn ($setting) => [$setting->key => $setting->value])->all();

        return array_merge(self::DEFAULTS, $stored);
    }
}
