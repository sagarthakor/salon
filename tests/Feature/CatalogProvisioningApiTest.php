<?php

namespace Tests\Feature;

use App\Enums\BusinessStatus;
use App\Enums\GenderType;
use App\Enums\ServiceAudience;
use App\Enums\TenantMembershipRole;
use App\Enums\UserRole;
use App\Models\Branch;
use App\Models\BranchWorkingHour;
use App\Models\Customer;
use App\Models\Salon;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\Staff;
use App\Models\StaffWorkingHour;
use App\Models\Tenant;
use App\Models\User;
use App\Services\Catalog\CatalogProvisioningService;
use App\Support\TenantContext;
use Database\Seeders\MasterCatalogSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Master catalog → tenant service provisioning, audience segmentation, and
 * tenant isolation. See MASTER_CATALOG_ARCHITECTURE.md.
 */
class CatalogProvisioningApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(MasterCatalogSeeder::class);
    }

    public function test_a_new_tenants_first_branch_automatically_receives_the_default_catalog(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $api->postJson('/api/v1/branches', ['name' => 'Main Branch', 'timezone' => 'Asia/Kolkata'])->assertCreated();

        app(TenantContext::class)->set($tenant);
        $this->assertGreaterThan(0, ServiceCategory::query()->count());
        $this->assertGreaterThan(0, Service::query()->count());
        $this->assertTrue(Service::query()->whereNotNull('master_service_id')->exists());
        app(TenantContext::class)->clear();
    }

    public function test_provisioning_is_idempotent_when_called_twice_directly(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $branch = $api->postJson('/api/v1/branches', ['name' => 'Main Branch', 'timezone' => 'Asia/Kolkata'])->json('data');

        app(TenantContext::class)->set($tenant);
        $countBefore = Service::query()->count();
        app(CatalogProvisioningService::class)->provisionForBranch(Branch::query()->findOrFail($branch['id']));
        app(CatalogProvisioningService::class)->provisionForBranch(Branch::query()->findOrFail($branch['id']));
        $countAfter = Service::query()->count();
        app(TenantContext::class)->clear();

        $this->assertSame($countBefore, $countAfter);
    }

    public function test_a_second_branch_does_not_receive_a_second_copy_of_the_catalog(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $api->postJson('/api/v1/branches', ['name' => 'Branch One', 'timezone' => 'Asia/Kolkata'])->assertCreated();

        app(TenantContext::class)->set($tenant);
        $countAfterFirstBranch = Service::query()->count();
        app(TenantContext::class)->clear();

        $api->postJson('/api/v1/branches', ['name' => 'Branch Two', 'timezone' => 'Asia/Kolkata'])->assertCreated();

        app(TenantContext::class)->set($tenant);
        $countAfterSecondBranch = Service::query()->count();
        app(TenantContext::class)->clear();

        $this->assertSame($countAfterFirstBranch, $countAfterSecondBranch);
    }

    public function test_two_tenants_receive_their_own_independent_service_records(): void
    {
        [$tenantA, $ownerA] = $this->tenantWithOwner('a');
        [$tenantB, $ownerB] = $this->tenantWithOwner('b');

        // `actingAs()`/`withHeader()` mutate the shared test-case HTTP
        // client, so tenant A's request must fully complete (and its result
        // captured as plain data) before switching identity to tenant B —
        // never interleave two "cached" authenticated clients.
        $this->actingAs($ownerA, 'sanctum')->withHeader('X-Tenant-Slug', $tenantA->slug)
            ->postJson('/api/v1/branches', ['name' => 'Main', 'timezone' => 'Asia/Kolkata'])->assertCreated();
        $serviceA = $this->actingAs($ownerA, 'sanctum')->withHeader('X-Tenant-Slug', $tenantA->slug)
            ->getJson('/api/v1/services?sort=name&per_page=1')->json('data.0');

        $this->actingAs($ownerB, 'sanctum')->withHeader('X-Tenant-Slug', $tenantB->slug)
            ->postJson('/api/v1/branches', ['name' => 'Main', 'timezone' => 'Asia/Kolkata'])->assertCreated();
        $serviceB = $this->actingAs($ownerB, 'sanctum')->withHeader('X-Tenant-Slug', $tenantB->slug)
            ->getJson('/api/v1/services?sort=name&per_page=1')->json('data.0');

        $this->assertNotSame($serviceA['id'], $serviceB['id']);
        $this->assertSame($serviceA['name'], $serviceB['name']);

        // Changing tenant A's copy must never affect tenant B's — real
        // independent rows, not a shared/live reference.
        $this->actingAs($ownerA, 'sanctum')->withHeader('X-Tenant-Slug', $tenantA->slug)
            ->patchJson('/api/v1/services/'.$serviceA['id'], [
                'branch_id' => $serviceA['branch_id'],
                'category_id' => $serviceA['category']['id'],
                'name' => $serviceA['name'],
                'gender' => $serviceA['gender'],
                'price' => '9999.00',
                'duration_minutes' => $serviceA['duration_minutes'],
                'instagram_url' => 'https://www.instagram.com/p/TenantAOnly/',
            ])->assertOk();

        $bFresh = $this->actingAs($ownerB, 'sanctum')->withHeader('X-Tenant-Slug', $tenantB->slug)
            ->getJson('/api/v1/services/'.$serviceB['id'])->json('data');
        $this->assertNotSame('9999.00', $bFresh['price']);
        $this->assertNull($bFresh['instagram_url']);
    }

    public function test_provisioned_service_starts_with_no_image_or_instagram_url(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $api->postJson('/api/v1/branches', ['name' => 'Main', 'timezone' => 'Asia/Kolkata'])->assertCreated();

        $service = $api->getJson('/api/v1/services?per_page=1')->json('data.0');

        $this->assertNull($service['image_url']);
        $this->assertNull($service['instagram_url']);
    }

    public function test_male_audience_filter_returns_only_male_services(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $branch = $api->postJson('/api/v1/branches', ['name' => 'Main', 'timezone' => 'Asia/Kolkata'])->json('data');

        $response = $api->getJson('/api/v1/services?audience=male&per_page=100')->assertOk();
        $audiences = collect($response->json('data'))->pluck('audience')->unique();
        $this->assertCount(1, $audiences);
        $this->assertSame('male', $audiences->first());
        $this->assertGreaterThan(0, count($response->json('data')));

        // Customer-facing catalog endpoint too.
        $customerResponse = $this->getJson('/api/v1/branches/'.$branch['id'].'/services?audience=male')->assertOk();
        $customerAudiences = collect($customerResponse->json('data.services'))->pluck('audience')->unique();
        $this->assertSame(['male'], $customerAudiences->values()->all());
    }

    public function test_female_audience_filter_returns_only_female_services(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $branch = $api->postJson('/api/v1/branches', ['name' => 'Main', 'timezone' => 'Asia/Kolkata'])->json('data');

        $response = $this->getJson('/api/v1/branches/'.$branch['id'].'/services?audience=female')->assertOk();
        $audiences = collect($response->json('data.services'))->pluck('audience')->unique();
        $this->assertSame(['female'], $audiences->values()->all());
    }

    public function test_unisex_audience_filter_returns_only_unisex_services_never_male_or_female(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $branch = $api->postJson('/api/v1/branches', ['name' => 'Main', 'timezone' => 'Asia/Kolkata'])->json('data');

        $response = $this->getJson('/api/v1/branches/'.$branch['id'].'/services?audience=unisex')->assertOk();
        $audiences = collect($response->json('data.services'))->pluck('audience')->unique();
        $this->assertSame(['unisex'], $audiences->values()->all());
    }

    public function test_kids_audience_filter_works(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $branch = $api->postJson('/api/v1/branches', ['name' => 'Main', 'timezone' => 'Asia/Kolkata'])->json('data');

        $response = $this->getJson('/api/v1/branches/'.$branch['id'].'/services?audience=kids')->assertOk();
        $audiences = collect($response->json('data.services'))->pluck('audience')->unique();
        $this->assertSame(['kids'], $audiences->values()->all());
        $this->assertContains('Kids Hair Cut', collect($response->json('data.services'))->pluck('name'));
    }

    public function test_inactive_services_are_excluded_from_the_customer_catalog(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $branch = $api->postJson('/api/v1/branches', ['name' => 'Main', 'timezone' => 'Asia/Kolkata'])->json('data');
        $service = $api->getJson('/api/v1/services?audience=male&per_page=1')->json('data.0');

        $api->patchJson('/api/v1/services/'.$service['id'], [
            'branch_id' => $service['branch_id'],
            'category_id' => $service['category']['id'],
            'name' => $service['name'],
            'gender' => $service['gender'],
            'price' => $service['price'],
            'duration_minutes' => $service['duration_minutes'],
            'status' => 'inactive',
        ])->assertOk();

        $response = $this->getJson('/api/v1/branches/'.$branch['id'].'/services?audience=male')->assertOk();
        $names = collect($response->json('data.services'))->pluck('id');
        $this->assertNotContains($service['id'], $names);
    }

    public function test_owner_can_update_a_provisioned_tenant_service(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $api->postJson('/api/v1/branches', ['name' => 'Main', 'timezone' => 'Asia/Kolkata'])->assertCreated();
        $service = $api->getJson('/api/v1/services?per_page=1')->json('data.0');

        $api->patchJson('/api/v1/services/'.$service['id'], [
            'branch_id' => $service['branch_id'],
            'category_id' => $service['category']['id'],
            'name' => $service['name'],
            'gender' => $service['gender'],
            'price' => '499.00',
            'duration_minutes' => 40,
        ])->assertOk()->assertJsonPath('data.price', '499.00')->assertJsonPath('data.duration_minutes', 40);
    }

    public function test_master_catalog_has_no_write_endpoint_reachable_by_an_owner(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $api->postJson('/api/v1/master-service-categories', ['name' => 'Hacked'])->assertNotFound();
        $api->postJson('/api/v1/master-services', ['name' => 'Hacked'])->assertNotFound();
    }

    public function test_customer_can_read_provisioned_services_but_cannot_modify_them(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $branch = $api->postJson('/api/v1/branches', ['name' => 'Main', 'timezone' => 'Asia/Kolkata'])->json('data');
        $service = $api->getJson('/api/v1/services?per_page=1')->json('data.0');

        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $this->actingAs($customer, 'sanctum')->getJson('/api/v1/branches/'.$branch['id'].'/services')->assertOk();

        $this->actingAs($customer, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug)->patchJson('/api/v1/services/'.$service['id'], [
            'branch_id' => $service['branch_id'],
            'category_id' => $service['category']['id'],
            'name' => 'Hijacked',
            'gender' => $service['gender'],
            'price' => '1.00',
            'duration_minutes' => 1,
        ])->assertForbidden();
    }

    public function test_staff_permissions_for_service_writes_remain_unchanged(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $api->postJson('/api/v1/branches', ['name' => 'Main', 'timezone' => 'Asia/Kolkata'])->assertCreated();
        $service = $api->getJson('/api/v1/services?per_page=1')->json('data.0');

        $staff = User::factory()->create(['role' => UserRole::STAFF]);
        $tenant->users()->attach($staff, ['role' => TenantMembershipRole::STAFF->value]);
        $this->actingAs($staff, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug)->patchJson('/api/v1/services/'.$service['id'], [
            'branch_id' => $service['branch_id'],
            'category_id' => $service['category']['id'],
            'name' => 'Hijacked',
            'gender' => $service['gender'],
            'price' => '1.00',
            'duration_minutes' => 1,
        ])->assertForbidden();
    }

    public function test_existing_service_media_fields_still_work_on_a_provisioned_service(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $api->postJson('/api/v1/branches', ['name' => 'Main', 'timezone' => 'Asia/Kolkata'])->assertCreated();
        $service = $api->getJson('/api/v1/services?per_page=1')->json('data.0');

        $api->patchJson('/api/v1/services/'.$service['id'], [
            'branch_id' => $service['branch_id'],
            'category_id' => $service['category']['id'],
            'name' => $service['name'],
            'gender' => $service['gender'],
            'price' => $service['price'],
            'duration_minutes' => $service['duration_minutes'],
            'description' => 'A lovely provisioned service, now customized.',
            'instagram_url' => 'https://www.instagram.com/reel/ProvisionedService1/',
        ])->assertOk()
            ->assertJsonPath('data.description', 'A lovely provisioned service, now customized.')
            ->assertJsonPath('data.instagram_url', 'https://www.instagram.com/reel/ProvisionedService1/');
    }

    public function test_existing_booking_flow_and_server_authoritative_pricing_remain_functional_for_a_provisioned_service(): void
    {
        [$tenant, $owner, $salon, $branch] = $this->tenantWithSalonAndBranchViaHttp('a');
        app(TenantContext::class)->set($tenant);
        $service = Service::query()->whereNotNull('master_service_id')->where('audience', ServiceAudience::MALE->value)->firstOrFail();
        foreach (range(0, 6) as $day) {
            BranchWorkingHour::query()->create(['branch_id' => $branch->id, 'day_of_week' => $day, 'is_open' => true, 'opening_time' => '09:00', 'closing_time' => '20:00']);
        }
        $staff = Staff::query()->create(['name' => 'Stylist', 'gender' => 'male', 'status' => BusinessStatus::ACTIVE]);
        $staff->branches()->sync([$branch->id => ['tenant_id' => $tenant->id]]);
        $staff->services()->sync([$service->id => ['tenant_id' => $tenant->id]]);
        foreach (range(0, 6) as $day) {
            StaffWorkingHour::query()->create(['staff_id' => $staff->id, 'day_of_week' => $day, 'is_working' => true, 'start_time' => '09:00', 'end_time' => '20:00']);
        }
        $customer = Customer::query()->create(['name' => 'Cust', 'phone' => '9000000001', 'normalized_phone' => '9000000001', 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();

        $ownerApi = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $bookingDate = now()->addDay()->format('Y-m-d');
        $response = $ownerApi->postJson('/api/v1/bookings', [
            'branch_id' => $branch->id,
            'customer_id' => $customer->id,
            'date' => $bookingDate,
            'start_time' => '11:00',
            'items' => [['service_id' => $service->id, 'staff_id' => $staff->id]],
        ]);

        // The total the server computed is derived entirely from the
        // provisioned service's own current price — never anything a
        // client could have supplied.
        $response->assertCreated()->assertJsonPath('data.total', (string) $service->price)
            ->assertJsonPath('data.items.0.service_price', (string) $service->price);
    }

    public function test_cross_tenant_direct_id_access_to_a_provisioned_service_remains_rejected(): void
    {
        [$tenantA, $ownerA] = $this->tenantWithOwner('a');
        [$tenantB, $ownerB] = $this->tenantWithOwner('b');
        $this->actingAs($ownerB, 'sanctum')->withHeader('X-Tenant-Slug', $tenantB->slug)
            ->postJson('/api/v1/branches', ['name' => 'Main', 'timezone' => 'Asia/Kolkata'])->assertCreated();
        $serviceB = $this->actingAs($ownerB, 'sanctum')->withHeader('X-Tenant-Slug', $tenantB->slug)
            ->getJson('/api/v1/services?per_page=1')->json('data.0');

        $this->actingAs($ownerA, 'sanctum')->withHeader('X-Tenant-Slug', $tenantA->slug)
            ->getJson('/api/v1/services/'.$serviceB['id'])->assertNotFound();
        $this->actingAs($ownerA, 'sanctum')->withHeader('X-Tenant-Slug', $tenantA->slug)
            ->deleteJson('/api/v1/services/'.$serviceB['id'])->assertNotFound();
    }

    public function test_seeding_and_provisioning_do_not_destroy_a_pre_existing_tenants_data(): void
    {
        [$tenant, $owner, $branch] = $this->fixtureWithoutMasterCatalog('legacy');
        app(TenantContext::class)->set($tenant);
        $legacyCategory = ServiceCategory::query()->create(['branch_id' => $branch->id, 'name' => 'Legacy Category', 'slug' => 'legacy-category', 'status' => BusinessStatus::ACTIVE]);
        $legacyService = Service::query()->create(['branch_id' => $branch->id, 'category_id' => $legacyCategory->id, 'name' => 'Legacy Service', 'slug' => 'legacy-service', 'gender' => GenderType::UNISEX, 'price' => '123.00', 'duration_minutes' => 15, 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();

        $this->seed(MasterCatalogSeeder::class);

        app(TenantContext::class)->set($tenant);
        $this->assertTrue(Service::query()->whereKey($legacyService->id)->exists());
        $this->assertSame('123.00', Service::query()->findOrFail($legacyService->id)->price);
        $this->assertNull(Service::query()->findOrFail($legacyService->id)->audience);
        app(TenantContext::class)->clear();
    }

    private function tenantWithOwner(string $slug): array
    {
        $tenant = Tenant::query()->create(['name' => strtoupper($slug), 'slug' => 'catalog-'.$slug]);
        $owner = User::factory()->create(['role' => UserRole::SALON_OWNER]);
        $tenant->users()->attach($owner, ['role' => TenantMembershipRole::SALON_OWNER->value]);
        app(TenantContext::class)->set($tenant);
        Salon::query()->create(['name' => strtoupper($slug), 'slug' => 'catalog-'.$slug, 'gender_type' => GenderType::UNISEX, 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();

        return [$tenant, $owner];
    }

    private function tenantWithSalonAndBranchViaHttp(string $slug): array
    {
        [$tenant, $owner] = $this->tenantWithOwner($slug);
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $branchData = $api->postJson('/api/v1/branches', ['name' => 'Main', 'timezone' => 'Asia/Kolkata'])->json('data');
        app(TenantContext::class)->set($tenant);
        $salon = Salon::query()->first();
        $branch = Branch::query()->findOrFail($branchData['id']);
        app(TenantContext::class)->clear();

        return [$tenant, $owner, $salon, $branch];
    }

    /** A tenant + branch with NO master-catalog provisioning (seeder not called yet), for the pre-existing-data safety test. */
    private function fixtureWithoutMasterCatalog(string $slug): array
    {
        $tenant = Tenant::query()->create(['name' => strtoupper($slug), 'slug' => 'catalog-'.$slug]);
        $owner = User::factory()->create(['role' => UserRole::SALON_OWNER]);
        $tenant->users()->attach($owner, ['role' => TenantMembershipRole::SALON_OWNER->value]);
        app(TenantContext::class)->set($tenant);
        $salon = Salon::query()->create(['name' => strtoupper($slug), 'slug' => 'catalog-'.$slug, 'gender_type' => GenderType::UNISEX, 'status' => BusinessStatus::ACTIVE]);
        $branch = Branch::query()->create(['salon_id' => $salon->id, 'name' => 'Main', 'slug' => 'main', 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();

        return [$tenant, $owner, $branch];
    }
}
