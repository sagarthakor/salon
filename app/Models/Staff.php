<?php

namespace App\Models;

use App\Enums\BusinessStatus;
use App\Enums\CommissionType;
use App\Enums\StaffGender;
use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class Staff extends Model
{
    use BelongsToTenant, HasUlids, SoftDeletes;

    protected $table = 'staff_profiles';

    protected $fillable = ['user_id', 'name', 'photo', 'phone', 'email', 'gender', 'bio', 'joining_date', 'status', 'commission_type', 'commission_value'];

    protected function casts(): array
    {
        return ['gender' => StaffGender::class, 'status' => BusinessStatus::class, 'commission_type' => CommissionType::class, 'commission_value' => 'decimal:2', 'joining_date' => 'date:Y-m-d'];
    }

    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function branches(): BelongsToMany
    {
        return $this->belongsToMany(Branch::class, 'staff_branches')->withTimestamps();
    }

    public function services(): BelongsToMany
    {
        return $this->belongsToMany(Service::class, 'staff_services')->withTimestamps();
    }

    public function workingHours(): HasMany
    {
        return $this->hasMany(StaffWorkingHour::class);
    }

    public function breaks(): HasMany
    {
        return $this->hasMany(StaffBreak::class);
    }

    public function leaves(): HasMany
    {
        return $this->hasMany(StaffLeave::class);
    }

    public function bookingItems(): HasMany
    {
        return $this->hasMany(BookingItem::class);
    }
}
