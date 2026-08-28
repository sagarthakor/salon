<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Immutable audit record — one row per coupon application. Never deleted or
 * updated after creation; a booking cancellation does not remove the usage
 * record (the coupon really was used), matching how `coupons.usage_count`
 * is never decremented either. See "Coupon usage" in
 * LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md.
 */
class CouponUsage extends Model
{
    use BelongsToTenant;

    protected $fillable = ['coupon_id', 'customer_id', 'booking_id', 'discount_amount', 'used_at'];

    protected function casts(): array
    {
        return ['discount_amount' => 'decimal:2', 'used_at' => 'datetime'];
    }

    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    public function coupon(): BelongsTo
    {
        return $this->belongsTo(Coupon::class);
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class);
    }

    public function booking(): BelongsTo
    {
        return $this->belongsTo(Booking::class);
    }
}
