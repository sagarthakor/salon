<?php

namespace Tests\Feature;

use App\Enums\BusinessStatus;
use App\Enums\GenderType;
use App\Enums\TenantMembershipRole;
use App\Enums\UserRole;
use App\Models\Branch;
use App\Models\Salon;
use App\Models\Tenant;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class CustomerManagementApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_owner_can_create_read_update_and_delete_customer(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $customer = $api->postJson('/api/v1/customers', [
            'name' => 'Anita',
            'phone' => '9876543210',
            'country_code' => '+91',
            'email' => 'anita@example.test',
            'gender' => 'female',
            'date_of_birth' => '1995-05-10',
        ])->assertCreated()->assertJsonPath('data.name', 'Anita')->assertJsonPath('data.status', 'active')->json('data');

        $api->getJson('/api/v1/customers/'.$customer['id'])->assertOk()->assertJsonPath('data.name', 'Anita');
        $api->getJson('/api/v1/customers')->assertOk()->assertJsonPath('data.0.id', $customer['id']);

        $api->patchJson('/api/v1/customers/'.$customer['id'], [
            'name' => 'Anita Sharma',
            'phone' => '9876543210',
            'country_code' => '+91',
            'status' => 'inactive',
        ])->assertOk()->assertJsonPath('data.name', 'Anita Sharma')->assertJsonPath('data.status', 'inactive');

        $api->deleteJson('/api/v1/customers/'.$customer['id'])->assertOk();
        $this->assertSoftDeleted('customer_profiles', ['id' => $customer['id']]);
        $api->getJson('/api/v1/customers')->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_customer_validation_rejects_bad_input(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $api->postJson('/api/v1/customers', ['name' => '', 'phone' => ''])->assertUnprocessable();
        $api->postJson('/api/v1/customers', ['name' => 'Bad', 'phone' => '123', 'gender' => 'invalid'])->assertUnprocessable();
    }

    public function test_duplicate_phone_within_tenant_is_rejected_but_allowed_across_tenants(): void
    {
        [$tenantA, $ownerA] = $this->fixture('a');
        [$tenantB, $ownerB] = $this->fixture('b');
        $apiA = $this->actingAs($ownerA, 'sanctum')->withHeader('X-Tenant-Slug', $tenantA->slug);
        $apiA->postJson('/api/v1/customers', ['name' => 'Ravi', 'phone' => '9876543210'])->assertCreated();
        $apiA->postJson('/api/v1/customers', ['name' => 'Ravi Duplicate', 'phone' => '(987) 654-3210'])->assertUnprocessable();

        $apiB = $this->actingAs($ownerB, 'sanctum')->withHeader('X-Tenant-Slug', $tenantB->slug);
        $apiB->postJson('/api/v1/customers', ['name' => 'Ravi', 'phone' => '9876543210'])->assertCreated();
    }

    public function test_search_and_filters(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $api->postJson('/api/v1/customers', ['name' => 'Neha Gupta', 'phone' => '9111111111', 'email' => 'neha@example.test', 'gender' => 'female', 'status' => 'active'])->assertCreated();
        $api->postJson('/api/v1/customers', ['name' => 'Karan Mehta', 'phone' => '9222222222', 'email' => 'karan@example.test', 'gender' => 'male', 'status' => 'inactive'])->assertCreated();

        $api->getJson('/api/v1/customers?search=Neha')->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.name', 'Neha Gupta');
        $api->getJson('/api/v1/customers?search=9222222222')->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.name', 'Karan Mehta');
        $api->getJson('/api/v1/customers?search=karan@example.test')->assertOk()->assertJsonCount(1, 'data');
        $api->getJson('/api/v1/customers?gender=male')->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.name', 'Karan Mehta');
        $api->getJson('/api/v1/customers?status=inactive')->assertOk()->assertJsonCount(1, 'data');
    }

    public function test_owner_can_manage_customer_notes(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $customerId = $api->postJson('/api/v1/customers', ['name' => 'Anita', 'phone' => '9876543210'])->assertCreated()->json('data.id');

        $noteId = $api->postJson("/api/v1/customers/$customerId/notes", ['body' => 'Prefers short haircut.'])->assertCreated()->assertJsonPath('data.body', 'Prefers short haircut.')->assertJsonPath('data.author.id', $owner->id)->json('data.id');
        $api->getJson("/api/v1/customers/$customerId/notes")->assertOk()->assertJsonCount(1, 'data');
        $api->patchJson("/api/v1/customers/$customerId/notes/$noteId", ['body' => 'Prefers short haircut, sensitive scalp.'])->assertOk()->assertJsonPath('data.body', 'Prefers short haircut, sensitive scalp.');
        $api->deleteJson("/api/v1/customers/$customerId/notes/$noteId")->assertOk();
        $api->getJson("/api/v1/customers/$customerId/notes")->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_customer_summary_returns_real_zeros_for_a_customer_with_no_bookings(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $api = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $customerId = $api->postJson('/api/v1/customers', ['name' => 'Anita', 'phone' => '9876543210'])->assertCreated()->json('data.id');

        $api->getJson("/api/v1/customers/$customerId/summary")->assertOk()
            ->assertJsonPath('data.customer.id', $customerId)
            ->assertJsonPath('data.summary.total_visits', 0)
            ->assertJsonPath('data.summary.completed_appointments', 0)
            ->assertJsonPath('data.summary.total_spent', '0.00')
            ->assertJsonPath('data.summary.last_visit_at', null)
            ->assertJsonPath('data.summary.upcoming_appointment', null);
    }

    public function test_staff_has_read_only_access_and_customer_role_is_forbidden(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $ownerApi = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $customerId = $ownerApi->postJson('/api/v1/customers', ['name' => 'Anita', 'phone' => '9876543210'])->assertCreated()->json('data.id');

        $staffUser = User::factory()->create(['role' => UserRole::STAFF]);
        $tenant->users()->attach($staffUser, ['role' => TenantMembershipRole::STAFF->value]);
        $staffApi = $this->actingAs($staffUser, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $staffApi->getJson('/api/v1/customers')->assertOk();
        $staffApi->getJson('/api/v1/customers/'.$customerId)->assertOk();
        $staffApi->postJson('/api/v1/customers', ['name' => 'New', 'phone' => '9333333333'])->assertForbidden();
        $staffApi->patchJson('/api/v1/customers/'.$customerId, ['name' => 'Hacked', 'phone' => '9876543210'])->assertForbidden();
        $staffApi->deleteJson('/api/v1/customers/'.$customerId)->assertForbidden();
        $staffApi->getJson('/api/v1/customers/'.$customerId.'/notes')->assertForbidden();
        $staffApi->getJson('/api/v1/customers/'.$customerId.'/summary')->assertForbidden();

        $platformCustomer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $this->actingAs($platformCustomer, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug)->getJson('/api/v1/customers')->assertForbidden();
    }

    public function test_customer_can_view_and_update_own_profile_via_self_service_endpoint(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $customerUser = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $ownerApi = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $customer = $ownerApi->postJson('/api/v1/customers', ['name' => 'Anita', 'phone' => '9876543210', 'user_id' => $customerUser->id])->assertCreated()->json('data');

        $selfApi = $this->actingAs($customerUser, 'sanctum');
        $selfApi->getJson('/api/v1/customer/profile')->assertOk()->assertJsonPath('data.id', $customer['id']);
        $selfApi->patchJson('/api/v1/customer/profile', ['name' => 'Anita R', 'phone' => '9876543210'])->assertOk()->assertJsonPath('data.name', 'Anita R');
        $selfApi->getJson('/api/v1/customer/profile')->assertOk()->assertJsonPath('data.name', 'Anita R');

        $unlinkedUser = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $this->actingAs($unlinkedUser, 'sanctum')->getJson('/api/v1/customer/profile')->assertNotFound();
    }

    public function test_customer_cannot_access_other_customer_or_owner_endpoints(): void
    {
        [$tenant, $owner] = $this->fixture('a');
        $customerUserA = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $customerUserB = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $ownerApi = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $customerA = $ownerApi->postJson('/api/v1/customers', ['name' => 'Anita', 'phone' => '9876543210', 'user_id' => $customerUserA->id])->assertCreated()->json('data');
        $ownerApi->postJson('/api/v1/customers', ['name' => 'Bina', 'phone' => '9111111112', 'user_id' => $customerUserB->id])->assertCreated();

        $this->actingAs($customerUserB, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug)->getJson('/api/v1/customers/'.$customerA['id'])->assertForbidden();
        $this->actingAs($customerUserB, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug)->getJson('/api/v1/customers')->assertForbidden();
    }

    public function test_tenant_a_cannot_access_tenant_b_customer_or_notes_by_direct_id(): void
    {
        [$tenantA, $ownerA] = $this->fixture('a');
        [$tenantB, $ownerB] = $this->fixture('b');
        $apiB = $this->actingAs($ownerB, 'sanctum')->withHeader('X-Tenant-Slug', $tenantB->slug);
        $customerB = $apiB->postJson('/api/v1/customers', ['name' => 'Foreign', 'phone' => '9000000000'])->assertCreated()->json('data');
        $noteB = $apiB->postJson("/api/v1/customers/{$customerB['id']}/notes", ['body' => 'Foreign note'])->assertCreated()->json('data');

        $apiA = $this->actingAs($ownerA, 'sanctum')->withHeader('X-Tenant-Slug', $tenantA->slug);
        $apiA->getJson('/api/v1/customers/'.$customerB['id'])->assertNotFound();
        $apiA->patchJson('/api/v1/customers/'.$customerB['id'], ['name' => 'Hijacked', 'phone' => '9000000000'])->assertNotFound();
        $apiA->deleteJson('/api/v1/customers/'.$customerB['id'])->assertNotFound();
        $apiA->getJson("/api/v1/customers/{$customerB['id']}/notes")->assertNotFound();
        $apiA->postJson("/api/v1/customers/{$customerB['id']}/notes", ['body' => 'Hijack'])->assertNotFound();
        $apiA->deleteJson("/api/v1/customers/{$customerB['id']}/notes/{$noteB['id']}")->assertNotFound();
        $apiA->getJson('/api/v1/customers/'.$customerB['id'].'/summary')->assertNotFound();
        $this->assertDatabaseHas('customer_profiles', ['id' => $customerB['id']]);
    }

    public function test_customer_can_list_only_the_salons_they_are_a_customer_of(): void
    {
        [$tenantA, $ownerA] = $this->fixture('a');
        [$tenantB, $ownerB] = $this->fixture('b');

        $customerUser = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $this->actingAs($ownerA, 'sanctum')->withHeader('X-Tenant-Slug', $tenantA->slug)
            ->postJson('/api/v1/customers', ['name' => 'Anita', 'phone' => '9876543210', 'user_id' => $customerUser->id])
            ->assertCreated();

        $unrelatedUser = User::factory()->create(['role' => UserRole::CUSTOMER]);

        $this->actingAs($customerUser, 'sanctum')->getJson('/api/v1/customer/salons')->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.tenant_slug', $tenantA->slug)
            ->assertJsonPath('data.0.salon.slug', $tenantA->slug)
            ->assertJsonPath('data.0.branches.0.name', 'Main');

        $this->actingAs($unrelatedUser, 'sanctum')->getJson('/api/v1/customer/salons')->assertOk()->assertJsonCount(0, 'data');
    }

    private function fixture(string $slug): array
    {
        $tenant = Tenant::query()->create(['name' => $slug, 'slug' => $slug]);
        $owner = User::factory()->create(['role' => UserRole::SALON_OWNER]);
        $tenant->users()->attach($owner, ['role' => TenantMembershipRole::SALON_OWNER->value]);
        app(TenantContext::class)->set($tenant);
        $salon = Salon::query()->create(['name' => $slug, 'slug' => $slug, 'gender_type' => GenderType::UNISEX, 'status' => BusinessStatus::ACTIVE]);
        Branch::query()->create(['salon_id' => $salon->id, 'name' => 'Main', 'slug' => 'main', 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();

        return [$tenant, $owner];
    }
}
