<?php

namespace App\Console\Commands;

use App\Models\Branch;
use App\Models\Service;
use App\Models\Tenant;
use App\Services\Catalog\BranchDefaultsService;
use App\Services\Catalog\CatalogProvisioningService;
use App\Support\TenantContext;
use Illuminate\Console\Command;

/**
 * Gives an existing tenant's branches the same defaults a newly onboarded
 * salon gets (see SALON_PROVISIONING.md). Additive only: never overwrites
 * settings, hours, staff or services that already exist.
 */
class ProvisionSalonDefaults extends Command
{
    protected $signature = 'salon:provision {tenant : Tenant slug}
        {--branch= : Only this branch id}
        {--with-catalog : Also copy the master service catalog even if the tenant already has services}
        {--dry-run : Show what would be provisioned, change nothing}';

    protected $description = 'Provision default catalog, booking settings, hours and a default stylist for a tenant (idempotent).';

    public function handle(CatalogProvisioningService $catalog, BranchDefaultsService $defaults, TenantContext $context): int
    {
        $tenant = Tenant::query()->where('slug', $this->argument('tenant'))->first();
        if ($tenant === null) {
            $this->error('Tenant not found.');

            return self::FAILURE;
        }

        $context->set($tenant);
        try {
            $branches = Branch::query()->when($this->option('branch'), fn ($q, $id) => $q->whereKey($id))->orderBy('created_at')->get();
            if ($branches->isEmpty()) {
                $this->error('No branches found. Create the salon/branch first (the app does this during onboarding).');

                return self::FAILURE;
            }
            // A tenant that already built its own catalog is not handed 75 extra services unless asked.
            $copyCatalog = $this->option('with-catalog') || Service::query()->doesntExist();
            $this->info(($this->option('dry-run') ? '[dry-run] ' : '')."Tenant {$tenant->slug}: {$branches->count()} branch(es); ".($copyCatalog ? 'catalog will be provisioned if missing.' : 'existing services kept, catalog skipped.'));
            if ($this->option('dry-run')) {
                return self::SUCCESS;
            }

            foreach ($branches as $i => $branch) {
                if ($copyCatalog && $i === 0) {
                    $catalog->provisionForBranch($branch);
                }
                $r = $defaults->apply($branch);
                $this->line(sprintf('  %s: +%d settings, +%d hours, default stylist %s, %d services assigned', $branch->name, $r['settings'], $r['working_hours'], $r['staff_created'] ? 'created' : 'kept', $r['services_assigned']));
            }
        } finally {
            $context->clear();
        }

        return self::SUCCESS;
    }
}
