<?php

namespace Database\Seeders;

use App\Enums\BusinessStatus;
use App\Enums\GenderType;
use App\Models\Branch;
use App\Models\Salon;
use App\Models\Tenant;
use App\Services\Catalog\BranchDefaultsService;
use App\Services\Catalog\CatalogProvisioningService;
use App\Support\TenantContext;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Seeder;

/**
 * Local/demo salon ("demo-salon") with a branch, catalog, settings, hours and
 * a default stylist, through the same services onboarding uses. Creates
 * nothing that already exists and seeds no bookings, customers or payments.
 * Refuses to run in production.
 */
class DemoSalonSeeder extends Seeder
{
    public function run(): void
    {
        if (app()->isProduction()) {
            $this->command?->warn('DemoSalonSeeder skipped: demo data is never seeded in production.');

            return;
        }

        $tenant = Tenant::query()->firstOrCreate(['slug' => 'demo-salon'], ['name' => 'Demo Salon', 'status' => 'active']);
        $context = app(TenantContext::class);
        $context->set($tenant);
        // DatabaseSeeder runs with model events off; tenant ownership relies on the
        // BelongsToTenant `creating` hook, so events are restored for this block.
        $dispatcher = Model::getEventDispatcher();
        Model::setEventDispatcher(app('events'));
        try {
            $salon = Salon::query()->firstOrCreate(['slug' => 'demo-salon'], [
                'name' => 'Demo Salon', 'gender_type' => GenderType::UNISEX, 'status' => BusinessStatus::ACTIVE,
                'timezone' => 'Asia/Kolkata', 'country' => 'IN',
            ]);
            $branch = Branch::query()->firstOrCreate(['salon_id' => $salon->id, 'slug' => 'main-branch'], [
                'name' => 'Main Branch', 'timezone' => 'Asia/Kolkata', 'status' => BusinessStatus::ACTIVE,
            ]);
            app(CatalogProvisioningService::class)->provisionForBranch($branch);
            app(BranchDefaultsService::class)->apply($branch);
        } finally {
            Model::setEventDispatcher($dispatcher);
            $context->clear();
        }
    }
}
