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
use Tests\TestCase;

class ServiceManagementApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_owner_can_manage_branch_categories_services_and_filters(): void
    {
        [$tenant,$owner,$branch] = $this->fixture('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $category = $api->postJson('/api/v1/service-categories', ['branch_id' => $branch->id, 'name' => 'Hair', 'status' => 'active'])->assertCreated()->json('data');
        $service = $api->postJson('/api/v1/services', ['branch_id' => $branch->id, 'category_id' => $category['id'], 'name' => 'Haircut', 'gender' => 'male', 'price' => '300.00', 'duration_minutes' => 30, 'status' => 'active'])->assertCreated()->assertJsonPath('data.price', '300.00')->json('data');
        $api->getJson('/api/v1/services?branch_id='.$branch->id.'&gender=male&status=active&category_id='.$category['id'].'&sort=price')->assertOk()->assertJsonPath('data.0.id', $service['id']);
        $api->patchJson('/api/v1/services/'.$service['id'], ['branch_id' => $branch->id, 'category_id' => $category['id'], 'name' => 'Haircut Deluxe', 'slug' => 'haircut', 'gender' => 'unisex', 'price' => '350.00', 'duration_minutes' => 45])->assertOk()->assertJsonPath('data.duration_minutes', 45);
        $api->deleteJson('/api/v1/services/'.$service['id'])->assertOk();
        $this->assertSoftDeleted('services', ['id' => $service['id']]);
        $api->deleteJson('/api/v1/service-categories/'.$category['id'])->assertOk();
    }

    public function test_service_validation_rejects_bad_price_duration_and_cross_branch_category(): void
    {
        [$tenant,$owner,$branch] = $this->fixture('a');
        [,,$otherBranch] = $this->fixture('b');
        app(TenantContext::class)->set($tenant);
        $category = ServiceCategory::query()->create(['branch_id' => $branch->id, 'name' => 'Hair', 'slug' => 'hair', 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $api->postJson('/api/v1/services', ['branch_id' => $branch->id, 'category_id' => $category->id, 'name' => 'Bad', 'gender' => 'male', 'price' => '-1', 'duration_minutes' => 0])->assertUnprocessable();
        $api->postJson('/api/v1/services', ['branch_id' => $otherBranch->id, 'category_id' => $category->id, 'name' => 'Cross', 'gender' => 'male', 'price' => '1', 'duration_minutes' => 30])->assertUnprocessable();
    }

    public function test_tenant_cannot_access_foreign_category_or_service_by_id(): void
    {
        [$tenantA,$ownerA,$branchA] = $this->fixture('a');
        [$tenantB,$ownerB,$branchB] = $this->fixture('b');
        app(TenantContext::class)->set($tenantB);
        $categoryB = ServiceCategory::query()->create(['branch_id' => $branchB->id, 'name' => 'Beard', 'slug' => 'beard', 'status' => BusinessStatus::ACTIVE]);
        $serviceB = Service::query()->create(['branch_id' => $branchB->id, 'category_id' => $categoryB->id, 'name' => 'Trim', 'slug' => 'trim', 'gender' => GenderType::MALE, 'price' => '150.00', 'duration_minutes' => 20, 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();
        $api = $this->actingAs($ownerA, 'sanctum')->withHeader('X-Tenant-Slug', $tenantA->slug);
        $api->getJson('/api/v1/service-categories/'.$categoryB->id)->assertNotFound();
        $api->patchJson('/api/v1/service-categories/'.$categoryB->id, ['branch_id' => $branchA->id, 'name' => 'Hack'])->assertNotFound();
        $api->deleteJson('/api/v1/service-categories/'.$categoryB->id)->assertNotFound();
        $api->getJson('/api/v1/services/'.$serviceB->id)->assertNotFound();
        $api->patchJson('/api/v1/services/'.$serviceB->id, ['branch_id' => $branchA->id, 'category_id' => $categoryB->id, 'name' => 'Hack'])->assertUnprocessable();
        $api->deleteJson('/api/v1/services/'.$serviceB->id)->assertNotFound();
    }

    private function fixture(string $slug): array
    {
        $tenant = Tenant::query()->create(['name' => $slug, 'slug' => $slug]);
        $owner = User::factory()->create(['role' => UserRole::SALON_OWNER]);
        $tenant->users()->attach($owner, ['role' => TenantMembershipRole::SALON_OWNER->value]);
        app(TenantContext::class)->set($tenant);
        $salon = Salon::query()->create(['name' => $slug, 'slug' => $slug, 'gender_type' => GenderType::UNISEX, 'status' => BusinessStatus::ACTIVE]);
        $branch = Branch::query()->create(['salon_id' => $salon->id, 'name' => 'Main', 'slug' => 'main', 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();

        return [$tenant, $owner, $branch];
    }
}
