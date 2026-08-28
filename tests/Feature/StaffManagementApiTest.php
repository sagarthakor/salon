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

class StaffManagementApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_owner_can_create_read_update_and_deactivate_staff(): void
    {
        [$tenant, $owner, , $branch] = $this->fixture('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $staff = $api->postJson('/api/v1/staff', [
            'name' => 'Rahul',
            'gender' => 'male',
            'phone' => '9998887777',
            'joining_date' => '2026-01-15',
            'branch_ids' => [$branch->id],
            'commission_type' => 'percentage',
            'commission_value' => 10,
        ])->assertCreated()->assertJsonPath('data.name', 'Rahul')->assertJsonPath('data.status', 'active')->assertJsonPath('data.branches.0.id', $branch->id)->json('data');

        $api->getJson('/api/v1/staff/'.$staff['id'])->assertOk()->assertJsonPath('data.name', 'Rahul');
        $api->getJson('/api/v1/staff')->assertOk()->assertJsonPath('data.0.id', $staff['id']);

        $api->patchJson('/api/v1/staff/'.$staff['id'], [
            'name' => 'Rahul Verma',
            'gender' => 'male',
            'status' => 'inactive',
            'branch_ids' => [$branch->id],
        ])->assertOk()->assertJsonPath('data.name', 'Rahul Verma')->assertJsonPath('data.status', 'inactive');

        $api->deleteJson('/api/v1/staff/'.$staff['id'])->assertOk();
        $this->assertSoftDeleted('staff_profiles', ['id' => $staff['id']]);
    }

    public function test_staff_validation_rejects_bad_input_and_foreign_branch(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        [, , , $otherBranch] = $this->fixture('b');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $api->postJson('/api/v1/staff', ['name' => '', 'gender' => 'invalid'])->assertUnprocessable();
        $api->postJson('/api/v1/staff', ['name' => 'Priya', 'gender' => 'female', 'branch_ids' => [$otherBranch->id]])->assertUnprocessable();
        $api->postJson('/api/v1/staff', ['name' => 'Priya', 'gender' => 'female', 'commission_type' => 'percentage', 'commission_value' => 150])->assertUnprocessable();
    }

    public function test_owner_can_assign_services_and_rejects_service_outside_assigned_branch(): void
    {
        [$tenant, $owner, $branch, $branch2] = $this->fixtureWithTwoBranches('a');
        app(TenantContext::class)->set($tenant);
        $category = ServiceCategory::query()->create(['branch_id' => $branch->id, 'name' => 'Hair', 'slug' => 'hair', 'status' => BusinessStatus::ACTIVE]);
        $service = Service::query()->create(['branch_id' => $branch->id, 'category_id' => $category->id, 'name' => 'Haircut', 'slug' => 'haircut', 'gender' => GenderType::MALE, 'price' => '300.00', 'duration_minutes' => 30, 'status' => BusinessStatus::ACTIVE]);
        $category2 = ServiceCategory::query()->create(['branch_id' => $branch2->id, 'name' => 'Spa', 'slug' => 'spa', 'status' => BusinessStatus::ACTIVE]);
        $foreignBranchService = Service::query()->create(['branch_id' => $branch2->id, 'category_id' => $category2->id, 'name' => 'Hair Spa', 'slug' => 'hair-spa', 'gender' => GenderType::FEMALE, 'price' => '500.00', 'duration_minutes' => 60, 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();

        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $staffId = $api->postJson('/api/v1/staff', ['name' => 'Rahul', 'gender' => 'male', 'branch_ids' => [$branch->id]])->assertCreated()->json('data.id');

        $api->putJson("/api/v1/staff/$staffId/services", ['service_ids' => [$service->id]])->assertOk()->assertJsonPath('data.0.id', $service->id);
        $api->getJson("/api/v1/staff/$staffId/services")->assertOk()->assertJsonCount(1, 'data');
        $api->putJson("/api/v1/staff/$staffId/services", ['service_ids' => [$foreignBranchService->id]])->assertUnprocessable();
    }

    public function test_owner_can_manage_working_hours_and_breaks_with_validation(): void
    {
        [$tenant, $owner, , $branch] = $this->fixture('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $staffId = $api->postJson('/api/v1/staff', ['name' => 'Priya', 'gender' => 'female', 'branch_ids' => [$branch->id]])->assertCreated()->json('data.id');

        $api->putJson("/api/v1/staff/$staffId/working-hours", ['hours' => [
            ['day_of_week' => 1, 'is_working' => true, 'start_time' => '10:00', 'end_time' => '19:00'],
            ['day_of_week' => 2, 'is_working' => false],
        ]])->assertOk()->assertJsonCount(2, 'data');

        $api->putJson("/api/v1/staff/$staffId/working-hours", ['hours' => [
            ['day_of_week' => 1, 'is_working' => true, 'start_time' => '19:00', 'end_time' => '10:00'],
        ]])->assertUnprocessable();

        $api->putJson("/api/v1/staff/$staffId/working-hours", ['hours' => [
            ['day_of_week' => 1, 'is_working' => true, 'start_time' => '10:00', 'end_time' => '19:00'],
            ['day_of_week' => 1, 'is_working' => false],
        ]])->assertUnprocessable();

        $api->putJson("/api/v1/staff/$staffId/working-hours", ['hours' => [
            ['day_of_week' => 1, 'is_working' => true, 'start_time' => '10:00', 'end_time' => '19:00'],
            ['day_of_week' => 2, 'is_working' => false],
        ]])->assertOk();

        $breakId = $api->postJson("/api/v1/staff/$staffId/breaks", ['day_of_week' => 1, 'start_time' => '13:00', 'end_time' => '14:00'])->assertCreated()->assertJsonPath('data.start_time', '13:00')->json('data.id');

        $api->postJson("/api/v1/staff/$staffId/breaks", ['day_of_week' => 2, 'start_time' => '13:00', 'end_time' => '14:00'])->assertUnprocessable();
        $api->postJson("/api/v1/staff/$staffId/breaks", ['day_of_week' => 1, 'start_time' => '09:00', 'end_time' => '09:30'])->assertUnprocessable();
        $api->postJson("/api/v1/staff/$staffId/breaks", ['day_of_week' => 1, 'start_time' => '13:30', 'end_time' => '14:30'])->assertUnprocessable();

        $api->patchJson("/api/v1/staff/$staffId/breaks/$breakId", ['day_of_week' => 1, 'start_time' => '13:00', 'end_time' => '13:30'])->assertOk()->assertJsonPath('data.end_time', '13:30');
        $api->getJson("/api/v1/staff/$staffId/breaks")->assertOk()->assertJsonCount(1, 'data');
        $api->deleteJson("/api/v1/staff/$staffId/breaks/$breakId")->assertOk();
        $api->getJson("/api/v1/staff/$staffId/breaks")->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_owner_can_manage_leave_with_overlap_validation(): void
    {
        [$tenant, $owner, , $branch] = $this->fixture('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $staffId = $api->postJson('/api/v1/staff', ['name' => 'Rahul', 'gender' => 'male', 'branch_ids' => [$branch->id]])->assertCreated()->json('data.id');

        $leaveId = $api->postJson("/api/v1/staff/$staffId/leaves", ['start_date' => '2026-09-15', 'end_date' => '2026-09-15', 'reason' => 'Personal work'])->assertCreated()->assertJsonPath('data.status', 'approved')->json('data.id');
        $api->postJson("/api/v1/staff/$staffId/leaves", ['start_date' => '2026-09-15', 'end_date' => '2026-09-16', 'reason' => 'Overlap'])->assertUnprocessable();
        $api->postJson("/api/v1/staff/$staffId/leaves", ['start_date' => '2026-09-20', 'end_date' => '2026-09-10'])->assertUnprocessable();
        $api->getJson("/api/v1/staff/$staffId/leaves")->assertOk()->assertJsonCount(1, 'data');
        $api->patchJson("/api/v1/staff/$staffId/leaves/$leaveId", ['start_date' => '2026-09-16', 'end_date' => '2026-09-16'])->assertOk()->assertJsonPath('data.start_date', '2026-09-16');
        $api->deleteJson("/api/v1/staff/$staffId/leaves/$leaveId")->assertOk();
        $api->getJson("/api/v1/staff/$staffId/leaves")->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_staff_member_can_view_own_records_but_not_modify_or_view_others(): void
    {
        [$tenant, $owner, , $branch] = $this->fixture('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $staffUser = User::factory()->create(['role' => UserRole::STAFF]);
        $tenant->users()->attach($staffUser, ['role' => TenantMembershipRole::STAFF->value]);
        $staff = $api->postJson('/api/v1/staff', ['name' => 'Rahul', 'gender' => 'male', 'user_id' => $staffUser->id, 'branch_ids' => [$branch->id]])->assertCreated()->json('data');

        $otherStaff = $api->postJson('/api/v1/staff', ['name' => 'Priya', 'gender' => 'female', 'branch_ids' => [$branch->id]])->assertCreated()->json('data');

        $staffApi = $this->actingAs($staffUser, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $staffApi->getJson('/api/v1/staff/'.$staff['id'])->assertOk()->assertJsonPath('data.id', $staff['id']);
        $staffApi->getJson('/api/v1/staff/'.$staff['id'].'/services')->assertOk();
        $staffApi->getJson('/api/v1/staff/'.$staff['id'].'/working-hours')->assertOk();
        $staffApi->getJson('/api/v1/staff/'.$staff['id'].'/leaves')->assertOk();

        $staffApi->getJson('/api/v1/staff/'.$otherStaff['id'])->assertForbidden();
        $staffApi->patchJson('/api/v1/staff/'.$staff['id'], ['name' => 'Hacked', 'gender' => 'male'])->assertForbidden();
        $staffApi->postJson('/api/v1/staff', ['name' => 'New', 'gender' => 'male'])->assertForbidden();
        $staffApi->deleteJson('/api/v1/staff/'.$staff['id'])->assertForbidden();
    }

    public function test_staff_me_resolves_own_profile_and_never_another_staff_members(): void
    {
        [$tenant, $owner, , $branch] = $this->fixture('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $staffUser = User::factory()->create(['role' => UserRole::STAFF]);
        $tenant->users()->attach($staffUser, ['role' => TenantMembershipRole::STAFF->value]);
        $staff = $api->postJson('/api/v1/staff', ['name' => 'Rahul', 'gender' => 'male', 'user_id' => $staffUser->id, 'branch_ids' => [$branch->id]])->assertCreated()->json('data');
        $api->postJson('/api/v1/staff', ['name' => 'Priya', 'gender' => 'female', 'branch_ids' => [$branch->id]])->assertCreated();

        $staffApi = $this->actingAs($staffUser, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $staffApi->getJson('/api/v1/staff/me')
            ->assertOk()
            ->assertJsonPath('data.id', $staff['id'])
            ->assertJsonPath('data.name', 'Rahul')
            ->assertJsonPath('data.branches.0.id', $branch->id);
    }

    public function test_staff_me_returns_404_when_the_authenticated_user_has_no_linked_staff_profile(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        // The owner is a tenant member but has no staff_profiles row of their own.
        $api->getJson('/api/v1/staff/me')->assertNotFound()->assertJsonPath('message', 'No staff profile is linked to your account.');

        $staffUser = User::factory()->create(['role' => UserRole::STAFF]);
        $tenant->users()->attach($staffUser, ['role' => TenantMembershipRole::STAFF->value]);
        $this->actingAs($staffUser, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug)
            ->getJson('/api/v1/staff/me')->assertNotFound();
    }

    public function test_staff_me_is_scoped_per_tenant_for_a_user_with_profiles_in_two_tenants(): void
    {
        [$tenantA, $ownerA, , $branchA] = $this->fixture('a');
        [$tenantB, $ownerB, , $branchB] = $this->fixture('b');

        $staffUser = User::factory()->create(['role' => UserRole::STAFF]);
        $tenantA->users()->attach($staffUser, ['role' => TenantMembershipRole::STAFF->value]);
        $tenantB->users()->attach($staffUser, ['role' => TenantMembershipRole::STAFF->value]);

        $staffA = $this->actingAs($ownerA, 'sanctum')->withHeader('X-Tenant-Slug', $tenantA->slug)
            ->postJson('/api/v1/staff', ['name' => 'Rahul in A', 'gender' => 'male', 'user_id' => $staffUser->id, 'branch_ids' => [$branchA->id]])
            ->assertCreated()->json('data');
        $staffB = $this->actingAs($ownerB, 'sanctum')->withHeader('X-Tenant-Slug', $tenantB->slug)
            ->postJson('/api/v1/staff', ['name' => 'Rahul in B', 'gender' => 'male', 'user_id' => $staffUser->id, 'branch_ids' => [$branchB->id]])
            ->assertCreated()->json('data');

        $staffApi = $this->actingAs($staffUser, 'sanctum');
        $staffApi->withHeader('X-Tenant-Slug', $tenantA->slug)->getJson('/api/v1/staff/me')->assertOk()->assertJsonPath('data.id', $staffA['id']);
        $staffApi->withHeader('X-Tenant-Slug', $tenantB->slug)->getJson('/api/v1/staff/me')->assertOk()->assertJsonPath('data.id', $staffB['id']);
    }

    public function test_customer_cannot_access_staff_endpoints(): void
    {
        [$tenant] = $this->fixture('a');
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $this->actingAs($customer, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug)->getJson('/api/v1/staff')->assertForbidden();
    }

    public function test_tenant_a_cannot_access_tenant_b_staff_by_direct_id(): void
    {
        [$tenantA, $ownerA] = $this->fixture('a');
        [$tenantB, $ownerB, , $branchB] = $this->fixture('b');
        $apiB = $this->actingAs($ownerB, 'sanctum')->withHeader('X-Tenant-Slug', $tenantB->slug);
        $staffB = $apiB->postJson('/api/v1/staff', ['name' => 'Foreign', 'gender' => 'male', 'branch_ids' => [$branchB->id]])->assertCreated()->json('data');
        $breakB = $apiB->putJson("/api/v1/staff/{$staffB['id']}/working-hours", ['hours' => [['day_of_week' => 1, 'is_working' => true, 'start_time' => '10:00', 'end_time' => '19:00']]])->assertOk();
        $breakIdB = $apiB->postJson("/api/v1/staff/{$staffB['id']}/breaks", ['day_of_week' => 1, 'start_time' => '13:00', 'end_time' => '14:00'])->assertCreated()->json('data.id');
        $leaveIdB = $apiB->postJson("/api/v1/staff/{$staffB['id']}/leaves", ['start_date' => '2026-10-01', 'end_date' => '2026-10-01'])->assertCreated()->json('data.id');

        $apiA = $this->actingAs($ownerA, 'sanctum')->withHeader('X-Tenant-Slug', $tenantA->slug);
        $apiA->getJson('/api/v1/staff/'.$staffB['id'])->assertNotFound();
        $apiA->patchJson('/api/v1/staff/'.$staffB['id'], ['name' => 'Hijacked', 'gender' => 'male'])->assertNotFound();
        $apiA->deleteJson('/api/v1/staff/'.$staffB['id'])->assertNotFound();
        $apiA->getJson("/api/v1/staff/{$staffB['id']}/services")->assertNotFound();
        $apiA->putJson("/api/v1/staff/{$staffB['id']}/services", ['service_ids' => []])->assertNotFound();
        $apiA->getJson("/api/v1/staff/{$staffB['id']}/working-hours")->assertNotFound();
        $apiA->getJson("/api/v1/staff/{$staffB['id']}/breaks")->assertNotFound();
        $apiA->patchJson("/api/v1/staff/{$staffB['id']}/breaks/$breakIdB", ['day_of_week' => 1, 'start_time' => '13:00', 'end_time' => '14:00'])->assertNotFound();
        $apiA->deleteJson("/api/v1/staff/{$staffB['id']}/breaks/$breakIdB")->assertNotFound();
        $apiA->getJson("/api/v1/staff/{$staffB['id']}/leaves")->assertNotFound();
        $apiA->deleteJson("/api/v1/staff/{$staffB['id']}/leaves/$leaveIdB")->assertNotFound();
        $this->assertDatabaseHas('staff_profiles', ['id' => $staffB['id']]);
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

        return [$tenant, $owner, $salon, $branch];
    }

    private function fixtureWithTwoBranches(string $slug): array
    {
        [$tenant, $owner, $salon, $branch] = $this->fixture($slug);
        app(TenantContext::class)->set($tenant);
        $branch2 = Branch::query()->create(['salon_id' => $salon->id, 'name' => 'Second', 'slug' => 'second', 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();

        return [$tenant, $owner, $branch, $branch2];
    }
}
