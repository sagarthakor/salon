<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class BookingItem extends Model
{
    use BelongsToTenant;

    protected $fillable = [
        'booking_id', 'service_id', 'staff_id', 'service_name', 'service_price',
        'service_duration_minutes', 'quantity', 'start_time', 'end_time', 'subtotal',
    ];

    protected function casts(): array
    {
        return ['service_price' => 'decimal:2', 'subtotal' => 'decimal:2'];
    }

    public function booking(): BelongsTo
    {
        return $this->belongsTo(Booking::class);
    }

    public function service(): BelongsTo
    {
        return $this->belongsTo(Service::class);
    }

    public function staff(): BelongsTo
    {
        return $this->belongsTo(Staff::class);
    }
}
