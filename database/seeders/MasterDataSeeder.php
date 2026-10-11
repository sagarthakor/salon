<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;

/**
 * Platform-level master data only — safe to run on production, any number of
 * times: `php artisan db:seed --class=MasterDataSeeder --force`.
 *
 * Audit of what the schema needs seeded:
 *  - master_service_categories / master_services → MasterCatalogSeeder (14 / 75).
 *  - plans → inserted by the billing migration itself (unchanged).
 *  - roles, booking statuses, payment statuses, gallery categories, audiences →
 *    PHP enums, nothing to seed. There is no permissions table.
 *  - payment methods → no table exists; none seeded.
 * Writes no tenant data, no users, and no demo records.
 */
class MasterDataSeeder extends Seeder
{
    public function run(): void
    {
        $this->call(MasterCatalogSeeder::class);
    }
}
