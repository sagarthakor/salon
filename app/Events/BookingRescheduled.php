<?php

namespace App\Events;

use App\Models\Booking;
use Illuminate\Foundation\Events\Dispatchable;

class BookingRescheduled
{
    use Dispatchable;

    public function __construct(public readonly Booking $booking, public readonly string $previousDate, public readonly string $previousStartTime) {}
}
