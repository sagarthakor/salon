<?php

namespace Tests\Feature;

use App\Enums\BusinessStatus;
use App\Enums\GenderType;
use App\Enums\TenantMembershipRole;
use App\Enums\UserRole;
use App\Models\Branch;
use App\Models\MasterService;
use App\Models\MasterServiceCategory;
use App\Models\Salon;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\Tenant;
use App\Models\User;
use App\Support\TenantContext;
use Database\Seeders\MasterCatalogSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Real-device bug fix: a freshly self-registered owner who only completes
 * Salon Profile (the actual onboarding flow) previously ended up with an
 * empty Services screen, because catalog provisioning only ever fired on
 * `POST /branches` — a step nothing in the onboarding flow ever prompted
 * the owner to take. `POST /salon` now also creates a default first Branch
 * and provisions the catalog through it, atomically, in the same request.
 * See MASTER_CATALOG_ARCHITECTURE.md, "Automatic onboarding provisioning".
 */
class OwnerOnboardingCatalogApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(MasterCatalogSeeder::class);
    }

    public function test_fresh_owner_registration_and_immediate_salon_creation_provisions_the_full_catalog_with_no_extra_step(): void
    {
        $response = $this->postJson('/api/v1/auth/register-owner', [
            'name' => 'Sunny Owner',
            'email' => 'sunny-owner@example.test',
            'password' => 'password12345',
            'password_confirmation' => 'password12345',
            'salon_name' => 'Sunny Unisex Salon',
        ])->assertCreated();
        $token = $response->json('data.token');
        $slug = $response->json('data.tenant_slug');
        $api = $this->withHeader('Authorization', "Bearer $token")->withHeader('X-Tenant-Slug', $slug);

        // The exact sequence a real device performs: register, then submit
        // Salon Details. No branch step, no separate "add a branch" tap.
        $salon = $api->postJson('/api/v1/salon', [
            'name' => 'Sunny Unisex Salon',
            'gender_type' => 'unisex',
        ])->assertCreated()->json('data');

        // GET /salon must succeed immediately, in the very next request —
        // the original bug: this used to be reachable (via the Booking
        // Settings screen) while nothing had actually failed, and other
        // paths could still show a raw ModelNotFoundException before this
        // fix closed the underlying gap. Asserting the exact real response
        // shape here, not just "some error", proves it's a real fix.
        $api->getJson('/api/v1/salon')->assertOk()->assertJsonPath('data.id', $salon['id']);
        $api->getJson('/api/v1/salon/settings')->assertOk();

        $services = $api->getJson('/api/v1/services?per_page=100')->assertOk()->json('data');
        $categories = $api->getJson('/api/v1/service-categories?per_page=100')->assertOk()->json('data');
        $this->assertCount(75, $services, 'A freshly onboarded owner must have the full default catalog immediately.');
        $this->assertCount(14, $categories);
    }

    public function test_the_default_branch_and_catalog_are_provisioned_atomically_with_the_salon(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $api->postJson('/api/v1/salon', ['name' => 'Sunny Unisex Salon', 'gender_type' => 'unisex'])->assertCreated();

        app(TenantContext::class)->set($tenant);
        $branches = Branch::query()->get();
        $this->assertCount(1, $branches, 'Exactly one default branch must be created alongside the salon.');
        $this->assertSame('Main Branch', $branches->first()->name);
        $this->assertSame(75, Service::query()->whereNotNull('master_service_id')->count());
        $this->assertSame(14, ServiceCategory::query()->count());
        app(TenantContext::class)->clear();
    }

    public function test_a_second_manually_created_branch_does_not_duplicate_the_catalog(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $api->postJson('/api/v1/salon', ['name' => 'Sunny Unisex Salon', 'gender_type' => 'unisex'])->assertCreated();

        $api->postJson('/api/v1/branches', ['name' => 'Second Branch', 'timezone' => 'Asia/Kolkata'])->assertCreated();

        app(TenantContext::class)->set($tenant);
        $this->assertCount(2, Branch::query()->get());
        $this->assertSame(75, Service::query()->count());
        $this->assertSame(14, ServiceCategory::query()->count());
        app(TenantContext::class)->clear();
    }

    public function test_catalog_provisioning_via_salon_creation_remains_idempotent_if_somehow_retried(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $api->postJson('/api/v1/salon', ['name' => 'Sunny Unisex Salon', 'gender_type' => 'unisex'])->assertCreated();

        // A second POST /salon for the same tenant is rejected outright
        // (the pre-existing guard) — proving the provisioning-triggering
        // path itself can never be invoked twice for one tenant.
        $api->postJson('/api/v1/salon', ['name' => 'Duplicate Attempt', 'gender_type' => 'unisex'])->assertStatus(409);

        app(TenantContext::class)->set($tenant);
        $this->assertSame(75, Service::query()->count());
        $this->assertSame(14, ServiceCategory::query()->count());
        app(TenantContext::class)->clear();
    }

    public function test_tenant_isolation_holds_for_auto_provisioned_catalogs(): void
    {
        [$tenantA, $ownerA] = $this->tenantWithOwner('a');
        [$tenantB, $ownerB] = $this->tenantWithOwner('b');
        $this->actingAs($ownerA, 'sanctum')->withHeader('X-Tenant-Slug', $tenantA->slug)
            ->postJson('/api/v1/salon', ['name' => 'Salon A', 'gender_type' => 'unisex'])->assertCreated();
        $serviceA = $this->actingAs($ownerA, 'sanctum')->withHeader('X-Tenant-Slug', $tenantA->slug)
            ->getJson('/api/v1/services?per_page=1')->json('data.0');

        $this->actingAs($ownerB, 'sanctum')->withHeader('X-Tenant-Slug', $tenantB->slug)
            ->postJson('/api/v1/salon', ['name' => 'Salon B', 'gender_type' => 'unisex'])->assertCreated();

        // Tenant B has no membership in tenant A — direct-ID cross-tenant
        // access to A's auto-provisioned service is rejected exactly like
        // any other tenant-owned resource.
        $this->actingAs($ownerB, 'sanctum')->withHeader('X-Tenant-Slug', $tenantA->slug)
            ->getJson('/api/v1/services/'.$serviceA['id'])->assertForbidden();
    }

    public function test_existing_owner_flow_without_the_http_salon_create_path_is_unaffected(): void
    {
        // The established fixture pattern used across this project's other
        // test suites (Eloquent-created Salon, bypassing SalonController::
        // store() entirely) — proving this fix only changes behavior for
        // the actual POST /salon endpoint, never for a tenant whose Salon
        // came from anywhere else (a seeder, a fixture, a pre-existing
        // production tenant).
        [$tenant, $owner, $salon] = $this->tenantWithSalon('legacy');
        app(TenantContext::class)->set($tenant);
        $this->assertSame(0, Branch::query()->count(), 'A Salon created outside the HTTP endpoint must not get an automatic branch.');
        app(TenantContext::class)->clear();

        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $api->getJson('/api/v1/salon')->assertOk()->assertJsonPath('data.id', $salon->id);
    }

    public function test_existing_services_and_the_master_catalog_are_unaffected_by_a_different_tenants_onboarding(): void
    {
        [$legacyTenant, $legacyOwner, $legacySalon, $legacyBranch] = $this->tenantWithSalonAndBranch('legacy');
        app(TenantContext::class)->set($legacyTenant);
        $legacyCategory = ServiceCategory::query()->create(['branch_id' => $legacyBranch->id, 'name' => 'Custom Category', 'slug' => 'custom-category', 'status' => BusinessStatus::ACTIVE]);
        $legacyService = Service::query()->create(['branch_id' => $legacyBranch->id, 'category_id' => $legacyCategory->id, 'name' => 'Custom Service', 'slug' => 'custom-service', 'gender' => GenderType::UNISEX, 'price' => '999.00', 'duration_minutes' => 25, 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();
        $categoriesBefore = MasterServiceCategory::query()->count();
        $servicesBefore = MasterService::query()->count();

        [$newTenant, $newOwner] = $this->tenantWithOwner('new');
        $this->actingAs($newOwner, 'sanctum')->withHeader('X-Tenant-Slug', $newTenant->slug)
            ->postJson('/api/v1/salon', ['name' => 'New Owner Salon', 'gender_type' => 'unisex'])->assertCreated();

        app(TenantContext::class)->set($legacyTenant);
        $freshLegacyService = Service::query()->findOrFail($legacyService->id);
        $this->assertSame('999.00', $freshLegacyService->price);
        $this->assertSame('Custom Service', $freshLegacyService->name);
        $this->assertSame(1, Service::query()->count(), "The legacy tenant's own service count must be unchanged.");
        app(TenantContext::class)->clear();

        $this->assertSame($categoriesBefore, MasterServiceCategory::query()->count());
        $this->assertSame($servicesBefore, MasterService::query()->count());
    }

    private function tenantWithOwner(string $slug): array
    {
        $tenant = Tenant::query()->create(['name' => strtoupper($slug), 'slug' => 'onboarding-'.$slug]);
        $owner = User::factory()->create(['role' => UserRole::SALON_OWNER]);
        $tenant->users()->attach($owner, ['role' => TenantMembershipRole::SALON_OWNER->value]);

        return [$tenant, $owner];
    }

    private function tenantWithSalon(string $slug): array
    {
        [$tenant, $owner] = $this->tenantWithOwner($slug);
        app(TenantContext::class)->set($tenant);
        $salon = Salon::query()->create(['name' => strtoupper($slug), 'slug' => 'onboarding-'.$slug, 'gender_type' => GenderType::UNISEX, 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();

        return [$tenant, $owner, $salon];
    }

    private function tenantWithSalonAndBranch(string $slug): array
    {
        [$tenant, $owner, $salon] = $this->tenantWithSalon($slug);
        app(TenantContext::class)->set($tenant);
        $branch = Branch::query()->create(['salon_id' => $salon->id, 'name' => 'Main', 'slug' => 'main', 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();

        return [$tenant, $owner, $salon, $branch];
    }
}
