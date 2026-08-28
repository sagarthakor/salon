<?php

namespace App\Models;

use App\Enums\CouponDiscountType;
use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class MembershipPlan extends Model
{
    use BelongsToTenant, HasUlids, SoftDeletes;

    protected $fillable = [
        'name', 'code', 'description', 'price', 'currency', 'duration_days',
        'discount_type', 'discount_value', 'maximum_discount_amount', 'is_active',
    ];

    protected function casts(): array
    {
        return [
            'price' => 'decimal:2',
            'duration_days' => 'integer',
            'discount_type' => CouponDiscountType::class,
            'discount_value' => 'decimal:2',
            'maximum_discount_amount' => 'decimal:2',
            'is_active' => 'boolean',
        ];
    }

    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    public function services(): BelongsToMany
    {
        return $this->belongsToMany(Service::class, 'membership_plan_services')->withTimestamps();
    }

    public function categories(): BelongsToMany
    {
        return $this->belongsToMany(ServiceCategory::class, 'membership_plan_categories', 'membership_plan_id', 'category_id')->withTimestamps();
    }

    public function customerMemberships(): HasMany
    {
        return $this->hasMany(CustomerMembership::class);
    }

    public function appliesToAllServices(): bool
    {
        return $this->relationLoaded('services') && $this->relationLoaded('categories')
            ? ($this->services->isEmpty() && $this->categories->isEmpty())
            : ($this->services()->count() === 0 && $this->categories()->count() === 0);
    }
}
