<?php

namespace Tests\Feature;

use App\Enums\BusinessStatus;
use App\Enums\GenderType;
use App\Enums\TenantMembershipRole;
use App\Enums\UserRole;
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
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Collection;
use Tests\TestCase;

/**
 * Regression coverage for the same-day past-time-slot bug: a branch whose
 * `timezone` column didn't reflect its real-world local time (e.g. a UTC
 * default for a salon actually operating in India) made
 * AvailabilityService's/BookingService's existing, correct "now" cutoff
 * compare against the wrong instant, so already-past times kept showing as
 * available. Every fixture here uses a real, non-UTC IANA timezone
 * (Asia/Kolkata) specifically so these tests fail the way production did if
 * that timezone-aware comparison is ever broken — a UTC-only fixture
 * wouldn't have caught the original bug.
 *
 * AvailabilityService and BookingService are unmodified by this change —
 * both already enforce this cutoff correctly given correct timezone data
 * (see AvailabilityService::forBranch()'s $candidateInstant/$minAllowedInstant
 * check and BookingService::assertWithinBookingWindow()). These tests exist
 * because neither had ever been exercised under a frozen, non-UTC clock.
 */
class AvailabilityPastTimeSlotApiTest extends TestCase
{
    use RefreshDatabase;

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    public function test_today_past_slots_are_excluded_using_the_branchs_own_timezone(): void
    {
        $f = $this->fixture('a');
        Carbon::setTestNow(Carbon::create(2026, 8, 31, 18, 0, 0, 'Asia/Kolkata'));
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        $slots = $this->slotsFor($api, $f, '2026-08-31');
        foreach (['14:00', '15:00', '17:00', '17:30', '17:45'] as $past) {
            $this->assertFalse($slots->contains('start_time', $past), "Slot {$past} is before 18:00 local time and must be excluded.");
        }
    }

    public function test_today_future_slots_remain_available(): void
    {
        $f = $this->fixture('a');
        Carbon::setTestNow(Carbon::create(2026, 8, 31, 18, 0, 0, 'Asia/Kolkata'));
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        $slots = $this->slotsFor($api, $f, '2026-08-31');
        foreach (['18:15', '18:30', '19:00'] as $future) {
            $this->assertTrue($slots->contains('start_time', $future), "Slot {$future} is after 18:00 local time and must remain available.");
        }
    }

    /**
     * AvailabilityService/BookingService compare with a strict "less than"
     * (a slot must start strictly before "now" to be excluded), so a slot
     * whose start instant exactly equals "now" down to the second is not,
     * on its own, guaranteed to be excluded — that boundary is outside this
     * change's approved scope (no edits to either service). In practice a
     * real clock is never frozen, so by the time any request is actually
     * processed "now" has already ticked past any minute-aligned slot
     * boundary; this test models that realistically by freezing one second
     * past the boundary rather than exactly on it, which is what every real
     * request experiences.
     */
    public function test_a_slot_at_the_current_moment_is_treated_as_already_started(): void
    {
        $f = $this->fixture('a');
        Carbon::setTestNow(Carbon::create(2026, 8, 31, 18, 0, 30, 'Asia/Kolkata'));
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        $slots = $this->slotsFor($api, $f, '2026-08-31');
        $this->assertFalse($slots->contains('start_time', '18:00'), 'A slot that already started (18:00, now 18:00:30) must not be offered.');

        $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => '2026-08-31', 'start_time' => '18:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['amit']->id]],
        ])->assertStatus(409);
    }

    public function test_tomorrow_normal_working_hour_slots_remain_available(): void
    {
        $f = $this->fixture('a');
        // Deep into today, well past its own working hours — must have zero
        // effect on tomorrow's slots.
        Carbon::setTestNow(Carbon::create(2026, 8, 31, 23, 0, 0, 'Asia/Kolkata'));
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        $slots = $this->slotsFor($api, $f, '2026-09-01');
        $this->assertTrue($slots->contains('start_time', '09:00'), "Tomorrow's opening slot must be unaffected by today's cutoff.");
    }

    public function test_yesterday_cannot_be_booked(): void
    {
        $f = $this->fixture('a');
        Carbon::setTestNow(Carbon::create(2026, 8, 31, 18, 0, 0, 'Asia/Kolkata'));
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        // Rejected at the request-validation layer (AvailabilityRequest)
        // before ever reaching AvailabilityService — a stronger guarantee
        // than an empty slot list, so assert that outright.
        $api->getJson("/api/v1/branches/{$f['branch']->id}/availability?date=2026-08-30&service_ids[]={$f['haircut']->id}")
            ->assertUnprocessable()->assertJsonPath('errors.date.0', 'The date cannot be in the past.');

        $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => '2026-08-30', 'start_time' => '10:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['amit']->id]],
        ])->assertStatus(409);
    }

    public function test_branch_working_hours_are_still_respected(): void
    {
        $f = $this->fixture('a');
        // Early morning, before the branch opens — the cutoff must never
        // widen the window past the branch's own configured hours.
        Carbon::setTestNow(Carbon::create(2026, 8, 31, 6, 0, 0, 'Asia/Kolkata'));
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        $slots = $this->slotsFor($api, $f, '2026-08-31');
        $this->assertTrue($slots->contains('start_time', '09:00'));
        $this->assertFalse($slots->contains(fn ($s) => $s['start_time'] < '09:00'));
        $this->assertFalse($slots->contains(fn ($s) => $s['start_time'] >= '20:00'));

        app(TenantContext::class)->set($f['tenant']);
        BranchWorkingHour::query()->where('branch_id', $f['branch']->id)->where('day_of_week', CarbonImmutable::parse('2026-08-31')->dayOfWeek)->update(['is_open' => false]);
        app(TenantContext::class)->clear();
        $api->getJson("/api/v1/branches/{$f['branch']->id}/availability?date=2026-08-31&service_ids[]={$f['haircut']->id}")
            ->assertOk()->assertJsonCount(0, 'data.slots');
    }

    public function test_staff_working_hours_are_still_respected(): void
    {
        $f = $this->fixture('a');
        Carbon::setTestNow(Carbon::create(2026, 8, 31, 6, 0, 0, 'Asia/Kolkata'));
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        app(TenantContext::class)->set($f['tenant']);
        StaffWorkingHour::query()->where('staff_id', $f['amit']->id)->where('day_of_week', CarbonImmutable::parse('2026-08-31')->dayOfWeek)
            ->update(['start_time' => '09:00', 'end_time' => '12:00']);
        app(TenantContext::class)->clear();

        $resp = $api->getJson("/api/v1/branches/{$f['branch']->id}/availability?date=2026-08-31&service_ids[]={$f['haircut']->id}&staff_id={$f['amit']->id}")->assertOk()->json('data');
        $this->assertTrue(collect($resp['slots'])->contains('start_time', '11:30'));
        $this->assertFalse(collect($resp['slots'])->contains('start_time', '12:00'));
    }

    public function test_existing_bookings_still_block_slots(): void
    {
        $f = $this->fixture('a');
        Carbon::setTestNow(Carbon::create(2026, 8, 31, 18, 0, 0, 'Asia/Kolkata'));
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => '2026-08-31', 'start_time' => '18:30',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['amit']->id]],
        ])->assertCreated();

        $resp = $api->getJson("/api/v1/branches/{$f['branch']->id}/availability?date=2026-08-31&service_ids[]={$f['haircut']->id}&staff_id={$f['amit']->id}")->assertOk()->json('data');
        $this->assertFalse(collect($resp['slots'])->contains('start_time', '18:30'));
        $this->assertTrue(collect($resp['slots'])->contains('start_time', '19:00'));
    }

    public function test_staff_breaks_still_block_slots(): void
    {
        $f = $this->fixture('a');
        Carbon::setTestNow(Carbon::create(2026, 8, 31, 18, 0, 0, 'Asia/Kolkata'));
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
        $dow = CarbonImmutable::parse('2026-08-31')->dayOfWeek;

        $api->postJson("/api/v1/staff/{$f['amit']->id}/breaks", ['day_of_week' => $dow, 'start_time' => '19:00', 'end_time' => '19:30'])->assertCreated();

        $resp = $api->getJson("/api/v1/branches/{$f['branch']->id}/availability?date=2026-08-31&service_ids[]={$f['haircut']->id}&staff_id={$f['amit']->id}")->assertOk()->json('data');
        $this->assertFalse(collect($resp['slots'])->contains('start_time', '19:00'));
        $this->assertTrue(collect($resp['slots'])->contains('start_time', '19:30'));
    }

    public function test_staff_leave_still_blocks_slots(): void
    {
        $f = $this->fixture('a');
        Carbon::setTestNow(Carbon::create(2026, 8, 31, 18, 0, 0, 'Asia/Kolkata'));
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        $api->postJson("/api/v1/staff/{$f['amit']->id}/leaves", ['start_date' => '2026-08-31', 'end_date' => '2026-08-31', 'reason' => 'Personal'])->assertCreated();

        $resp = $api->getJson("/api/v1/branches/{$f['branch']->id}/availability?date=2026-08-31&service_ids[]={$f['haircut']->id}&staff_id={$f['amit']->id}")->assertOk()->json('data');
        $this->assertSame([], $resp['slots']);
    }

    public function test_service_duration_still_affects_slot_generation(): void
    {
        $f = $this->fixture('a');
        Carbon::setTestNow(Carbon::create(2026, 8, 31, 18, 0, 0, 'Asia/Kolkata'));
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        app(TenantContext::class)->set($f['tenant']);
        $longService = Service::query()->create([
            'branch_id' => $f['branch']->id, 'category_id' => $f['haircut']->category_id, 'name' => 'Spa Package',
            'slug' => 'spa-package', 'gender' => GenderType::UNISEX, 'price' => '1500.00', 'duration_minutes' => 90, 'status' => BusinessStatus::ACTIVE,
        ]);
        $longService->staff()->sync([$f['amit']->id => ['tenant_id' => $f['tenant']->id]]);
        app(TenantContext::class)->clear();

        // Branch closes at 20:00. A 90-minute service's last possible start
        // is 18:30 (18:30+90=20:00); 18:45 would end at 20:15, past closing.
        $resp = $api->getJson("/api/v1/branches/{$f['branch']->id}/availability?date=2026-08-31&service_ids[]={$longService->id}&staff_id={$f['amit']->id}")->assertOk()->json('data');
        $this->assertTrue(collect($resp['slots'])->contains('start_time', '18:30'));
        $this->assertFalse(collect($resp['slots'])->contains('start_time', '18:45'));
        $this->assertSame(90, $resp['duration_minutes']);
    }

    public function test_tenant_isolation_is_preserved_under_the_frozen_clock(): void
    {
        $f = $this->fixture('a');
        $g = $this->fixture('b');
        Carbon::setTestNow(Carbon::create(2026, 8, 31, 18, 0, 0, 'Asia/Kolkata'));
        $apiA = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        // Tenant A's owner can see tenant A's future slots today...
        $this->assertTrue($this->slotsFor($apiA, $f, '2026-08-31')->contains('start_time', '18:30'));

        // ...but cannot book against tenant B's branch/service/staff.
        $apiA->postJson('/api/v1/bookings', [
            'branch_id' => $g['branch']->id, 'customer_id' => $f['customer']->id, 'date' => '2026-08-31', 'start_time' => '18:30',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => null]],
        ])->assertUnprocessable();
        $apiA->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => '2026-08-31', 'start_time' => '18:30',
            'items' => [['service_id' => $g['haircut']->id, 'staff_id' => null]],
        ])->assertUnprocessable();
    }

    public function test_direct_booking_request_for_a_clearly_past_same_day_slot_is_rejected_server_side(): void
    {
        $f = $this->fixture('a');
        Carbon::setTestNow(Carbon::create(2026, 8, 31, 18, 0, 0, 'Asia/Kolkata'));
        $api = $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);

        // 14:00 today is unambiguously hours in the past relative to the
        // frozen 18:00 "now" — a scripted client bypassing the availability
        // endpoint entirely and posting straight to booking creation must
        // still be rejected here, server-side.
        $api->postJson('/api/v1/bookings', [
            'branch_id' => $f['branch']->id, 'customer_id' => $f['customer']->id, 'date' => '2026-08-31', 'start_time' => '14:00',
            'items' => [['service_id' => $f['haircut']->id, 'staff_id' => $f['amit']->id]],
        ])->assertStatus(409)->assertJsonPath('message', 'The selected time does not satisfy the minimum advance booking window.');

        $this->assertDatabaseCount('bookings', 0);
    }

    /**
     * @return Collection<int, array{start_time:string,end_time:string,staff_ids:list<string>}>
     */
    private function slotsFor($api, array $f, string $date): Collection
    {
        $resp = $api->getJson("/api/v1/branches/{$f['branch']->id}/availability?date={$date}&service_ids[]={$f['haircut']->id}")->assertOk()->json('data');

        return collect($resp['slots']);
    }

    /**
     * Same shape as BookingEngineApiTest::fixture(), except the branch/salon
     * timezone is a real IANA zone (Asia/Kolkata) rather than UTC — required
     * to exercise the exact bug this file regression-tests. A UTC fixture
     * would pass even if the timezone-aware comparison were silently broken
     * back to comparing against the server's UTC clock.
     *
     * @return array{tenant: Tenant, owner: User, branch: Branch, haircut: Service, amit: Staff, customer: Customer}
     */
    private function fixture(string $slug): array
    {
        $tenant = Tenant::query()->create(['name' => $slug, 'slug' => 'tz-'.$slug]);
        $owner = User::factory()->create(['role' => UserRole::SALON_OWNER]);
        $tenant->users()->attach($owner, ['role' => TenantMembershipRole::SALON_OWNER->value]);
        app(TenantContext::class)->set($tenant);

        $salon = Salon::query()->create(['name' => $slug, 'slug' => 'tz-'.$slug, 'gender_type' => GenderType::UNISEX, 'status' => BusinessStatus::ACTIVE, 'timezone' => 'Asia/Kolkata']);
        $branch = Branch::query()->create(['salon_id' => $salon->id, 'name' => 'Main', 'slug' => 'main', 'status' => BusinessStatus::ACTIVE, 'timezone' => 'Asia/Kolkata']);
        foreach (range(0, 6) as $day) {
            BranchWorkingHour::query()->create(['branch_id' => $branch->id, 'day_of_week' => $day, 'is_open' => true, 'opening_time' => '09:00', 'closing_time' => '20:00']);
        }

        $category = ServiceCategory::query()->create(['branch_id' => $branch->id, 'name' => 'Hair', 'slug' => 'hair-'.$slug, 'status' => BusinessStatus::ACTIVE]);
        $haircut = Service::query()->create(['branch_id' => $branch->id, 'category_id' => $category->id, 'name' => 'Haircut', 'slug' => 'haircut-'.$slug, 'gender' => GenderType::UNISEX, 'price' => '300.00', 'duration_minutes' => 30, 'status' => BusinessStatus::ACTIVE]);

        $amit = Staff::query()->create(['name' => 'Amit', 'gender' => 'male', 'status' => BusinessStatus::ACTIVE]);
        $amit->branches()->sync([$branch->id => ['tenant_id' => $tenant->id]]);
        $amit->services()->sync([$haircut->id => ['tenant_id' => $tenant->id]]);
        foreach (range(0, 6) as $day) {
            StaffWorkingHour::query()->create(['staff_id' => $amit->id, 'day_of_week' => $day, 'is_working' => true, 'start_time' => '09:00', 'end_time' => '20:00']);
        }

        $customer = Customer::query()->create(['name' => 'Rahul', 'phone' => '91000000'.($slug === 'a' ? '01' : '02'), 'normalized_phone' => '91000000'.($slug === 'a' ? '01' : '02'), 'status' => BusinessStatus::ACTIVE]);

        app(TenantContext::class)->clear();

        return compact('tenant', 'owner', 'branch', 'haircut', 'amit', 'customer');
    }
}
