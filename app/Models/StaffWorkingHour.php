<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class StaffWorkingHour extends Model
{
    use BelongsToTenant;

    protected $fillable = ['staff_id', 'day_of_week', 'is_working', 'start_time', 'end_time'];

    protected function casts(): array
    {
        return ['is_working' => 'boolean'];
    }

    public function staff(): BelongsTo
    {
        return $this->belongsTo(Staff::class);
    }
}
