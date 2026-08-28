<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * One row per (tenant, customer). `balance`/`lifetime_earned`/
 * `lifetime_redeemed` are denormalized for cheap reads but are only ever
 * changed by `LoyaltyService` alongside a matching `LoyaltyTransaction` row
 * — never mutated directly. See "Loyalty ledger".
 */
class LoyaltyAccount extends Model
{
    use BelongsToTenant, HasUlids;

    protected $fillable = ['customer_id', 'balance', 'lifetime_earned', 'lifetime_redeemed'];

    protected function casts(): array
    {
        return ['balance' => 'integer', 'lifetime_earned' => 'integer', 'lifetime_redeemed' => 'integer'];
    }

    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class);
    }

    public function transactions(): HasMany
    {
        return $this->hasMany(LoyaltyTransaction::class);
    }
}
