<?php

namespace Tests\Feature;

use App\Enums\ServiceAudience;
use App\Models\MasterService;
use App\Models\MasterServiceCategory;
use Database\Seeders\MasterCatalogSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The platform-level master catalog itself (never tenant-scoped) — see
 * CatalogProvisioningApiTest for how it becomes a tenant's own services.
 */
class MasterCatalogSeederTest extends TestCase
{
    use RefreshDatabase;

    public function test_seeder_creates_master_categories_and_services(): void
    {
        $this->seed(MasterCatalogSeeder::class);

        $this->assertGreaterThan(0, MasterServiceCategory::query()->count());
        $this->assertGreaterThan(0, MasterService::query()->count());
    }

    public function test_all_four_required_audiences_exist_in_the_master_catalog(): void
    {
        $this->seed(MasterCatalogSeeder::class);

        foreach (ServiceAudience::cases() as $audience) {
            $this->assertTrue(
                MasterServiceCategory::query()->where('audience', $audience->value)->exists(),
                "Expected at least one master category for audience [{$audience->value}].",
            );
            $this->assertTrue(
                MasterService::query()->where('audience', $audience->value)->exists(),
                "Expected at least one master service for audience [{$audience->value}].",
            );
        }
    }

    public function test_seeder_is_repeatable_and_never_creates_duplicates(): void
    {
        $this->seed(MasterCatalogSeeder::class);
        $categoryCountBefore = MasterServiceCategory::query()->count();
        $serviceCountBefore = MasterService::query()->count();

        $this->seed(MasterCatalogSeeder::class);
        $this->seed(MasterCatalogSeeder::class);

        $this->assertSame($categoryCountBefore, MasterServiceCategory::query()->count());
        $this->assertSame($serviceCountBefore, MasterService::query()->count());
    }

    public function test_every_master_service_belongs_to_a_category_with_the_same_audience(): void
    {
        $this->seed(MasterCatalogSeeder::class);

        foreach (MasterService::query()->with('masterServiceCategory')->get() as $service) {
            $this->assertSame(
                $service->masterServiceCategory->audience,
                $service->audience,
                "Master service [{$service->name}] audience must match its category's audience.",
            );
        }
    }

    public function test_kids_hair_cut_is_a_real_seeded_master_service(): void
    {
        $this->seed(MasterCatalogSeeder::class);

        $this->assertTrue(
            MasterService::query()->where('audience', ServiceAudience::KIDS->value)->where('name', 'Kids Hair Cut')->exists(),
        );
    }
}
