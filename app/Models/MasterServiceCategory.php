<?php

namespace App\Models;

use App\Enums\ServiceAudience;
use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Platform-level (never tenant-scoped) service category template. See
 * MASTER_CATALOG_ARCHITECTURE.md and MasterCatalogSeeder for how this is
 * populated and CatalogProvisioningService for how it becomes a tenant's own
 * `ServiceCategory` row.
 */
class MasterServiceCategory extends Model
{
    use HasUlids;

    protected $fillable = ['audience', 'name', 'slug', 'sort_order', 'is_active'];

    protected function casts(): array
    {
        return ['audience' => ServiceAudience::class, 'is_active' => 'boolean'];
    }

    public function masterServices(): HasMany
    {
        return $this->hasMany(MasterService::class);
    }
}
