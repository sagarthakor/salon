<?php

namespace Tests\Feature;

use App\Enums\BusinessStatus;
use App\Enums\GenderType;
use App\Enums\ServiceAudience;
use App\Enums\TenantMembershipRole;
use App\Enums\UserRole;
use App\Models\Branch;
use App\Models\BranchWorkingHour;
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
use Illuminate\Support\Facades\Config;
use Tests\TestCase;

/**
 * Covers the additive branded-single-salon-app surface: resolving a salon by
 * tenant id (`GET /customer/brand/{tenant}`) and the opt-in `X-App-Brand`
 * guard (App\Support\BrandAppGuard) that locks a branded app's requests to
 * its one configured tenant. Every assertion here that a request WITHOUT the
 * `X-App-Brand` header behaves exactly as before is the regression proof
 * that the existing multi-tenant customer app is untouched by this feature.
 */
class BrandedSalonApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        // A tenant id is only known at fixture-creation time, so each test
        // registers its own brand mapping rather than relying on the
        // production config/brand_apps.php entry.
        Config::set('brand_apps', []);
    }

    public function test_brand_endpoint_resolves_the_salon_for_a_known_tenant(): void
    {
        $f = $this->fixture('a');
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);

        $this->actingAs($customer, 'sanctum')->getJson("/api/v1/customer/brand/{$f['tenant']->id}")
            ->assertOk()->assertJsonPath('data.slug', $f['salon']->slug);
    }

    public function test_brand_endpoint_404s_for_an_unknown_or_inactive_tenant(): void
    {
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);

        $this->actingAs($customer, 'sanctum')->getJson('/api/v1/customer/brand/not-a-real-tenant-id')->assertNotFound();

        $inactive = $this->fixture('b', salonStatus: BusinessStatus::INACTIVE);
        $this->actingAs($customer, 'sanctum')->getJson("/api/v1/customer/brand/{$inactive['tenant']->id}")->assertNotFound();
    }

    public function test_without_the_brand_header_every_existing_endpoint_is_completely_unaffected(): void
    {
        $a = $this->fixture('a');
        $b = $this->fixture('b');
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $api = $this->actingAs($customer, 'sanctum');

        // No X-App-Brand at all — a customer can still freely reach any
        // tenant's branch/service/booking endpoints, exactly like today's
        // multi-tenant discovery app.
        $api->getJson("/api/v1/branches/{$a['branch']->id}/services")->assertOk();
        $api->getJson("/api/v1/branches/{$b['branch']->id}/services")->assertOk();

        $booking = $api->postJson('/api/v1/customer/bookings', [
            'branch_id' => $b['branch']->id,
            'date' => $this->bookingDate(),
            'start_time' => '09:00',
            'items' => [['service_id' => $b['services']['unisex']->id, 'staff_id' => null]],
            'phone' => '9123456780',
        ])->assertCreated()->json('data');

        $api->getJson("/api/v1/customer/bookings/{$booking['id']}")->assertOk();
    }

    public function test_brand_header_allows_the_matching_tenants_branch_service_and_booking_endpoints(): void
    {
        $f = $this->fixture('a');
        Config::set('brand_apps.nil_hair_port', $f['tenant']->id);
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $api = $this->actingAs($customer, 'sanctum')->withHeader('X-App-Brand', 'nil_hair_port');

        $api->getJson("/api/v1/branches/{$f['branch']->id}/services")->assertOk();
        $api->getJson("/api/v1/branches/{$f['branch']->id}/availability?date={$this->bookingDate()}&service_ids[]={$f['services']['unisex']->id}")->assertOk();

        $booking = $api->postJson('/api/v1/customer/bookings', [
            'branch_id' => $f['branch']->id,
            'date' => $this->bookingDate(),
            'start_time' => '09:00',
            'items' => [['service_id' => $f['services']['unisex']->id, 'staff_id' => null]],
            'phone' => '9123456780',
        ])->assertCreated()->json('data');

        $api->getJson("/api/v1/customer/bookings/{$booking['id']}")->assertOk();
    }

    public function test_brand_header_denies_a_different_tenants_branch_services_and_availability(): void
    {
        $home = $this->fixture('a');
        $other = $this->fixture('b');
        Config::set('brand_apps.nil_hair_port', $home['tenant']->id);
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $api = $this->actingAs($customer, 'sanctum')->withHeader('X-App-Brand', 'nil_hair_port');

        $api->getJson("/api/v1/branches/{$other['branch']->id}/services")->assertStatus(403);
        $api->getJson("/api/v1/branches/{$other['branch']->id}/availability?date={$this->bookingDate()}&service_ids[]={$other['services']['unisex']->id}")
            ->assertStatus(403);
    }

    public function test_brand_header_denies_booking_against_a_different_tenants_branch(): void
    {
        $home = $this->fixture('a');
        $other = $this->fixture('b');
        Config::set('brand_apps.nil_hair_port', $home['tenant']->id);
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);

        $this->actingAs($customer, 'sanctum')->withHeader('X-App-Brand', 'nil_hair_port')->postJson('/api/v1/customer/bookings', [
            'branch_id' => $other['branch']->id,
            'date' => $this->bookingDate(),
            'start_time' => '09:00',
            'items' => [['service_id' => $other['services']['unisex']->id, 'staff_id' => null]],
            'phone' => '9123456780',
        ])->assertStatus(403);
    }

    public function test_brand_header_denies_viewing_a_booking_that_belongs_to_a_different_tenant(): void
    {
        $home = $this->fixture('a');
        $other = $this->fixture('b');
        Config::set('brand_apps.nil_hair_port', $home['tenant']->id);
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $api = $this->actingAs($customer, 'sanctum');

        $booking = $api->postJson('/api/v1/customer/bookings', [
            'branch_id' => $other['branch']->id,
            'date' => $this->bookingDate(),
            'start_time' => '09:00',
            'items' => [['service_id' => $other['services']['unisex']->id, 'staff_id' => null]],
            'phone' => '9123456780',
        ])->assertCreated()->json('data');

        $api->withHeader('X-App-Brand', 'nil_hair_port')->getJson("/api/v1/customer/bookings/{$booking['id']}")->assertStatus(403);
    }

    public function test_an_unrecognized_brand_header_is_rejected_rather_than_silently_ignored(): void
    {
        $f = $this->fixture('a');
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);

        $this->actingAs($customer, 'sanctum')->withHeader('X-App-Brand', 'not-a-real-brand')
            ->getJson("/api/v1/branches/{$f['branch']->id}/services")->assertStatus(403);
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
        $tenant = Tenant::query()->create(['name' => 'Brand '.$slug, 'slug' => 'brand-'.$slug]);
        $owner = User::factory()->create(['role' => UserRole::SALON_OWNER]);
        $tenant->users()->attach($owner, ['role' => TenantMembershipRole::SALON_OWNER->value]);
        app(TenantContext::class)->set($tenant);

        $salon = Salon::query()->create(['name' => 'Brand '.$slug, 'slug' => 'brand-'.$slug, 'gender_type' => GenderType::UNISEX, 'status' => $salonStatus, 'timezone' => 'UTC']);
        $branch = Branch::query()->create(['salon_id' => $salon->id, 'name' => 'Main', 'slug' => 'main', 'status' => $branchStatus, 'timezone' => 'UTC']);
        foreach (range(0, 6) as $day) {
            BranchWorkingHour::query()->create(['branch_id' => $branch->id, 'day_of_week' => $day, 'is_open' => true, 'opening_time' => '09:00', 'closing_time' => '20:00']);
        }

        $category = ServiceCategory::query()->create(['branch_id' => $branch->id, 'audience' => ServiceAudience::UNISEX, 'name' => 'Hair', 'slug' => 'hair-'.$slug, 'status' => BusinessStatus::ACTIVE]);
        $services = [
            'unisex' => Service::query()->create([
                'branch_id' => $branch->id,
                'category_id' => $category->id,
                'name' => 'Unisex Cut',
                'slug' => 'unisex-cut-'.$slug,
                'gender' => GenderType::UNISEX,
                'audience' => ServiceAudience::UNISEX,
                'price' => '300.00',
                'duration_minutes' => 30,
                'status' => BusinessStatus::ACTIVE,
            ]),
        ];

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
