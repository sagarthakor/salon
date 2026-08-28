<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * `description`/`unit_amount` are a snapshot taken at billing time — never a
 * live join to `plans`. If a plan's price changes later, every invoice
 * already issued keeps showing exactly what was actually charged.
 */
class InvoiceItem extends Model
{
    use BelongsToTenant;

    protected $fillable = ['invoice_id', 'description', 'quantity', 'unit_amount', 'amount', 'metadata'];

    protected function casts(): array
    {
        return ['quantity' => 'integer', 'unit_amount' => 'decimal:2', 'amount' => 'decimal:2', 'metadata' => 'array'];
    }

    public function invoice(): BelongsTo
    {
        return $this->belongsTo(Invoice::class);
    }
}
