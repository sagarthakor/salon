<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SalonSetting extends Model
{
    use BelongsToTenant;

    protected $fillable = ['salon_id', 'key', 'value'];

    protected function casts(): array
    {
        return ['value' => 'json'];
    }

    public function salon(): BelongsTo
    {
        return $this->belongsTo(Salon::class);
    }
}
