<?php

namespace Tests\Feature;

use App\Enums\BusinessStatus;
use App\Enums\GenderType;
use App\Enums\TenantMembershipRole;
use App\Enums\UserRole;
use App\Models\Salon;
use App\Models\Tenant;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * A brand-new self-registered owner (Tenant + trial + membership, no Salon
 * yet) must never hit a raw 500/ModelNotFoundException on owner-management
 * endpoints that assume a Salon already exists. See requireSalon() on
 * TenantManagementController and BranchController::store().
 */
class OwnerSetupOnboardingApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_freshly_registered_owner_without_salon_can_authenticate_and_use_the_api(): void
    {
        $response = $this->postJson('/api/v1/auth/register-owner', [
            'name' => 'New Owner',
            'email' => 'new-owner@example.test',
            'password' => 'password12345',
            'password_confirmation' => 'password12345',
            'salon_name' => 'New Owner Salon',
        ])->assertCreated()->assertJsonPath('success', true);

        $tenantSlug = $response->json('data.tenant_slug');
        $token = $response->json('data.token');
        $this->assertNotEmpty($tenantSlug);
        $this->assertNotEmpty($token);

        $client = $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Tenant-Slug', $tenantSlug);
        $client->getJson('/api/v1/salon')->assertNotFound();
    }

    public function test_creating_a_branch_before_salon_setup_returns_actionable_422_not_500(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('freshowner');
        $client = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $response = $client->postJson('/api/v1/branches', ['name' => 'Main Branch', 'timezone' => 'Asia/Kolkata']);

        $response->assertStatus(422);
        $response->assertJsonPath('success', false);
        $response->assertJsonPath('message', 'Please set up your salon profile before adding a branch.');
        $this->assertStringNotContainsString('ModelNotFoundException', $response->getContent());
        $this->assertStringNotContainsString('No query results for model', $response->getContent());
        $this->assertDatabaseCount('branches', 0);
    }

    public function test_creating_a_service_category_before_branch_setup_returns_clean_validation_422(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('freshowner-cat');
        $client = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $response = $client->postJson('/api/v1/service-categories', ['branch_id' => 999999, 'name' => 'Haircuts']);

        $response->assertStatus(422)->assertJsonPath('success', false);
        $this->assertStringNotContainsString('ModelNotFoundException', $response->getContent());
        $this->assertDatabaseCount('service_categories', 0);
    }

    public function test_creating_a_service_before_branch_setup_returns_clean_validation_422(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('freshowner-svc');
        $client = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $response = $client->postJson('/api/v1/services', [
            'branch_id' => 999999,
            'category_id' => 999999,
            'name' => 'Haircut',
            'gender' => 'unisex',
            'price' => '100.00',
            'duration_minutes' => 30,
        ]);

        $response->assertStatus(422)->assertJsonPath('success', false);
        $this->assertStringNotContainsString('ModelNotFoundException', $response->getContent());
        $this->assertDatabaseCount('services', 0);
    }

    public function test_existing_owner_with_salon_can_still_create_a_branch(): void
    {
        [$tenant, $owner, $salon] = $this->tenantWithSalon('withsalon');
        $client = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $branch = $client->postJson('/api/v1/branches', ['name' => 'Main', 'timezone' => 'Asia/Kolkata'])
            ->assertCreated()
            ->json('data');

        $this->assertDatabaseHas('branches', ['id' => $branch['id'], 'tenant_id' => $tenant->id, 'salon_id' => $salon->id]);
    }

    public function test_existing_owner_with_salon_can_still_create_services_and_categories(): void
    {
        [$tenant, $owner, $salon] = $this->tenantWithSalon('withsalon-svc');
        $client = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $branch = $client->postJson('/api/v1/branches', ['name' => 'Main', 'timezone' => 'Asia/Kolkata'])->json('data');

        $category = $client->postJson('/api/v1/service-categories', ['branch_id' => $branch['id'], 'name' => 'Haircuts'])
            ->assertCreated()
            ->json('data');

        $client->postJson('/api/v1/services', [
            'branch_id' => $branch['id'],
            'category_id' => $category['id'],
            'name' => 'Haircut',
            'gender' => 'unisex',
            'price' => '100.00',
            'duration_minutes' => 30,
        ])->assertCreated();
    }

    public function test_tenant_a_without_salon_cannot_have_tenant_bs_salon_selected_when_creating_a_branch(): void
    {
        [$tenantB, $ownerB, $salonB] = $this->tenantWithSalon('other-tenant-salon');
        [$tenantA, $ownerA] = $this->tenantWithOwner('no-salon-tenant');

        $client = $this->actingAs($ownerA, 'sanctum')->withHeader('X-Tenant-Slug', $tenantA->slug);
        $response = $client->postJson('/api/v1/branches', ['name' => 'Sneaky Branch', 'timezone' => 'Asia/Kolkata']);

        $response->assertStatus(422);
        $this->assertDatabaseCount('branches', 0);
        $this->assertDatabaseMissing('branches', ['salon_id' => $salonB->id, 'tenant_id' => $tenantA->id]);
    }

    private function tenantWithOwner(string $slug): array
    {
        $tenant = Tenant::query()->create(['name' => ucfirst($slug), 'slug' => $slug]);
        $owner = User::factory()->create(['role' => UserRole::SALON_OWNER]);
        $tenant->users()->attach($owner, ['role' => TenantMembershipRole::SALON_OWNER->value]);

        return [$tenant, $owner];
    }

    private function tenantWithSalon(string $slug): array
    {
        [$tenant, $owner] = $this->tenantWithOwner($slug);
        app(TenantContext::class)->set($tenant);
        $salon = Salon::query()->create(['name' => ucfirst($slug), 'slug' => $slug, 'gender_type' => GenderType::UNISEX, 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();

        return [$tenant, $owner, $salon];
    }
}
