<?php

namespace App\Models;

use App\Enums\ServiceAudience;
use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Platform-level (never tenant-scoped) service template — name, suggested
 * duration/price, description. Never carries an image or Instagram URL:
 * those are always salon-specific and start `null` on every provisioned
 * tenant service (see CatalogProvisioningService). `default_price` is a
 * suggestion only — the tenant's own `Service.price` is what booking/pricing
 * actually reads, and is never overwritten by this row again after the
 * one-time copy.
 */
class MasterService extends Model
{
    use HasUlids;

    protected $fillable = ['master_service_category_id', 'audience', 'name', 'slug', 'description', 'default_duration_minutes', 'default_price', 'sort_order', 'is_active'];

    protected function casts(): array
    {
        return ['audience' => ServiceAudience::class, 'is_active' => 'boolean', 'default_price' => 'decimal:2'];
    }

    public function masterServiceCategory(): BelongsTo
    {
        return $this->belongsTo(MasterServiceCategory::class);
    }
}
