<?php

namespace App\Models;

use App\Enums\BookingStatus;
use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Booking extends Model
{
    use BelongsToTenant, HasUlids;

    protected $fillable = [
        'branch_id', 'customer_id', 'booking_date', 'start_time', 'end_time', 'status',
        'subtotal', 'discount', 'tax', 'total', 'notes', 'cancellation_reason',
        'cancelled_at', 'cancelled_by', 'created_by',
        // Phase 12 pricing breakdown/snapshot — see BookingPricingService and
        // "Booking snapshot" in LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md.
        // `discount` above remains the combined total of the three below,
        // for backward compatibility with the existing Flutter Booking model.
        'coupon_id', 'coupon_code', 'coupon_discount',
        'customer_membership_id', 'membership_discount',
        'loyalty_points_redeemed', 'loyalty_discount', 'loyalty_points_earned',
    ];

    protected function casts(): array
    {
        return [
            'booking_date' => 'date:Y-m-d',
            'status' => BookingStatus::class,
            'subtotal' => 'decimal:2',
            'discount' => 'decimal:2',
            'tax' => 'decimal:2',
            'total' => 'decimal:2',
            'cancelled_at' => 'datetime',
            'coupon_discount' => 'decimal:2',
            'membership_discount' => 'decimal:2',
            'loyalty_points_redeemed' => 'integer',
            'loyalty_discount' => 'decimal:2',
            'loyalty_points_earned' => 'integer',
        ];
    }

    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class);
    }

    public function coupon(): BelongsTo
    {
        return $this->belongsTo(Coupon::class);
    }

    public function customerMembership(): BelongsTo
    {
        return $this->belongsTo(CustomerMembership::class);
    }

    public function items(): HasMany
    {
        return $this->hasMany(BookingItem::class);
    }

    public function statusHistories(): HasMany
    {
        return $this->hasMany(BookingStatusHistory::class);
    }

    public function cancelledBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'cancelled_by');
    }

    public function createdBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }
}
