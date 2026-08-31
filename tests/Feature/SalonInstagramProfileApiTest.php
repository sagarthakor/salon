<?php

namespace Tests\Feature;

use App\Enums\BusinessStatus;
use App\Enums\GenderType;
use App\Enums\TenantMembershipRole;
use App\Enums\UserRole;
use App\Models\Customer;
use App\Models\Salon;
use App\Models\Tenant;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The salon's official Instagram profile link — deliberately separate from
 * `services.instagram_url` (a specific post/reel/video for one service; see
 * `ServiceMediaApiTest`). Both live on their own respective entities: this
 * one on `Salon`, the tenant's single business-profile row. See
 * SALON_ARCHITECTURE.md.
 */
class SalonInstagramProfileApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_owner_can_set_the_salon_instagram_url_on_create(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $api->postJson('/api/v1/salon', [
            'name' => 'Prime Hair Studio',
            'gender_type' => 'unisex',
            'timezone' => 'Asia/Kolkata',
            'instagram_url' => 'https://www.instagram.com/primehairstudio/',
        ])->assertCreated()->assertJsonPath('data.instagram_url', 'https://www.instagram.com/primehairstudio/');
    }

    public function test_owner_can_update_the_salon_instagram_url(): void
    {
        [$tenant, $owner] = $this->tenantWithSalon('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $api->patchJson('/api/v1/salon', [
            'name' => 'Prime Hair Studio',
            'gender_type' => 'unisex',
            'instagram_url' => 'https://www.instagram.com/primehairstudio_official/',
        ])->assertOk()->assertJsonPath('data.instagram_url', 'https://www.instagram.com/primehairstudio_official/');
    }

    public function test_owner_can_remove_the_salon_instagram_url(): void
    {
        [$tenant, $owner, $salon] = $this->tenantWithSalon('a');
        app(TenantContext::class)->set($tenant);
        $salon->update(['instagram_url' => 'https://www.instagram.com/primehairstudio/']);
        app(TenantContext::class)->clear();
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $api->patchJson('/api/v1/salon', [
            'name' => 'Prime Hair Studio',
            'gender_type' => 'unisex',
            'instagram_url' => '',
        ])->assertOk()->assertJsonPath('data.instagram_url', null);
    }

    public function test_valid_instagram_profile_url_is_accepted_and_scheme_is_normalized(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $api->postJson('/api/v1/salon', [
            'name' => 'Prime Hair Studio',
            'gender_type' => 'unisex',
            'timezone' => 'Asia/Kolkata',
            'instagram_url' => 'instagram.com/PrimeHairStudio',
        ])->assertCreated()->assertJsonPath('data.instagram_url', 'https://instagram.com/PrimeHairStudio');
    }

    public function test_non_instagram_url_is_rejected(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $response = $api->postJson('/api/v1/salon', [
            'name' => 'Prime Hair Studio',
            'gender_type' => 'unisex',
            'instagram_url' => 'https://www.facebook.com/primehairstudio/',
        ]);

        $response->assertUnprocessable()->assertJsonPath('success', false);
        $this->assertArrayHasKey('instagram_url', $response->json('errors'));
    }

    public function test_a_service_post_link_is_rejected_as_a_salon_profile_url(): void
    {
        // A salon profile URL and a service content URL are validated
        // differently — a /p/... post link is valid for a service, never
        // for the salon's own profile field.
        [$tenant, $owner] = $this->tenantWithOwner('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $api->postJson('/api/v1/salon', [
            'name' => 'Prime Hair Studio',
            'gender_type' => 'unisex',
            'instagram_url' => 'https://www.instagram.com/p/Cabc123XYZ/',
        ])->assertUnprocessable();
    }

    public function test_dangerous_url_scheme_is_rejected(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $response = $api->postJson('/api/v1/salon', [
            'name' => 'Prime Hair Studio',
            'gender_type' => 'unisex',
            'instagram_url' => 'javascript:alert(document.cookie)',
        ]);

        $response->assertUnprocessable();
        $this->assertArrayHasKey('instagram_url', $response->json('errors'));
        $this->assertDatabaseCount('salons', 0);
    }

    public function test_existing_salon_without_instagram_url_continues_to_work(): void
    {
        [$tenant, $owner] = $this->tenantWithSalon('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $api->getJson('/api/v1/salon')->assertOk()->assertJsonPath('data.instagram_url', null);

        // Updating unrelated fields must not invent an Instagram URL or fail.
        $api->patchJson('/api/v1/salon', ['name' => 'Prime Hair Studio Updated', 'gender_type' => 'unisex'])
            ->assertOk()
            ->assertJsonPath('data.instagram_url', null)
            ->assertJsonPath('data.name', 'Prime Hair Studio Updated');
    }

    public function test_customer_can_read_the_salon_instagram_url(): void
    {
        [$tenant, , $salon] = $this->tenantWithSalon('a');
        app(TenantContext::class)->set($tenant);
        $salon->update(['instagram_url' => 'https://www.instagram.com/primehairstudio/']);
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        Customer::query()->create(['user_id' => $customer->id, 'name' => 'Cust', 'phone' => '9000000001', 'normalized_phone' => '9000000001', 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();

        $response = $this->actingAs($customer, 'sanctum')->getJson('/api/v1/customer/salons')->assertOk();
        $entry = collect($response->json('data'))->firstWhere('tenant_slug', $tenant->slug);
        $this->assertNotNull($entry);
        $this->assertSame('https://www.instagram.com/primehairstudio/', $entry['salon']['instagram_url']);
    }

    public function test_customer_cannot_modify_the_salon_instagram_url(): void
    {
        [$tenant] = $this->tenantWithSalon('a');
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $api = $this->actingAs($customer, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $api->patchJson('/api/v1/salon', [
            'name' => 'Hijacked',
            'gender_type' => 'unisex',
            'instagram_url' => 'https://www.instagram.com/hijacked/',
        ])->assertForbidden();
    }

    public function test_cross_tenant_salon_modification_is_rejected(): void
    {
        [$tenantA, $ownerA] = $this->tenantWithSalon('a');
        [$tenantB, , $salonB] = $this->tenantWithSalon('b');

        // Owner A has no membership in tenant B — selecting tenant B's slug
        // is rejected before the request even reaches SalonController.
        $this->actingAs($ownerA, 'sanctum')->withHeader('X-Tenant-Slug', $tenantB->slug)->patchJson('/api/v1/salon', [
            'name' => 'Hijacked',
            'gender_type' => 'unisex',
            'instagram_url' => 'https://www.instagram.com/hijacked/',
        ])->assertForbidden();

        $this->assertNull($salonB->fresh()->instagram_url);
        $this->assertSame('B', $salonB->fresh()->name);
        unset($tenantA);
    }

    private function tenantWithOwner(string $slug): array
    {
        $tenant = Tenant::query()->create(['name' => strtoupper($slug), 'slug' => $slug]);
        $owner = User::factory()->create(['role' => UserRole::SALON_OWNER]);
        $tenant->users()->attach($owner, ['role' => TenantMembershipRole::SALON_OWNER->value]);

        return [$tenant, $owner];
    }

    private function tenantWithSalon(string $slug): array
    {
        [$tenant, $owner] = $this->tenantWithOwner($slug);
        app(TenantContext::class)->set($tenant);
        $salon = Salon::query()->create(['name' => strtoupper($slug), 'slug' => $slug, 'gender_type' => GenderType::UNISEX, 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();

        return [$tenant, $owner, $salon];
    }
}
