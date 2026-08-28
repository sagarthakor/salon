<?php

namespace App\Models;

use App\Enums\BusinessStatus;
use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class Branch extends Model
{
    use BelongsToTenant, HasUlids, SoftDeletes;

    protected $fillable = ['salon_id', 'name', 'slug', 'phone', 'email', 'address_line_1', 'address_line_2', 'city', 'state', 'country', 'postal_code', 'latitude', 'longitude', 'timezone', 'status'];

    protected function casts(): array
    {
        return ['status' => BusinessStatus::class, 'latitude' => 'decimal:7', 'longitude' => 'decimal:7'];
    }

    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    public function salon(): BelongsTo
    {
        return $this->belongsTo(Salon::class);
    }

    public function workingHours(): HasMany
    {
        return $this->hasMany(BranchWorkingHour::class);
    }

    public function holidays(): HasMany
    {
        return $this->hasMany(BranchHoliday::class);
    }

    public function serviceCategories(): HasMany
    {
        return $this->hasMany(ServiceCategory::class);
    }

    public function services(): HasMany
    {
        return $this->hasMany(Service::class);
    }

    public function staff(): BelongsToMany
    {
        return $this->belongsToMany(Staff::class, 'staff_branches')->withTimestamps();
    }

    public function bookings(): HasMany
    {
        return $this->hasMany(Booking::class);
    }
}
