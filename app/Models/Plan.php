<?php

namespace App\Models;

use App\Enums\BillingInterval;
use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Platform-global — never tenant-scoped, no `BelongsToTenant`. Every salon
 * subscribes to one of these; see SAAS_BILLING_ARCHITECTURE.md for why
 * ₹500/month lives here as a database row (`SALON_BASIC`) rather than a
 * constant anywhere in the codebase.
 */
class Plan extends Model
{
    use HasUlids;

    protected $fillable = ['name', 'code', 'description', 'amount', 'currency', 'billing_interval', 'billing_interval_count', 'trial_days', 'is_active', 'features'];

    protected function casts(): array
    {
        return [
            'amount' => 'decimal:2',
            'billing_interval' => BillingInterval::class,
            'billing_interval_count' => 'integer',
            'trial_days' => 'integer',
            'is_active' => 'boolean',
            'features' => 'array',
        ];
    }

    public function subscriptions(): HasMany
    {
        return $this->hasMany(Subscription::class);
    }
}
