<?php

namespace App\Models;

use App\Enums\BookingStatus;
use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class BookingStatusHistory extends Model
{
    use BelongsToTenant;

    protected $fillable = ['booking_id', 'from_status', 'to_status', 'changed_by', 'reason'];

    protected function casts(): array
    {
        return ['from_status' => BookingStatus::class, 'to_status' => BookingStatus::class];
    }

    public function booking(): BelongsTo
    {
        return $this->belongsTo(Booking::class);
    }

    public function changedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'changed_by');
    }
}
