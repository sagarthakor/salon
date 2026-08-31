<?php

namespace Tests\Feature;

use App\Enums\BusinessStatus;
use App\Enums\GenderType;
use App\Enums\TenantMembershipRole;
use App\Enums\UserRole;
use App\Models\Branch;
use App\Models\BranchHoliday;
use App\Models\Salon;
use App\Models\SalonSetting;
use App\Models\Tenant;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class SalonManagementApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_owner_can_create_read_update_salon_and_manage_supported_settings(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('royal');
        $client = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $client->postJson('/api/v1/salon', ['name' => 'Royal Gents', 'gender_type' => 'male', 'email' => 'hello@royal.test', 'timezone' => 'Asia/Kolkata'])->assertCreated()->assertJsonPath('data.slug', 'royal-gents')->assertJsonPath('data.status', 'active');
        $client->getJson('/api/v1/salon')->assertOk()->assertJsonPath('data.name', 'Royal Gents');
        $client->patchJson('/api/v1/salon', ['name' => 'Royal Gents Updated', 'slug' => 'royal-gents', 'gender_type' => 'unisex', 'status' => 'inactive'])->assertOk()->assertJsonPath('data.gender_type', 'unisex');
        $client->putJson('/api/v1/salon/settings', ['settings' => ['booking_enabled' => true, 'default_timezone' => 'Asia/Kolkata']])->assertOk()->assertJsonPath('data.booking_enabled', true);
        $client->putJson('/api/v1/salon/settings', ['settings' => ['online_payment_enabled' => true]])->assertUnprocessable();
    }

    /**
     * Real-device QA bug fix: `GET /salon/settings` for a salon that has
     * never had its booking settings saved returned an empty array
     * (`SalonSettingsResource` on a zero-row `salon_settings` collection),
     * which PHP/Laravel serializes as a JSON array (`[]`) rather than an
     * object (`{}`) — the Flutter client's `Map<String, dynamic>` cast then
     * threw a raw `TypeError`, surfacing as "Could not load settings" with
     * no useful information. `SalonSettingsResource` now always merges in
     * sensible defaults, which both fixes the array/object bug (the
     * response can never be empty) and gives a new salon usable settings
     * immediately, per the actual product requirement.
     */
    public function test_a_brand_new_salons_booking_settings_have_sensible_defaults_and_are_never_an_empty_array(): void
    {
        [$tenant, $owner, $salon] = $this->tenantWithSalon('freshsettings');
        $client = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $response = $client->getJson('/api/v1/salon/settings')->assertOk();
        $response->assertJsonPath('data.booking_enabled', true)
            ->assertJsonPath('data.customer_booking_enabled', true)
            ->assertJsonPath('data.slot_interval_minutes', 15)
            ->assertJsonPath('data.min_advance_booking_minutes', 0)
            ->assertJsonPath('data.max_advance_booking_days', 30)
            ->assertJsonPath('data.booking_buffer_minutes', 0)
            ->assertJsonPath('data.cancellation_window_minutes', 0);

        // The literal bug: an empty PHP array json_encodes as `[]`, not
        // `{}` — assert the raw response body is genuinely object-shaped,
        // not just that Laravel's test helpers happened to tolerate either.
        $this->assertStringContainsString('"data":{', $response->getContent());
        $this->assertStringNotContainsString('"data":[]', $response->getContent());

        app(TenantContext::class)->set($tenant);
        $this->assertSame(0, SalonSetting::query()->count(), 'Defaults must not be persisted until the owner actually saves something.');
        app(TenantContext::class)->clear();
    }

    /**
     * Saving only one setting must not blow away the defaults for every
     * other key — both the fresh GET and the PUT's own response reflect the
     * same fully-merged shape.
     */
    public function test_updating_one_booking_setting_leaves_the_others_at_their_defaults(): void
    {
        [$tenant, $owner] = $this->tenantWithSalon('partialsettings');
        $client = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);

        $client->putJson('/api/v1/salon/settings', ['settings' => ['slot_interval_minutes' => 20]])
            ->assertOk()
            ->assertJsonPath('data.slot_interval_minutes', 20)
            ->assertJsonPath('data.booking_enabled', true)
            ->assertJsonPath('data.max_advance_booking_days', 30);

        $client->getJson('/api/v1/salon/settings')->assertOk()
            ->assertJsonPath('data.slot_interval_minutes', 20)
            ->assertJsonPath('data.cancellation_window_minutes', 0);
    }

    public function test_booking_settings_are_tenant_isolated(): void
    {
        [$tenantA, $ownerA] = $this->tenantWithSalon('settingsa');
        [$tenantB, $ownerB] = $this->tenantWithSalon('settingsb');

        $this->actingAs($ownerA, 'sanctum')->withHeader('X-Tenant-Slug', $tenantA->slug)
            ->putJson('/api/v1/salon/settings', ['settings' => ['slot_interval_minutes' => 45]])->assertOk();

        // Tenant B never touched its settings — still the untouched default,
        // never tenant A's saved value.
        $this->actingAs($ownerB, 'sanctum')->withHeader('X-Tenant-Slug', $tenantB->slug)
            ->getJson('/api/v1/salon/settings')->assertOk()
            ->assertJsonPath('data.slot_interval_minutes', 15);
    }

    public function test_salon_validation_and_owner_authorization_are_enforced(): void
    {
        [$tenant, $owner] = $this->tenantWithOwner('validate');
        $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug)->postJson('/api/v1/salon', ['name' => '', 'gender_type' => 'unknown', 'latitude' => 100])->assertUnprocessable()->assertJsonPath('success', false);

        $staff = User::factory()->create(['role' => UserRole::STAFF]);
        $tenant->users()->attach($staff, ['role' => TenantMembershipRole::STAFF->value]);
        $this->actingAs($staff, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug)->postJson('/api/v1/salon', ['name' => 'Forbidden', 'gender_type' => 'male', 'timezone' => 'Asia/Kolkata'])->assertForbidden();
    }

    public function test_owner_can_manage_branches_working_hours_and_holidays(): void
    {
        [$tenant, $owner, $salon] = $this->tenantWithSalon('manage');
        $client = $this->actingAs($owner, 'sanctum')->withHeader('X-Tenant-Slug', $tenant->slug);
        $client->postJson('/api/v1/branches', ['name' => '', 'latitude' => 91])->assertUnprocessable();
        $branch = $client->postJson('/api/v1/branches', ['name' => 'Manjalpur', 'city' => 'Vadodara', 'timezone' => 'Asia/Kolkata', 'tenant_id' => 'untrusted', 'salon_id' => 'untrusted'])->assertCreated()->assertJsonPath('data.slug', 'manjalpur')->json('data');
        $branchId = $branch['id'];
        $this->assertDatabaseHas('branches', ['id' => $branchId, 'tenant_id' => $tenant->id, 'salon_id' => $salon->id]);
        $client->getJson("/api/v1/branches/$branchId")->assertOk()->assertJsonPath('data.name', 'Manjalpur');
        $client->patchJson("/api/v1/branches/$branchId", ['name' => 'Manjalpur Main', 'slug' => 'manjalpur', 'status' => 'inactive'])->assertOk()->assertJsonPath('data.status', 'inactive');
        $client->putJson("/api/v1/branches/$branchId/working-hours", ['hours' => [['day_of_week' => 1, 'is_open' => true, 'opening_time' => '10:00', 'closing_time' => '20:00'], ['day_of_week' => 0, 'is_open' => false]]])->assertOk()->assertJsonCount(2, 'data');
        $client->putJson("/api/v1/branches/$branchId/working-hours", ['hours' => [['day_of_week' => 1, 'is_open' => true, 'opening_time' => '20:00', 'closing_time' => '10:00']]])->assertUnprocessable();
        $client->putJson("/api/v1/branches/$branchId/working-hours", ['hours' => [['day_of_week' => 1, 'is_open' => false, 'opening_time' => '10:00'], ['day_of_week' => 1, 'is_open' => false]]])->assertUnprocessable();
        $holiday = $client->postJson("/api/v1/branches/$branchId/holidays", ['holiday_date' => '2026-08-15', 'name' => 'Independence Day'])->assertCreated()->assertJsonPath('data.is_closed', true)->json('data');
        $client->postJson("/api/v1/branches/$branchId/holidays", ['holiday_date' => '2026-08-15', 'name' => 'Duplicate'])->assertUnprocessable();
        $client->patchJson("/api/v1/branches/$branchId/holidays/{$holiday['id']}", ['holiday_date' => '2026-08-16', 'name' => 'Updated Holiday', 'is_closed' => false])->assertOk()->assertJsonPath('data.name', 'Updated Holiday');
        $client->deleteJson("/api/v1/branches/$branchId/holidays/{$holiday['id']}")->assertOk();
        $client->deleteJson("/api/v1/branches/$branchId")->assertOk();
        $this->assertSoftDeleted('branches', ['id' => $branchId]);
    }

    public function test_tenant_a_cannot_access_tenant_b_salon_branch_hours_or_holidays_by_direct_id(): void
    {
        [$tenantA, $ownerA, $salonA, $branchA] = $this->tenantWithSalon('salon-a', true);
        [$tenantB, $ownerB, $salonB, $branchB] = $this->tenantWithSalon('salon-b', true);
        $holidayB = $this->createHoliday($branchB, '2026-12-25');
        $client = $this->actingAs($ownerA, 'sanctum')->withHeader('X-Tenant-Slug', $tenantA->slug);

        $client->getJson('/api/v1/salon')->assertOk()->assertJsonPath('data.id', $salonA->id);
        $client->withHeader('X-Tenant-Slug', $tenantB->slug)->getJson('/api/v1/salon')->assertForbidden();
        $client->withHeader('X-Tenant-Slug', $tenantA->slug)->getJson("/api/v1/branches/{$branchB->id}")->assertNotFound();
        $client->patchJson("/api/v1/branches/{$branchB->id}", ['name' => 'Hijacked'])->assertNotFound();
        $client->deleteJson("/api/v1/branches/{$branchB->id}")->assertNotFound();
        $client->getJson("/api/v1/branches/{$branchB->id}/working-hours")->assertNotFound();
        $client->getJson("/api/v1/branches/{$branchB->id}/holidays")->assertNotFound();
        $client->patchJson("/api/v1/branches/{$branchB->id}/holidays/{$holidayB->id}", ['holiday_date' => '2026-12-26', 'name' => 'Hijacked'])->assertNotFound();
        $client->deleteJson("/api/v1/branches/{$branchB->id}/holidays/{$holidayB->id}")->assertNotFound();
        $this->assertDatabaseHas('branches', ['id' => $branchB->id]);
    }

    private function tenantWithOwner(string $slug): array
    {
        $tenant = Tenant::query()->create(['name' => ucfirst($slug), 'slug' => $slug]);
        $owner = User::factory()->create(['role' => UserRole::SALON_OWNER]);
        $tenant->users()->attach($owner, ['role' => TenantMembershipRole::SALON_OWNER->value]);

        return [$tenant, $owner];
    }

    private function tenantWithSalon(string $slug, bool $withBranch = false): array
    {
        [$tenant, $owner] = $this->tenantWithOwner($slug);
        app(TenantContext::class)->set($tenant);
        $salon = Salon::query()->create(['name' => ucfirst($slug), 'slug' => $slug, 'gender_type' => GenderType::UNISEX, 'status' => BusinessStatus::ACTIVE]);
        $branch = $withBranch ? Branch::query()->create(['salon_id' => $salon->id, 'name' => 'Main', 'slug' => 'main', 'status' => BusinessStatus::ACTIVE]) : null;
        app(TenantContext::class)->clear();

        return [$tenant, $owner, $salon, $branch];
    }

    private function createHoliday(Branch $branch, string $date): BranchHoliday
    {
        app(TenantContext::class)->set($branch->tenant);
        $holiday = BranchHoliday::query()->create(['branch_id' => $branch->id, 'holiday_date' => $date, 'name' => 'Closed']);
        app(TenantContext::class)->clear();

        return $holiday;
    }
}
