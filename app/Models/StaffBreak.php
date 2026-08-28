<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class StaffBreak extends Model
{
    use BelongsToTenant;

    protected $fillable = ['staff_id', 'day_of_week', 'start_time', 'end_time'];

    public function staff(): BelongsTo
    {
        return $this->belongsTo(Staff::class);
    }
}
