<?php

namespace App\Models;

use App\Enums\SubscriptionStatus;
use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * One row per tenant (unique `tenant_id`) — persists across its whole
 * lifecycle; renewals extend this same row rather than creating a new one.
 * Every status transition goes through `SubscriptionService`, never a
 * client-supplied `status` — see SAAS_BILLING_ARCHITECTURE.md.
 */
class Subscription extends Model
{
    use BelongsToTenant, HasUlids;

    protected $fillable = [
        'plan_id', 'status', 'trial_starts_at', 'trial_ends_at', 'starts_at',
        'current_period_start', 'current_period_end', 'cancel_at_period_end',
        'cancelled_at', 'grace_ends_at', 'ended_at', 'gateway', 'gateway_customer_id', 'gateway_subscription_id',
    ];

    protected function casts(): array
    {
        return [
            'status' => SubscriptionStatus::class,
            'trial_starts_at' => 'datetime',
            'trial_ends_at' => 'datetime',
            'starts_at' => 'datetime',
            'current_period_start' => 'datetime',
            'current_period_end' => 'datetime',
            'cancel_at_period_end' => 'boolean',
            'cancelled_at' => 'datetime',
            'grace_ends_at' => 'datetime',
            'ended_at' => 'datetime',
        ];
    }

    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    public function plan(): BelongsTo
    {
        return $this->belongsTo(Plan::class);
    }

    public function payments(): HasMany
    {
        return $this->hasMany(Payment::class);
    }

    public function invoices(): HasMany
    {
        return $this->hasMany(Invoice::class);
    }

    public function hasBusinessAccess(): bool
    {
        return in_array($this->status, SubscriptionStatus::accessAllowed(), true);
    }
}
