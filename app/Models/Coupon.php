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

class Coupon extends Model
{
    use BelongsToTenant, HasUlids, SoftDeletes;

    protected $fillable = [
        'code', 'name', 'description', 'discount_type', 'discount_value',
        'minimum_booking_amount', 'maximum_discount_amount', 'starts_at', 'expires_at',
        'usage_limit', 'usage_limit_per_customer', 'usage_count', 'is_active', 'first_booking_only',
    ];

    protected function casts(): array
    {
        return [
            'discount_type' => CouponDiscountType::class,
            'discount_value' => 'decimal:2',
            'minimum_booking_amount' => 'decimal:2',
            'maximum_discount_amount' => 'decimal:2',
            'starts_at' => 'datetime',
            'expires_at' => 'datetime',
            'is_active' => 'boolean',
            'first_booking_only' => 'boolean',
        ];
    }

    /**
     * The one normalization rule every lookup/creation goes through —
     * uppercased and trimmed, so `WELCOME10`/`welcome10`/` Welcome10 ` are
     * always the same logical code. See "Coupon code" in
     * LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md.
     */
    public static function normalizeCode(string $code): string
    {
        return strtoupper(trim($code));
    }

    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    public function services(): BelongsToMany
    {
        return $this->belongsToMany(Service::class, 'coupon_services')->withTimestamps();
    }

    public function categories(): BelongsToMany
    {
        return $this->belongsToMany(ServiceCategory::class, 'coupon_categories', 'coupon_id', 'category_id')->withTimestamps();
    }

    public function usages(): HasMany
    {
        return $this->hasMany(CouponUsage::class);
    }

    /** True only when neither `services()` nor `categories()` have any rows — applies tenant-wide. */
    public function appliesToAllServices(): bool
    {
        return $this->relationLoaded('services') && $this->relationLoaded('categories')
            ? ($this->services->isEmpty() && $this->categories->isEmpty())
            : ($this->services()->count() === 0 && $this->categories()->count() === 0);
    }
}
