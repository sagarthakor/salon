<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class BranchHoliday extends Model
{
    use BelongsToTenant;

    protected $fillable = ['branch_id', 'holiday_date', 'name', 'is_closed'];

    protected function casts(): array
    {
        return ['holiday_date' => 'date:Y-m-d', 'is_closed' => 'boolean'];
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }
}
