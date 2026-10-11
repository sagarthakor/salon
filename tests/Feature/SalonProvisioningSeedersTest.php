<?php

namespace Tests\Feature;

use App\Enums\BusinessStatus;
use App\Enums\GenderType;
use App\Enums\UserRole;
use App\Models\Booking;
use App\Models\Branch;
use App\Models\BranchWorkingHour;
use App\Models\Customer;
use App\Models\MasterService;
use App\Models\MasterServiceCategory;
use App\Models\Salon;
use App\Models\SalonSetting;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\Staff;
use App\Models\StaffBreak;
use App\Models\StaffWorkingHour;
use App\Models\Tenant;
use App\Models\User;
use App\Support\TenantContext;
use Carbon\Carbon;
use Database\Seeders\DatabaseSeeder;
use Database\Seeders\DemoSalonSeeder;
use Database\Seeders\MasterDataSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** Seeders + onboarding defaults: idempotent, tenant-safe, and the real availability API returns slots. */
class SalonProvisioningSeedersTest extends TestCase
{
    use RefreshDatabase;

    /** Next Monday — a working day under the default hours. */
    private function monday(): string
    {
        return Carbon::today()->next(Carbon::MONDAY)->toDateString();
    }

    private function counts(): array
    {
        $t = Tenant::query()->where('slug', 'demo-salon')->firstOrFail();
        app(TenantContext::class)->set($t);
        $c = [
            'master_categories' => MasterServiceCategory::count(), 'master_services' => MasterService::count(),
            'salons' => Salon::count(), 'branches' => Branch::count(), 'services' => Service::count(),
            'staff' => Staff::count(), 'settings' => SalonSetting::count(),
            'branch_hours' => BranchWorkingHour::count(), 'staff_hours' => StaffWorkingHour::count(),
            'staff_services' => \DB::table('staff_services')->count(), 'breaks' => StaffBreak::count(),
            'users' => User::count(), 'tenants' => Tenant::count(),
        ];
        app(TenantContext::class)->clear();

        return $c;
    }

    public function test_master_data_seeder_creates_the_documented_catalog_and_is_repeatable(): void
    {
        $this->seed(MasterDataSeeder::class);
        $this->seed(MasterDataSeeder::class);

        $this->assertSame(14, MasterServiceCategory::count());
        $this->assertSame(75, MasterService::count());
        foreach (['male' => 19, 'female' => 40, 'unisex' => 13, 'kids' => 3] as $audience => $n) {
            $this->assertSame($n, MasterService::where('audience', $audience)->count(), $audience);
        }
        $this->assertSame(0, Tenant::count());
        $this->assertSame(0, User::count());
    }

    public function test_full_seed_run_twice_creates_no_duplicates_and_no_fake_transactions(): void
    {
        $this->seed(DatabaseSeeder::class);
        $first = $this->counts();
        $this->seed(DatabaseSeeder::class);
        $this->assertSame($first, $this->counts());

        $this->assertSame(1, $first['salons']);
        $this->assertSame(1, $first['branches']);
        $this->assertSame(75, $first['services']);
        $this->assertSame(7, $first['branch_hours']);
        $this->assertSame(0, Booking::withoutGlobalScope('tenant')->count());
        $this->assertSame(0, Customer::withoutGlobalScope('tenant')->count());
        $this->assertSame(0, \DB::table('payments')->count());
        $this->assertSame(0, \DB::table('salon_media')->count());
        $this->assertSame(0, \DB::table('instagram_connections')->count());
    }

    public function test_demo_salon_seeder_refuses_to_run_in_production(): void
    {
        $this->app['env'] = 'production';
        $this->artisan('db:seed', ['--class' => DemoSalonSeeder::class, '--force' => true])->assertSuccessful();

        $this->assertSame(0, Tenant::count());
    }

    public function test_after_seeding_the_real_availability_api_returns_slots_and_breaks_and_bookings_block_them(): void
    {
        $this->seed(DatabaseSeeder::class);
        $branch = Branch::withoutGlobalScope('tenant')->firstOrFail();
        $tenant = Tenant::findOrFail($branch->tenant_id);
        app(TenantContext::class)->set($tenant);
        $haircut = Service::query()->where('audience', 'male')->where('name', 'Hair Cut')->firstOrFail();
        $stylist = Staff::query()->where('email', 'like', 'default-stylist-%')->firstOrFail();
        app(TenantContext::class)->clear();

        $customerUser = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $url = "/api/v1/branches/{$branch->id}/availability?date={$this->monday()}&service_ids[]={$haircut->id}";
        $slots = $this->actingAs($customerUser, 'sanctum')->getJson($url)->assertOk()->json('data.slots');
        $starts = array_column($slots, 'start_time');
        $this->assertNotEmpty($slots);
        $this->assertContains('09:00', $starts);
        $this->assertContains($stylist->id, $slots[0]['staff_ids']);
        // 13:00–14:00 lunch break: a 30-min cut may not start at 13:00 or 13:30 …
        $this->assertNotContains('13:00', $starts);
        $this->assertNotContains('13:30', $starts);
        $this->assertContains('14:00', $starts);

        // … and an existing booking removes its slot (single stylist).
        $owner = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $this->actingAs($owner, 'sanctum')->postJson('/api/v1/customer/bookings', [
            'branch_id' => $branch->id, 'date' => $this->monday(), 'start_time' => '10:00', 'phone' => '9876543210',
            'items' => [['service_id' => $haircut->id, 'staff_id' => null]],
        ])->assertCreated();
        $after = array_column($this->actingAs($customerUser, 'sanctum')->getJson($url)->json('data.slots'), 'start_time');
        $this->assertNotContains('10:00', $after);
        $this->assertContains('10:30', $after);

        // Sunday is closed by default.
        $sunday = Carbon::today()->next(Carbon::SUNDAY)->toDateString();
        $this->actingAs($customerUser, 'sanctum')->getJson("/api/v1/branches/{$branch->id}/availability?date=$sunday&service_ids[]={$haircut->id}")->assertOk()->assertJsonPath('data.slots', []);
    }

    public function test_owner_onboarding_makes_a_new_salon_bookable_without_touching_other_tenants(): void
    {
        $this->seed(MasterDataSeeder::class);
        $before = $this->seedOther();

        $response = $this->postJson('/api/v1/auth/register-owner', [
            'name' => 'New Owner', 'email' => 'new-owner@example.test', 'password' => 'password12345', 'password_confirmation' => 'password12345', 'salon_name' => 'Fresh Salon',
        ])->assertCreated();
        $api = $this->withHeader('Authorization', 'Bearer '.$response->json('data.token'))->withHeader('X-Tenant-Slug', $response->json('data.tenant_slug'));
        $api->postJson('/api/v1/salon', ['name' => 'Fresh Salon', 'gender_type' => 'unisex', 'timezone' => 'Asia/Kolkata'])->assertCreated();

        $branch = Branch::withoutGlobalScope('tenant')->whereHas('salon', fn ($q) => $q->withoutGlobalScope('tenant')->where('name', 'Fresh Salon'))->firstOrFail();
        $service = Service::withoutGlobalScope('tenant')->where('branch_id', $branch->id)->where('name', 'Hair Cut')->where('audience', 'female')->firstOrFail();
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $this->withHeaders([])->actingAs($customer, 'sanctum')
            ->getJson("/api/v1/branches/{$branch->id}/availability?date={$this->monday()}&service_ids[]={$service->id}")
            ->assertOk()->assertJsonPath('data.slots.0.start_time', '09:00');

        // The unrelated tenant is exactly as it was.
        $this->assertSame($before, $this->otherState());
        // The new tenant's defaults are its own.
        $this->assertSame(7, \DB::table('branch_working_hours')->where('branch_id', $branch->id)->count());
        $this->assertSame(1, \DB::table('staff_branches')->where('branch_id', $branch->id)->count());
        // Slots for the new branch do not appear when asking about the other tenant's branch.
        $otherBranch = Branch::withoutGlobalScope('tenant')->where('slug', 'other-main')->firstOrFail();
        $this->actingAs($customer, 'sanctum')->getJson("/api/v1/branches/{$otherBranch->id}/availability?date={$this->monday()}&service_ids[]={$service->id}")->assertStatus(422);
    }

    public function test_provisioning_never_overwrites_an_owners_settings_hours_or_staff(): void
    {
        $this->seed(MasterDataSeeder::class);
        $tenant = Tenant::create(['name' => 'Real', 'slug' => 'real']);
        app(TenantContext::class)->set($tenant);
        $salon = Salon::create(['name' => 'Real', 'slug' => 'real', 'gender_type' => GenderType::UNISEX, 'status' => BusinessStatus::ACTIVE]);
        $branch = Branch::create(['salon_id' => $salon->id, 'name' => 'Main', 'slug' => 'main', 'status' => BusinessStatus::ACTIVE, 'timezone' => 'Asia/Kolkata']);
        SalonSetting::create(['salon_id' => $salon->id, 'key' => 'slot_interval_minutes', 'value' => 45]);
        $branch->workingHours()->create(['day_of_week' => 1, 'is_open' => true, 'opening_time' => '11:00', 'closing_time' => '15:00']);
        $mine = Staff::create(['name' => 'Real Barber', 'gender' => 'male', 'status' => BusinessStatus::ACTIVE]);
        $mine->branches()->attach($branch->id, ['tenant_id' => $tenant->id]);
        $service = $cat = ServiceCategory::create(['branch_id' => $branch->id, 'name' => 'Mine', 'slug' => 'mine', 'status' => BusinessStatus::ACTIVE]);
        $service = Service::create(['category_id' => $cat->id, 'branch_id' => $branch->id, 'name' => 'My Cut', 'slug' => 'my-cut', 'gender' => GenderType::UNISEX, 'price' => 777, 'duration_minutes' => 20, 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();

        $this->artisan('salon:provision', ['tenant' => 'real'])->assertSuccessful();
        $this->artisan('salon:provision', ['tenant' => 'real'])->assertSuccessful();

        app(TenantContext::class)->set($tenant);
        $this->assertSame(45, SalonSetting::where('key', 'slot_interval_minutes')->firstOrFail()->value);
        $this->assertSame('11:00', substr((string) $branch->workingHours()->where('day_of_week', 1)->firstOrFail()->opening_time, 0, 5));
        $this->assertSame(7, $branch->workingHours()->count());
        $this->assertSame(1, Staff::count(), 'a branch that already has staff gets no default stylist');
        $this->assertSame(1, Service::count(), 'an owner-built catalog is not padded with the master catalog');
        $this->assertSame('777.00', (string) $service->fresh()->price);
        app(TenantContext::class)->clear();

        $this->artisan('salon:provision', ['tenant' => 'missing'])->assertFailed();
    }

    private function seedOther(): array
    {
        $tenant = Tenant::create(['name' => 'Other', 'slug' => 'other']);
        app(TenantContext::class)->set($tenant);
        $salon = Salon::create(['name' => 'Other', 'slug' => 'other', 'gender_type' => GenderType::UNISEX, 'status' => BusinessStatus::ACTIVE]);
        Branch::create(['salon_id' => $salon->id, 'name' => 'Main', 'slug' => 'other-main', 'status' => BusinessStatus::ACTIVE, 'timezone' => 'Asia/Kolkata']);
        app(TenantContext::class)->clear();

        return $this->otherState();
    }

    private function otherState(): array
    {
        $id = Tenant::where('slug', 'other')->value('id');

        return [
            'services' => Service::withoutGlobalScope('tenant')->where('tenant_id', $id)->count(),
            'staff' => Staff::withoutGlobalScope('tenant')->where('tenant_id', $id)->count(),
            'settings' => SalonSetting::withoutGlobalScope('tenant')->where('tenant_id', $id)->count(),
            'hours' => BranchWorkingHour::withoutGlobalScope('tenant')->where('tenant_id', $id)->count(),
        ];
    }
}
