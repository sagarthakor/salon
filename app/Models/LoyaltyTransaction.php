<?php

namespace App\Models;

use App\Enums\LoyaltyTransactionType;
use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One immutable ledger row per balance-changing operation — see
 * LoyaltyService. Never updated or deleted; a correction is always a new
 * ADJUSTMENT or REVERSAL row, never an edit to history.
 */
class LoyaltyTransaction extends Model
{
    use BelongsToTenant;

    protected $fillable = [
        'customer_id', 'loyalty_account_id', 'booking_id', 'type', 'points',
        'balance_after', 'description', 'reference_type', 'reference_id',
    ];

    protected function casts(): array
    {
        return [
            'type' => LoyaltyTransactionType::class,
            'points' => 'integer',
            'balance_after' => 'integer',
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

    public function loyaltyAccount(): BelongsTo
    {
        return $this->belongsTo(LoyaltyAccount::class);
    }

    public function booking(): BelongsTo
    {
        return $this->belongsTo(Booking::class);
    }
}
