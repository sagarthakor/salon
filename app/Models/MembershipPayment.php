<?php

namespace App\Models;

use App\Enums\PaymentStatus;
use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Deliberately separate from Phase 10's `payments` table (whose
 * `subscription_id` is a required FK into the unrelated SaaS-billing
 * domain) — see "Subscription vs Membership" in
 * LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md. Still the exact same
 * `PaymentGatewayInterface` binding as Phase 10; never a second gateway.
 */
class MembershipPayment extends Model
{
    use BelongsToTenant, HasUlids;

    protected $fillable = [
        'customer_id', 'membership_plan_id', 'customer_membership_id', 'amount', 'currency', 'status',
        'gateway', 'gateway_order_id', 'gateway_payment_id', 'gateway_signature', 'idempotency_key',
        'failure_reason', 'paid_at', 'failed_at',
    ];

    protected function casts(): array
    {
        return [
            'amount' => 'decimal:2',
            'status' => PaymentStatus::class,
            'paid_at' => 'datetime',
            'failed_at' => 'datetime',
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

    public function customerMembership(): BelongsTo
    {
        return $this->belongsTo(CustomerMembership::class);
    }
}
