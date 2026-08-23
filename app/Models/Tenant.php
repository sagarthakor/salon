<?php

namespace App\Models;

use App\Enums\TenantStatus;
use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;

class Tenant extends Model
{
    use HasUlids;

    protected $fillable = ['name', 'slug', 'status'];

    protected function casts(): array
    {
        return ['status' => TenantStatus::class];
    }

    public function users(): BelongsToMany
    {
        return $this->belongsToMany(User::class)->withPivot('role')->withTimestamps();
    }

    public function salon(): HasOne
    {
        return $this->hasOne(Salon::class);
    }

    public function branches(): HasMany
    {
        return $this->hasMany(Branch::class);
    }
}
