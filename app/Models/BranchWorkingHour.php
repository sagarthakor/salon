<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class BranchWorkingHour extends Model
{
    use BelongsToTenant;

    protected $fillable = ['branch_id', 'day_of_week', 'is_open', 'opening_time', 'closing_time'];

    protected function casts(): array
    {
        return ['is_open' => 'boolean'];
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }
}
