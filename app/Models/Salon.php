<?php

namespace App\Models;

use App\Enums\BusinessStatus;
use App\Enums\GenderType;
use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class Salon extends Model
{
    use BelongsToTenant, HasUlids, SoftDeletes;

    protected $fillable = ['name', 'slug', 'description', 'gender_type', 'logo', 'cover_image', 'phone', 'email', 'website', 'address_line_1', 'address_line_2', 'city', 'state', 'country', 'postal_code', 'latitude', 'longitude', 'timezone', 'status'];

    protected function casts(): array
    {
        return ['gender_type' => GenderType::class, 'status' => BusinessStatus::class, 'latitude' => 'decimal:7', 'longitude' => 'decimal:7'];
    }

    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    public function branches(): HasMany
    {
        return $this->hasMany(Branch::class);
    }

    public function settings(): HasMany
    {
        return $this->hasMany(SalonSetting::class);
    }
}
