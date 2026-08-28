<?php

namespace Tests\Feature;

use App\Enums\BusinessStatus;
use App\Enums\GenderType;
use App\Enums\TenantMembershipRole;
use App\Enums\UserRole;
use App\Models\Branch;
use App\Models\Salon;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\Tenant;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/**
 * Service image + description + Instagram reference URL. `description` and
 * `image` (the stored path) already existed from Phase 3 — this feature adds
 * `instagram_url`, exposes a real `image_url` instead of a raw storage path
 * (see ServiceResource), and adds old-image cleanup on replace/remove. See
 * SERVICE_ARCHITECTURE.md.
 */
class ServiceMediaApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('public');
    }

    public function test_owner_can_create_service_with_a_valid_image_and_the_image_is_stored_and_returned_as_a_url(): void
    {
        [$tenant, $owner, $branch, $category] = $this->fixture('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $response = $api->post('/api/v1/services', [
            'branch_id' => $branch->id,
            'category_id' => $category->id,
            'name' => 'Haircut',
            'gender' => 'unisex',
            'price' => '300.00',
            'duration_minutes' => 30,
            'image' => UploadedFile::fake()->image('haircut.jpg', 400, 400)->size(200),
        ]);

        $response->assertCreated();
        $imageUrl = $response->json('data.image_url');
        $this->assertNotNull($imageUrl);
        $this->assertStringContainsString('/storage/services/', $imageUrl);

        $service = Service::withoutGlobalScope('tenant')->findOrFail($response->json('data.id'));
        $this->assertNotNull($service->image);
        Storage::disk('public')->assertExists($service->image);
    }

    public function test_owner_can_update_an_existing_services_image_and_the_old_file_is_deleted(): void
    {
        [$tenant, $owner, $branch, $category] = $this->fixture('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $service = $api->post('/api/v1/services', [
            'branch_id' => $branch->id,
            'category_id' => $category->id,
            'name' => 'Haircut',
            'gender' => 'unisex',
            'price' => '300.00',
            'duration_minutes' => 30,
            'image' => UploadedFile::fake()->image('original.jpg', 400, 400),
        ])->json('data');
        $originalPath = Service::withoutGlobalScope('tenant')->findOrFail($service['id'])->image;
        Storage::disk('public')->assertExists($originalPath);

        $response = $api->post('/api/v1/services/'.$service['id'], [
            '_method' => 'PUT',
            'branch_id' => $branch->id,
            'category_id' => $category->id,
            'name' => 'Haircut',
            'gender' => 'unisex',
            'price' => '300.00',
            'duration_minutes' => 30,
            'image' => UploadedFile::fake()->image('replacement.jpg', 400, 400),
        ]);

        $response->assertOk();
        $newPath = Service::withoutGlobalScope('tenant')->findOrFail($service['id'])->image;
        $this->assertNotSame($originalPath, $newPath);
        Storage::disk('public')->assertExists($newPath);
        Storage::disk('public')->assertMissing($originalPath);
    }

    public function test_owner_can_remove_an_existing_services_image(): void
    {
        [$tenant, $owner, $branch, $category] = $this->fixture('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $service = $api->post('/api/v1/services', [
            'branch_id' => $branch->id,
            'category_id' => $category->id,
            'name' => 'Haircut',
            'gender' => 'unisex',
            'price' => '300.00',
            'duration_minutes' => 30,
            'image' => UploadedFile::fake()->image('original.jpg', 400, 400),
        ])->json('data');
        $originalPath = Service::withoutGlobalScope('tenant')->findOrFail($service['id'])->image;

        $response = $api->post('/api/v1/services/'.$service['id'], [
            '_method' => 'PUT',
            'branch_id' => $branch->id,
            'category_id' => $category->id,
            'name' => 'Haircut',
            'gender' => 'unisex',
            'price' => '300.00',
            'duration_minutes' => 30,
            'remove_image' => '1',
        ]);

        $response->assertOk()->assertJsonPath('data.image_url', null);
        $this->assertNull(Service::withoutGlobalScope('tenant')->findOrFail($service['id'])->image);
        Storage::disk('public')->assertMissing($originalPath);
    }

    public function test_valid_instagram_post_url_is_accepted(): void
    {
        [$tenant, $owner, $branch, $category] = $this->fixture('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $response = $api->postJson('/api/v1/services', [
            'branch_id' => $branch->id,
            'category_id' => $category->id,
            'name' => 'Haircut',
            'gender' => 'unisex',
            'price' => '300.00',
            'duration_minutes' => 30,
            'instagram_url' => 'https://www.instagram.com/p/Cabc123XYZ/',
        ]);

        $response->assertCreated()->assertJsonPath('data.instagram_url', 'https://www.instagram.com/p/Cabc123XYZ/');
    }

    public function test_valid_instagram_reel_url_is_accepted_and_a_missing_scheme_is_normalized(): void
    {
        [$tenant, $owner, $branch, $category] = $this->fixture('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $response = $api->postJson('/api/v1/services', [
            'branch_id' => $branch->id,
            'category_id' => $category->id,
            'name' => 'Haircut',
            'gender' => 'unisex',
            'price' => '300.00',
            'duration_minutes' => 30,
            'instagram_url' => 'instagram.com/reel/Cxyz789ABC',
        ]);

        $response->assertCreated()->assertJsonPath('data.instagram_url', 'https://instagram.com/reel/Cxyz789ABC');
    }

    public function test_invalid_instagram_url_is_rejected(): void
    {
        [$tenant, $owner, $branch, $category] = $this->fixture('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $response = $api->postJson('/api/v1/services', [
            'branch_id' => $branch->id,
            'category_id' => $category->id,
            'name' => 'Haircut',
            'gender' => 'unisex',
            'price' => '300.00',
            'duration_minutes' => 30,
            'instagram_url' => 'https://www.facebook.com/p/Cabc123XYZ/',
        ]);

        $response->assertUnprocessable()->assertJsonPath('success', false);
        $this->assertArrayHasKey('instagram_url', $response->json('errors'));
    }

    public function test_dangerous_url_scheme_is_rejected(): void
    {
        [$tenant, $owner, $branch, $category] = $this->fixture('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $response = $api->postJson('/api/v1/services', [
            'branch_id' => $branch->id,
            'category_id' => $category->id,
            'name' => 'Haircut',
            'gender' => 'unisex',
            'price' => '300.00',
            'duration_minutes' => 30,
            'instagram_url' => 'javascript:alert(document.cookie)',
        ]);

        $response->assertUnprocessable();
        $this->assertArrayHasKey('instagram_url', $response->json('errors'));
        $this->assertDatabaseCount('services', 0);
    }

    public function test_existing_service_without_image_continues_to_work(): void
    {
        [$tenant, $owner, $branch, $category] = $this->fixture('a');
        app(TenantContext::class)->set($tenant);
        $service = Service::query()->create(['branch_id' => $branch->id, 'category_id' => $category->id, 'name' => 'Legacy', 'slug' => 'legacy', 'gender' => GenderType::UNISEX, 'price' => '100.00', 'duration_minutes' => 15, 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $api->getJson('/api/v1/services/'.$service->id)->assertOk()
            ->assertJsonPath('data.image_url', null)
            ->assertJsonPath('data.name', 'Legacy');
    }

    public function test_existing_service_without_instagram_url_continues_to_work(): void
    {
        [$tenant, $owner, $branch, $category] = $this->fixture('a');
        app(TenantContext::class)->set($tenant);
        $service = Service::query()->create(['branch_id' => $branch->id, 'category_id' => $category->id, 'name' => 'Legacy', 'slug' => 'legacy', 'gender' => GenderType::UNISEX, 'price' => '100.00', 'duration_minutes' => 15, 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $api->getJson('/api/v1/services/'.$service->id)->assertOk()->assertJsonPath('data.instagram_url', null);
        // Updating other fields without ever touching instagram_url must not fail or invent one.
        $api->patchJson('/api/v1/services/'.$service->id, ['branch_id' => $branch->id, 'category_id' => $category->id, 'name' => 'Legacy Updated', 'gender' => 'unisex', 'price' => '100.00', 'duration_minutes' => 15])
            ->assertOk()->assertJsonPath('data.instagram_url', null);
    }

    public function test_cross_tenant_service_media_modification_is_rejected(): void
    {
        [$tenantA, $ownerA, $branchA, $categoryA] = $this->fixture('a');
        [$tenantB, , $branchB, $categoryB] = $this->fixture('b');
        app(TenantContext::class)->set($tenantB);
        $serviceB = Service::query()->create(['branch_id' => $branchB->id, 'category_id' => $categoryB->id, 'name' => 'Foreign', 'slug' => 'foreign', 'gender' => GenderType::UNISEX, 'price' => '50.00', 'duration_minutes' => 10, 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();

        $api = $this->actingAs($ownerA, 'sanctum')->withHeader('X-Tenant-Slug', $tenantA->slug);

        // A fully valid tenant-A body (own branch/category) targeting tenant
        // B's service by id — proves the service lookup itself, not just
        // the branch/category validation, is tenant-scoped.
        $api->post('/api/v1/services/'.$serviceB->id, [
            '_method' => 'PUT',
            'branch_id' => $branchA->id,
            'category_id' => $categoryA->id,
            'name' => 'Hijacked',
            'gender' => 'unisex',
            'price' => '50.00',
            'duration_minutes' => 10,
            'image' => UploadedFile::fake()->image('hijack.jpg', 400, 400),
            'instagram_url' => 'https://www.instagram.com/p/Hijack123/',
        ])->assertNotFound();

        $api->deleteJson('/api/v1/services/'.$serviceB->id)->assertNotFound();

        $fresh = Service::withoutGlobalScope('tenant')->findOrFail($serviceB->id);
        $this->assertNull($fresh->image);
        $this->assertNull($fresh->instagram_url);
        $this->assertSame('Foreign', $fresh->name);
    }

    public function test_customer_can_read_image_url_description_and_instagram_url(): void
    {
        [$tenant, , $branch, $category] = $this->fixture('a');
        app(TenantContext::class)->set($tenant);
        Service::query()->create([
            'branch_id' => $branch->id,
            'category_id' => $category->id,
            'name' => 'Signature Cut',
            'slug' => 'signature-cut',
            'description' => 'Our signature precision cut.',
            'gender' => GenderType::UNISEX,
            'price' => '500.00',
            'duration_minutes' => 45,
            'image' => 'services/signature.jpg',
            'instagram_url' => 'https://www.instagram.com/reel/Signature1/',
            'status' => BusinessStatus::ACTIVE,
        ]);
        app(TenantContext::class)->clear();

        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $response = $this->actingAs($customer, 'sanctum')->getJson('/api/v1/branches/'.$branch->id.'/services')->assertOk();
        $service = collect($response->json('data.services'))->firstWhere('name', 'Signature Cut');
        $this->assertNotNull($service);
        $this->assertSame('Our signature precision cut.', $service['description']);
        $this->assertStringContainsString('/storage/services/signature.jpg', $service['image_url']);
        $this->assertSame('https://www.instagram.com/reel/Signature1/', $service['instagram_url']);
    }

    public function test_customer_cannot_modify_service_media(): void
    {
        [$tenant, , $branch, $category] = $this->fixture('a');
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $api = $this->actingAs($customer, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $api->postJson('/api/v1/services', [
            'branch_id' => $branch->id,
            'category_id' => $category->id,
            'name' => 'Sneaky',
            'gender' => 'unisex',
            'price' => '100.00',
            'duration_minutes' => 10,
        ])->assertForbidden();

        $this->assertDatabaseCount('services', 0);
    }

    public function test_existing_service_authorization_remains_unchanged_for_non_owner_staff(): void
    {
        [$tenant, , $branch, $category] = $this->fixture('a');
        $staff = User::factory()->create(['role' => UserRole::STAFF]);
        $tenant->users()->attach($staff, ['role' => TenantMembershipRole::STAFF->value]);
        $api = $this->actingAs($staff, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $api->postJson('/api/v1/services', [
            'branch_id' => $branch->id,
            'category_id' => $category->id,
            'name' => 'Sneaky',
            'gender' => 'unisex',
            'price' => '100.00',
            'duration_minutes' => 10,
        ])->assertForbidden();
    }

    private function fixture(string $slug): array
    {
        $tenant = Tenant::query()->create(['name' => $slug, 'slug' => $slug]);
        $owner = User::factory()->create(['role' => UserRole::SALON_OWNER]);
        $tenant->users()->attach($owner, ['role' => TenantMembershipRole::SALON_OWNER->value]);
        app(TenantContext::class)->set($tenant);
        $salon = Salon::query()->create(['name' => $slug, 'slug' => $slug, 'gender_type' => GenderType::UNISEX, 'status' => BusinessStatus::ACTIVE]);
        $branch = Branch::query()->create(['salon_id' => $salon->id, 'name' => 'Main', 'slug' => 'main', 'status' => BusinessStatus::ACTIVE]);
        $category = ServiceCategory::query()->create(['branch_id' => $branch->id, 'name' => 'Hair', 'slug' => 'hair', 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();

        return [$tenant, $owner, $branch, $category];
    }
}
