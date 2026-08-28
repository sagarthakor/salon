<?php

namespace App\Models;

use App\Enums\CustomerMembershipStatus;
use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One row per purchase/renewal/grant — a renewal creates a *new* row rather
 * than mutating an existing one, so a customer's full membership history
 * (and the exact plan/price/benefit that was active for any past booking)
 * stays intact. See "Membership renewal" in
 * LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md.
 */
class CustomerMembership extends Model
{
    use BelongsToTenant, HasUlids;

    protected $fillable = ['customer_id', 'membership_plan_id', 'status', 'starts_at', 'expires_at', 'purchased_amount', 'currency', 'source'];

    protected function casts(): array
    {
        return [
            'status' => CustomerMembershipStatus::class,
            'starts_at' => 'datetime',
            'expires_at' => 'datetime',
            'purchased_amount' => 'decimal:2',
        ];
    }

    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class);
    }

    public function membershipPlan(): BelongsTo
    {
        return $this->belongsTo(MembershipPlan::class);
    }

    /**
     * Server-authoritative check, never a cached/scheduled-only flag — a
     * membership whose `status` hasn't been swept to EXPIRED yet by the
     * scheduler is still correctly denied a benefit the instant its
     * `expires_at` passes. See "Membership expiration".
     */
    public function isCurrentlyActive(): bool
    {
        return $this->status === CustomerMembershipStatus::ACTIVE && $this->expires_at->isFuture();
    }
}
