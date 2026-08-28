<?php

namespace Tests\Feature;

use App\Enums\BusinessStatus;
use App\Enums\GenderType;
use App\Enums\ServiceAudience;
use App\Enums\TenantMembershipRole;
use App\Enums\UserRole;
use App\Models\Booking;
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
use App\Support\TenantContext;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * A customer must be able to discover, browse, and book a salon entirely on
 * their own — a real-device QA finding showed the previous `/customer/salons`
 * (membership-only) endpoint left a brand-new customer with nothing to see,
 * even after a salon owner manually registered them. See
 * CUSTOMER_ARCHITECTURE.md, "Customer discovery and first-time booking", and
 * CustomerSalonController/CustomerBookingController::resolveOrCreateCustomer().
 */
class CustomerSalonDiscoveryApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_a_new_customer_with_zero_salon_memberships_discovers_active_salons_with_no_tenant_header(): void
    {
        $f = $this->fixture('a');
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);

        // No X-Tenant-Slug at all — discovery must not require one.
        $response = $this->actingAs($customer, 'sanctum')->getJson('/api/v1/customer/discover-salons')->assertOk();
        $response->assertJsonCount(1, 'data')->assertJsonPath('data.0.slug', $f['salon']->slug);
    }

    public function test_discovery_lists_multiple_active_salons_across_tenants_and_hides_inactive_ones(): void
    {
        $a = $this->fixture('a');
        $b = $this->fixture('b');
        $inactive = $this->fixture('c', salonStatus: BusinessStatus::INACTIVE);
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);

        $slugs = $this->actingAs($customer, 'sanctum')->getJson('/api/v1/customer/discover-salons')
            ->assertOk()->assertJsonCount(2, 'data')->json('data.*.slug');

        $this->assertContains($a['salon']->slug, $slugs);
        $this->assertContains($b['salon']->slug, $slugs);
        $this->assertNotContains($inactive['salon']->slug, $slugs);
    }

    public function test_a_customer_already_registered_by_a_salon_still_sees_it_in_discovery(): void
    {
        $f = $this->fixture('a');
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        app(TenantContext::class)->set($f['tenant']);
        Customer::query()->create(['user_id' => $customer->id, 'name' => 'Sagar', 'phone' => '9000000001', 'normalized_phone' => '9000000001', 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();

        $this->actingAs($customer, 'sanctum')->getJson('/api/v1/customer/discover-salons')
            ->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.slug', $f['salon']->slug);
    }

    public function test_discovery_never_exposes_owner_or_tenant_internal_fields(): void
    {
        $this->fixture('a');
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);

        $salon = $this->actingAs($customer, 'sanctum')->getJson('/api/v1/customer/discover-salons')->assertOk()->json('data.0');

        foreach (['tenant_id', 'owner_id', 'subscription', 'subscription_status', 'coupons', 'staff', 'customers'] as $forbidden) {
            $this->assertArrayNotHasKey($forbidden, $salon, "Discovery must never expose '{$forbidden}'.");
        }
    }

    public function test_salon_branch_discovery_returns_only_that_salons_active_branches_and_never_another_salons(): void
    {
        $a = $this->fixture('a');
        $b = $this->fixture('b');
        app(TenantContext::class)->set($a['tenant']);
        $inactiveBranch = Branch::query()->create(['salon_id' => $a['salon']->id, 'name' => 'Closed Branch', 'slug' => 'closed', 'status' => BusinessStatus::INACTIVE, 'timezone' => 'UTC']);
        app(TenantContext::class)->clear();
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);

        $branches = $this->actingAs($customer, 'sanctum')->getJson("/api/v1/customer/salons/{$a['salon']->id}/branches")
            ->assertOk()->json('data');

        $ids = collect($branches)->pluck('id');
        $this->assertContains($a['branch']->id, $ids);
        $this->assertNotContains($inactiveBranch->id, $ids, 'Inactive branches must never be discoverable.');
        $this->assertNotContains($b['branch']->id, $ids, 'A different salon\'s branch must never appear here.');
    }

    public function test_branch_discovery_for_an_inactive_salon_is_not_found(): void
    {
        $inactive = $this->fixture('a', salonStatus: BusinessStatus::INACTIVE);
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);

        $this->actingAs($customer, 'sanctum')->getJson("/api/v1/customer/salons/{$inactive['salon']->id}/branches")->assertNotFound();
    }

    public function test_the_full_discovery_funnel_reaches_the_existing_unmodified_audience_filtered_service_catalog(): void
    {
        $f = $this->fixture('a');
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $api = $this->actingAs($customer, 'sanctum');

        // Discover -> pick salon -> pick branch, using only server responses.
        $salon = $api->getJson('/api/v1/customer/discover-salons')->assertOk()->json('data.0');
        $branch = $api->getJson("/api/v1/customer/salons/{$salon['id']}/branches")->assertOk()->json('data.0');
        $this->assertSame($f['branch']->id, $branch['id']);

        // The existing, unmodified branch/service endpoint continues to
        // enforce audience filtering exactly as before.
        foreach (ServiceAudience::cases() as $audience) {
            $services = $api->getJson("/api/v1/branches/{$branch['id']}/services?audience={$audience->value}")
                ->assertOk()->json('data.services');
            $this->assertCount(1, $services);
            $this->assertSame($audience->value, $services[0]['audience']);
            $this->assertSame($f['services'][$audience->value]->id, $services[0]['id']);
        }
    }

    public function test_first_time_customer_can_book_and_it_automatically_creates_exactly_one_customer_profile(): void
    {
        $f = $this->fixture('a');
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER, 'name' => 'Sagar Thakor', 'email' => 'sagar@example.test']);
        app(TenantContext::class)->set($f['tenant']);
        $this->assertSame(0, Customer::where('user_id', $customer->id)->count());
        app(TenantContext::class)->clear();

        $booking = $this->actingAs($customer, 'sanctum')->postJson('/api/v1/customer/bookings', [
            'branch_id' => $f['branch']->id,
            'date' => $this->bookingDate(),
            'start_time' => '09:00',
            'items' => [['service_id' => $f['services']['unisex']->id, 'staff_id' => null]],
            'phone' => '9123456780',
        ])->assertCreated()->json('data');

        app(TenantContext::class)->set($f['tenant']);
        $profiles = Customer::where('user_id', $customer->id)->get();
        $this->assertCount(1, $profiles, 'Exactly one Customer profile must be auto-created.');
        $this->assertSame('Sagar Thakor', $profiles->first()->name);
        $this->assertSame($profiles->first()->id, Booking::withoutGlobalScope('tenant')->find($booking['id'])->customer_id);
        app(TenantContext::class)->clear();
    }

    public function test_a_first_time_booking_without_a_phone_is_rejected_cleanly_not_with_a_raw_exception(): void
    {
        $f = $this->fixture('a');
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);

        $this->actingAs($customer, 'sanctum')->postJson('/api/v1/customer/bookings', [
            'branch_id' => $f['branch']->id,
            'date' => $this->bookingDate(),
            'start_time' => '09:00',
            'items' => [['service_id' => $f['services']['unisex']->id, 'staff_id' => null]],
        ])->assertStatus(422)->assertJsonValidationErrors(['phone']);
    }

    public function test_repeated_booking_requests_from_the_same_first_time_customer_do_not_create_duplicate_profiles(): void
    {
        $f = $this->fixture('a');
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $api = $this->actingAs($customer, 'sanctum');

        $api->postJson('/api/v1/customer/bookings', [
            'branch_id' => $f['branch']->id, 'date' => $this->bookingDate(), 'start_time' => '09:00',
            'items' => [['service_id' => $f['services']['unisex']->id, 'staff_id' => null]], 'phone' => '9123456780',
        ])->assertCreated();

        $api->postJson('/api/v1/customer/bookings', [
            'branch_id' => $f['branch']->id, 'date' => $this->bookingDate(), 'start_time' => '11:00',
            'items' => [['service_id' => $f['services']['unisex']->id, 'staff_id' => null]], 'phone' => '9123456780',
        ])->assertCreated();

        app(TenantContext::class)->set($f['tenant']);
        $this->assertSame(1, Customer::where('user_id', $customer->id)->count());
        $this->assertSame(2, Booking::count());
        app(TenantContext::class)->clear();
    }

    public function test_an_existing_customer_profile_is_reused_for_booking_not_recreated(): void
    {
        $f = $this->fixture('a');
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        app(TenantContext::class)->set($f['tenant']);
        $existing = Customer::query()->create(['user_id' => $customer->id, 'name' => 'Sagar', 'phone' => '9000000099', 'normalized_phone' => '9000000099', 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();

        $booking = $this->actingAs($customer, 'sanctum')->postJson('/api/v1/customer/bookings', [
            'branch_id' => $f['branch']->id, 'date' => $this->bookingDate(), 'start_time' => '09:00',
            'items' => [['service_id' => $f['services']['unisex']->id, 'staff_id' => null]],
            // No phone sent — must not be needed since a profile already exists.
        ])->assertCreated()->json('data');

        $this->assertSame($existing->id, Booking::withoutGlobalScope('tenant')->find($booking['id'])->customer_id);
        app(TenantContext::class)->set($f['tenant']);
        $this->assertSame(1, Customer::where('user_id', $customer->id)->count());
        app(TenantContext::class)->clear();
    }

    public function test_a_phone_colliding_with_a_different_existing_customer_is_a_clean_conflict_not_a_raw_db_error(): void
    {
        $f = $this->fixture('a');
        app(TenantContext::class)->set($f['tenant']);
        Customer::query()->create(['name' => 'Walk-in Customer', 'phone' => '9555500000', 'normalized_phone' => '9555500000', 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);

        $this->actingAs($customer, 'sanctum')->postJson('/api/v1/customer/bookings', [
            'branch_id' => $f['branch']->id, 'date' => $this->bookingDate(), 'start_time' => '09:00',
            'items' => [['service_id' => $f['services']['unisex']->id, 'staff_id' => null]],
            'phone' => '9555500000',
        ])->assertStatus(409);
    }

    public function test_customer_cannot_book_against_another_tenants_branch_or_service(): void
    {
        $a = $this->fixture('a');
        $b = $this->fixture('b');
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);

        // Branch from tenant A, service from tenant B.
        $this->actingAs($customer, 'sanctum')->postJson('/api/v1/customer/bookings', [
            'branch_id' => $a['branch']->id, 'date' => $this->bookingDate(), 'start_time' => '09:00',
            'items' => [['service_id' => $b['services']['unisex']->id, 'staff_id' => null]],
            'phone' => '9123456780',
        ])->assertStatus(422)->assertJsonValidationErrors(['items.0.service_id']);
    }

    public function test_a_client_supplied_tenant_id_cannot_override_the_actual_branch_tenant(): void
    {
        $a = $this->fixture('a');
        $b = $this->fixture('b');
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);

        $booking = $this->actingAs($customer, 'sanctum')->postJson('/api/v1/customer/bookings', [
            'branch_id' => $a['branch']->id, 'date' => $this->bookingDate(), 'start_time' => '09:00',
            'items' => [['service_id' => $a['services']['unisex']->id, 'staff_id' => null]],
            'phone' => '9123456780',
            'tenant_id' => $b['tenant']->id, // ignored — not a recognized field
        ])->assertCreated()->json('data');

        app(TenantContext::class)->set($a['tenant']);
        $this->assertNotNull(Booking::find($booking['id']), 'Booking must belong to branch A\'s real tenant.');
        app(TenantContext::class)->clear();
        app(TenantContext::class)->set($b['tenant']);
        $this->assertNull(Booking::find($booking['id']), 'Booking must never be visible under the spoofed tenant.');
        app(TenantContext::class)->clear();
    }

    public function test_existing_owner_created_customer_registration_is_unaffected(): void
    {
        $f = $this->fixture('a');
        $ownerApi = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        $ownerApi->postJson('/api/v1/customers', ['name' => 'Walk-in', 'phone' => '9666600000'])
            ->assertCreated()->assertJsonPath('data.name', 'Walk-in');

        app(TenantContext::class)->set($f['tenant']);
        $created = Customer::where('phone', '9666600000')->first();
        $this->assertNotNull($created);
        $this->assertNull($created->user_id, 'A staff-registered walk-in customer must not be auto-linked to any app user.');
        app(TenantContext::class)->clear();
    }

    public function test_existing_booking_pricing_still_computes_correctly_for_an_auto_created_first_time_customer(): void
    {
        $f = $this->fixture('a');
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);

        $preview = $this->actingAs($customer, 'sanctum')->postJson('/api/v1/customer/bookings/price-preview', [
            'branch_id' => $f['branch']->id,
            'service_ids' => [$f['services']['unisex']->id],
            'phone' => '9123456780',
        ])->assertOk()->json('data');

        $this->assertEquals(300, $preview['total']);
    }

    private function bookingDate(): string
    {
        return Carbon::today()->addDay()->toDateString();
    }

    /**
     * @return array{tenant: Tenant, owner: User, salon: Salon, branch: Branch, services: array<string, Service>}
     */
    private function fixture(string $slug, BusinessStatus $salonStatus = BusinessStatus::ACTIVE, BusinessStatus $branchStatus = BusinessStatus::ACTIVE): array
    {
        $tenant = Tenant::query()->create(['name' => 'Discover '.$slug, 'slug' => 'discover-'.$slug]);
        $owner = User::factory()->create(['role' => UserRole::SALON_OWNER]);
        $tenant->users()->attach($owner, ['role' => TenantMembershipRole::SALON_OWNER->value]);
        app(TenantContext::class)->set($tenant);

        $salon = Salon::query()->create(['name' => 'Discover '.$slug, 'slug' => 'discover-'.$slug, 'gender_type' => GenderType::UNISEX, 'status' => $salonStatus, 'timezone' => 'UTC']);
        $branch = Branch::query()->create(['salon_id' => $salon->id, 'name' => 'Main', 'slug' => 'main', 'status' => $branchStatus, 'timezone' => 'UTC']);
        foreach (range(0, 6) as $day) {
            BranchWorkingHour::query()->create(['branch_id' => $branch->id, 'day_of_week' => $day, 'is_open' => true, 'opening_time' => '09:00', 'closing_time' => '20:00']);
        }

        $category = ServiceCategory::query()->create(['branch_id' => $branch->id, 'audience' => ServiceAudience::UNISEX, 'name' => 'Hair', 'slug' => 'hair-'.$slug, 'status' => BusinessStatus::ACTIVE]);
        $genderFor = fn (ServiceAudience $a): GenderType => match ($a) {
            ServiceAudience::MALE => GenderType::MALE,
            ServiceAudience::FEMALE => GenderType::FEMALE,
            default => GenderType::UNISEX,
        };
        $services = [];
        foreach (ServiceAudience::cases() as $audience) {
            $services[$audience->value] = Service::query()->create([
                'branch_id' => $branch->id,
                'category_id' => $category->id,
                'name' => ucfirst($audience->value).' Cut',
                'slug' => $audience->value.'-cut-'.$slug,
                'gender' => $genderFor($audience),
                'audience' => $audience,
                'price' => '300.00',
                'duration_minutes' => 30,
                'status' => BusinessStatus::ACTIVE,
            ]);
        }

        $staff = Staff::query()->create(['name' => 'Staff '.$slug, 'gender' => 'male', 'status' => BusinessStatus::ACTIVE]);
        $staff->branches()->sync([$branch->id => ['tenant_id' => $tenant->id]]);
        $staff->services()->sync(collect($services)->mapWithKeys(fn (Service $s) => [$s->id => ['tenant_id' => $tenant->id]])->all());
        foreach (range(0, 6) as $day) {
            StaffWorkingHour::query()->create(['staff_id' => $staff->id, 'day_of_week' => $day, 'is_working' => true, 'start_time' => '09:00', 'end_time' => '20:00']);
        }

        app(TenantContext::class)->clear();

        return compact('tenant', 'owner', 'salon', 'branch', 'services');
    }
}
